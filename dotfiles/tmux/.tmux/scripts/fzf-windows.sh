#!/usr/bin/env bash
# Scoped fzf window switcher for tmux
# Called from tmux bind: display-popup -w 80 -h 70% -E "~/.tmux/scripts/fzf-windows.sh"
#
# Modes:
#   (default)       Show windows with optional session filter
#   --pick-session  Show session list, then relaunch filtered by picked session
#
# Filters:
#   --session NAME  Show only windows from this session

SCRIPT="$0"
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#S:#I')
CURRENT_WINDOW_DISPLAY=$(tmux display-message -p '#S:#I - #W')

MODE="main"
FILTER_SESSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --session) FILTER_SESSION="$2"; shift 2;;
    --pick-session) MODE="pick-session"; shift;;
    *) shift;;
  esac
done

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

# Build header based on current filter state
if [[ -n "$FILTER_SESSION" ]]; then
  FILTER_LINE="Filter: session [$FILTER_SESSION]"
  if [[ "$FILTER_SESSION" == "$CURRENT_SESSION" ]]; then
    ACTIONS="^a all sessions | ^e pick session"
  else
    ACTIONS="^s this session | ^a all sessions | ^e pick session"
  fi
else
  FILTER_LINE="Filter: all"
  ACTIONS="^s this session | ^e pick session"
fi

HEADER="Windows | Current: $CURRENT_WINDOW_DISPLAY
$FILTER_LINE
$ACTIONS"

# Build become commands for state transitions
BECOME_THIS="$SCRIPT --session $CURRENT_SESSION"
BECOME_ALL="$SCRIPT"
if [[ -n "$FILTER_SESSION" ]]; then
  BECOME_PICK="$SCRIPT --pick-session --session $FILTER_SESSION"
else
  BECOME_PICK="$SCRIPT --pick-session"
fi

selected=$(list_windows "$FILTER_SESSION" | \
  fzf --reverse \
      --header="$HEADER" \
      --header-first \
      --bind "ctrl-s:become($BECOME_THIS)" \
      --bind "ctrl-a:become($BECOME_ALL)" \
      --bind "ctrl-e:become($BECOME_PICK)")

if [[ -n "$selected" ]]; then
  target=$(echo "$selected" | cut -d' ' -f1)
  tmux switch-client -t "$target"
fi
