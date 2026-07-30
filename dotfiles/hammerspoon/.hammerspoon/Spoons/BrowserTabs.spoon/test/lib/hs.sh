#!/usr/bin/env bash
# Talking to the harness agent inside Hammerspoon.
#
# A command goes out as a URL and the answer comes back in a file. That looks roundabout and it is
# deliberate. The Hammerspoon command line tool blocks until the config finishes what it is doing,
# this tool is asynchronous by nature so there is nearly always something in flight, and a call
# killed while blocked leaves the channel dead for the rest of the session. A URL is one way, so it
# cannot block, and the reply file carries the answer back.

# Percent encode a value for a query string. Written in bash rather than shelled out to python,
# because this runs several times per round and a round is already slow enough.
hs_urlencode() {
  local s=$1 out= c
  local i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9.~_-]) out+=$c ;;
      *) printf -v c '%%%02X' "'$c" ; out+=$c ;;
    esac
  done
  printf '%s' "$out"
}

# hs_cmd <command> [key=value ...] and the JSON answer on stdout. Every reply file is named for
# this shell and a counter, so two runners could not read each other's answers.
HS_REPLY_SEQ=0
hs_cmd() {
  local cmd=$1; shift
  HS_REPLY_SEQ=$(( HS_REPLY_SEQ + 1 ))
  local reply="$HS_REPLY_DIR/reply.$$.$HS_REPLY_SEQ.json"
  rm -f "$reply" "$reply.part"

  local url="hammerspoon://bttest?cmd=$(hs_urlencode "$cmd")&reply=$(hs_urlencode "$reply")"
  local kv
  for kv in "$@"; do
    url+="&$(hs_urlencode "${kv%%=*}")=$(hs_urlencode "${kv#*=}")"
  done

  # Opened in the background so asking Hammerspoon a question never takes the front away from the
  # browser the round is about, which would change the very thing being measured.
  open -g "$url"

  local waited=0
  while [ "$waited" -lt 120 ]; do
    if [ -f "$reply" ]; then
      cat "$reply"
      rm -f "$reply"
      return 0
    fi
    sleep 0.05
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
