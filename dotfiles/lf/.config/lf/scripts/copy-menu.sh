#!/usr/bin/env bash
# Copy menu popup for lf
# Args: $1 = count, $2 = file containing paths, $3 = result file

COUNT="$1"
PATHS_FILE="$2"
RESULT_FILE="$3"

clear
tput civis
rows=$(tput lines)
cols=$(tput cols)

# Title
tput cup 0 1
printf '\033[1mCopy to clipboard\033[0m'

# Divider
tput cup 1 0
for ((i=0; i<cols; i++)); do printf '─'; done

# Options
if [ "$COUNT" -gt 1 ]; then
  tput cup 2 1
  printf '[p]  %s paths' "$COUNT"
  tput cup 3 1
  printf '[n]  %s names' "$COUNT"
else
  tput cup 2 1
  printf '[p]  full path'
  tput cup 3 1
  printf '[n]  file name'
fi

tput cup $rows 0
read -rsn 1 ans
tput cnorm

paths=$(cat "$PATHS_FILE")

case "$ans" in
  p)
    printf '%s' "$paths" | pbcopy
    echo "path" > "$RESULT_FILE"
    ;;
  n)
    echo "$paths" | while IFS= read -r item; do basename "$item"; done | pbcopy
    echo "name" > "$RESULT_FILE"
    ;;
esac
