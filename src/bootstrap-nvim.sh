#!/bin/bash
set -e

# Bootstrap Neovim plugins via lazy.nvim headlessly

LAZY_DIR="$HOME/.local/share/nvim/lazy/LazyVim"

if [[ -d "$LAZY_DIR" ]]; then
    echo "Neovim plugins already bootstrapped"
    exit 0
fi

echo "Bootstrapping Neovim plugins..."
nvim --headless "+Lazy! sync" +qa

echo "Neovim plugins bootstrapped successfully"
