#!/usr/bin/env bash
# Tag browser popup for lf with scope toggling
# Args: $1 = scope (current/all), $2 = base dir, $3 = result file

SCRIPT="$0"
SCOPE="${1:-current}"
BASE_DIR="${2:-$PWD}"
RESULT_FILE="$3"
TAGS_FILE="$HOME/.local/share/lf/tags"

# Extract all tagged paths
ALL_TAGS=""
if [ -f "$TAGS_FILE" ] && [ -s "$TAGS_FILE" ]; then
  ALL_TAGS=$(awk -F'\t' '{print $1}' "$TAGS_FILE")
fi

# Filter by scope
if [ "$SCOPE" = "current" ]; then
  if [ -n "$ALL_TAGS" ]; then
    LIST=$(echo "$ALL_TAGS" | grep "^$BASE_DIR")
  else
    LIST=""
  fi
else
  LIST="$ALL_TAGS"
fi

# Build header
if [ "$SCOPE" = "current" ]; then
  scope_line="[current dir]  ^a all tags"
else
  scope_line="^s current dir  [all tags]"
fi

if [ -z "$LIST" ]; then
  if [ -z "$ALL_TAGS" ]; then
    empty_msg="No tags anywhere. Press t to tag files."
  else
    empty_msg="No tags in current dir. Press t to tag, ^a to see all."
  fi
  HEADER="$scope_line
$empty_msg"
else
  HEADER="$scope_line"
fi

echo "$LIST" | fzf --reverse \
  --header="$HEADER" \
  --header-first \
  --bind "esc:abort" \
  --bind "ctrl-s:become($SCRIPT current \"$BASE_DIR\" \"$RESULT_FILE\")" \
  --bind "ctrl-a:become($SCRIPT all \"$BASE_DIR\" \"$RESULT_FILE\")" > "$RESULT_FILE"
