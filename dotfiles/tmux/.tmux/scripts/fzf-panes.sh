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

SCRIPT="$0"
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#S:#I')
CURRENT_PANE=$(tmux display-message -p '#S:#I.#P')
CURRENT_PANE_DISPLAY=$(tmux display-message -p '#S:#I.#P - #W')

MODE="main"
FILTER_SESSION=""
FILTER_WINDOW=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --session) FILTER_SESSION="$2"; shift 2;;
    --window) FILTER_WINDOW="$2"; shift 2;;
    --pick-session) MODE="pick-session"; shift;;
    --pick-window) MODE="pick-window"; shift;;
    *) shift;;
  esac
done

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

# Determine the active session context (for scoping pick-window)
ACTIVE_SESSION="$FILTER_SESSION"
if [[ -n "$FILTER_WINDOW" ]]; then
  # Extract session from window target (session:index -> session)
  ACTIVE_SESSION="${FILTER_WINDOW%%:*}"
fi

# Build header based on current filter state
if [[ -n "$FILTER_WINDOW" ]]; then
  WINDOW_NAME=$(tmux display-message -t "$FILTER_WINDOW" -p '#W' 2>/dev/null || echo "$FILTER_WINDOW")
  FILTER_LINE="Filter: window [$FILTER_WINDOW - $WINDOW_NAME]"

  ACTIONS="^a all | ^e pick session | ^f pick window"
  if [[ "$ACTIVE_SESSION" != "$CURRENT_SESSION" ]]; then
    ACTIONS="^s this session | $ACTIONS"
  fi
  if [[ "$FILTER_WINDOW" != "$CURRENT_WINDOW" ]]; then
    ACTIONS="$ACTIONS | ^w this window"
  fi
elif [[ -n "$FILTER_SESSION" ]]; then
  FILTER_LINE="Filter: session [$FILTER_SESSION]"

  ACTIONS="^a all | ^e pick session | ^w this window | ^f pick window"
  if [[ "$FILTER_SESSION" != "$CURRENT_SESSION" ]]; then
    ACTIONS="^s this session | $ACTIONS"
  fi
else
  FILTER_LINE="Filter: all"
  ACTIONS="^s session | ^e pick session | ^w window | ^f pick window"
fi

HEADER="Panes | Current: $CURRENT_PANE_DISPLAY
$FILTER_LINE
$ACTIONS"

# Build become commands for state transitions
BECOME_THIS_SESSION="$SCRIPT --session $CURRENT_SESSION"
BECOME_ALL="$SCRIPT"
BECOME_THIS_WINDOW="$SCRIPT --window $CURRENT_WINDOW"

# Pick session preserves current state for fallback on cancel
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
      --bind "ctrl-s:become($BECOME_THIS_SESSION)" \
      --bind "ctrl-a:become($BECOME_ALL)" \
      --bind "ctrl-e:become($BECOME_PICK_SESSION)" \
      --bind "ctrl-w:become($BECOME_THIS_WINDOW)" \
      --bind "ctrl-f:become($BECOME_PICK_WINDOW)")

if [[ -n "$selected" ]]; then
  target=$(echo "$selected" | cut -d' ' -f1)
  tmux switch-client -t "$target"
fi
