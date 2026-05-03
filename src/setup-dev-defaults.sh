#!/bin/bash
set -e

# Set Zed as default application for development file types

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting Zed as default for development files..."
"$SCRIPT_DIR/set-dev-defaults.sh" "Zed"
