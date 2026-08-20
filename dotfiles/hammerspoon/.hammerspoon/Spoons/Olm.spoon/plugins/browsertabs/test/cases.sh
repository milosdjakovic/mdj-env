#!/usr/bin/env bash
# The cases. This file is policy and nothing else. It says what states are worth putting the tool
# in, which browser each one is worth trying on, and how many times a case that was once flaky has
# to pass before it counts. The runner knows none of it.
#
# Every case that can be is built out of pages this suite opens itself, because a case that depends
# on what happens to be open is a case that quietly stops testing anything. The exceptions are the
# few states no script can create, a tab group, a pinned tab, a discarded tab, and those say so
# rather than pretending, so the summary at the end distinguishes what passed from what was never
# tried.

# The browsers the suite knows about, which is also the set the restore puts back.
BROWSERS=(com.google.Chrome com.apple.Safari)

# Each entry is a case and the browser it runs against. One body serves both browsers, so a state
# worth checking on each appears twice, and a state that only exists in one appears once.
CASES=(
  "frontmost chrome"                 "frontmost safari"
  "background_window chrome"         "background_window safari"
  "other_app_front chrome"           "other_app_front safari"
  "minimized chrome"                 "minimized safari"
  "hidden_app chrome"                "hidden_app safari"
  "already_selected chrome"          "already_selected safari"
  "far_from_selected chrome"         "far_from_selected safari"
  "long_title chrome"                "long_title safari"
  "blank_title chrome"               "blank_title safari"
  "duplicate_in_window chrome"       "duplicate_in_window safari"
  "duplicate_two_windows chrome"     "duplicate_two_windows safari"
  "retitles_on_load chrome"          "retitles_on_load safari"
  "discarded chrome"
  "pinned safari"
  "tab_group safari"
  "drift_tab_inserted chrome"        "drift_tab_inserted safari"
  "drift_tab_closed chrome"          "drift_tab_closed safari"
  "drift_window_reordered chrome"    "drift_window_reordered safari"
  "drift_tab_moved chrome"
  "drift_window_closed chrome"       "drift_window_closed safari"
  "phantom_not_listed safari"
  "back_to_back chrome"
  "not_running arc"
  "switched_off chrome"
  "escape_raises_nothing chrome"
  "no_query chrome"                  "no_query safari"
  "slow_press chrome"                "slow_press safari"
  "existing_user_tab chrome"         "existing_user_tab safari"
  "fullscreen chrome"
)

# How many times a case has to pass. Three for the states that were actually seen failing, since
# those are the ones where one pass proves least, and one for the deterministic rest.
bt_case_reps() {
  case $1 in
    background_window|minimized|other_app_front|hidden_app|back_to_back|far_from_selected) printf 3 ;;
    *) printf 1 ;;
  esac
}

# There is deliberately no per case choice of how a round is driven. One was built, on the reasoning
# that a case about a minimized window is not a case about typing, and it was withdrawn because its
# effect could not be separated from the machine's own drift. It is not established that the
# keyboard is a precondition, only that it has not been shown to be safe to remove. The measurement
# and the reason are recorded above `round` in run.sh.

#-------------------------------------------------------------------------------
# Helpers the cases share
#-------------------------------------------------------------------------------

# A short token unique to this round, used as the page title and as the query. Unique matters twice
# over, once so the row can be found at all among a hundred tabs, and once so the row that was found
# is provably the one this case opened.
#
# The counter lives in a file rather than in a variable, and that is not fussiness. An arrange runs
# inside a command substitution, so it is a subshell, and a variable it increments dies with it.
# When the counter was a variable, two arranges in one case both produced the first token, both
# browsers got a page with the same name, and the second round of the pair opened the first
# browser's tab instead. It read as the tool failing to switch browsers, which is the exact fault
# this suite exists to catch, so the harness was manufacturing a false report of the real bug.
bt_uniq() {
  local f=$HS_REPLY_DIR/uniq n
  n=$(( $(cat "$f" 2>/dev/null || printf 0) + 1 ))
  printf '%s' "$n" > "$f"
  printf 'bttag%sx%s' "$$" "$n"
}

# The address of a fixture, carrying the marker that tells the restore this page is ours.
bt_fx() {
  local file=$1 name=$2 extra=${3:-}
  printf 'file://%s/fixtures/%s?%s&t=%s%s' "$BT_TEST_DIR" "$file" "$BT_MARK" "$name" "$extra"
}

bt_first_window() {
  bt "$1" list | jq -r '.windows[0].id // ""'
}

# A window of this browser other than the given one, empty when there is not one. Several cases
# need a second window to hide behind and say so rather than inventing one, since a browser with a
# single window is a legitimate state to be in.
bt_other_window() {
  bt "$1" list | jq -r --arg w "$2" '[.windows[] | select(.id != $w)] | .[0].id // ""'
}

# Open a fixture in a window and answer with its position and the address the browser settled on,
# which is read back rather than assumed because a browser may normalise what it was given.
bt_open_fixture() {
  local bundle=$1 win=$2 url=$3 name=$4
  bt "$bundle" open "$win" "$url" > /dev/null

  # Wait for the page to have named itself, since the title is both the query and the proof.
  local waited=0 row
  while [ "$waited" -lt 50 ]; do
    row=$(bt "$bundle" list | jq -r --arg w "$win" --arg n "$name" \
      '.windows[] | select(.id == $w) | .tabs[] | select(.title == $n) | "\(.index)\t\(.url)"' | head -1)
    [ -n "$row" ] && { printf '%s' "$row"; return 0; }
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  return 1
}

# The target descriptor every arrange answers with.
bt_target() {
  jq -nc --arg b "$1" --arg w "$2" --argjson i "$3" --arg u "$4" --arg q "$5" \
    --arg m "${6:-full}" --arg h "${7:-0.12}" \
    '{bundleID:$b, windowID:$w, tabIndex:($i|tonumber), url:$u, query:$q, mode:$m, hold:$h}'
}

bt_skip() {
  jq -nc --arg s "$1" '{skip:$s}'
}

# The common opening move. Put a fixture in the browser's front window and answer with everything a
# target needs, leaving the state itself to the case.
bt_simple_target() {
  local bundle=$1 name win row idx url
  name=$(bt_uniq)
  win=$(bt_first_window "$bundle")
  [ -n "$win" ] || { bt_skip "the browser has no window"; return 1; }
  row=$(bt_open_fixture "$bundle" "$win" "$(bt_fx page.html "$name")" "$name") || {
    bt_skip "the fixture tab never finished loading"; return 1; }
  idx=${row%%$'\t'*}; url=${row##*$'\t'}
  printf '%s\t%s\t%s\t%s' "$win" "$idx" "$url" "$name"
}

#-------------------------------------------------------------------------------
# Where the target window is
#-------------------------------------------------------------------------------

# The easy one, and the reason it is here is that it is the only case where doing nothing at all
# would look like success. Everything else has to move.
case_frontmost_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  bt "$BT_BUNDLE" raise "$win" > /dev/null
  osascript -e "tell application id \"$BT_BUNDLE\" to activate" > /dev/null 2>&1
  sleep 0.4
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# The target is behind another window of the same browser. This is the case that proved raising the
# application is not the same as raising a window, since the application comes forward showing
# whichever window it remembers rather than the one the tab is in.
case_background_window_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  local other; other=$(bt_other_window "$BT_BUNDLE" "$win")
  [ -n "$other" ] || { bt_skip "this browser has only one window open"; return; }
  bt "$BT_BUNDLE" raise "$other" > /dev/null
  osascript -e "tell application id \"$BT_BUNDLE\" to activate" > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

case_other_app_front_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# A minimized target. Raising the application leaves it in the Dock, so without the restore the
# whole thing looks like it did nothing, which is one of the ways this tool used to appear broken.
case_minimized_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  bt "$BT_BUNDLE" minimize "$win" 1 > /dev/null
  sleep 0.8
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

case_minimized_cleanup() {
  local w
  for w in $(bt "$BT_BUNDLE" list | jq -r '.windows[] | select(.minimized == true) | .id'); do
    bt "$BT_BUNDLE" minimize "$w" 0 > /dev/null
  done
}

# The browser hidden outright. This is where the application lookup used to come back empty on the
# first call, so the tool could not find the browser it had just finished scripting.
case_hidden_app_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  osascript -e "tell application \"System Events\" to set visible of (first application process whose bundle identifier is \"$BT_BUNDLE\") to false" > /dev/null 2>&1
  sleep 0.6
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# A full screen window lives on its own Space, which is the nearest this machine can get to the
# Spaces case, since it has only one ordinary desktop.
case_fullscreen_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  local proc; proc=$(bt_process_name "$BT_BUNDLE")
  bt "$BT_BUNDLE" raise "$win" > /dev/null
  osascript -e "tell application id \"$BT_BUNDLE\" to activate" > /dev/null 2>&1
  sleep 0.4
  osascript -e "tell application \"System Events\" to tell process \"$proc\" to set value of attribute \"AXFullScreen\" of window 1 to true" > /dev/null 2>&1 || {
    bt_skip "this window would not go full screen"; return; }
  sleep 2.5
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 1.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

case_fullscreen_cleanup() {
  local proc; proc=$(bt_process_name "$BT_BUNDLE")
  osascript -e "tell application \"System Events\" to tell process \"$proc\" to set value of attribute \"AXFullScreen\" of window 1 to false" > /dev/null 2>&1
  sleep 2
}

#-------------------------------------------------------------------------------
# What the target tab is
#-------------------------------------------------------------------------------

case_already_selected_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  bt "$BT_BUNDLE" select "$win" "$idx" > /dev/null
  bt "$BT_BUNDLE" back "$win" > /dev/null
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# The window is showing something else entirely, so the tab switch and the window raise both have
# to happen and in the right order.
case_far_from_selected_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  bt "$BT_BUNDLE" select "$win" 1 > /dev/null
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# A title long enough that Chrome elides the window name it reports, which is what stops the window
# name from being matchable and makes the fall through to the tab title necessary.
case_long_title_arrange() {
  local name win row idx url
  name=$(bt_uniq)
  win=$(bt_first_window "$BT_BUNDLE")
  [ -n "$win" ] || { bt_skip "the browser has no window"; return; }
  # The page names itself with the tag first and a great deal after it, so the tag is still what
  # the query finds while the name as a whole is long enough to be elided.
  local waited=0
  bt "$BT_BUNDLE" open "$win" "$(bt_fx long.html "$name")" > /dev/null
  while [ "$waited" -lt 50 ]; do
    row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
      '.windows[] | select(.id == $w) | .tabs[] | select(.title | startswith($n)) | "\(.index)\t\(.url)\t\(.title)"' | head -1)
    [ -n "$row" ] && break
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  [ -n "$row" ] || { bt_skip "the long title fixture never loaded"; return; }
  IFS=$'\t' read -r idx url title <<<"$row"
  local other; other=$(bt_other_window "$BT_BUNDLE" "$win")
  [ -n "$other" ] && bt "$BT_BUNDLE" raise "$other" > /dev/null
  osascript -e "tell application id \"$BT_BUNDLE\" to activate" > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# No title element at all, so the browser names the tab after its address and the row has nothing
# but the address to be found by.
case_blank_title_arrange() {
  local name win row idx url
  name=$(bt_uniq)
  win=$(bt_first_window "$BT_BUNDLE")
  [ -n "$win" ] || { bt_skip "the browser has no window"; return; }
  bt "$BT_BUNDLE" open "$win" "$(bt_fx blank.html "$name")" > /dev/null
  local waited=0
  while [ "$waited" -lt 50 ]; do
    row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
      '.windows[] | select(.id == $w) | .tabs[] | select((.url // "") | contains($n)) | "\(.index)\t\(.url)"' | head -1)
    [ -n "$row" ] && break
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  [ -n "$row" ] || { bt_skip "the blank title fixture never loaded"; return; }
  IFS=$'\t' read -r idx url <<<"$row"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# Two tabs in one window on the same address. The position has to win, because the address cannot
# say which of the two was meant and preferring it would open the wrong one.
case_duplicate_in_window_arrange() {
  local name win row idx url first
  name=$(bt_uniq)
  win=$(bt_first_window "$BT_BUNDLE")
  [ -n "$win" ] || { bt_skip "the browser has no window"; return; }
  local addr; addr=$(bt_fx page.html "$name")
  first=$(bt_open_fixture "$BT_BUNDLE" "$win" "$addr" "$name") || { bt_skip "the first copy never loaded"; return; }
  bt "$BT_BUNDLE" open "$win" "$addr" > /dev/null
  sleep 1.2
  # Take the second of the two, so a tool that resolved by address alone would land on the first.
  row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
    '.windows[] | select(.id == $w) | [.tabs[] | select(.title == $n)] | if length > 1 then .[1] else empty end | "\(.index)\t\(.url)"')
  [ -n "$row" ] || { bt_skip "the second copy never loaded"; return; }
  IFS=$'\t' read -r idx url <<<"$row"
  bt "$BT_BUNDLE" select "$win" 1 > /dev/null
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  # The two rows are identical in the list, so the top one is whichever the ranking put first, and
  # requiring a particular one of them would be testing the matcher rather than the switch.
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name" "tab"
}

# The same page open in two different windows. This is genuinely ambiguous at the accessibility
# layer, and the tool is supposed to fall back to raising the application rather than guessing, so
# only the tab selection is required here.
case_duplicate_two_windows_arrange() {
  local name win other row idx url addr
  name=$(bt_uniq)
  win=$(bt_first_window "$BT_BUNDLE")
  other=$(bt_other_window "$BT_BUNDLE" "$win")
  [ -n "$other" ] || { bt_skip "this browser has only one window open"; return; }
  addr=$(bt_fx page.html "$name")
  row=$(bt_open_fixture "$BT_BUNDLE" "$win" "$addr" "$name") || { bt_skip "the fixture never loaded"; return; }
  bt "$BT_BUNDLE" open "$other" "$addr" > /dev/null
  sleep 1.2
  IFS=$'\t' read -r idx url <<<"$row"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name" "tab"
}

# A page that renames itself after the listing was taken. The tab title the tool remembered is now
# wrong, so anything that depends on it alone fails, and the window name read at the moment of the
# switch is what has to carry it.
case_retitles_on_load_arrange() {
  local name win row idx url
  name=$(bt_uniq)
  win=$(bt_first_window "$BT_BUNDLE")
  [ -n "$win" ] || { bt_skip "the browser has no window"; return; }
  bt "$BT_BUNDLE" open "$win" "$(bt_fx slow.html "$name" "&wait=6000")" > /dev/null
  local waited=0
  while [ "$waited" -lt 50 ]; do
    row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
      '.windows[] | select(.id == $w) | .tabs[] | select(.title == ($n + " loading")) | "\(.index)\t\(.url)"' | head -1)
    [ -n "$row" ] && break
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  [ -n "$row" ] || { bt_skip "the slow fixture never loaded"; return; }
  IFS=$'\t' read -r idx url <<<"$row"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.4
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

#-------------------------------------------------------------------------------
# States no script can create
#-------------------------------------------------------------------------------

# A discarded tab. Chrome exposes no discard flag over Apple Events, so the tab is pushed out
# through the discard page and the proof that it really was discarded is behavioural. A discarded
# tab reloads when it is selected, and a reload renames it, so the fixture that renames itself on
# load is both the bait and the evidence.
# It is a check rather than a plain round because passing is not enough here. The round has to be
# shown to have actually happened against a discarded tab, and the only proof available is
# behavioural. A discarded tab reloads the moment it is selected, and the fixture renames itself
# from loading to settled three seconds after each load, so finding it back on loading right after
# the switch is proof that it really did reload and therefore really was discarded. Finding it
# still settled means it was never pushed out, and that is reported as not covered rather than as a
# pass, since a pass would be claiming a state the round never reached.
case_discarded_check() {
  local name win row idx url target reason title
  name=$(bt_uniq)
  win=$(bt_first_window "$BT_BUNDLE")
  [ -n "$win" ] || { printf 'skip the browser has no window'; return 1; }
  bt "$BT_BUNDLE" open "$win" "$(bt_fx slow.html "$name" "&wait=3000")" > /dev/null
  local waited=0
  while [ "$waited" -lt 80 ]; do
    row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
      '.windows[] | select(.id == $w) | .tabs[] | select(.title == ($n + " settled")) | "\(.index)\t\(.url)"' | head -1)
    [ -n "$row" ] && break
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  [ -n "$row" ] || { printf 'skip the fixture never settled'; return 1; }
  IFS=$'\t' read -r idx url <<<"$row"

  bt_force_discard "$BT_BUNDLE" || { printf 'skip %s' "$BT_DISCARD_REASON"; return 1; }

  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  target=$(bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name")
  reason=$(round "$target" "")
  [ $? -eq 0 ] || { printf '%s' "$reason"; return 1; }

  title=$(bt "$BT_BUNDLE" front | jq -r '.window.tabs[(.window.activeTabIndex - 1)].title // ""')
  case $title in
    *loading*) return 0 ;;
    *) printf 'skip the tab never reloaded, so Chrome had not discarded it and this state was not reached' ; return 1 ;;
  esac
}

# Push every background tab out of memory through Chrome's own discard page, then close the page
# again. Pressing the control goes through the harness agent rather than through System Events,
# because Chrome keeps the contents of a page out of the accessibility tree until an assistive
# technology asks for it, and the agent knows how to ask.
# It answers with the reason on failure rather than only a status, because a suite that says a state
# was not reached and cannot say why is asking the next person to redo the whole investigation.
BT_DISCARD_REASON=""
bt_force_discard() {
  local bundle=$1 win pressed blocked
  BT_DISCARD_REASON="Chrome would not discard the tab"
  win=$(bt_open_window "$bundle" "chrome://discards/")
  [ -n "$win" ] || { BT_DISCARD_REASON="a window for the discard page could not be opened"; return 1; }
  sleep 2
  osascript -e "tell application id \"$bundle\" to activate" > /dev/null 2>&1
  sleep 1

  # This machine's Chrome is managed, and a managed Chrome can have its internal pages switched off
  # entirely, which looks identical to a button that simply is not there. Asking which it is turns a
  # useless result into a final one.
  blocked=$(hs_cmd axfind "bundleID=$bundle" "name=internal debugging pages" | jq -r '.found')
  if [ "$blocked" = "true" ]; then
    BT_DISCARD_REASON="Chrome has internal debugging pages disabled by policy on this machine, so a tab cannot be forced out of memory by any means available here"
    bt "$bundle" closewin "$win" > /dev/null
    return 1
  fi

  pressed=$(hs_cmd press "bundleID=$bundle" "name=urgent discard all" | jq -r '.pressed')
  sleep 2.5
  bt "$bundle" closewin "$win" > /dev/null
  sleep 0.8
  [ "$pressed" = "true" ]
}

# A pinned tab. Safari can pin through its own menu, Chrome only through a context menu that is not
# worth driving, so Chrome is left out of this case rather than faked.
case_pinned_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  bt "$BT_BUNDLE" raise "$win" > /dev/null
  bt "$BT_BUNDLE" select "$win" "$idx" > /dev/null
  osascript -e "tell application id \"$BT_BUNDLE\" to activate" > /dev/null 2>&1
  sleep 0.6
  osascript -e 'tell application "System Events" to tell process "Safari" to click menu item "Pin Tab" of menu 1 of menu bar item "Window" of menu bar 1' > /dev/null 2>&1 || {
    bt_skip "Safari would not pin the tab"; return; }
  sleep 1
  # Pinning moves the tab to the front of the window, so where it is has to be read again.
  local row
  row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
    '.windows[] | select(.id == $w) | .tabs[] | select(.title == $n) | "\(.index)\t\(.url)"' | head -1)
  [ -n "$row" ] || { bt_skip "the tab vanished after pinning"; return; }
  IFS=$'\t' read -r idx url <<<"$row"
  bt "$BT_BUNDLE" select "$win" 1 > /dev/null
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# A tab in a Safari tab group, which is the state that made matching on the tab title fail, since
# Safari names the window after the group as well as the page. Tab groups cannot be created by
# script, so this uses one that already exists and says so when there is none.
case_tab_group_arrange() {
  local proc win axname own
  proc=$(bt_process_name "$BT_BUNDLE")
  # A window in a group is one whose accessibility name is not simply its selected tab's title.
  own=$(bt "$BT_BUNDLE" front)
  win=$(jq -r '.window.id // ""' <<<"$own")
  local title; title=$(jq -r '.window.tabs[(.window.activeTabIndex - 1)].title // ""' <<<"$own")
  axname=$(bt_ax "$BT_BUNDLE" | jq -r '.window.name // ""')
  [ -n "$win" ] || { bt_skip "Safari has no window"; return; }
  if [ "$axname" = "$title" ] || [ -z "$axname" ]; then
    bt_skip "no Safari window is in a tab group, so this state does not exist here"
    return
  fi
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  local w2 idx url name
  IFS=$'\t' read -r w2 idx url name <<<"$s"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$w2" "$idx" "$url" "$name"
}

#-------------------------------------------------------------------------------
# Drift between the listing and the choice
#-------------------------------------------------------------------------------

# Every disturbance reads the target it was handed rather than a variable the arrange set, because
# an arrange runs in a subshell and anything it assigns is gone by the time the disturbance runs.
bt_target_field() {
  jq -r ".$1" <<<"$BT_TARGET"
}

# A tab appears before the target after the list was taken, so every number after it has moved by
# one and the position the tool recorded now points at the tab next door.
case_drift_tab_inserted_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  local win idx url name
  IFS=$'\t' read -r win idx url name <<<"$s"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

case_drift_tab_inserted_disturb() {
  bt "$BT_BUNDLE" insert "$(bt_target_field windowID)" 1 "$(bt_fx page.html "$(bt_uniq)")"
  sleep 0.8
}

case_drift_tab_closed_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  local win idx url name row
  IFS=$'\t' read -r win idx url name <<<"$s"
  # A tab of ours to close, placed before the target so closing it moves the target.
  bt "$BT_BUNDLE" insert "$win" 1 "$(bt_fx page.html "$(bt_uniq)")" > /dev/null
  sleep 1
  row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
    '.windows[] | select(.id == $w) | .tabs[] | select(.title == $n) | "\(.index)\t\(.url)"' | head -1)
  [ -n "$row" ] || { bt_skip "the target moved out of sight during setup"; return; }
  IFS=$'\t' read -r idx url <<<"$row"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

# The tab to close is looked up by the marker rather than assumed to still be at the position the
# arrange put it. It was assumed once, the insert that was meant to put it there had failed without
# anybody checking, and the position held a real page of the person's instead. Closing it emptied
# the window and the browser closed the window with it.
case_drift_tab_closed_disturb() {
  local win want idx
  win=$(bt_target_field windowID)
  want=$(bt_target_field url)
  # Ours, in the target's window, before the target, and not the target itself. Closing it is what
  # moves every position after it, which is the whole point of the case.
  idx=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg m "$BT_MARK" --arg u "$want" \
    '.windows[] | select(.id == $w) | . as $win
     | ([$win.tabs[] | select(.url == $u) | .index] | first) as $t
     | $win.tabs[] | select((.url // "") | contains($m)) | select(.url != $u)
     | select($t == null or .index < $t) | .index' | head -1)
  [ -n "$idx" ] && bt "$BT_BUNDLE" close "$win" "$idx" "$BT_MARK"
  sleep 0.8
}

# The window order changes between the listing and the choice, which is exactly what a positional
# window reference cannot survive and is why the window is addressed by its own id.
case_drift_window_reordered_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  local win idx url name
  IFS=$'\t' read -r win idx url name <<<"$s"
  [ -n "$(bt_other_window "$BT_BUNDLE" "$win")" ] || { bt_skip "this browser has only one window open"; return; }
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name"
}

case_drift_window_reordered_disturb() {
  local win other
  win=$(bt_target_field windowID)
  other=$(bt_other_window "$BT_BUNDLE" "$win")
  bt "$BT_BUNDLE" raise "$other"
  sleep 0.5
}

# The tab is dragged into another window after the listing. The window the tool recorded no longer
# holds it, and no amount of checking inside that window can recover it, so what matters is that
# the tab still ends up selected and in front rather than something else being opened in its place.
case_drift_tab_moved_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  local win idx url name
  IFS=$'\t' read -r win idx url name <<<"$s"
  [ -n "$(bt_other_window "$BT_BUNDLE" "$win")" ] || { bt_skip "this browser has only one window open"; return; }
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name" "tab"
}

case_drift_tab_moved_disturb() {
  local win other
  win=$(bt_target_field windowID)
  other=$(bt_other_window "$BT_BUNDLE" "$win")
  bt "$BT_BUNDLE" move "$win" "$(bt_target_field tabIndex)" "$other"
  sleep 0.8
}

# The target's whole window is closed before the choice lands. Nothing can succeed here, so the
# requirement is only that it fails quietly, without raising some other window as though it had
# worked and without taking the tool down.
case_drift_window_closed_arrange() {
  local name win row idx url
  name=$(bt_uniq)
  win=$(bt_open_window "$BT_BUNDLE" "$(bt_fx page.html "$name")")
  [ -n "$win" ] || { bt_skip "a window could not be opened for this case"; return; }
  sleep 1.5
  row=$(bt "$BT_BUNDLE" list | jq -r --arg w "$win" --arg n "$name" \
    '.windows[] | select(.id == $w) | .tabs[] | select(.title == $n) | "\(.index)\t\(.url)"' | head -1)
  [ -n "$row" ] || { bt_skip "the throwaway window never loaded"; return; }
  IFS=$'\t' read -r idx url <<<"$row"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name" "nocrash"
}

case_drift_window_closed_disturb() {
  bt "$BT_BUNDLE" closewin "$(bt_target_field windowID)"
  sleep 0.8
}

#-------------------------------------------------------------------------------
# The listing itself
#-------------------------------------------------------------------------------

# Safari keeps a window with no document that is not on screen and is invisible to the
# accessibility layer. A row for it can be chosen and nothing can possibly happen, which is one of
# the ways this tool looked broken, so no row may name it.
case_phantom_not_listed_check() {
  local phantom listing
  phantom=$(bt "$BT_BUNDLE" list | jq -r '[.windows[] | select(.document == false) | .id] | join(" ")')
  if [ -z "$phantom" ]; then
    printf 'skip Safari has no document free window right now, so there is nothing to filter'
    return 1
  fi
  listing=$(hs_cmd listing)
  local w found=""
  for w in $phantom; do
    if [ "$(jq -r --arg w "$w" '[.rows[] | select(.windowID == $w)] | length' <<<"$listing")" != "0" ]; then
      found="$found $w"
    fi
  done
  if [ -n "$found" ]; then
    printf 'the list still offers rows for the phantom window%s' "$found"
    return 1
  fi
  return 0
}

# A browser that is not running must never be started by a listing, since being asked what tabs are
# open is not a reason to open a browser.
case_not_running_check() {
  if [ "$(bt_running "$BT_BUNDLE")" = "true" ]; then
    printf 'skip %s is running, so this case has nothing to prove' "$BT_BROWSER"
    return 1
  fi
  hs_cmd listing > /dev/null
  sleep 1
  if [ "$(bt_running "$BT_BUNDLE")" = "true" ]; then
    printf 'listing the tabs started %s' "$BT_BROWSER"
    return 1
  fi
  return 0
}

# A browser switched off contributes nothing to the list. The setting is put back before this
# returns, whether it passed or not.
case_switched_off_check() {
  local before after reason=""
  before=$(hs_cmd enabled "bundleID=$BT_BUNDLE" | jq -r '.enabled')
  [ "$before" = "true" ] || { printf 'skip %s is already switched off' "$BT_BROWSER"; return 1; }

  hs_cmd enabled "bundleID=$BT_BUNDLE" "on=0" > /dev/null
  sleep 0.3
  local n
  n=$(hs_cmd listing | jq -r --arg b "$BT_BUNDLE" '[.rows[] | select(.bundleID == $b)] | length')
  [ "$n" = "0" ] || reason="the list still carried $n tabs from a browser that is switched off"

  hs_cmd enabled "bundleID=$BT_BUNDLE" "on=1" > /dev/null
  sleep 0.3
  [ "$(hs_cmd enabled "bundleID=$BT_BUNDLE" | jq -r '.enabled')" = "true" ] || \
    reason="$reason the browser could not be switched back on"

  [ -n "$reason" ] && { printf '%s' "$reason"; return 1; }
  return 0
}

#-------------------------------------------------------------------------------
# The way the list is driven
#-------------------------------------------------------------------------------

# Two browsers one after another with nothing allowed to settle in between, which is where the
# application lookup used to come back empty.
case_back_to_back_check() {
  local reason=""
  if [ "$(bt_running com.apple.Safari)" != "true" ]; then
    printf 'skip Safari is not running, so there is no second browser to follow with'
    return 1
  fi
  local saved_bundle=$BT_BUNDLE
  local a b

  BT_BUNDLE=com.google.Chrome
  a=$(case_frontmost_arrange)
  BT_BUNDLE=com.apple.Safari
  b=$(case_frontmost_arrange)

  BT_BUNDLE=com.google.Chrome
  reason=$(round "$a" "")
  [ $? -eq 0 ] || reason="the first round failed, $reason"
  if [ -z "$reason" ]; then
    BT_BUNDLE=com.apple.Safari
    reason=$(round "$b" "")
    [ $? -eq 0 ] || reason="the second round failed, $reason"
  fi

  BT_BUNDLE=$saved_bundle
  [ -n "$reason" ] && { printf '%s' "$reason"; return 1; }
  return 0
}

# Escape must leave everything exactly where it was.
case_escape_raises_nothing_check() {
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  hs_cmd chord "key=w" "hold=0.12" > /dev/null
  hs_wait_showing true || { printf 'the shortcut did not open the list'; return 1; }
  hs_cmd key "name=escape" > /dev/null
  sleep 0.8
  local front
  front=$(bt_ax "$BT_BUNDLE" | jq -r '.front.bundleID // ""')
  if [ "$front" = "$BT_BUNDLE" ]; then
    printf 'closing the list without choosing brought the browser forward anyway'
    return 1
  fi
  return 0
}

# No query at all, the top row taken with a bare Return. This is the path that skips the matcher
# entirely.
#
# Getting a known tab onto the top row is the whole arrangement, and it used to be done by
# selecting the tab and activating the browser, because the order was observed and that is what it
# followed. Nothing done inside a browser moves the order now, so the arrangement asks for what it
# wants directly. Two tabs are recorded rather than one so the check proves the order ranks two
# remembered tabs against each other rather than only floating a remembered one above untouched
# ones. The most recently touched is the top row, which is this tool's whole ordering rule.
#
# This sentence used to say the top row was the second most recently opened, because the tab you
# are on sits below the one you came from. That described a demotion which was removed from the
# tool before this was written, so the case has been failing every round on both browsers ever
# since, and the failure was read as a defect in the switcher rather than a stale expectation.
case_no_query_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"

  # Any other tab of this browser, recorded BEFORE the fixture so the fixture outranks it. Its own
  # row is never chosen, it only has to exist and be remembered, so that the check is about two
  # remembered tabs rather than a remembered one against untouched ones.
  local other
  other=$(bt "$BT_BUNDLE" list | jq -r --arg u "$url" \
    '[.windows[].tabs[] | select(.url != $u) | .url] | .[0] // ""')
  [ -n "$other" ] || { bt_skip "this browser holds only the fixture tab, so there is no second one to record"; return; }

  # The fixture is touched SECOND so it is the most recently opened, because that is the only
  # ordering rule this tool has. It used to be touched first, on the strength of a demotion that
  # swapped the top two rows so the switcher never spent its best position on the tab you were
  # already looking at. That demotion was built, found wrong in use and deliberately removed, and
  # the reasoning is in the CLAUDE.md beside this suite under the last tab you opened leads. This
  # case kept asserting it for long enough to fail every round on both browsers and on untouched
  # main, and to be mistaken for a defect in the tool rather than a stale expectation here.
  #
  # The other tab is still touched, and first, which makes this a stronger check than touching the
  # fixture alone. It proves the order actually ranks two remembered tabs against each other rather
  # than merely floating a remembered one above untouched ones.
  hs_cmd touch "bundleID=$BT_BUNDLE" "url=$other" > /dev/null
  hs_cmd touch "bundleID=$BT_BUNDLE" "url=$url" > /dev/null

  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.8
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" ""
}

# The leader held long enough that the cheat sheet comes up first, so the list has to open over it.
case_slow_press_arrange() {
  local s; s=$(bt_simple_target "$BT_BUNDLE") || { printf '%s' "$s"; return; }
  IFS=$'\t' read -r win idx url name <<<"$s"
  osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
  sleep 0.5
  bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$name" "full" "1.1"
}

# A tab this suite did not open, chosen out of what was already there. Everything else here is
# built from fixtures, which is what makes it repeatable, and this is the one case that keeps the
# suite honest about real pages with real titles.
# A real page title is not guaranteed to bring its own row to the top, because other tabs can score
# better on the same words and a site that opens several pages often gives them near identical
# names. That is the matcher behaving correctly, so rather than assert something untrue this walks
# candidates until it finds one whose title does put its own row first, and says so when none does.
case_existing_user_tab_arrange() {
  local candidates pick win idx url title
  candidates=$(bt "$BT_BUNDLE" list | jq -r --arg m "$BT_MARK" '
    [ .windows[] as $w | $w.tabs[]
      | select((.url // "") | contains($m) | not)
      | select((.title // "") | length > 10)
      # Plain ASCII only. A real page title is full of dashes, bullets and curly quotes, and what
      # reaches the field when one of those is typed is not reliably the character that was asked
      # for, so the query and the ranking this case checked against would be about different text.
      | select((.title // "") | test("^[ -~]+$"))
      | {win: $w.id, idx: .index, url: .url, title: .title} ]
    | sort_by(- (.title | length))
    | .[] | "\(.win)\t\(.idx)\t\(.url)\t\(.title)"')
  [ -n "$candidates" ] || { bt_skip "there is no ordinary tab to pick"; return; }

  hs_cmd listing > /dev/null
  local tried=0 query
  while IFS=$'\t' read -r win idx url title; do
    [ -n "$title" ] || continue
    tried=$(( tried + 1 ))
    [ "$tried" -gt 25 ] && break
    # A few words rather than the whole title, which is both what a person actually types and what
    # the matcher is built for. Handing it a title sixty characters long returned nothing at all.
    query=${title:0:22}
    # This one candidate check asks for a query that matches exactly one row, which the suite
    # deliberately does not ask for anywhere else. A real page title often scores identically to
    # several other tabs from the same site, ties are broken by position in the listing, and that
    # listing reorders itself by recency as the suite runs. So a tie that put this tab first when
    # the candidate was chosen can put another first a second later, and the round then opens a tab
    # nobody asked for through no fault of the tool. The point of this case is a real page rather
    # than a fixture, not an ambiguous query, so the ambiguity is excluded rather than tolerated.
    if [ "$(hs_cmd rows "query=$query" "n=3" | jq -r 'if (.rows | length) == 1 then .rows[0].url else "" end')" = "$url" ]; then
      osascript -e 'tell application "Finder" to activate' > /dev/null 2>&1
      sleep 0.5
      bt_target "$BT_BUNDLE" "$win" "$idx" "$url" "$query"
      return
    fi
  done <<<"$candidates"
  bt_skip "no ordinary tab here is distinctive enough in its first few words to reach the top row"
}
