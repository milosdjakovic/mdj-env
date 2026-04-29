#!/usr/bin/env bash
# Sourced by all tmux fzf popup scripts.
# Tweak here to update every popup at once.
FZF_BASE_OPTS=(
  --reverse
  --no-mouse
  --border=bottom
  --border-label-pos=1
  --color='border:#15141b,label:#949494'
  # --header-first  # uncomment to pin header above the list
)

FZF_LABEL_SEP=" | "

# Build a border label from individual shortcut strings joined by FZF_LABEL_SEP.
# Usage: fzf_label "↵ copy" "^v nvim" "^h ←" ...
fzf_label() {
  local result=""
  for item in "$@"; do
    [ -z "$result" ] && result="$item" || result="${result}${FZF_LABEL_SEP}${item}"
  done
  printf ' %s ' "$result"
}
