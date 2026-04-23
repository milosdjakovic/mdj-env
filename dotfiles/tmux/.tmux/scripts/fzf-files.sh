#!/usr/bin/env bash
# File/folder search with fzf, copies selected path to clipboard.
# Defaults to $PWD (set by display-popup -d) because tmux formats
# do not expand inside the -E shell-command argument.
#
# Invocation patterns:
#   $1 = type (dirs|files), $2 = query      -- normal and ^f toggle
#   $1 = --down, $2 = path, $3 = next type  -- ^l descend
#   $1 = --up,   $2 = next type             -- ^h move one level up
#
# ^l on a directory enters it. ^l on a file jumps to its parent directory.
# The active type (dirs or files) is preserved across navigation.

SCRIPT="$0"

# Handle --down: resolve selected path against SEARCH_DIR. If it resolves
# to a file, use its parent directory. Preserves the requested type.
if [ "$1" = "--down" ]; then
  TARGET="$2"
  NEXT_TYPE="${3:-dirs}"
  BASE="${SEARCH_DIR:-$PWD}"
  case "$TARGET" in
    /*) RESOLVED="$TARGET";;
    *)  RESOLVED="$BASE/${TARGET#./}";;
  esac
  NEW_DIR=""
  if [ -d "$RESOLVED" ]; then
    NEW_DIR="$(cd "$RESOLVED" 2>/dev/null && pwd)"
  elif [ -f "$RESOLVED" ]; then
    NEW_DIR="$(cd "$(dirname "$RESOLVED")" 2>/dev/null && pwd)"
  fi
  [ -z "$NEW_DIR" ] && exit 0
  SEARCH_DIR="$NEW_DIR"
  export SEARCH_DIR
  exec "$SCRIPT" "$NEXT_TYPE"
fi

# Handle --up: move SEARCH_DIR one level up, preserving current type.
if [ "$1" = "--up" ]; then
  NEXT_TYPE="${2:-dirs}"
  PARENT="$(cd "${SEARCH_DIR:-$PWD}/.." 2>/dev/null && pwd)"
  [ -z "$PARENT" ] && exit 0
  SEARCH_DIR="$PARENT"
  export SEARCH_DIR
  exec "$SCRIPT" "$NEXT_TYPE"
fi

SEARCH_DIR="${SEARCH_DIR:-$PWD}"
TYPE="${1:-dirs}"
QUERY="${2:-}"

export SEARCH_DIR

FD_ARGS="--hidden --exclude .git"
case "$TYPE" in
  dirs)  FD_ARGS="$FD_ARGS --type d"; TOGGLE_TYPE="files"; toggle_hint="^f files";;
  files) FD_ARGS="$FD_ARGS --type f"; TOGGLE_TYPE="dirs";  toggle_hint="^f directories";;
esac

display_dir="${SEARCH_DIR/#$HOME/~}"

HEADER="$display_dir
<enter> copy path | ^h ← .. | ^l cd → | $toggle_hint"

# Run fd and fzf from SEARCH_DIR so the list shows paths relative to the
# header base. The selected item gets re-joined to SEARCH_DIR before copy.
result=$(cd "$SEARCH_DIR" && fzf --reverse --no-mouse \
  --query="$QUERY" \
  --header="$HEADER" \
  --header-first \
  --bind "ctrl-f:become($SCRIPT $TOGGLE_TYPE {q})" \
  --bind "ctrl-l:become($SCRIPT --down {} $TYPE)" \
  --bind "ctrl-h:become($SCRIPT --up $TYPE)" \
  --bind "ctrl-j:down,ctrl-k:up" \
  < <(fd $FD_ARGS))

if [ -n "$result" ]; then
  case "$result" in
    /*) printf '%s' "$result" | pbcopy;;
    *)  printf '%s' "${SEARCH_DIR%/}/${result#./}" | pbcopy;;
  esac
fi
