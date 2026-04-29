#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"

current_session=$(tmux display-message -p '#S')

selected=$(tmux list-sessions -F '#{session_last_attached} #{session_name}' | \
  sort -r | cut -d' ' -f2- | \
  grep -v "^${current_session}\$" | \
  fzf "${FZF_BASE_OPTS[@]}" \
      --header="Sessions" \
      --border-label=" current: ${current_session} ")

[ -n "$selected" ] && tmux switch-client -t "$selected"
