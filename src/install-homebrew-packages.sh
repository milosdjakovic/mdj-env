#!/bin/bash
set -e

# Install packages from Brewfile via Homebrew

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/../Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
    echo "Error: Brewfile not found at $BREWFILE"
    exit 1
fi

echo "Installing packages from Brewfile..."
brew bundle --file="$BREWFILE"

echo "Packages installed successfully"
