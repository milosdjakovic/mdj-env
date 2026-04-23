#!/usr/bin/env bash
# File/folder search with fzf, copies selected path to clipboard
# Defaults to $PWD, which the caller sets via display-popup -d
# (tmux formats do not expand inside the -E arg, so we rely on -d)
# Args (used during become() recursion): $1 = type (dirs/files), $2 = query

SCRIPT="$0"
SEARCH_DIR="${SEARCH_DIR:-$PWD}"
TYPE="${1:-dirs}"
QUERY="${2:-}"

export SEARCH_DIR

FD_ARGS="--hidden --exclude .git"
case "$TYPE" in
  dirs)  FD_ARGS="$FD_ARGS --type d";;
  files) FD_ARGS="$FD_ARGS --type f";;
esac

display_dir="${SEARCH_DIR/#$HOME/~}"

if [ "$TYPE" = "dirs" ]; then
  TOGGLE_TYPE="files"
  toggle_hint="^f files"
else
  TOGGLE_TYPE="dirs"
  toggle_hint="^f directories"
fi

HEADER="$display_dir
<enter> copy path | $toggle_hint"

result=$(fzf --reverse --no-mouse \
  --query="$QUERY" \
  --header="$HEADER" \
  --header-first \
  --bind "ctrl-f:become($SCRIPT $TOGGLE_TYPE {q})" \
  < <(fd $FD_ARGS . "$SEARCH_DIR"))

[ -n "$result" ] && printf '%s' "$result" | pbcopy
