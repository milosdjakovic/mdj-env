#!/usr/bin/env bash
# File/folder search with fzf, copies selected path to clipboard.
# Defaults to $PWD (set by display-popup -d) because tmux formats
# do not expand inside the -E shell-command argument.
#
# Invocation patterns:
#   $1 = type (dirs|files), $2 = query      -- normal, ^f, and alt-. toggles
#   $1 = --down, $2 = path, $3 = next type  -- ^l descend
#   $1 = --up,   $2 = next type             -- ^h move one level up
#
# ^l on a directory enters it. ^l on a file jumps to its parent directory.
# Type and hidden state persist across navigation within a popup session
# and reset to defaults each time the popup reopens.

SCRIPT="$0"

# Version control metadata, dependency trees, caches, build output,
# IDE state. Excluded regardless of the hidden toggle.
DEV_DIRS=(
  .git .hg .svn
  node_modules .next .nuxt .turbo
  __pycache__ .venv venv .mypy_cache .pytest_cache .ruff_cache .tox
  target dist build out
  .direnv .cache .DS_Store .idea
  coverage .terraform .parcel-cache .svelte-kit .angular .serverless
)

# macOS opaque bundle directories. Finder treats them as files but they
# are folders containing tens of thousands of internal assets.
MACOS_BUNDLES=(
  '*.photoslibrary' '*.musiclibrary' '*.tvlibrary'
  '*.imovielibrary' '*.fcpbundle'
)

# macOS Library subdirs that hold pure system noise. Library itself
# stays searchable because Mobile Documents and CloudStorage live there.
MACOS_LIBRARY=(
  Caches Containers WebKit Cookies
  'Saved Application State'
)

# Language toolchain homes in the user home directory. Hold downloaded
# archives, compiled deps, and version manager installs.
TOOLCHAIN_HOMES=(
  .cargo .rustup .gradle .m2
  .npm .yarn .pnpm-store .bun .deno
  .nvm .pyenv .rbenv .sdkman .android
)

# Trash directories on both macOS and Linux.
TRASH_DIRS=(
  .Trash Trash
)

EXCLUDE=(
  "${DEV_DIRS[@]}"
  "${MACOS_BUNDLES[@]}"
  "${MACOS_LIBRARY[@]}"
  "${TOOLCHAIN_HOMES[@]}"
  "${TRASH_DIRS[@]}"
)

# Handle --down: resolve selected path against SEARCH_DIR. If it resolves
# to a file, use its parent directory. Preserves the requested type.
if [ "$1" = "--down" ]; then
  TARGET="$2"
  NEXT_TYPE="${3:-dirs}"
  BASE="${SEARCH_DIR:-$PWD}"
  case "$TARGET" in
    /*) RESOLVED="$TARGET";;
    *)  RESOLVED="$BASE/${TARGET#./}";;
  esac
  NEW_DIR=""
  if [ -d "$RESOLVED" ]; then
    NEW_DIR="$(cd "$RESOLVED" 2>/dev/null && pwd)"
  elif [ -f "$RESOLVED" ]; then
    NEW_DIR="$(cd "$(dirname "$RESOLVED")" 2>/dev/null && pwd)"
  fi
  [ -z "$NEW_DIR" ] && exit 0
  SEARCH_DIR="$NEW_DIR"
  export SEARCH_DIR
  exec "$SCRIPT" "$NEXT_TYPE"
fi

# Handle --up: move SEARCH_DIR one level up, preserving current type.
if [ "$1" = "--up" ]; then
  NEXT_TYPE="${2:-dirs}"
  PARENT="$(cd "${SEARCH_DIR:-$PWD}/.." 2>/dev/null && pwd)"
  [ -z "$PARENT" ] && exit 0
  SEARCH_DIR="$PARENT"
  export SEARCH_DIR
  exec "$SCRIPT" "$NEXT_TYPE"
fi

SEARCH_DIR="${SEARCH_DIR:-$PWD}"
TYPE="${1:-dirs}"
QUERY="${2:-}"
SHOW_HIDDEN="${SHOW_HIDDEN:-0}"

export SEARCH_DIR SHOW_HIDDEN

# fd respects gitignore by default. Turn that off so worktrees and
# other intentionally ignored directories still surface in search.
FD_ARGS=(--no-ignore)
for pattern in "${EXCLUDE[@]}"; do
  FD_ARGS+=(--exclude "$pattern")
done

if [ "$SHOW_HIDDEN" = "1" ]; then
  FD_ARGS+=(--hidden)
  NEXT_HIDDEN=0
  hidden_hint="alt-. hide dotfiles"
else
  NEXT_HIDDEN=1
  hidden_hint="alt-. show dotfiles"
fi

case "$TYPE" in
  dirs)  FD_ARGS+=(--type d); TOGGLE_TYPE="files"; toggle_hint="^f files";;
  files) FD_ARGS+=(--type f); TOGGLE_TYPE="dirs";  toggle_hint="^f directories";;
esac

display_dir="${SEARCH_DIR/#$HOME/~}"

HEADER="$display_dir
<enter> copy path | ^h ← .. | ^l cd → | alt-h home | $toggle_hint | $hidden_hint"

# Run fd and fzf from SEARCH_DIR so the list shows paths relative to the
# header base. The selected item gets re-joined to SEARCH_DIR before copy.
result=$(cd "$SEARCH_DIR" && fzf --reverse --no-mouse \
  --query="$QUERY" \
  --header="$HEADER" \
  --header-first \
  --bind "ctrl-f:become($SCRIPT $TOGGLE_TYPE {q})" \
  --bind "alt-.:become(SHOW_HIDDEN=$NEXT_HIDDEN $SCRIPT $TYPE {q})" \
  --bind "alt-h:become(SEARCH_DIR=\"$HOME\" $SCRIPT $TYPE {q})" \
  --bind "ctrl-l:become($SCRIPT --down {} $TYPE)" \
  --bind "ctrl-h:become($SCRIPT --up $TYPE)" \
  --bind "ctrl-j:down,ctrl-k:up" \
  < <(fd "${FD_ARGS[@]}"))

if [ -n "$result" ]; then
  case "$result" in
    /*) printf '%s' "$result" | pbcopy;;
    *)  printf '%s' "${SEARCH_DIR%/}/${result#./}" | pbcopy;;
  esac
fi
