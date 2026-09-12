#!/usr/bin/env bash
# Lazygit for the repository the calling pane sits in. Outside a repository there is
# nothing to open, so the recent list lazygit already keeps for itself stands in.
set -u

HERDR="${HERDR_BIN_PATH:-herdr}"
. "$(dirname "$0")/context.sh"

cd "$(herdr_pane_cwd)" 2>/dev/null || cd "$HOME" || exit 1

# Lazygit resolves its own config directory per platform, so it is asked rather than
# guessed. The overlay goes last because the later file in the list wins, and the real
# config goes first so nothing in it is lost by loading a second one.
overlay="$(dirname "$0")/lazygit-popup.yml"
config_dir="$(lazygit --print-config-dir 2>/dev/null)"
if [ -n "$config_dir" ] && [ -f "$config_dir/config.yml" ]; then
  export LG_CONFIG_FILE="$config_dir/config.yml,$overlay"
else
  export LG_CONFIG_FILE="$overlay"
fi

if root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ]; then
  cd "$root" || exit 1
  exec lazygit
fi

# One entry per line under the recentrepos key, which is where lazygit records
# every repository it has been opened in, most recent first.
state="$HOME/Library/Application Support/lazygit/state.yml"
repos=$(awk '
  /^recentrepos:/ { inlist = 1; next }
  inlist && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
  inlist { exit }
' "$state" 2>/dev/null)

if [ -z "$repos" ]; then
  "$HERDR" notification show "lazygit" --body "not a repository, and lazygit has no recent ones yet" >/dev/null 2>&1
  exit 0
fi

pick=$(printf '%s\n' "$repos" | fzf --reverse --prompt 'repo> ' \
  --header 'this directory is not a repository, pick a recent one') || exit 0

if [ ! -d "$pick" ]; then
  "$HERDR" notification show "lazygit" --body "that path is gone, $pick" >/dev/null 2>&1
  exit 0
fi

cd "$pick" || exit 1
exec lazygit
