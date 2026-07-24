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

# Make sure ~/.claude/skills is a real directory before stowing. Claude Code
# writes its own skills into this folder, so it must stay a normal folder that
# stow links into per skill. If the folder is missing on a fresh machine, stow
# would fold the whole directory into one symlink and later runtime skills would
# be written into this repo. Creating it first forces the per skill linking.
mkdir -p "$HOME/.claude/skills"

# Stow main configurations
# --adopt: adopt existing files into the stow directory
stow -t "$HOME" ghostty tmux nvim zsh hammerspoon claude lf lazygit

echo "Dotfiles stowed successfully"
