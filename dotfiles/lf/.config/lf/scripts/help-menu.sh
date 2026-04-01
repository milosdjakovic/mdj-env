#!/usr/bin/env bash
# Help menu popup for lf
# Args: $1 = lf id

LF_ID="$1"

selected=$(grep '^map .* # ' ~/.config/lf/lfrc | \
  sed 's/^map //' | \
  awk -F'#' '{
    split($1, parts, " ")
    key=parts[1]
    desc=$2
    gsub(/^ +| +$/, "", desc)
    printf "%-10s %s\n", key, desc
  }' | \
  fzf --reverse --no-mouse \
      --header='Keybindings (enter to execute)' \
      --header-first \
      --bind 'esc:abort')

if [ -n "$selected" ] && [ -n "$LF_ID" ]; then
  key=$(echo "$selected" | awk '{print $1}')
  cmd=$(grep "^map $key " ~/.config/lf/lfrc | head -1 | awk '{print $3}')
  lf -remote "send $LF_ID $cmd"
fi
