#!/usr/bin/env bash
# Recursive fzf finder for lf with two independent filter dimensions
# Args: $1 = type (all/dirs/files), $2 = scope (current/global), $3 = base dir
# Returns the selected path to stdout

SCRIPT="$0"
TYPE="${1:-all}"
SCOPE="${2:-current}"
BASE_DIR="${3:-$PWD}"

# Build fd command based on type and scope
if [ "$SCOPE" = "global" ]; then
  SEARCH_DIR="$HOME"
else
  SEARCH_DIR="$BASE_DIR"
fi

FD_ARGS="--hidden --exclude .git"
case "$TYPE" in
  dirs)  FD_ARGS="$FD_ARGS --type d";;
  files) FD_ARGS="$FD_ARGS --type f";;
esac

LIST_CMD="fd $FD_ARGS . \"$SEARCH_DIR\""

# Build header showing both dimensions with active option in brackets
if [ "$SCOPE" = "current" ]; then
  scope_line="[current dir]  ^a global"
else
  scope_line="^s current dir  [global]"
fi

case "$TYPE" in
  all)   type_line="[all]  ^d dirs  ^f files";;
  dirs)  type_line="^t all  [dirs]  ^f files";;
  files) type_line="^t all  ^d dirs  [files]";;
esac

HEADER="$scope_line  |  $type_line"

# Run fd in background and kill it when fzf exits
tmpfifo=$(mktemp -u)
mkfifo "$tmpfifo"
eval "$LIST_CMD" > "$tmpfifo" 2>/dev/null &
FD_PID=$!

fzf --reverse \
  --header="$HEADER" \
  --header-first \
  --bind "esc:abort" \
  --bind "ctrl-s:become($SCRIPT $TYPE current \"$BASE_DIR\")" \
  --bind "ctrl-a:become($SCRIPT $TYPE global \"$BASE_DIR\")" \
  --bind "ctrl-t:become($SCRIPT all $SCOPE \"$BASE_DIR\")" \
  --bind "ctrl-d:become($SCRIPT dirs $SCOPE \"$BASE_DIR\")" \
  --bind "ctrl-f:become($SCRIPT files $SCOPE \"$BASE_DIR\")" < "$tmpfifo"

kill "$FD_PID" 2>/dev/null
wait "$FD_PID" 2>/dev/null
rm -f "$tmpfifo"
