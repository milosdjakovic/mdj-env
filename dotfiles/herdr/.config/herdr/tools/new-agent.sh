#!/usr/bin/env bash
# Starts a coding agent of the given kind in a new pane beside the given one, under the given
# name, in the given directory. herdr does this in two calls, a split and an agent start, and
# the second refuses a pane whose shell is not yet at its prompt, which a pane split a moment
# ago never is. So the start is retried while herdr gives that one answer, for up to ten
# seconds, and any other answer is the error.
#
#   new-agent.sh <beside pane> <cwd> <name> <kind>
set -u
HERDR="${HERDR_BIN_PATH:-herdr}"

pane=$("$HERDR" pane split "$1" --direction right --cwd "$2" --focus | jq -r '.result.pane.pane_id // empty')
[ -n "$pane" ] || exit 1

for _ in $(seq 40); do
  out=$("$HERDR" agent start "$3" --kind "$4" --pane "$pane" 2>&1) && exit 0
  case "$out" in
    *"not an available shell"*) sleep 0.25 ;;
    *) printf '%s\n' "$out" >&2; exit 1 ;;
  esac
done
printf '%s\n' "$out" >&2
exit 1
