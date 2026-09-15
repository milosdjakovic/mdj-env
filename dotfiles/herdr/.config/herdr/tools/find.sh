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
# the noisy trees are cut and the walk drops to a quarter of a second.
#
# What is cut and what is reached back into lives in find-scope beside this file rather
# than here, because the answer differs per machine while this logic does not. The file
# says why each line is there, including the cloud rule that is the reason this picker
# was unusable before, and adding a tree is then an edit to data rather than to code.
fd_args=()
extra_roots=()
scope="$(dirname "$0")/find-scope"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  verb="${line%% *}"
  path="${line#* }"
  case "$verb" in
    exclude) fd_args+=(--exclude "$path") ;;
    # A root that is not on this machine is skipped rather than refused, which is what lets
    # one file serve every machine. fd exits nonzero when every search path it was given is
    # missing, so an unfiltered list would turn a machine without the vault into an error.
    include) [ -d "$HOME/$path" ] && extra_roots+=("$path") ;;
  esac
done < "$scope"

[ "$FIND_FILES" = 1 ] || fd_args+=(--type d)
[ "$FIND_HIDDEN" = 1 ] && fd_args+=(--hidden)

# The home walk and each reached in root, as one stream. The first carries
# --strip-cwd-prefix and the rest cannot, since fd prints an explicit search path as it was
# given and the flag makes it print nothing at all. Both halves come out relative to the home
# directory anyway, which is what the pick below expects, because the walk starts there and
# every included path is written relative to it.
scan() {
  fd --strip-cwd-prefix "${fd_args[@]}"
  for root in ${extra_roots[@]+"${extra_roots[@]}"}; do
    fd "${fd_args[@]}" . "$root"
  done
}

# The selection bar is the one colour in this popup that cannot be a palette slot and cannot
# live in FZF_DEFAULT_OPTS beside the rest. A bar has to be a tint of the page under it, and no
# slot is dark on the dark palette and light on the light one, which is the same wall the iris
# menu hit and the reason that grew appearance aware tables. So it is hex, and a hex value has
# to be chosen at the moment of drawing rather than baked into a string a shell exported once.
#
# The value is herdr's own selection_bg, read out of its config rather than copied here, so the
# picker and the sidebar agree and there is one place to change either. active_row_bg is the
# other candidate and is one word away if the lighter lift is wanted instead.
#
# Ghostty is set to light:aura-light,dark:aura-dark, so it follows the macOS appearance and the
# system answer and the terminal's cannot disagree. defaults prints Dark when the system is dark
# and fails with the key absent when it is light, which is the whole test. Asking the system is
# also the only route open from inside a herdr popup, since this process is a child of the herdr
# server rather than of a shell, so anything an interactive shell exported about the appearance
# reaches here as whatever it was when the server started.
theme_colour() {
  awk -v section="[theme.custom.$1]" -v key="$2" '
    $0 == section { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && $1 == key { gsub(/"/, "", $3); print $3; exit }
  ' "$(dirname "$0")/../config.toml" 2>/dev/null
}

if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = Dark ]; then
  selection_bg=$(theme_colour dark selection_bg)
else
  selection_bg=$(theme_colour light selection_bg)
fi

# A missing config or a renamed token leaves the bar off rather than guessing at a colour, since
# fzf still marks the current row with its pointer and an invented tint is worse than none.
if [ -n "$selection_bg" ]; then
  bar_opts=(--highlight-line --color "bg+:$selection_bg")
else
  bar_opts=()
fi

if [ "$FIND_FILES" = 1 ]; then files_state="files and folders"; else files_state="folders only"; fi
if [ "$FIND_HIDDEN" = 1 ]; then hidden_state="hidden shown"; else hidden_state="hidden skipped"; fi

next_files=$((1 - FIND_FILES))
next_hidden=$((1 - FIND_HIDDEN))

# The keys and the toggle states sit in --footer rather than --header, so they are pinned to the
# bottom edge of the popup instead of riding above the list. fzf rules them off with the same
# horizontal line it draws under the match counter, which gives the window symmetric chrome and
# is a separator rather than a second frame, so the popup still has the one border it came with.
#
# ctrl-y leaves with the path on the clipboard instead of opening anything, and it is
# --expect rather than a binding that copies in place because a picker that has already
# answered should close. fzf then prints the key it left on first and the selection after,
# so the two endings share one parse. The key is ctrl-y and not the shift-enter that reads
# more naturally, since fzf rejects that name outright, and not ctrl-c, which is how fzf
# aborts.
result=$(scan 2>/dev/null | fzf \
  --reverse \
  ${bar_opts[@]+"${bar_opts[@]}"} \
  --query "$FIND_QUERY" \
  --prompt "$HOME/" \
  --footer "ctrl-f $files_state, ctrl-h $hidden_state, ctrl-y copy path" \
  --expect=ctrl-y \
  --bind "ctrl-f:become(FIND_FILES=$next_files FIND_HIDDEN=$FIND_HIDDEN FIND_QUERY={q} '$0')" \
  --bind "ctrl-h:become(FIND_FILES=$FIND_FILES FIND_HIDDEN=$next_hidden FIND_QUERY={q} '$0')") || exit 0

leave_key=$(printf '%s\n' "$result" | head -n 1)
pick=$(printf '%s\n' "$result" | tail -n +2)

[ -n "$pick" ] || exit 0
target="$HOME/$pick"

# The popup is gone by the time this runs and the clipboard says nothing about itself, so the
# notification is the only confirmation there is that the copy happened and of what.
if [ "$leave_key" = ctrl-y ]; then
  printf '%s' "$target" | pbcopy
  "$HERDR" notification show "fuzzy search" \
    --body "copied ${target/#$HOME/~}" >/dev/null 2>&1
  exit 0
fi

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
