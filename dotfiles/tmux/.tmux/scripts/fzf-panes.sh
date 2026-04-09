#!/usr/bin/env bash
# Scoped fzf pane switcher for tmux
# Called from tmux bind: display-popup -w 80 -h 70% -E "~/.tmux/scripts/fzf-panes.sh"
#
# Modes:
#   (default)       Show panes with optional session/window filter
#   --pick-session  Show session list, then relaunch filtered by picked session
#   --pick-window   Show window list (scoped by session filter), then relaunch filtered
#
# Filters:
#   --session NAME          Show only panes from this session
#   --window SESSION:INDEX  Show only panes from this window
#   --all                   Show panes from all sessions (overrides default)
#   --query TEXT            Pre-fill fzf search query (for carryover across scope switches)

SCRIPT="$0"
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#S:#I')
CURRENT_PANE=$(tmux display-message -p '#S:#I.#P')
CURRENT_SESSION_NAME=$(tmux display-message -p '#S')
CURRENT_WINDOW_NAME=$(tmux display-message -p '#W')
CURRENT_PANE_INDEX=$(tmux display-message -p '#P')

MODE="main"
FILTER_SESSION=""
FILTER_WINDOW=""
SHOW_ALL=""
QUERY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --session) FILTER_SESSION="$2"; shift 2;;
    --window) FILTER_WINDOW="$2"; shift 2;;
    --pick-session) MODE="pick-session"; shift;;
    --pick-window) MODE="pick-window"; shift;;
    --all) SHOW_ALL=1; shift;;
    --query) QUERY="$2"; shift 2;;
    *) shift;;
  esac
done

# Default to current window unless --all was passed or a filter is set
if [[ -z "$SHOW_ALL" && -z "$FILTER_SESSION" && -z "$FILTER_WINDOW" && "$MODE" == "main" ]]; then
  FILTER_WINDOW="$CURRENT_WINDOW"
fi

list_panes() {
  local session_filter="$1"
  local window_filter="$2"

  if [[ -n "$window_filter" ]]; then
    tmux list-panes -t "$window_filter" \
      -F '#{pane_last_used} #{session_name}:#{window_index}.#{pane_index} - #{window_name}: #{pane_current_command}'
  elif [[ -n "$session_filter" ]]; then
    tmux list-panes -s -t "$session_filter" \
      -F '#{pane_last_used} #{session_name}:#{window_index}.#{pane_index} - #{window_name}: #{pane_current_command}'
  else
    tmux list-panes -a \
      -F '#{pane_last_used} #{session_name}:#{window_index}.#{pane_index} - #{window_name}: #{pane_current_command}'
  fi | sort -r | cut -d' ' -f2- | grep -v "^${CURRENT_PANE} "
}

# --- Pick session mode ---
if [[ "$MODE" == "pick-session" ]]; then
  selected=$(tmux list-sessions -F '#{session_last_attached} #{session_name}' | \
    sort -r | cut -d' ' -f2- | \
    fzf --reverse \
        --header="Pick a session to filter panes" \
        --header-first)

  if [[ -n "$selected" ]]; then
    exec "$SCRIPT" --session "$selected"
  fi

  # Canceled, return to previous state
  if [[ -n "$FILTER_WINDOW" ]]; then
    exec "$SCRIPT" --window "$FILTER_WINDOW"
  elif [[ -n "$FILTER_SESSION" ]]; then
    exec "$SCRIPT" --session "$FILTER_SESSION"
  else
    exec "$SCRIPT"
  fi
fi

# --- Pick window mode ---
if [[ "$MODE" == "pick-window" ]]; then
  # Scope window list to session filter if active
  if [[ -n "$FILTER_SESSION" ]]; then
    window_list=$(tmux list-windows -t "$FILTER_SESSION" \
      -F '#{window_activity} #{session_name}:#{window_index} - #{window_name}' | \
      sort -r | cut -d' ' -f2-)
  else
    window_list=$(tmux list-windows -a \
      -F '#{window_activity} #{session_name}:#{window_index} - #{window_name}' | \
      sort -r | cut -d' ' -f2-)
  fi

  selected=$(echo "$window_list" | \
    fzf --reverse \
        --header="Pick a window to filter panes" \
        --header-first)

  if [[ -n "$selected" ]]; then
    target=$(echo "$selected" | cut -d' ' -f1)
    exec "$SCRIPT" --window "$target"
  fi

  # Canceled, return to previous state
  if [[ -n "$FILTER_WINDOW" ]]; then
    exec "$SCRIPT" --window "$FILTER_WINDOW"
  elif [[ -n "$FILTER_SESSION" ]]; then
    exec "$SCRIPT" --session "$FILTER_SESSION"
  else
    exec "$SCRIPT"
  fi
fi

# --- Main mode ---

# Build header: ^a toggles between scoped and all
if [[ -n "$FILTER_WINDOW" || -n "$FILTER_SESSION" ]]; then
  SCOPE_LINE="Window: [this]  ^a all"
  BECOME_TOGGLE="$SCRIPT --all --query {q}"
else
  SCOPE_LINE="Window: [all]  ^a this"
  BECOME_TOGGLE="$SCRIPT --window $CURRENT_WINDOW --query {q}"
fi

HEADER="Panes | Session: $CURRENT_SESSION_NAME - Window: $CURRENT_WINDOW_NAME - Pane: $CURRENT_PANE_INDEX
$SCOPE_LINE"

# Determine the active session context (for scoping pick-window)
ACTIVE_SESSION="$FILTER_SESSION"
if [[ -n "$FILTER_WINDOW" ]]; then
  ACTIVE_SESSION="${FILTER_WINDOW%%:*}"
fi

# Pick shortcuts still work as hidden bindings
if [[ -n "$FILTER_WINDOW" ]]; then
  BECOME_PICK_SESSION="$SCRIPT --pick-session --window $FILTER_WINDOW"
  BECOME_PICK_WINDOW="$SCRIPT --pick-window --session $ACTIVE_SESSION --window $FILTER_WINDOW"
elif [[ -n "$FILTER_SESSION" ]]; then
  BECOME_PICK_SESSION="$SCRIPT --pick-session --session $FILTER_SESSION"
  BECOME_PICK_WINDOW="$SCRIPT --pick-window --session $FILTER_SESSION"
else
  BECOME_PICK_SESSION="$SCRIPT --pick-session"
  BECOME_PICK_WINDOW="$SCRIPT --pick-window"
fi

selected=$(list_panes "$FILTER_SESSION" "$FILTER_WINDOW" | \
  fzf --reverse \
      --header="$HEADER" \
      --header-first \
      --query="$QUERY" \
      --bind "ctrl-a:become($BECOME_TOGGLE)" \
      --bind "ctrl-e:become($BECOME_PICK_SESSION)" \
      --bind "ctrl-f:become($BECOME_PICK_WINDOW)")

if [[ -n "$selected" ]]; then
  target=$(echo "$selected" | cut -d' ' -f1)
  tmux switch-client -t "$target"
fi
