#!/bin/bash
set -e

# Install packages from Brewfile via Homebrew

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/../Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
    echo "Error: Brewfile not found at $BREWFILE"
    exit 1
fi

# Present, not newest.
#
# This step's guarantee is that everything the Brewfile declares is on the machine, and that is
# the whole of it. Moving something already present to a newer version is a different job, and
# it is one a person chooses rather than one a setup run performs on the way past.
#
# The two were the same command until a cask upgrade wanted a password. The machine had the
# declared thing, so the guarantee was already met, and the run still aborted and left fourteen
# later steps unrun over a version bump none of them cared about. The same argument settled the
# Neovim bootstrap, where updating every plugin was a side effect of setting a machine up and
# is now a deliberate act performed on purpose and recorded.
#
# So upgrading is its own act, taken when it is the thing being done, and
# decisions/homebrew-upgrades.md has the reasoning.
echo "Installing packages from Brewfile..."
brew bundle --no-upgrade --file="$BREWFILE"

echo "Packages installed successfully"
