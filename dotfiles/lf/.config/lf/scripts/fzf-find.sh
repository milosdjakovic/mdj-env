#!/usr/bin/env bash
# Recursive fzf finder for lf with scope toggling
# Returns the selected path to stdout

SCRIPT="$0"
MODE="${1:-all}"

case "$MODE" in
  all)
    LIST_CMD="fd --hidden --exclude .git"
    FILTER="Filter: all"
    ACTIONS="^d dirs | ^f files"
    ;;
  dirs)
    LIST_CMD="fd --hidden --exclude .git --type d"
    FILTER="Filter: dirs"
    ACTIONS="^f files | ^a all"
    ;;
  files)
    LIST_CMD="fd --hidden --exclude .git --type f"
    FILTER="Filter: files"
    ACTIONS="^a all | ^d dirs"
    ;;
esac

HEADER="$FILTER
$ACTIONS"

eval "$LIST_CMD" | fzf --reverse \
  --header="$HEADER" \
  --header-first \
  --bind "ctrl-d:become($SCRIPT dirs)" \
  --bind "ctrl-f:become($SCRIPT files)" \
  --bind "ctrl-a:become($SCRIPT all)"
