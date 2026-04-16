#!/usr/bin/env bash
# Confirmation screen for removing visible tags
# Reads state from environment variables set by tag-browser.sh

TAGS_FILE="$TB_TAGS_FILE"
SCOPE="$TB_SCOPE"
BASE_DIR="$TB_BASE_DIR"

# Get visible tags based on scope
if [ "$SCOPE" = "current" ]; then
  tags=$(sed 's/:.$//' "$TAGS_FILE" 2>/dev/null | grep "^$BASE_DIR")
else
  tags=$(sed 's/:.$//' "$TAGS_FILE" 2>/dev/null)
fi

count=$(echo "$tags" | grep -c . 2>/dev/null)
[ "$count" -eq 0 ] 2>/dev/null && exit 0

if [ "$SCOPE" = "current" ]; then
  title="Remove $count tags in current directory?"
else
  title="Remove all $count tags?"
fi

clear
tput civis
rows=$(tput lines)
cols=$(tput cols)

# Title
tput cup 0 1
printf '\033[1m%s\033[0m \033[38;5;246m(permanent)\033[0m' "$title"

# [Y]es / [N]o on the right
prompt="[Y]es / [N]o"
tput cup 0 $((cols - ${#prompt} - 1))
printf '%s' "$prompt"

# Divider
tput cup 1 0
for ((i=0; i<cols; i++)); do printf '─'; done

# Tag list
available=$((rows - 5))
line=0
echo "$tags" | while IFS= read -r item; do
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
done

# Wait
tput cup $rows 0
read -rsn 1 ans
tput cnorm

if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  if [ "$SCOPE" = "current" ]; then
    awk -v p="^$BASE_DIR" '{path=$0; sub(/:.$/, "", path)} path !~ p' "$TAGS_FILE" > "$TAGS_FILE.tmp" && mv "$TAGS_FILE.tmp" "$TAGS_FILE"
  else
    : > "$TAGS_FILE"
  fi
fi
