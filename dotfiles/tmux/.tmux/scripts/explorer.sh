#!/usr/bin/env bash
# File explorer interface, used by the prefix+b binding, by the launcher, and by
# the tag picker.
#
# This file is the whole interface and it is deliberately rigid. It never names
# an explorer. It asks the active adapter for normalized values and runs them
# the same way for any explorer. All explorer specifics live in
# explorer/<adapter>.sh, which must define explorer_name, explorer_argv,
# explorer_needs_nested_session, and explorer_tags. See explorer/_template.sh.
#
# Called as:
#   explorer.sh --name           the label, for wherever the explorer is named
#   explorer.sh --open [dir]     resume it, or start it at dir, default $PWD
#   explorer.sh --reveal <path>  start it showing path, a file or a directory
#   explorer.sh --tags           every tagged path, one per line

DIR="$(dirname "$0")"
EXPLORER_ADAPTER="${EXPLORER_ADAPTER:-lf}"

if [ ! -r "$DIR/explorer/$EXPLORER_ADAPTER.sh" ]; then
  echo "explorer adapter not found: $DIR/explorer/$EXPLORER_ADAPTER.sh" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$DIR/explorer/$EXPLORER_ADAPTER.sh"

# Name of the nested tmux session the explorer runs inside. One fixed name, so
# reopening the popup attaches to the session already there and the explorer
# keeps its place.
SESSION='~files'

# Run the explorer in the terminal the popup already gave us. An explorer that
# opens sub-popups gets wrapped in a nested tmux session first, because a popup
# has no real pane and a second display-popup from inside one would target the
# outer client instead. A target is handed to the explorer as its trailing
# argument, which is why the contract asks an adapter for a command that accepts
# an optional path.
run() {
  local dir="$1" target="$2"
  local -a argv=()
  while IFS= read -r word; do argv+=("$word"); done < <(explorer_argv)
  [ -n "$target" ] && argv+=("$target")

  if explorer_needs_nested_session; then
    exec tmux new-session -A -s "$SESSION" -c "$dir" "${argv[@]}" ';' set status off
  fi
  cd "$dir" || exit 1
  exec "${argv[@]}"
}

# Resume the explorer where it was left, or start it here when nothing is
# running. This is what the plain binding does, and the kept place is the point.
open() { run "${1:-$PWD}" ""; }

# Start the explorer showing one path, the containing directory when the path is
# a file, with the file itself selected. Any running session is killed first,
# because tmux new-session -A attaches to an existing session and ignores both
# the working directory and the command, so reusing it would land the explorer
# wherever it was last left rather than on the path that was asked for. Being
# taken somewhere specific is the whole request here, so the kept place loses.
reveal() {
  local target="$1" dir
  [ -z "$target" ] && { open; return; }
  if [ -d "$target" ]; then dir="$target"; else dir="$(dirname "$target")"; fi
  explorer_needs_nested_session && tmux kill-session -t "$SESSION" 2>/dev/null
  run "$dir" "$target"
}

case "$1" in
  --name)   explorer_name; exit 0;;
  --open)   open "$2";;
  --reveal) reveal "$2";;
  --tags)   explorer_tags; exit 0;;
  *)        echo "usage: $0 --name | --open [dir] | --reveal <path> | --tags" >&2; exit 1;;
esac
