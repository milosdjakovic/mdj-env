#!/usr/bin/env bash
# Tag browser popup for lf with scope toggling and tag management
# Args: $1 = scope (current/all), $2 = base dir, $3 = lf id, $4 = query

SCRIPT="$0"
SCOPE="${1:-current}"
BASE_DIR="${2:-$PWD}"
LF_ID="$3"
QUERY="${4:-}"
TAGS_FILE="$HOME/.local/share/lf/tags"

# Export state for become() scripts to inherit
export TB_TAGS_FILE="$TAGS_FILE"
export TB_SCRIPT="$SCRIPT"
export TB_SCOPE="$SCOPE"
export TB_BASE_DIR="$BASE_DIR"
export TB_LF_ID="$LF_ID"

# Build the reload command (reused for initial load and after delete)
if [ "$SCOPE" = "current" ]; then
  LIST_CMD="awk -F'\t' '{print \$1}' \"$TAGS_FILE\" 2>/dev/null | grep \"^$BASE_DIR\" || true"
else
  LIST_CMD="awk -F'\t' '{print \$1}' \"$TAGS_FILE\" 2>/dev/null || true"
fi

# Check tag counts
ALL_COUNT=0
if [ -f "$TAGS_FILE" ] && [ -s "$TAGS_FILE" ]; then
  ALL_COUNT=$(wc -l < "$TAGS_FILE" | tr -d ' ')
fi

LIST=$(eval "$LIST_CMD")

# Build header
if [ "$SCOPE" = "current" ]; then
  scope_line="[current dir]  ^a all tags"
  remove_label="^x remove visible"
else
  scope_line="^s current dir  [all tags]"
  remove_label="^x remove all"
fi

action_line="enter navigate  ^d remove  $remove_label"

if [ -z "$LIST" ]; then
  if [ "$ALL_COUNT" -eq 0 ]; then
    empty_msg="No tags anywhere. Press t in lf to tag files."
  else
    empty_msg="No tags in current dir. ^a to see all."
  fi
  HEADER="$scope_line
$action_line
$empty_msg"
else
  HEADER="$scope_line
$action_line"
fi

result=$(echo "$LIST" | fzf --reverse --no-mouse \
  --query="$QUERY" \
  --header="$HEADER" \
  --header-first \
  --bind "esc:abort" \
  --bind "ctrl-s:become($SCRIPT current \"$BASE_DIR\" \"$LF_ID\" {q})" \
  --bind "ctrl-a:become($SCRIPT all \"$BASE_DIR\" \"$LF_ID\" {q})" \
  --bind "ctrl-d:execute-silent(~/.config/lf/scripts/tag-delete.sh {})+reload($LIST_CMD)" \
  --bind "ctrl-x:execute(~/.config/lf/scripts/tag-clear-confirm.sh)+reload($LIST_CMD)")

if [ -n "$result" ] && [ -n "$LF_ID" ]; then
  parent=$(dirname "$result")
  lf -remote "send $LF_ID cd \"$parent\""
  lf -remote "send $LF_ID select \"$(basename "$result")\""
fi
