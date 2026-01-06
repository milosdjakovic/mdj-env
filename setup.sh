#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

echo "==> Starting dotfiles setup..."
echo ""

# Install Homebrew package manager
"$SRC_DIR/install-homebrew.sh"

# Install packages from Brewfile
"$SRC_DIR/install-homebrew-packages.sh"

# Install oh-my-zsh framework
"$SRC_DIR/install-ohmyzsh.sh"

# Install oh-my-zsh plugins (autosuggestions, syntax highlighting, fzf-tab)
"$SRC_DIR/install-ohmyzsh-plugins.sh"

# Stow dotfiles to home directory
"$SRC_DIR/setup-stow-dotfiles.sh"

# Copy Claude Code configuration
"$SRC_DIR/setup-claude-config.sh"

# Install tmux plugins via TPM
"$SRC_DIR/install-tmux-plugins.sh"

# Setup .zshrc with Powerlevel10k
"$SRC_DIR/setup-zshrc.sh"

echo ""
echo "==> Setup complete!"
echo "    Restart your terminal, then run 'nvim' to let LazyVim bootstrap itself."
echo ""
echo "    Optional: Run 'src/set-dev-defaults.sh \"App Name\"' to set default editor for dev files."
