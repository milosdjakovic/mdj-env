#!/usr/bin/env bash
# Recursive fzf finder for lf with two independent filter dimensions
# Args: $1 = type (all/dirs/files), $2 = scope (current/global), $3 = base dir, $4 = lf id

SCRIPT="$0"
TYPE="${1:-all}"
SCOPE="${2:-current}"
BASE_DIR="${3:-$PWD}"
LF_ID="$4"

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

HEADER="$scope_line  |  $type_line  |  ^y copy path  ^c copy path + close"

result=$(fd $FD_ARGS . "$SEARCH_DIR" | fzf --reverse --no-mouse \
  --header="$HEADER" \
  --header-first \
  --bind "esc:abort" \
  --bind "ctrl-y:execute-silent(printf '%s' {} | pbcopy)" \
  --bind "ctrl-c:execute-silent(printf '%s' {} | pbcopy)+abort" \
  --bind "ctrl-s:become($SCRIPT $TYPE current \"$BASE_DIR\" \"$LF_ID\")" \
  --bind "ctrl-a:become($SCRIPT $TYPE global \"$BASE_DIR\" \"$LF_ID\")" \
  --bind "ctrl-t:become($SCRIPT all $SCOPE \"$BASE_DIR\" \"$LF_ID\")" \
  --bind "ctrl-d:become($SCRIPT dirs $SCOPE \"$BASE_DIR\" \"$LF_ID\")" \
  --bind "ctrl-f:become($SCRIPT files $SCOPE \"$BASE_DIR\" \"$LF_ID\")")

if [ -n "$result" ] && [ -n "$LF_ID" ]; then
  if [ -d "$result" ]; then
    lf -remote "send $LF_ID cd \"$result\""
  else
    lf -remote "send $LF_ID select \"$result\""
  fi
fi
