#!/usr/bin/env bash
# Remove a single tag from lf's tags file
# Args: $1 = path to untag
TAGS_FILE="$HOME/.local/share/lf/tags"
awk -F'\t' -v p="$1" '$1 != p' "$TAGS_FILE" > "$TAGS_FILE.tmp" && mv "$TAGS_FILE.tmp" "$TAGS_FILE"
