#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"

{ tmux list-keys -N -T prefix | awk '/\[p:[0-9]+\]/{print}' | sort -t: -k2 -n
  tmux list-keys -N -T prefix | awk '!/\[p:[0-9]+\]/{print}'; } | \
  sed 's/\[p:[0-9]*\] //' | \
  fzf "${FZF_BASE_OPTS[@]}" \
      --header="Keybindings" \
      --border-label=" prefix = Alt-z " \
      --bind='enter:ignore'
