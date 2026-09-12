#!/usr/bin/env bash
# Fuzzy finder over the home directory. Folders only until ctrl-f asks for files,
# and visible entries only until ctrl-h asks for hidden ones. Both toggles re-exec
# this script through fzf's become, which is what carries the state and the typed
# query across the restart, since fzf itself keeps neither.
set -u

HERDR="${HERDR_BIN_PATH:-herdr}"
. "$(dirname "$0")/context.sh"

FIND_FILES="${FIND_FILES:-0}"
FIND_HIDDEN="${FIND_HIDDEN:-0}"
FIND_QUERY="${FIND_QUERY:-}"

cd "$HOME" || exit 1

# A plain walk of the home directory reports a hundred and sixty thousand folders and
# takes seven seconds, which is not a picker. Almost all of it is machine chatter, so
# the noisy trees are cut and the walk drops to about a second. Library itself is kept
# rather than cut whole, because the Obsidian vault lives under Mobile Documents.
fd_args=(
  --strip-cwd-prefix
  --exclude 'Library/Caches'
  --exclude 'Library/Containers'
  --exclude 'Library/Group Containers'
  --exclude 'Library/Application Support'
  --exclude 'Library/Developer'
  --exclude 'Library/CloudStorage'
  --exclude node_modules
  --exclude .git
  --exclude .Trash
  --exclude .cache
  --exclude Applications
)
[ "$FIND_FILES" = 1 ] || fd_args+=(--type d)
[ "$FIND_HIDDEN" = 1 ] && fd_args+=(--hidden)

if [ "$FIND_FILES" = 1 ]; then files_state="files and folders"; else files_state="folders only"; fi
if [ "$FIND_HIDDEN" = 1 ]; then hidden_state="hidden shown"; else hidden_state="hidden skipped"; fi

next_files=$((1 - FIND_FILES))
next_hidden=$((1 - FIND_HIDDEN))

pick=$(fd "${fd_args[@]}" 2>/dev/null | fzf \
  --reverse \
  --border sharp \
  --border-label ' fuzzy search ' \
  --query "$FIND_QUERY" \
  --prompt "$HOME/" \
  --header "ctrl-f $files_state, ctrl-h $hidden_state" \
  --bind "ctrl-f:become(FIND_FILES=$next_files FIND_HIDDEN=$FIND_HIDDEN FIND_QUERY={q} '$0')" \
  --bind "ctrl-h:become(FIND_FILES=$FIND_FILES FIND_HIDDEN=$next_hidden FIND_QUERY={q} '$0')") || exit 0

[ -n "$pick" ] || exit 0
target="$HOME/$pick"
[ -d "$target" ] && dest="$target" || dest="$(dirname "$target")"

pane="$(herdr_pane_id)"
[ -n "$pane" ] || exit 0

# Typing into a pane is only safe when the shell itself is what is waiting for input.
# When anything else holds the foreground, a coding agent, an editor, a running build,
# the text lands inside that program and is taken as its input, so the pane is left
# alone and the chosen place opens as a new tab instead. Herdr reports the shell as
# foreground by giving the process group the same id as the shell itself.
free=$("$HERDR" pane process-info --pane "$pane" 2>/dev/null | jq -r '
  .result.process_info
  | if .foreground_process_group_id == .shell_pid then "yes" else "no" end
' 2>/dev/null)

if [ "$free" = yes ]; then
  if [ -d "$target" ]; then
    "$HERDR" pane run "$pane" "cd $(printf '%q' "$dest")" >/dev/null 2>&1
  else
    "$HERDR" pane run "$pane" "cd $(printf '%q' "$dest") && nvim $(printf '%q' "$target")" >/dev/null 2>&1
  fi
else
  "$HERDR" tab create --cwd "$dest" --focus >/dev/null 2>&1
  "$HERDR" notification show "fuzzy search" \
    --body "that pane is busy, so this opened in a new tab" >/dev/null 2>&1
fi
