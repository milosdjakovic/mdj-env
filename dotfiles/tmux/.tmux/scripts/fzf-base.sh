#!/usr/bin/env bash
# Sourced by all tmux fzf popup scripts.
# Tweak here to update every popup at once.
FZF_BASE_OPTS=(
  --reverse
  --no-mouse
  --border=bottom
  --border-label-pos=1
  # Only what a tmux popup needs on top of ~/.config/fzf/fzfrc, which every fzf reads at
  # launch and which owns the colours, the bar under the current row included. The frame
  # is the popup's own, so fzf draws none, and the label rides slot 8 with the lines. The
  # current row used to be overridden here as reverse green, because no slot among the
  # sixteen could carry a bar, and slot 16 in Ghostty's theme-map is what ended that.
  --color='border:-1,label:8'
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
