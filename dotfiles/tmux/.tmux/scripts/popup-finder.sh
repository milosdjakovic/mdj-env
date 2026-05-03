#!/usr/bin/env bash
# Open a finder popup sized at 90% of the terminal, capped at 200x50.
# All arguments are forwarded to display-popup, so callers can pass
# -d, -E, or any other flag without knowing about the sizing logic.

W=$(tmux display-message -p '#{window_width}')
H=$(tmux display-message -p '#{window_height}')

PW=$(( W * 9 / 10 ))
PH=$(( H * 9 / 10 ))

[ "$PW" -gt 200 ] && PW=200
[ "$PH" -gt 50 ]  && PH=50

tmux display-popup -w "$PW" -h "$PH" "$@"
