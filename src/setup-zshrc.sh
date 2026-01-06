#!/bin/bash
set -e

# Setup .zshrc with Powerlevel10k and custom config

if grep -q "source ~/.zshrc.custom" "$HOME/.zshrc" 2>/dev/null; then
    echo ".zshrc already configured"
    exit 0
fi

echo "Setting up .zshrc..."

BREW_PREFIX="$(brew --prefix)"

cat > "$HOME/.zshrc" << EOF
# Powerlevel10k instant prompt
if [[ -r "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh" ]]; then
  source "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh"
fi

# Homebrew PATH
export PATH="$BREW_PREFIX/bin:\$PATH"

# Load dotfiles config
source ~/.zshrc.custom

# Powerlevel10k theme
[[ -f $BREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme ]] && \\
  source $BREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
EOF

echo ".zshrc configured successfully"
