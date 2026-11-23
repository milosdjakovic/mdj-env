#!/bin/sh
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.cwd // ""')
dir=$(basename "$cwd")

# Truncate dir to 18 chars; append "..." only if truncated (counts as 3 of 18)
if [ ${#dir} -gt 18 ]; then
  dir="$(printf '%.15s' "$dir")..."
fi

# Get git branch for the cwd, truncate to 8 chars (5 + "..." if longer)
branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    if [ ${#branch} -gt 8 ]; then
      branch="$(printf '%.5s' "$branch")..."
    fi
    dir="${dir} (${branch})"
  fi
fi

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Inside herdr, the /rename name goes to this pane as the agent name its sidebar shows, and is
# cleared when there is none so the row says claude again. Detached and silent, so a slow or
# absent herdr never holds up the status line.
if [ -n "$HERDR_PANE_ID" ]; then
  session=$(echo "$input" | jq -r '.session_name // empty')
  if [ -n "$session" ]; then
    set -- --display-agent "$session"
  else
    set -- --clear-display-agent
  fi
  (herdr pane report-metadata "$HERDR_PANE_ID" --source claude-statusline "$@" >/dev/null 2>&1 &)
fi

# The grey is the terminal's faint text, SGR 2, the ink drawn at the strength the terminal gives
# faint, the way Claude Code draws its own secondary text. It names no colour, so it follows the
# half in every terminal with nothing to ask and nothing to send, and an app restart cannot reset
# it. It was slot 17 until 2026-11-16, which a Herdr theme cannot hold, so every bar in the Herdr
# app turned xterm's navy when the app restarted under a running session.
# decisions/herdr-app-colors.md has it.
gray="\033[2m"

yellow="\033[0;33m"
red="\033[0;31m"
reset="\033[0m"

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")

  # Build bar: 10 segments, filled proportionally
  filled=$(( used_int / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  empty=$(( 10 - filled ))

  bar=""
  i=0
  while [ $i -lt $filled ]; do
    bar="${bar}█"
    i=$(( i + 1 ))
  done
  i=0
  while [ $i -lt $empty ]; do
    bar="${bar}░"
    i=$(( i + 1 ))
  done

  if [ "$used_int" -ge 75 ]; then
    bar_color="$red"
  elif [ "$used_int" -ge 50 ]; then
    bar_color="$yellow"
  else
    bar_color="$gray"
  fi

  printf "${gray}%s${reset} | ${gray}%s${reset} | ${bar_color}%s %d%%${reset}" \
    "$dir" "$model" "$bar" "$used_int"
else
  printf "${gray}%s${reset} | ${gray}%s${reset} | ${gray}░░░░░░░░░░${reset}" \
    "$dir" "$model"
fi
