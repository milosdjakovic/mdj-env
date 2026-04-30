#!/usr/bin/env bash
# Called by fzf --preview with the selected item as $1.
# SEARCH_DIR is inherited from the parent fzf-files.sh environment.
echo "sel=$1 SEARCH_DIR=$SEARCH_DIR" > /tmp/fzf-preview-debug.txt
sel="$1"
base="${SEARCH_DIR:-$HOME}"
abs="${base%/}/$sel"
mime=$(file --mime-type -b "$abs" 2>/dev/null)
cols="${FZF_PREVIEW_COLUMNS:-80}"
lines="${FZF_PREVIEW_LINES:-40}"

if [[ -d "$abs" ]]; then
  eza --tree --level=2 --color=always "$abs"
elif [[ "$mime" == image/* ]]; then
  chafa --size="${cols}x${lines}" "$abs"
elif file --mime-encoding -b "$abs" 2>/dev/null | grep -q "binary"; then
  printf "\033[2m%s\033[0m\n\n" "$mime"
  ls -lh "$abs" | awk '{print "size:", $5}'
else
  bat --color=always --style=numbers --line-range=:200 "$abs" 2>/dev/null
fi
