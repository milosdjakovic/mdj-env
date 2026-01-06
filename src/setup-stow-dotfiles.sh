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

# Stow main configurations
# --adopt: adopt existing files into the stow directory
stow -t "$HOME" --adopt ghostty tmux nvim zsh hammerspoon

echo "Dotfiles stowed successfully"
