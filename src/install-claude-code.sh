#!/bin/bash
set -e

# Install Claude Code from Anthropic's native installer.
#
# Not the claude-code cask, because Claude Code switches its own updater off when Homebrew
# installed it, and this repository never upgrades anything on a setup run, so the cask would
# stay on whatever version a machine first got. The native copy updates itself, which is why
# this step only ever installs it once. decisions/claude-code-install.md has it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

NATIVE="$HOME/.local/bin/claude"

if [[ -x "$NATIVE" ]]; then
    echo "Claude Code already installed, $("$NATIVE" --version 2>/dev/null || echo "version unknown")"
else
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    echo "Claude Code installed successfully"
fi

# A cask left over from before this step still sits on PATH behind the native copy and never
# updates, so it goes once the native copy is in place. Homebrew is borrowed for that when it
# belongs to another account, and when it cannot be, with no terminal for the password, the
# cask stays and a note says so. decisions/claude-code-install.md has it.
if command -v brew >/dev/null 2>&1 && [[ -x "$NATIVE" ]] && [[ -d "$(brew --prefix)/Caskroom/claude-code" ]]; then
    # shellcheck source=lib/brew.sh
    source "$SCRIPT_DIR/lib/brew.sh"
    if mdj_brew_borrow; then
        trap mdj_brew_return EXIT
        echo "Removing the claude-code cask, which the native copy replaces"
        brew uninstall --cask claude-code
    else
        mdj_note "The claude-code cask is still installed and no longer used, the next setup run from a terminal removes it."
    fi
fi
