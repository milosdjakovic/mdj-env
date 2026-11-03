#!/bin/bash
set -e

# Install herdr from its own installer, on a machine whose herdr piece is on.
#
# Not the Homebrew formula, because herdr refuses `herdr update` when Homebrew installed it, and
# this repository never upgrades anything on a setup run, so the formula would stay on whatever
# version a machine first got. The installer's copy updates itself with `herdr update`, which is
# why this step only ever installs it once. decisions/herdr-install.md has it.

NATIVE="$HOME/.local/bin/herdr"

if [[ -x "$NATIVE" ]]; then
    echo "herdr already installed, $("$NATIVE" --version 2>/dev/null || echo "version unknown")"
else
    echo "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
    echo "herdr installed successfully"
fi
