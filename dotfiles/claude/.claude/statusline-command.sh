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

# The chrome grey is slot 17, which dotfiles/ghostty/theme-map declares as the overlay role,
# Aura's statusBar.foreground on the dark half and the light grey herdr's secondary line
# carries on the light one. A slot is right here because Claude Code passes the escape
# through to the terminal and the terminal paints it from whichever half it is on, so the
# script never has to ask which that is. It used to, with two truecolour literals chosen by
# reading AppleInterfaceStyle, because no slot among the sixteen holds a chrome grey, slot 8
# being the comment grey at 3.54 to 1 on purpose so that comments recede, and a status bar is
# the one thing that must not. Ghostty paints all 256, which is what ended that.
gray="\033[38;5;17m"

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
