#!/usr/bin/env bash
# Sourced by all tmux fzf popup scripts.
# Tweak here to update every popup at once.
FZF_BASE_OPTS=(
  --reverse
  --no-mouse
  --border=bottom
  --border-label-pos=1
  --highlight-line
  # Slots rather than hex, so the terminal decides what these mean at paint time.
  # The current row is the one thing a slot pair cannot express, because a light
  # palette has no bright pastel to put dark text on. reverse names only the accent
  # and lets the terminal supply the contrasting side, which renders as dark text on
  # a bright bar under a dark theme and light text on a dark bar under a light one.
  --color='border:-1,label:8,separator:8,bg+:-1,fg+:2:reverse,hl+:2:reverse:bold'
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
