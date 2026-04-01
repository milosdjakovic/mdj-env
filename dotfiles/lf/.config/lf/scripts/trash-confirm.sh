#!/usr/bin/env bash
# Trash confirmation popup for lf
# Args: $1 = file containing list of items to trash
# Handles trashing internally if confirmed

ITEMS_FILE="$1"
items=$(cat "$ITEMS_FILE")
count=$(echo "$items" | wc -l | tr -d ' ')

# Count files and dirs
files=0; dirs=0
while IFS= read -r item; do
  if [ -d "$item" ]; then dirs=$((dirs+1)); else files=$((files+1)); fi
done <<< "$items"

# Build title
if [ "$count" -eq 1 ]; then
  if [ -d "$(head -1 <<< "$items")" ]; then
    title="Trash 1 selected directory?"
  else
    title="Trash 1 selected file?"
  fi
else
  parts=""
  if [ "$dirs" -gt 0 ]; then
    parts="$dirs dir$([ "$dirs" -gt 1 ] && echo s)"
  fi
  if [ "$files" -gt 0 ]; then
    [ -n "$parts" ] && parts="$parts and "
    parts="$parts$files file$([ "$files" -gt 1 ] && echo s)"
  fi
  title="Trash $count selected ($parts)?"
fi

clear
tput civis
rows=$(tput lines)
cols=$(tput cols)

# Title
tput cup 0 1
printf '\033[1m%s\033[0m' "$title"

# [Y]es / [N]o on the right
prompt="[Y]es / [N]o"
tput cup 0 $((cols - ${#prompt} - 1))
printf '[Y]es / [N]o'

# Divider
tput cup 1 0
for ((i=0; i<cols; i++)); do printf '─'; done

# File list
available=$((rows - 3))
line=0
while IFS= read -r item; do
  line=$((line + 1))
  if [ "$line" -gt "$available" ]; then
    tput cup $((line + 1)) 1
    more=$((count - available))
    printf '\033[2m... and %d more\033[0m' "$more"
    break
  fi
  display="$item"
  max=$((cols - 4))
  if [ ${#display} -gt $max ]; then
    half=$(( (max - 3) / 2 ))
    display="${display:0:$half}...${display: -$half}"
  fi
  tput cup $((line + 1)) 1
  if [ -d "$item" ]; then
    printf '\033[1;34m%s/\033[0m' "$display"
  else
    printf '%s' "$display"
  fi
done <<< "$items"

# Wait
tput cup $rows 0
read -rsn 1 ans
tput cnorm

if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  while IFS= read -r item; do
    trash "$item"
  done <<< "$items"
  exit 0
else
  exit 1
fi
