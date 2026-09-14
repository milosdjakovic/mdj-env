#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# One stamp for the whole run, so every step that has to move something out of this
# repository's way puts it in the same directory. Exported rather than passed, because the
# steps are separate processes and each one also has to work when it is run on its own, which
# src/lib/backup.sh handles by making its own stamp when this is absent.
export MDJ_BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> Starting dotfiles setup..."
echo ""

# Make sure a developer toolchain exists, before anything that compiles or wants one. The
# Homebrew installer below asks for it too, so doing it here is what stops that step waiting.
"$SRC_DIR/install-xcode-clt.sh"

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

# Build iris from the fork, since the two fixes it carries are not in any released build
"$SRC_DIR/build-iris.sh"

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

# Register the herdr module's local plugin, which stow places but cannot register
"$SRC_DIR/setup-herdr-plugins.sh"

# Reconcile what every module declares it needs against what this repo knows how to install
# and what actually landed on the machine. It only reports, it never installs, so it runs
# last once everything above has had its chance. A structural gap fails the setup, since that
# is a defect in the repository and the same on every machine, while a tool merely absent
# here is a warning. Run it alone any time with src/check-dependencies.sh.
"$SRC_DIR/check-dependencies.sh"

# A module may also own checks that only make sense inside it, kept beside the module rather
# than here because the rest of the repository has no use for the rule. They report on the
# repository rather than on this machine, so a failure is the same everywhere and fails setup.
echo ""
echo "==> Module checks"
"$SCRIPT_DIR/dotfiles/hammerspoon/check-timers"

echo ""
echo "==> Setup complete!"
echo "    Restart your terminal to apply all changes."

# Said at the end rather than as it happens, because the steps that displace a file are spread
# through the run and a line buried in the middle of the output is a line nobody reads. This
# repository takes precedence over whatever it finds, which is the point of running it, so the
# only thing owed is telling you plainly where the old copies went.
BACKUP_DIR="$HOME/.mdj-env-backup/$MDJ_BACKUP_STAMP"
if [[ -d "$BACKUP_DIR" ]]; then
    echo ""
    echo "    Files this run replaced were kept, not deleted:"
    echo "      $BACKUP_DIR"
    ( cd "$BACKUP_DIR" && find . -type f | sed 's|^\./|        |' )
fi
