#!/usr/bin/env bash
# The runner. It knows how to put the tool through one round and how to judge the result, and it
# knows no case by name. Every case lives in cases.sh as data, which is what keeps adding one to a
# single function there rather than an edit here.
#
# A round is always the whole path. The real leader chord, the real chooser, a real query typed
# into it and a real Return. Driving the engine directly was tried and rejected, because three of
# the four defects this suite guards against were not in the engine, and a suite that cannot see
# them is worse than none for being reassuring.
#
# A round is judged by two witnesses that do not share an implementation. The browser's own
# dictionary says which window it has in front and which tab that window is showing. System
# Events, in a separate process, says which application is frontmost and which window the
# accessibility layer has in front. The tool writes to both layers and reads back through only one
# of them, so agreeing with itself is not evidence and only the pair is.

set -o pipefail

BT_TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export BT_TEST_DIR

# shellcheck source=lib/hs.sh
source "$BT_TEST_DIR/lib/hs.sh"
# shellcheck source=lib/browser.sh
source "$BT_TEST_DIR/lib/browser.sh"
# shellcheck source=lib/state.sh
source "$BT_TEST_DIR/lib/state.sh"

HS_REPLY_DIR=${TMPDIR:-/tmp}/browsertabs-test.$$
export HS_REPLY_DIR
mkdir -p "$HS_REPLY_DIR"

RESULT_DIR=$BT_TEST_DIR/results
mkdir -p "$RESULT_DIR"
RUN_LOG=$RESULT_DIR/last-run.log
: > "$RUN_LOG"

ONLY=""
REPS_OVERRIDE=""
LIST_ONLY=""
while [ $# -gt 0 ]; do
  case $1 in
    --only) ONLY=$2; shift 2 ;;
    --reps) REPS_OVERRIDE=$2; shift 2 ;;
    # One pass of everything, dropping the repeats and the two cases that spend most of their time
    # waiting on animation or on a state this machine cannot reach anyway. Roughly a third of the
    # full run. Use it while working on a change and the full one before merging, since the repeats
    # exist for the cases that were genuinely flaky and one pass proves least about exactly those.
    --quick) REPS_OVERRIDE=1; QUICK=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    *) printf 'unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

PASSED=0
FAILED=0
SKIPPED=0
declare -a FAILURES=()
declare -a SKIPS=()

say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$RUN_LOG"; }
note() { printf '%s\n' "$*" >> "$RUN_LOG"; }

#-------------------------------------------------------------------------------
# Judging a round
#-------------------------------------------------------------------------------

# The frames two layers report for the same window, compared with a small tolerance. They have
# matched exactly every time so far, but a window manager that rounds a coordinate should not read
# as the tool putting the wrong window in front.
frames_agree() {
  local ax=$1 own=$2 tol=4
  local axx axy axw axh ox oy ow oh
  axx=$(jq -r '.window.position.x // "x"' <<<"$ax")
  axy=$(jq -r '.window.position.y // "x"' <<<"$ax")
  axw=$(jq -r '.window.size.w // "x"' <<<"$ax")
  axh=$(jq -r '.window.size.h // "x"' <<<"$ax")
  ox=$(jq -r '.window.bounds.x // "y"' <<<"$own")
  oy=$(jq -r '.window.bounds.y // "y"' <<<"$own")
  ow=$(jq -r '.window.bounds.w // "y"' <<<"$own")
  oh=$(jq -r '.window.bounds.h // "y"' <<<"$own")
  local a b
  for pair in "$axx $ox" "$axy $oy" "$axw $ow" "$axh $oh"; do
    a=${pair%% *}; b=${pair##* }
    case $a$b in *x*|*y*) return 1 ;; esac
    local d=$(( a - b )); [ "$d" -lt 0 ] && d=$(( -d ))
    [ "$d" -gt "$tol" ] && return 1
  done
  return 0
}

# Whether the accessibility layer and the browser are talking about the same window. The frame is
# the strong half, since it is a number and belongs to one window. It is not enough on its own,
# because two windows of the same browser are very often stacked at exactly the same size and
# position, so when the frame is shared the title has to break the tie. Containment rather than
# equality, since Chrome appends its own name and profile and Safari prefixes the tab group.
ax_agrees() {
  local ax=$1 own=$2
  frames_agree "$ax" "$own" || return 1

  local shared
  shared=$(jq --argjson b "$(jq -c '.window.bounds' <<<"$own")" \
    '[.windows[] | select(.position.x == $b.x and .position.y == $b.y and .size.w == $b.w and .size.h == $b.h)] | length' <<<"$ax")
  [ "${shared:-0}" -le 1 ] && return 0

  # The title is read from the browser now rather than from the listing, because a page that
  # finishes loading between the two retitles itself, and that is the tool behaving correctly.
  local want axname
  want=$(jq -r '.window.tabs[(.window.activeTabIndex - 1)].title // ""' <<<"$own")
  axname=$(jq -r '.window.name // ""' <<<"$ax")
  [ -z "$want" ] && return 0
  case $axname in *"$want"*) return 0 ;; esac
  return 1
}

# Judge one round. mode is full when the tool must land on exactly the right window, tab when only
# the tab selection is required because the window is genuinely ambiguous, and quiet when nothing
# should have moved at all.
judge() {
  local bundle=$1 wantWindow=$2 wantURL=$3 mode=$4
  local ax own frontBundle gotWindow gotURL reasons=""

  ax=$(bt_ax "$bundle")
  own=$(bt "$bundle" front)
  note "    ax   $(jq -c '{front, window: {name: .window.name, position: .window.position, size: .window.size}}' <<<"$ax" 2>/dev/null)"
  note "    own  $(jq -c '{id: .window.id, active: .window.activeTabIndex, url: .window.tabs[(.window.activeTabIndex - 1)].url}' <<<"$own" 2>/dev/null)"

  frontBundle=$(jq -r '.front.bundleID // ""' <<<"$ax")
  gotWindow=$(jq -r '.window.id // ""' <<<"$own")
  gotURL=$(jq -r '.window.tabs[(.window.activeTabIndex - 1)].url // ""' <<<"$own")

  if [ "$mode" = "quiet" ]; then
    [ "$frontBundle" = "$bundle" ] && reasons+="the browser was raised when nothing should have moved. "
    [ -n "$reasons" ] && { printf '%s' "$reasons"; return 1; }
    return 0
  fi

  # Nothing can succeed when the target is gone, so the requirement is that the tool survives it
  # and does not present some other window as though it had worked. The list must have closed, the
  # config must still be answering, and whatever is in front must not be a tab of ours pretending
  # to be the one that was asked for.
  if [ "$mode" = "nocrash" ]; then
    [ "$(hs_cmd ping | jq -r '.ok')" = "true" ] || reasons+="the config stopped answering. "
    [ "$(hs_cmd showing | jq -r '.showing')" = "false" ] || reasons+="the list stayed open. "
    [ "$gotURL" = "$wantURL" ] && reasons+="a tab that no longer exists was reported as selected. "
    [ -n "$reasons" ] && { printf '%s' "$reasons"; return 1; }
    return 0
  fi

  # The frontmost application is read twice when the first read is wrong, because the two ways it
  # can be wrong are not the same finding. A browser that never came forward is the tool failing.
  # A browser that came forward and then lost the front a second later is something else on the
  # machine taking it back, which was seen during the original investigation and never reproduced
  # deliberately. Saying which happened is the whole point of looking twice.
  if [ "$frontBundle" != "$bundle" ]; then
    sleep 1
    local later
    later=$(jq -r '.front.bundleID // ""' <<<"$(bt_ax "$bundle")")
    if [ "$later" = "$bundle" ]; then
      reasons+="the browser reached the front late, $frontBundle held it for a moment first. "
    else
      reasons+="the frontmost application was $frontBundle. "
    fi
  fi
  [ "$gotURL" = "$wantURL" ] || reasons+="the selected tab is $gotURL. "

  if [ "$mode" = "full" ]; then
    [ "$gotWindow" = "$wantWindow" ] || reasons+="the browser has window $gotWindow in front, not $wantWindow. "
    ax_agrees "$ax" "$own" || reasons+="the accessibility layer has a different window in front than the browser does. "
  fi

  [ -n "$reasons" ] && { printf '%s' "$reasons"; return 1; }
  return 0
}

#-------------------------------------------------------------------------------
# One round
#-------------------------------------------------------------------------------

# Everything between arranging the browser and judging the result. The case supplies a target and
# optionally a disturbance, and this drives the tool the way a person would.
# Whether the screen is locked, asked of the window server. The accessibility layer cannot be asked
# this, since it goes on answering questions about processes while returning no windows for any of
# them, which is indistinguishable from the tool having put nothing in front.
#
# Counted rather than matched quietly, because a quiet grep stops reading as soon as it finds the
# thing, the process feeding it dies of the broken pipe, and with pipefail the pipeline then reports
# failure exactly when the answer was yes.
screen_locked() {
  [ "$(ioreg -n Root -d1 -a 2>/dev/null | grep -c CGSSessionScreenIsLocked)" -gt 0 ]
}

round() {
  local target=$1 disturb=$2

  # Checked every round rather than once at the start. A run is long, the machine locks on its own
  # timer, and synthesised events do not count as somebody being there. Two rounds of a full run
  # were reported as the tool putting the wrong window in front when what had actually happened was
  # that the screen locked underneath them.
  if screen_locked; then
    printf 'the screen locked during this run, so nothing could be measured'
    return 1
  fi
  local bundle windowID tabIndex url query mode hold
  bundle=$(jq -r '.bundleID' <<<"$target")
  windowID=$(jq -r '.windowID' <<<"$target")
  tabIndex=$(jq -r '.tabIndex' <<<"$target")
  url=$(jq -r '.url' <<<"$target")
  query=$(jq -r '.query' <<<"$target")
  mode=$(jq -r '.mode // "full"' <<<"$target")
  hold=$(jq -r '.hold // "0.12"' <<<"$target")

  # A fresh listing before the list is even opened. The chooser keeps the previous one on screen
  # while a new one is in flight, which is the right behaviour for a person and a trap for a
  # harness, since rows read a moment after opening are the previous listing and do not contain
  # whatever the case just arranged. Waiting for this one to land removes the race rather than
  # sleeping through it.
  hs_cmd prepare > /dev/null

  # Open the list exactly as the shortcut does. A chord that does not open it is the tool failing,
  # not the harness, so it is reported as a failure of the round.
  hs_cmd chord "key=w" "hold=$hold" > /dev/null
  if ! hs_wait_showing true; then
    printf 'the shortcut did not open the list'
    return 1
  fi

  [ -n "$query" ] && hs_cmd type "text=$query" > /dev/null

  # Wait for the intended tab to actually reach the top of the ranking, rather than sleeping a
  # guessed interval and hoping. The chooser reloads again when it opens, so the ranking can change
  # under a round for a second after the query is typed.
  local waited=0 rows top
  while [ "$waited" -lt 40 ]; do
    rows=$(hs_cmd rows "query=$query" "n=3")
    top=$(jq -r '.rows[0].url // ""' <<<"$rows")
    [ "$top" = "$url" ] && break
    sleep 0.1
    waited=$(( waited + 1 ))
  done

  # The top row for this query is the precondition, since the top row is what Return takes. It is
  # not that the query matched one row only, because a fuzzy match over a hundred tabs always
  # matches many and requiring uniqueness made an earlier version abort every round.
  #
  # This asks for the ranking rather than asking the open chooser what it has highlighted, which was
  # tried and does not work. The chooser's selected row is only meaningful inside its own Return
  # handler, and read from outside it reports the first row of the unfiltered list however the list
  # is actually filtered. That reading was believed for one round of changes and it accused the tool
  # of opening tabs it had never been asked for, while a real Return in the same state opened the
  # right one every time. So the ranking is recomputed here, and the check that matters stays the
  # one after Return, where what actually opened is compared against what was asked for.
  note "    top  $(jq -c '[.rows[] | {title, url}]' <<<"$rows" 2>/dev/null)"
  if [ "$top" != "$url" ]; then
    hs_cmd key "name=escape" > /dev/null
    printf 'the intended tab was not the top row, the top row was %s' "$top"
    return 1
  fi

  # The disturbance goes here on purpose, after the tool has taken its listing and before the
  # choice is made, which is the window where a tab number or a window can go stale underneath it.
  #
  # It is handed the target rather than reading a variable the arrange set, because an arrange runs
  # inside a command substitution and anything it assigns dies with that subshell. When the
  # disturbances read such a variable they were silently disturbing nothing at all, and four drift
  # cases passed without ever testing drift.
  if [ -n "$disturb" ]; then
    BT_TARGET=$target "$disturb" > /dev/null
    sleep 0.3
  fi

  hs_cmd key "name=return" > /dev/null
  sleep 1.2

  judge "$bundle" "$windowID" "$url" "$mode"
}

#-------------------------------------------------------------------------------
# Cases
#-------------------------------------------------------------------------------

# shellcheck source=cases.sh
source "$BT_TEST_DIR/cases.sh"

if [ -n "$LIST_ONLY" ]; then
  for name in "${CASES[@]}"; do printf '%s\n' "$name"; done
  exit 0
fi

# A case is a name and the browser it runs against, so one case body covers both browsers and the
# list below is where the pairing is decided. A case that is meaningful for only one browser simply
# appears once.
run_case() {
  local name=$1
  local reps disturb target reason

  reps=$(bt_case_reps "$name")
  [ -n "$REPS_OVERRIDE" ] && reps=$REPS_OVERRIDE

  local i
  for (( i = 1; i <= reps; i++ )); do
    local label="$name on $BT_BROWSER"
    [ "$reps" -gt 1 ] && label="$label ($i of $reps)"
    note "  round $label"

    # A case that judges something other than one round, such as a listing or two rounds back to
    # back, brings its own check and answers the same way, empty for a pass and a reason for a
    # failure.
    if declare -F "case_${name}_check" > /dev/null; then
      reason=$("case_${name}_check" 2>>"$RUN_LOG")
      if [ $? -eq 0 ]; then
        say "  pass  $label"
        PASSED=$(( PASSED + 1 ))
      elif [ "${reason#skip }" != "$reason" ]; then
        say "  SKIP  $label, ${reason#skip }"
        SKIPPED=$(( SKIPPED + 1 ))
        SKIPS+=("$label, ${reason#skip }")
      else
        say "  FAIL  $label, $reason"
        FAILED=$(( FAILED + 1 ))
        FAILURES+=("$label, $reason")
      fi
      declare -F "case_${name}_cleanup" > /dev/null && "case_${name}_cleanup" > /dev/null
      bt_drop_ours "$BT_BUNDLE" > /dev/null
      continue
    fi

    target=$("case_${name}_arrange" 2>>"$RUN_LOG")
    reason=""
    if [ -z "$target" ]; then
      reason="the case could not be set up"
    else
      reason=$(jq -r '.skip // ""' <<<"$target" 2>/dev/null)
    fi
    if [ -n "$reason" ]; then
      say "  SKIP  $label, $reason"
      SKIPPED=$(( SKIPPED + 1 ))
      SKIPS+=("$label, $reason")
      return
    fi
    note "    want $(jq -c '{bundleID, windowID, tabIndex, url, mode}' <<<"$target")"

    disturb=""
    declare -F "case_${name}_disturb" > /dev/null && disturb="case_${name}_disturb"

    reason=$(round "$target" "$disturb")
    if [ $? -eq 0 ]; then
      say "  pass  $label"
      PASSED=$(( PASSED + 1 ))
    else
      say "  FAIL  $label, $reason"
      FAILED=$(( FAILED + 1 ))
      FAILURES+=("$label, $reason")
    fi

    declare -F "case_${name}_cleanup" > /dev/null && "case_${name}_cleanup" > /dev/null
    # Every page this round opened goes now rather than at the end, so a suite of thirty cases does
    # not leave a browser carrying sixty tabs by the time it reaches the last one.
    bt_drop_ours "$BT_BUNDLE" > /dev/null
  done
}

#-------------------------------------------------------------------------------
# Preflight, the suite, and putting the machine back
#-------------------------------------------------------------------------------

# Nothing here works behind a locked screen. The accessibility layer reports no windows for any
# application at all, so every round fails on its outside witness while the browser's own answers
# stay perfectly correct, which reads exactly like the tool putting the wrong window in front. A
# whole run was lost to that before this check existed. The display is also held awake for the
# duration, since a suite drives the machine with synthesised events and the idle timer does not
# count those as somebody being there.
# Asked of the window server rather than of the accessibility layer, since the accessibility layer
# is the thing that stops answering and cannot be trusted to report its own blindness. It goes on
# answering questions about processes quite happily while returning no windows for any of them.
say "checking the screen is awake"
if screen_locked; then
  say "the screen is locked, so the accessibility layer can see nothing and no round could mean anything"
  exit 1
fi

# Idle sleep, display sleep, and a standing assertion that somebody is here, which is the one that
# actually holds off the lock. Holding the display awake alone was not enough, since the lock runs
# off the idle timer and synthesised keystrokes do not reset it.
caffeinate -d -i -u -w $$ &
say "  awake, and held awake until this finishes"

say "checking the harness is live"
if [ "$(hs_cmd ping | jq -r '.ok')" != "true" ]; then
  say "the harness agent is not answering, is the marker in place and Hammerspoon pointed here"
  exit 1
fi
say "  config $(hs_cmd ping | jq -r '.config')"

# One chord that counts for nothing, because the first one after a config load has been seen to
# arrive before the tool is ready and a suite whose first case fails for that reason reports a
# defect that is not there.
say "  warming up"
hs_cmd chord "key=w" "hold=0.12" > /dev/null
hs_wait_showing true > /dev/null
hs_cmd key "name=escape" > /dev/null
sleep 0.5

bt_snapshot
trap 'bt_restore; rm -rf "$HS_REPLY_DIR"' EXIT

say ""
for entry in "${CASES[@]}"; do
  if [ -n "$ONLY" ] && [[ $entry != *$ONLY* ]]; then continue; fi
  if [ -n "${QUICK:-}" ]; then
    case $entry in fullscreen*|discarded*) continue ;; esac
  fi
  BT_BROWSER=${entry##* }
  BT_BUNDLE=$(bt_bundle_for "$BT_BROWSER")
  # A case that brings its own check decides for itself what state it needs, and one of them exists
  # precisely to prove that a closed browser stays closed, so the running check must not stand in
  # front of it.
  if declare -F "case_${entry% *}_check" > /dev/null; then
    run_case "${entry% *}"
    continue
  fi
  if [ "$(bt_running "$BT_BUNDLE")" != "true" ]; then
    say "  SKIP  ${entry% *} on $BT_BROWSER, it is not running and a suite must never launch a browser"
    SKIPPED=$(( SKIPPED + 1 ))
    SKIPS+=("${entry% *} on $BT_BROWSER, not running")
    continue
  fi
  run_case "${entry% *}"
done

say ""
say "passed $PASSED, failed $FAILED, skipped $SKIPPED"
if [ ${#FAILURES[@]} -gt 0 ]; then
  say ""
  say "failures"
  for f in "${FAILURES[@]}"; do say "  $f"; done
fi
if [ ${#SKIPS[@]} -gt 0 ]; then
  say ""
  say "not covered"
  for s in "${SKIPS[@]}"; do say "  $s"; done
fi
say ""
say "the full witness record is in $RUN_LOG"

[ "$FAILED" -eq 0 ]
