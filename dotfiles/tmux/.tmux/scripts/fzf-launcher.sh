#!/usr/bin/env bash
# FZF launcher (command palette) for tmux
# Called from: display-popup -w 80 -h 70% -E "PANE_PATH='...' ~/.tmux/scripts/fzf-launcher.sh"
#
# Category filters via --category flag (default: all)
# Uses become() for state transitions, same pattern as fzf-find.sh

SCRIPT="$0"
CATEGORY="all"
EXECUTE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --category) CATEGORY="$2"; shift 2;;
    --execute) EXECUTE="$2"; shift 2;;
    *) shift;;
  esac
done

# --- Entry data: category|display_key|description|command_id ---
# To add a new entry: add a line here and a case in execute_cmd below
ENTRIES="tools|prefix+g|Lazygit popup|lazygit
tools|prefix+G|Recent repos & worktrees lazygit|lazygit-recent
tools|prefix+b|File explorer popup (lf)|lf
tools|prefix+\`|Scratch shell popup|scratch
tools|prefix+t|Search lf tags (enter copy, ^v nvim, alt-v new window)|fzf-tags
tools|prefix+f|Find files globally (enter copy, ^v nvim, alt-v new window)|fzf-files-global
tools|prefix+F|Find files (enter copy, ^v nvim, alt-v new window)|fzf-files
nav|prefix+s|Sessions (fzf switcher)|fzf-sessions
nav|prefix+S|Sessions (tree view)|tree-sessions
nav|prefix+e|Last session|last-session
nav|prefix+a|Last window|last-window
tmux|---|Save session|save-session
tmux|---|Restore session|restore-session
tmux|prefix+R|Reload config|reload-config
tmux|prefix+I|Install plugins|install-plugins
tmux|prefix+U|Update plugins|update-plugins"

execute_cmd() {
  case "$1" in
    lazygit)         tmux display-popup -d "$PANE_PATH" -w 90% -h 90% -E "lazygit";;
    lazygit-recent)  tmux display-popup -w 60% -h 50% -E "~/.tmux/scripts/fzf-recent-repos.sh";;
    lf)              tmux display-popup -d "$PANE_PATH" -w 90% -h 90% -E "tmux new-session -A -s '~files' -c '$PANE_PATH' lf \\; set status off";;
    scratch)         tmux display-popup -d "$PANE_PATH" -w 90% -h 90% -E "$SHELL";;
    fzf-sessions)
      local current_session
      current_session=$(tmux display-message -p '#S')
      tmux display-popup -w 80 -h 70% -E "\
        tmux list-sessions -F '#{session_last_attached} #{session_name}' | \
        sort -r | cut -d' ' -f2- | \
        grep -v '^${current_session}\$' | \
        fzf --reverse \
            --header=\"Sessions | Current: ${current_session}\" \
            --header-first | \
        xargs tmux switch-client -t"
      ;;
    fzf-tags)        tmux display-popup -w 90% -h 90% -E "~/.tmux/scripts/fzf-tags.sh";;
    fzf-files)       tmux display-popup -d "$PANE_PATH" -w 90% -h 90% -E "SEARCH_DIR='$PANE_PATH' ~/.tmux/scripts/fzf-files.sh";;
    fzf-files-global) tmux display-popup -w 90% -h 90% -E "SEARCH_DIR='$HOME' ~/.tmux/scripts/fzf-files.sh";;
    tree-sessions)   tmux choose-tree -Zs;;
    last-session)    tmux switch-client -l;;
    last-window)     tmux last-window;;
    save-session)    ~/.tmux/plugins/tmux-resurrect/scripts/save.sh;;
    restore-session) ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh;;
    reload-config)   tmux source-file ~/.tmux.conf \; display-message "Config reloaded";;
    install-plugins) tmux run-shell "$(brew --prefix tpm)/share/tpm/bindings/install_plugins";;
    update-plugins)  tmux run-shell "$(brew --prefix tpm)/share/tpm/bindings/update_plugins";;
  esac
}

# Deferred execution mode: called via tmux run-shell after the popup closes
if [[ -n "$EXECUTE" ]]; then
  execute_cmd "$EXECUTE"
  exit 0
fi

build_list() {
  local cat_filter="$1"
  echo "$ENTRIES" | while IFS='|' read -r category key desc cmd_id; do
    if [[ "$cat_filter" == "all" || "$category" == "$cat_filter" ]]; then
      printf "%s\t%-14s %s\n" "$cmd_id" "$key" "$desc"
    fi
  done
}

# Build header
case "$CATEGORY" in
  all)   cat_line="[all]  ^t tools  ^n nav  ^x tmux";;
  tools) cat_line="^a all  [tools]  ^n nav  ^x tmux";;
  nav)   cat_line="^a all  ^t tools  [nav]  ^x tmux";;
  tmux)  cat_line="^a all  ^t tools  ^n nav  [tmux]";;
esac

HEADER="Launcher | prefix+Space
$cat_line"

selected=$(build_list "$CATEGORY" | \
  fzf --reverse \
      --header="$HEADER" \
      --header-first \
      --delimiter=$'\t' \
      --with-nth=2 \
      --bind "ctrl-a:become($SCRIPT --category all)" \
      --bind "ctrl-t:become($SCRIPT --category tools)" \
      --bind "ctrl-n:become($SCRIPT --category nav)" \
      --bind "ctrl-x:become($SCRIPT --category tmux)")

if [[ -n "$selected" ]]; then
  cmd_id=$(echo "$selected" | cut -f1)
  # Defer execution via tmux run-shell so the launcher popup closes first.
  # Tmux allows only one popup per client, so commands that open popups
  # (lazygit, lf, fzf switchers) would fail if run while this popup is alive.
  tmux run-shell -b "PANE_PATH='$PANE_PATH' $SCRIPT --execute $cmd_id"
fi
