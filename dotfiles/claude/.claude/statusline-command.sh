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

# Aura's statusBar.foreground, because that is literally what this is. The published palette
# names one grey, #6d6d6d, and calls it muted, but its job there is comments and it sits at
# 3.54 to 1 on purpose so that comments recede. A status bar is the one thing that must not.
# #adacae is the value Aura's own VS Code theme puts on statusBar.foreground, and #727276 is
# the light half of it, the same pair herdr's overlay0 carries.
#
# This is a truecolour literal rather than an ANSI slot because no slot holds a chrome grey.
# Slot 8 is the comment grey, which is the wrong job, so the appearance has to be read by
# hand. Claude Code offers nothing for that. Its statusline payload carries no theme,
# appearance or background field and it sets only COLUMNS and LINES, so the macOS setting
# Ghostty itself resolves its theme pair from is the only source. The read costs about 5 ms
# against the four processes this script already spawns per refresh.
if [ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
  gray="\033[38;2;173;172;174m"
else
  gray="\033[38;2;114;114;118m"
fi

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
