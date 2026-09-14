#!/bin/bash
set -e

# Setup .zshrc with Powerlevel10k and custom config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

if grep -q "source ~/.zshrc.custom" "$HOME/.zshrc" 2>/dev/null; then
    echo ".zshrc already configured"
    exit 0
fi

echo "Setting up .zshrc..."

BREW_PREFIX="$(brew --prefix)"

# This file is generated rather than stowed, so it cannot be a symlink and the only way to
# install it is to write over whatever is there. On a machine that has been used that is
# somebody's shell configuration, and the oh-my-zsh installer two steps earlier writes one of
# its own as well, so there is almost always something to lose here. It moves to the backup
# directory rather than being overwritten in place, which costs nothing and is the difference
# between a setup you can undo and one you cannot.
mdj_displace "$HOME/.zshrc" || true

cat > "$HOME/.zshrc" << EOF
# PATH, hoisted above everything else because the iris hook below is the first thing that
# runs and has to find the binary. macOS does not put the Homebrew prefix on the PATH it
# hands a login shell, so nothing here may assume it, and ~/.local/bin comes first because
# that is where src/build-iris.sh puts iris and it has to win over any package manager copy
# still lying around.
export PATH="\$HOME/.local/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:\$PATH"

# IRIS autocomplete. The hook execs iris as a PTY proxy, replacing this shell with one
# running behind it, so it belongs above the Powerlevel10k instant prompt rather than
# below. Painting a prompt into a process that is about to be replaced leaves a screen
# p10k never gets to tear down.
eval "\$(iris init zsh)"

# Powerlevel10k instant prompt
if [[ -r "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh" ]]; then
  source "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh"
fi

# Load dotfiles config
source ~/.zshrc.custom

# Powerlevel10k theme
[[ -f $BREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme ]] && \\
  source $BREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
EOF

echo ".zshrc configured successfully"
