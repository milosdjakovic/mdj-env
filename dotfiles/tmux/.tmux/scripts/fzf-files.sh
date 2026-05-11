#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"
# File/folder search with fzf, copies selected path to clipboard.
# Defaults to $PWD (set by display-popup -d) because tmux formats
# do not expand inside the -E shell-command argument.
#
# Invocation patterns:
#   $1 = type (dirs|files), $2 = query      -- normal, ^f, alt-., ^s toggles
#   $1 = --down, $2 = path, $3 = next type  -- ^l descend
#   $1 = --up,   $2 = next type             -- ^h move one level up
#
# ^l on a directory enters it. ^l on a file jumps to its parent directory.
# Type, hidden, and follow-links state persist across navigation within a
# popup session and reset to defaults each time the popup reopens.

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
SHOW_HIDDEN="${SHOW_HIDDEN:-1}"
FOLLOW_LINKS="${FOLLOW_LINKS:-1}"

export SEARCH_DIR SHOW_HIDDEN FOLLOW_LINKS

# fd respects gitignore by default. Turn that off so worktrees and
# other intentionally ignored directories still surface in search.
FD_ARGS=(--no-ignore)
for pattern in "${EXCLUDE[@]}"; do
  FD_ARGS+=(--exclude "$pattern")
done

ICON_NVIM_WIN=$(printf '\xef\x82\x8e')   # nf-fa-external_link (nvim in new window)
ICON_HOME=$(printf '\xef\x80\x95')       # nf-fa-home
ICON_EYE=$(printf '\xef\x81\xae')        # nf-fa-eye (show hidden)
ICON_EYE_SLASH=$(printf '\xef\x81\xb0')  # nf-fa-eye-slash (hide hidden)
ICON_LINK=$(printf '\xef\x83\x81')       # nf-fa-link (follow symlinks)
ICON_UNLINK=$(printf '\xef\x84\xa7')     # nf-fa-chain_broken (skip symlinks)
ICON_SEARCH=$(printf '\xef\x80\x82')     # nf-fa-search
ICON_DIR=$(printf '\xef\x81\xbb')        # nf-fa-folder (directory entry)
ICON_FILE=$(printf '\xef\x80\x96')       # nf-fa-file_o (file entry)

if [ "$SHOW_HIDDEN" = "1" ]; then
  FD_ARGS+=(--hidden)
  NEXT_HIDDEN=0
  hidden_hint="alt-. ${ICON_EYE_SLASH}"
else
  NEXT_HIDDEN=1
  hidden_hint="alt-. ${ICON_EYE}"
fi

if [ "$FOLLOW_LINKS" = "1" ]; then
  FD_ARGS+=(--follow --type l)
  NEXT_FOLLOW=0
  follow_hint="^s ${ICON_UNLINK}"
else
  NEXT_FOLLOW=1
  follow_hint="^s ${ICON_LINK}"
fi

case "$TYPE" in
  dirs)  FD_ARGS+=(--type d); TOGGLE_TYPE="files"; toggle_hint="^f ${ICON_FILE}";;
  files) FD_ARGS+=(--type f); TOGGLE_TYPE="dirs";  toggle_hint="^f ${ICON_DIR}";;
esac

# Tab-delimited output for fzf: <real-path>\t<icon>  <display-path>.
# fzf renders only column 2 (--with-nth=2) while binds and selection
# extraction read column 1 via {1} / cut -f1. Symlinks are filtered by
# target type so dirs mode keeps only symlinks-to-dirs and files mode
# keeps only symlinks-to-files. Tests run with CWD=SEARCH_DIR so they
# resolve relative paths emitted by fd. fd 10+ appends a trailing /
# to directory entries, which makes -L follow the link, so the lstat
# test runs against the slash-stripped path while output preserves
# fd's original formatting.
classify_entries() {
  local p bare
  while IFS= read -r p; do
    bare="${p%/}"
    if [ -L "$bare" ]; then
      if [ "$TYPE" = "dirs" ]; then
        [ -d "$bare" ] || continue
      else
        [ -d "$bare" ] && continue
      fi
      printf '%s\t%s  %s\n' "$p" "$ICON_LINK" "$p"
    elif [ -d "$p" ]; then
      printf '%s\t%s  %s\n' "$p" "$ICON_DIR" "$p"
    else
      printf '%s\t%s  %s\n' "$p" "$ICON_FILE" "$p"
    fi
  done
}

display_dir="${SEARCH_DIR/#$HOME/~}"
BORDER_LABEL=$(fzf_label "↵ copy" "^v nvim" "alt-v nvim ${ICON_NVIM_WIN}" "^h ←" "^l →" "alt-h ${ICON_HOME}" "$toggle_hint" "$hidden_hint" "$follow_hint" "^p ${ICON_SEARCH}")
# Preview-only hint. The preview command only runs when the preview pane is
# visible, so emitting this header line inside the preview body keeps the
# alt-j / alt-k shortcuts tied to the preview half and hides them when ^p
# closes the pane. ANSI 246 matches the #949494 used for the rest of the
# popup chrome.
PREVIEW_HINT_LINE=$(printf '\033[38;5;246malt-j ↓ | alt-k ↑\033[0m')
export PREVIEW_HINT_LINE


# Run fd and fzf from SEARCH_DIR so the list shows paths relative to the
# header base. The selected item gets re-joined to SEARCH_DIR before copy.
# --expect makes ^v and alt-v terminate fzf with the key name printed first,
# so we can branch between copy (enter), inline nvim (^v), and new-window
# nvim (alt-v) below.
result=$(cd "$SEARCH_DIR" && fzf "${FZF_BASE_OPTS[@]}" \
  --query="$QUERY" \
  --header="$display_dir" \
  --border-label="$BORDER_LABEL" \
  --expect=ctrl-v,alt-v \
  --delimiter=$'\t' \
  --with-nth=2 \
  --preview='
    printf "%s\n" "$PREVIEW_HINT_LINE"
    f={1}
    abs="$SEARCH_DIR/$f"
    mime=$(file --mime-type -b "$abs" 2>/dev/null)
    if [ -d "$abs" ]; then
      eza --tree --level=2 --color=always "$abs"
    elif printf "%s" "$mime" | grep -q "^image/"; then
      chafa --format=symbols --size="${FZF_PREVIEW_COLUMNS:-80}x${FZF_PREVIEW_LINES:-40}" "$abs"
    elif file --mime-encoding -b "$abs" 2>/dev/null | grep -q "binary"; then
      printf "\033[2m%s\033[0m\n\n" "$mime"
      ls -lh "$abs"
    else
      bat --color=always --style=numbers --line-range=:200 "$abs" 2>/dev/null
    fi
  ' \
  --color='preview-border:#949494' \
  --preview-window='right:50%:hidden:border-left:~1' \
  --bind 'ctrl-p:toggle-preview' \
  --bind "ctrl-f:become($SCRIPT $TOGGLE_TYPE {q})" \
  --bind "alt-.:become(SHOW_HIDDEN=$NEXT_HIDDEN $SCRIPT $TYPE {q})" \
  --bind "ctrl-s:become(FOLLOW_LINKS=$NEXT_FOLLOW $SCRIPT $TYPE {q})" \
  --bind "alt-h:become(SEARCH_DIR=\"$HOME\" $SCRIPT $TYPE {q})" \
  --bind "ctrl-l:become($SCRIPT --down {1} $TYPE)" \
  --bind "ctrl-h:become($SCRIPT --up $TYPE)" \
  --bind "ctrl-j:down,ctrl-k:up" \
  --bind "alt-j:preview-half-page-down,alt-k:preview-half-page-up" \
  < <(fd "${FD_ARGS[@]}" | classify_entries))

key=$(printf '%s' "$result" | head -n1)
sel=$(printf '%s' "$result" | tail -n +2 | cut -f1)

[ -z "$sel" ] && exit 0

case "$sel" in
  /*) abs_path="$sel";;
  *)  abs_path="${SEARCH_DIR%/}/${sel#./}";;
esac

if [ -d "$abs_path" ]; then
  nvim_cwd="$abs_path"
else
  nvim_cwd="$(dirname "$abs_path")"
fi

case "$key" in
  ctrl-v)
    # Replace this script with nvim so the popup hosts nvim directly.
    # Popup closes when nvim exits because the script process ends.
    cd "$nvim_cwd" && exec nvim "$abs_path"
    ;;
  alt-v)
    # New window auto-closes on nvim exit (tmux remain-on-exit defaults off).
    tmux new-window -c "$nvim_cwd" nvim "$abs_path"
    ;;
  *)
    printf '%s' "$abs_path" | pbcopy
    ;;
esac
