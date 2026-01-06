#!/bin/bash
set -e

# Install tmux plugins via TPM (Tmux Plugin Manager)

echo "Installing tmux plugins..."

TPM_INSTALLER="$(brew --prefix tpm)/share/tpm/bin/install_plugins"

if [[ ! -f "$TPM_INSTALLER" ]]; then
    echo "Error: TPM not found. Ensure 'tpm' is installed via Homebrew."
    exit 1
fi

"$TPM_INSTALLER"

echo "Tmux plugins installed successfully"
