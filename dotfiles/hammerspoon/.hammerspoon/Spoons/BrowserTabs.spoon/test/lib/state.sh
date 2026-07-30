#!/usr/bin/env bash
# Taking the machine as it was found and giving it back that way.
#
# This suite runs against whatever browsers are already open, with whatever the person had in them,
# because the faults it guards against only appear in a real window list. So it has to put things
# back, and putting things back honestly is harder than it sounds. A closed tab cannot be recreated
# and a window order cannot be recovered once lost.
#
# The rule that makes it tractable is that the suite never closes anything it did not open. Every
# page it opens is a local fixture carrying a marker in its address, so at the end anything with
# that marker goes and everything else stays. What is restored beyond that is the selected tab of
# each window, matched by address rather than by position since positions have moved, whether each
# window was minimized, the front to back order, and which application was in front.

# The marker every page this suite opens carries in its address.
BT_MARK="bttest=1"

# bt_open_window <bundle> <url> - open a window and remember that it was ours, answering with its id.
#
# Every window the suite opens has to go through here. Recognising one afterwards by its contents
# does not work, because what a new window contains is not the suite's to decide. Safari opens one
# on the person's own homepage, so a window this suite created is indistinguishable by its tabs from
# one of theirs, and the marker test that cleans up tabs quietly left eight of these behind across a
# few runs. An id written down at the moment of creation cannot be mistaken for anything else.
bt_open_window() {
  local b=$1 url=$2 id
  id=$(bt "$b" openwin "$url" | jq -r '.id // ""')
  [ -n "$id" ] || return 1
  printf '%s\n' "$id" >> "$HS_REPLY_DIR/created.$b"
  printf '%s' "$id"
}

BT_SNAP_DIR=""
BT_SNAP_FRONT=""

bt_snapshot() {
  BT_SNAP_DIR=$HS_REPLY_DIR/snapshot
  mkdir -p "$BT_SNAP_DIR"
  local b
  for b in "${BROWSERS[@]}"; do
    [ "$(bt_running "$b")" = "true" ] || continue
    bt "$b" list > "$BT_SNAP_DIR/$b.json"
  done
  BT_SNAP_FRONT=$(osascript -e 'tell application "System Events" to return bundle identifier of first application process whose frontmost is true' 2>/dev/null)

  # A copy that outlives the run, since the working one goes with the reply directory. Without it,
  # a question about what the browsers looked like beforehand has no answer once the suite has
  # finished, and that question does get asked.
  cp "$BT_SNAP_DIR"/*.json "$RESULT_DIR/" 2>/dev/null
  say "  snapshot taken, front was $BT_SNAP_FRONT"
}

# Close every window whose tabs are all ours, then every remaining tab of ours. In that order, so a
# window we opened goes in one step rather than tab by tab down to an empty shell.
#
# A window that existed when the snapshot was taken is never closed, whatever its tabs now say. That
# guard is here because it was needed. A window of the person's was navigated to a fixture page by a
# separate bug, which left it looking exactly like a window this suite had opened, and it was
# closed. The bug is fixed, and this stands behind it, because the cost of the two failing together
# is somebody's window and the cost of the guard is that a window the suite opened during a run that
# died halfway lives until the next one.
bt_drop_ours() {
  local b=$1 list wid snap created
  list=$(bt "$b" list)
  snap=$BT_SNAP_DIR/$b.json
  created=$HS_REPLY_DIR/created.$b

  # Windows this suite opened, by the ids it wrote down, plus any window left holding nothing but
  # our own pages. The written down ids are the reliable half and the tab test only catches what
  # slipped past them.
  for wid in $( { [ -f "$created" ] && cat "$created"
                  jq -r --arg m "$BT_MARK" '.windows[] | select((.tabs | length) > 0) | select(([.tabs[] | select((.url // "") | contains($m))] | length) == (.tabs | length)) | .id' <<<"$list"
                } | sort -u ); do
    if [ -f "$snap" ] && [ "$(jq -r --arg w "$wid" '[.windows[] | select(.id == $w)] | length' "$snap")" != "0" ]; then
      say "  leaving window $wid alone, it was open before this run started"
      continue
    fi
    bt "$b" closewin "$wid" > /dev/null
  done
  [ -f "$created" ] && : > "$created"

  # Re-read, since closing windows moved everything, and take the tabs highest index first so
  # closing one cannot shift the next one out from under us.
  list=$(bt "$b" list)
  local pair
  for pair in $(jq -r --arg m "$BT_MARK" '.windows[] as $w | $w.tabs[] | select((.url // "") | contains($m)) | "\($w.id):\(.index)"' <<<"$list" | sort -t: -k2 -rn); do
    bt "$b" close "${pair%%:*}" "${pair##*:}" "$BT_MARK" > /dev/null
  done
}

bt_restore() {
  [ -n "$BT_SNAP_DIR" ] || return 0
  say ""
  say "putting the browsers back"

  local b snap wid url
  for b in "${BROWSERS[@]}"; do
    snap=$BT_SNAP_DIR/$b.json
    [ -f "$snap" ] || continue
    [ "$(bt_running "$b")" = "true" ] || continue

    bt_drop_ours "$b"

    # The selected tab of each window, found by address because every index has moved.
    while IFS=$'\t' read -r wid url; do
      [ -n "$wid" ] || continue
      local idx
      idx=$(bt "$b" list | jq -r --arg w "$wid" --arg u "$url" '.windows[] | select(.id == $w) | .tabs[] | select(.url == $u) | .index' | head -1)
      [ -n "$idx" ] && bt "$b" select "$wid" "$idx" > /dev/null
    done < <(jq -r '.windows[] | select(.activeTabIndex > 0) | "\(.id)\t\(.tabs[(.activeTabIndex - 1)].url // "")"' "$snap")

    # Minimized state, then the front to back order, restored back to front so the window that was
    # first ends up first.
    while IFS=$'\t' read -r wid m; do
      [ -n "$wid" ] || continue
      bt "$b" minimize "$wid" "$([ "$m" = "true" ] && printf 1 || printf 0)" > /dev/null
    done < <(jq -r '.windows[] | "\(.id)\t\(.minimized)"' "$snap")

    for wid in $(jq -r '[.windows[].id] | reverse | .[]' "$snap"); do
      bt "$b" raise "$wid" > /dev/null
    done
  done

  if [ -n "$BT_SNAP_FRONT" ]; then
    osascript -e "tell application id \"$BT_SNAP_FRONT\" to activate" > /dev/null 2>&1
  fi
  say "  restored, front returned to $BT_SNAP_FRONT"
}
