#!/bin/bash
set -e

# Stow dotfiles to home directory using GNU Stow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$SCRIPT_DIR/../dotfiles"

if [[ ! -d "$DOTFILES" ]]; then
    echo "Error: dotfiles directory not found at $DOTFILES"
    exit 1
fi

echo "Stowing dotfiles..."
cd "$DOTFILES"

# Keep ~/.claude/skills a real directory before stowing. Claude Code writes its
# own skills into this folder, so it must stay a real folder that stow links into
# per skill. Missing on a fresh machine, stow would fold the whole folder into one
# symlink and later runtime skills would be written into this repo. Every other
# folder is left to fold as normal, which is deliberate, so a new file inside an
# already linked package, a config file or a spoon file, appears without restowing.
mkdir -p "$HOME/.claude/skills"

# Restow (-R) so re-running removes stale links left by renamed or deleted files
# and relinks the current tree, giving the same result on a fresh or an already
# set up machine. Package docs named CLAUDE.md are kept out of $HOME by each
# package's own .stow-local-ignore.
stow -R -t "$HOME" ghostty tmux nvim zsh hammerspoon claude lf lazygit

echo "Dotfiles stowed successfully"
