#!/usr/bin/env bash
# Scoped fzf window switcher for tmux
#
# Modes:
#   (default)       Show windows with optional session filter
#   --pick-session  Show session list, then relaunch filtered by picked session
#
# Filters:
#   --session NAME  Show only windows from this session
#   --all           Show windows from all sessions (overrides default)
#   --query TEXT    Pre-fill fzf search query (for carryover across scope switches)

SCRIPT="$0"
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#S:#I')
CURRENT_SESSION_NAME=$(tmux display-message -p '#S')
CURRENT_WINDOW_NAME=$(tmux display-message -p '#W')

MODE="main"
FILTER_SESSION=""
SHOW_ALL=""
QUERY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --session) FILTER_SESSION="$2"; shift 2;;
    --pick-session) MODE="pick-session"; shift;;
    --all) SHOW_ALL=1; shift;;
    --query) QUERY="$2"; shift 2;;
    *) shift;;
  esac
done

# Default to current session unless --all was passed or a session filter is set
if [[ -z "$SHOW_ALL" && -z "$FILTER_SESSION" && "$MODE" == "main" ]]; then
  FILTER_SESSION="$CURRENT_SESSION"
fi

list_windows() {
  local session_filter="$1"
  if [[ -n "$session_filter" ]]; then
    tmux list-windows -t "$session_filter" \
      -F '#{window_activity} #{session_name}:#{window_index} - #{window_name}'
  else
    tmux list-windows -a \
      -F '#{window_activity} #{session_name}:#{window_index} - #{window_name}'
  fi | sort -r | cut -d' ' -f2- | grep -v "^${CURRENT_WINDOW} "
}

# --- Pick session mode ---
if [[ "$MODE" == "pick-session" ]]; then
  selected=$(tmux list-sessions -F '#{session_last_attached} #{session_name}' | \
    sort -r | cut -d' ' -f2- | \
    fzf --reverse \
        --header="Pick a session to filter windows" \
        --header-first)

  if [[ -n "$selected" ]]; then
    exec "$SCRIPT" --session "$selected"
  fi

  # Canceled, return to previous state
  if [[ -n "$FILTER_SESSION" ]]; then
    exec "$SCRIPT" --session "$FILTER_SESSION"
  else
    exec "$SCRIPT"
  fi
fi

# --- Main mode ---

# Build header: ^a toggles between scoped and all
if [[ -n "$FILTER_SESSION" ]]; then
  SCOPE_LINE="Session: [this]  ^a all"
  BECOME_TOGGLE="$SCRIPT --all --query {q}"
else
  SCOPE_LINE="Session: [all]  ^a this"
  BECOME_TOGGLE="$SCRIPT --session $CURRENT_SESSION --query {q}"
fi

HEADER="Windows | Session: $CURRENT_SESSION_NAME - Window: $CURRENT_WINDOW_NAME
$SCOPE_LINE"

# Pick session still works as a hidden shortcut
if [[ -n "$FILTER_SESSION" ]]; then
  BECOME_PICK="$SCRIPT --pick-session --session $FILTER_SESSION"
else
  BECOME_PICK="$SCRIPT --pick-session"
fi

selected=$(list_windows "$FILTER_SESSION" | \
  fzf --reverse \
      --header="$HEADER" \
      --header-first \
      --query="$QUERY" \
      --bind "ctrl-a:become($BECOME_TOGGLE)" \
      --bind "ctrl-e:become($BECOME_PICK)")

if [[ -n "$selected" ]]; then
  target=$(echo "$selected" | cut -d' ' -f1)
  tmux switch-client -t "$target"
fi
