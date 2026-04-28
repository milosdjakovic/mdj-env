#!/usr/bin/env bash
# fzf picker for recent lazygit repos and worktrees
# Source: ~/Library/Application Support/lazygit/state.yml (recentrepos)
# Augmented with `git worktree list` for any worktrees not yet visited via lazygit
# On selection, exec lazygit at the chosen path

set -euo pipefail

STATE_FILE="$HOME/Library/Application Support/lazygit/state.yml"
ICON_REPO=""
ICON_WORKTREE=""

if [[ ! -f "$STATE_FILE" ]]; then
  printf 'lazygit state file not found at %s\n' "$STATE_FILE" >&2
  printf 'open lazygit at least once to populate recent repos\n' >&2
  read -rp "press enter to close..."
  exit 1
fi

# Extract recentrepos: list items from the YAML state file.
# Format is a top-level `recentrepos:` key followed by lines like `    - <path>`.
recent=$(awk '
  /^recentrepos:/ { flag=1; next }
  /^[a-zA-Z]/    { flag=0 }
  flag && /^    - / {
    sub(/^    - /, "")
    print
  }
' "$STATE_FILE")

# Augment with worktrees of each main repo that are not yet in `recent`.
seen=$'\n'"$recent"$'\n'
augmented=""
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  [[ ! -d "$path" ]] && continue
  # Only augment from main worktrees (where .git is a directory).
  # Secondary worktrees (.git is a file) would produce the same list.
  [[ ! -d "$path/.git" ]] && continue
  while IFS= read -r wt; do
    [[ -z "$wt" ]] && continue
    if [[ "$seen" != *$'\n'"$wt"$'\n'* ]]; then
      augmented+="$wt"$'\n'
      seen+="$wt"$'\n'
    fi
  done < <(git -C "$path" worktree list --porcelain 2>/dev/null | awk '/^worktree /{ $1=""; sub(/^ /,""); print }')
done <<< "$recent"

# Build display list: <icon>\t<path-with-tilde>
# Icon depends on whether the path is a main repo or a secondary worktree.
build_line() {
  local p="$1"
  local icon
  if [[ -d "$p/.git" ]]; then
    icon="$ICON_REPO"
  else
    icon="$ICON_WORKTREE"
  fi
  local display="${p/#$HOME/~}"
  printf '%s\t%s  %s\n' "$p" "$icon" "$display"
}

list=""
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  [[ ! -d "$p" ]] && continue
  list+=$(build_line "$p")$'\n'
done <<< "$recent"$'\n'"$augmented"

if [[ -z "$list" ]]; then
  printf 'no recent repos found\n' >&2
  read -rp "press enter to close..."
  exit 1
fi

selected=$(printf '%s' "$list" \
  | fzf --reverse \
        --header="Recent repos & worktrees" \
        --header-first \
        --delimiter=$'\t' \
        --with-nth=2 \
        --no-mouse)

[[ -z "$selected" ]] && exit 0

target=$(printf '%s' "$selected" | cut -f1)
cd "$target"
exec lazygit
