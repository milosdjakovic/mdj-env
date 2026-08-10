#!/usr/bin/env bash
# Talking to the harness agent inside Hammerspoon.
#
# A command goes out as a file and the answer comes back as a file. Neither half of that is
# arbitrary and both were arrived at the hard way.
#
# The answer cannot come back through the Hammerspoon command line tool, because that tool blocks
# until the config finishes what it is doing, this one is asynchronous by nature so there is nearly
# always something in flight, and a call killed while blocked leaves the channel dead for the rest
# of the session. So the agent writes its answer to a file the runner is watching for.
#
# The command used to go out as a URL, and that was the single worst thing in this harness. Opening
# a URL goes through Launch Services, which takes focus, and focus is the very thing most of these
# rounds measure. It had already been caught once making typed characters land in the app underneath
# the list instead of in the list. It is also the likeliest explanation for the one failure of the
# last full run, where both witnesses agreed the tool had done its job and the terminal held the
# front. A harness may not disturb what it measures, so nothing here activates anything now. The
# runner drops a request file in a directory the agent polls, and the agent answers where the
# request told it to.
#
# The directory is derived from HOME on both sides rather than passed across, since the agent is
# loaded by Hammerspoon and has no way to be told anything at load. It sits under the caches
# directory, deliberately outside the watched config tree, the same reasoning the spoon's own Swift
# helper cache follows, because a file written inside that tree triggers a config reload.
BT_CHANNEL=${HOME}/Library/Caches/browsertabs-test/channel
# Made on both sides, since either may run first. The suite asks the agent whether it is alive
# before any runner has started, and the agent makes it at load whether or not a runner ever comes.
mkdir -p "$BT_CHANNEL"

# hs_cmd <command> [key=value ...] and the JSON answer on stdout. Every reply file is named for
# this shell and a counter, so two runners could not read each other's answers.
HS_REPLY_SEQ=0
hs_cmd() {
  local cmd=$1; shift
  HS_REPLY_SEQ=$(( HS_REPLY_SEQ + 1 ))
  local reply="$HS_REPLY_DIR/reply.$$.$HS_REPLY_SEQ.json"
  rm -f "$reply" "$reply.part"

  # Built in one jq rather than one per parameter, since this runs several times per round.
  local filter='{cmd:$cmd, reply:$reply}'
  local -a args=(--arg cmd "$cmd" --arg reply "$reply")
  local kv i=0
  for kv in "$@"; do
    i=$(( i + 1 ))
    args+=(--arg "k$i" "${kv%%=*}" --arg "v$i" "${kv#*=}")
    filter="$filter | .[\$k$i] = \$v$i"
  done

  # Written under a temporary name and renamed into place, so the agent polling this directory can
  # never pick up half a request. Rename is atomic on the same filesystem.
  local req="$BT_CHANNEL/req.$$.$HS_REPLY_SEQ.json"
  jq -nc "${args[@]}" "$filter" > "$req.part"
  mv "$req.part" "$req"

  local waited=0
  while [ "$waited" -lt 500 ]; do
    if [ -f "$reply" ]; then
      cat "$reply"
      rm -f "$reply"
      return 0
    fi
    sleep 0.02
    waited=$(( waited + 1 ))
  done
  printf '{"ok":false,"err":"the agent did not answer"}'
  return 1
}

# Wait for the chooser to be open, or give up. Returns non zero when it never opened, which is a
# real result rather than an error, since a chord that does not open the chooser is a failure of
# the thing under test.
hs_wait_showing() {
  local want=${1:-true} waited=0
  while [ "$waited" -lt 60 ]; do
    if [ "$(hs_cmd showing | jq -r '.showing')" = "$want" ]; then return 0; fi
    sleep 0.1
    waited=$(( waited + 1 ))
  done
  return 1
}
