#!/bin/bash

# Configuration
DIRECTORY_MAX_LENGTH=16
GIT_BRANCH_MAX_LENGTH=21

# Read JSON input from stdin
input=$(cat)

# Truncation function with configurable limits
# Args: string, max_display_length
# Truncates only if at least 3 chars would be saved
# max_display_length + 3 = minimum length before truncation
truncate_string() {
    local str="$1"
    local max_len="$2"
    local len=${#str}
    local truncate_at=$((max_len + 3))  # Only truncate if length >= max_len + 3

    if [ "$len" -ge "$truncate_at" ]; then
        local show_chars=$((max_len - 3))  # Reserve 3 chars for "..."
        echo "${str:0:$show_chars}..."
    else
        echo "$str"
    fi
}

# Extract basic info
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
dir=$(basename "$cwd")
dir=$(truncate_string "$dir" "$DIRECTORY_MAX_LENGTH")

# Shorten model name (remove "Claude" prefix and simplify)
# Examples: "Claude Opus 4.5" -> "Opus 4.5", "Claude 3.5 Sonnet" -> "Sonnet 3.5"
model=$(echo "$model" | sed -E 's/^Claude //; s/3\.5 Sonnet/Sonnet 3.5/; s/4 Opus/Opus 4/')

# Git info
git_info=""
if cd "$cwd" 2>/dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -c core.useBuiltinFSMonitor=false symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    branch=$(truncate_string "$branch" "$GIT_BRANCH_MAX_LENGTH")
    if ! git -c core.useBuiltinFSMonitor=false diff --quiet 2>/dev/null || ! git -c core.useBuiltinFSMonitor=false diff --cached --quiet 2>/dev/null; then
        status="*"
    else
        status=""
    fi
    [ -n "$branch" ] && git_info=" ($branch$status)"
fi

# Session context window percentage (current conversation) - showing remaining
usage=$(echo "$input" | jq '.context_window.current_usage')
size=$(echo "$input" | jq '.context_window.context_window_size')

if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    pct=$((current * 100 / size))
    remaining=$((100 - pct))
else
    # At start of conversation, show 100% remaining
    remaining=100
fi

# Build a 10-char fill bar where filled portion represents context used
used=$((100 - remaining))
filled=$(( (used * 10 + 99) / 100 ))
empty=$((10 - filled))
bar=""
for i in $(seq 1 $filled); do bar="${bar}█"; done
for i in $(seq 1 $empty); do bar="${bar}░"; done

# Color thresholds: gray under 50%, yellow at 50%, red at 75%
gray="\033[38;2;153;153;153m"
yellow="\033[38;2;204;153;0m"
red="\033[38;2;204;50;50m"
reset="\033[0m"

if [ "$used" -ge 75 ]; then
    ctx_color="$red"
elif [ "$used" -ge 50 ]; then
    ctx_color="$yellow"
else
    ctx_color="$gray"
fi

# Print status line with lighter gray color (#999 / RGB 153, 153, 153)
printf "${gray}%s%s | %s | ${ctx_color}[${bar}] ${used}%%${reset}\n" "$dir" "$git_info" "$model"
