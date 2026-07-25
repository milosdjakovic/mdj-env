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

# Install tmux plugins via TPM
"$SRC_DIR/install-tmux-plugins.sh"

# Setup .zshrc with Powerlevel10k
"$SRC_DIR/setup-zshrc.sh"

# Bootstrap Neovim plugins
"$SRC_DIR/bootstrap-nvim.sh"

# Set Zed as default for development file types
"$SRC_DIR/setup-dev-defaults.sh"

# Remap Caps Lock -> F18 for the Hammerspoon Hyper key
"$SRC_DIR/setup-capslock-hyper.sh"

# Wire the statusline script into Claude Code's settings.json
"$SRC_DIR/setup-claude-settings.sh"

# Reconcile what every module declares it needs against what this repo knows how to install
# and what actually landed on the machine. It only reports, it never installs, so it runs
# last once everything above has had its chance. A structural gap fails the setup, since that
# is a defect in the repository and the same on every machine, while a tool merely absent
# here is a warning. Run it alone any time with src/check-dependencies.sh.
"$SRC_DIR/check-dependencies.sh"

echo ""
echo "==> Setup complete!"
echo "    Restart your terminal to apply all changes."
