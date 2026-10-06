#!/bin/bash
set -e

# Install every runtime the mise module lists and this machine lacks.
#
# Runs after stow, since the list is the stowed ~/.config/mise/config.toml. It installs what is
# absent and never moves a version already present, which is the rule for this whole layer.
# Run from the home directory so a project's own mise.toml in the caller's directory cannot add
# to what a setup run installs.

if ! command -v mise >/dev/null 2>&1; then
    echo "Error: mise not found. It is declared by the mise module and mapped in DEPENDENCIES.map."
    exit 1
fi

if [[ ! -f "$HOME/.config/mise/config.toml" ]]; then
    echo "Error: ~/.config/mise/config.toml is missing. Stow the mise package first."
    exit 1
fi

echo "Installing mise runtimes..."

cd "$HOME"
mise install

echo "mise runtimes present"
mise ls --current
