#!/bin/bash
set -e

# Setup Claude Code configuration using shared sync utility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

echo "Setting up Claude Code configuration..."

"$SCRIPT_DIR/lib/sync-files.sh" "$@" -r "$REPO_ROOT" "$REPO_ROOT/configs/claude-files.conf"

echo ""
echo "Claude Code configuration complete"
