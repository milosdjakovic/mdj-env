#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"

selected=$(printf 'Save Session\nRestore Session\nReload Config\n' | \
  fzf "${FZF_BASE_OPTS[@]}" \
      --header="Tmux Management" \
      --border-label=" ↵ select ")

case "$selected" in
  Save*)    ~/.tmux/plugins/tmux-resurrect/scripts/save.sh;;
  Restore*) ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh;;
  Reload*)  tmux source-file ~/.tmux.conf \; display-message "Config reloaded";;
esac
