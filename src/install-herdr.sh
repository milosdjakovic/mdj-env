#!/bin/bash
set -e

# Install herdr from its own installer, on a machine whose herdr piece is on.
#
# Not the Homebrew formula, because herdr refuses `herdr update` when Homebrew installed it, and
# this repository never upgrades anything on a setup run, so the formula would stay on whatever
# version a machine first got. The installer's copy updates itself with `herdr update`, which is
# why this step only ever installs it once. decisions/herdr-install.md has it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

NATIVE="$HOME/.local/bin/herdr"

if [[ -x "$NATIVE" ]]; then
    echo "herdr already installed, $("$NATIVE" --version 2>/dev/null || echo "version unknown")"
else
    echo "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
    echo "herdr installed successfully"
fi

# A formula left over from before this step sits on PATH behind the installer's copy and never
# updates. Nothing here removes what a machine has, so it is only reported, and removing it is a
# one off act done with the person. decisions/herdr-install.md has it.
if command -v brew >/dev/null 2>&1 && [[ -x "$NATIVE" ]] && [[ -d "$(brew --prefix)/Cellar/herdr" ]]; then
    mdj_note "The herdr formula is still installed beside the installer's copy and no longer used, remove it with brew uninstall --formula herdr."
fi
