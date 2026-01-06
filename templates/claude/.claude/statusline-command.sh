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

# Session context window percentage (current conversation)
usage=$(echo "$input" | jq '.context_window.current_usage')
session_ctx=""
if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    size=$(echo "$input" | jq '.context_window.context_window_size')
    pct=$((current * 100 / size))
    session_ctx=" | s: ${pct}%"
fi

# Total token usage tracking (5-hour window)
token_tracker_file="$HOME/.claude/token_tracker"
rate_limit_file="$HOME/.claude/rate_limit_tracker"
current_time=$(date +%s)

# Get current session totals
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
session_total=$((total_input + total_output))

# Initialize or read tracking files
if [ -f "$rate_limit_file" ]; then
    reset_time=$(cat "$rate_limit_file")
else
    reset_time=$((current_time + 18000))
    echo "$reset_time" > "$rate_limit_file"
fi

if [ -f "$token_tracker_file" ]; then
    cumulative_tokens=$(cat "$token_tracker_file")
else
    cumulative_tokens=0
    echo "$cumulative_tokens" > "$token_tracker_file"
fi

# Check if window has expired and reset if needed
if [ "$current_time" -ge "$reset_time" ]; then
    reset_time=$((current_time + 18000))
    echo "$reset_time" > "$rate_limit_file"
    cumulative_tokens=0
    echo "$cumulative_tokens" > "$token_tracker_file"
fi

# Update cumulative total (only if session total changed)
session_id=$(echo "$input" | jq -r '.session_id')
last_session_file="$HOME/.claude/last_session_${session_id}"

if [ -f "$last_session_file" ]; then
    last_session_total=$(cat "$last_session_file")
else
    last_session_total=0
fi

if [ "$session_total" -ne "$last_session_total" ]; then
    tokens_added=$((session_total - last_session_total))
    cumulative_tokens=$((cumulative_tokens + tokens_added))
    echo "$cumulative_tokens" > "$token_tracker_file"
    echo "$session_total" > "$last_session_file"
fi

# Calculate percentage used (assuming 5M token limit per 5h window)
rate_limit_max=5000000
used_pct=$((cumulative_tokens * 100 / rate_limit_max))
if [ "$used_pct" -gt 100 ]; then
    used_pct=100
fi

# Reset time (human readable, 24-hour format without AM/PM)
reset_at=$(date -r "$reset_time" +"%H:%M")
usage_info=" | 5h: ${used_pct}% ($reset_at)"

# Print status line with lighter gray color (#999 / RGB 153, 153, 153)
printf "$(printf '\033[38;2;153;153;153m')%s%s | %s%s%s$(printf '\033[0m')\n" "$dir" "$git_info" "$model" "$session_ctx" "$usage_info"
