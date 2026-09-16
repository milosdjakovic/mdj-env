#!/bin/bash
set -e

# Setup .zshrc with Powerlevel10k and custom config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

BREW_PREFIX="$(brew --prefix)"

# The file this machine should have, built first and compared second.
#
# The guard used to be a grep for "source ~/.zshrc.custom", which every version of this
# template has ever contained, so it answered has this machine been set up at all rather than
# is this machine's .zshrc the current one. Once a machine had been set up it never received a
# template change again, and the step reported already configured while doing nothing, which is
# the worst of both, a machine left behind and a run that says it is fine.
#
# It is not a theoretical gap. The iris hook below was added to this template and no existing
# machine got it, so the shell that was supposed to exec iris simply did not, and the only way
# to land it was to move .zshrc aside by hand.
#
# Comparing the whole generated file is the smallest thing that is actually true. It cannot go
# stale the way a grep for one line does, because the thing it tests is the thing it writes, so
# any future edit to this template is picked up with no matching edit to the guard.
GENERATED="$(cat << EOF
# PATH, hoisted above everything else because the iris hook below is the first thing that
# runs and has to find the binary. macOS does not put the Homebrew prefix on the PATH it
# hands a login shell, so nothing here may assume it, and ~/.local/bin comes first because
# that is where src/build-iris.sh puts iris and it has to win over any package manager copy
# still lying around.
export PATH="\$HOME/.local/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:\$PATH"

# IRIS autocomplete. The hook execs iris as a PTY proxy, replacing this shell with one
# running behind it, so it belongs above the Powerlevel10k instant prompt rather than
# below. Painting a prompt into a process that is about to be replaced leaves a screen
# p10k never gets to tear down. A proxy hides every session behind it from the herdr
# agents panel, and this line was out for half a day on 2026-09-16 for that reason before
# the in shell picker lost on feel. decisions/shell-autocomplete.md has the whole of it.
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
)"

# Command substitution strips trailing newlines and so does the read below, so both sides of
# the comparison are newline normalised the same way and a file differing only in how it ends
# does not read as a change.
if [[ -f "$HOME/.zshrc" ]] && [[ "$(cat "$HOME/.zshrc")" == "$GENERATED" ]]; then
    echo ".zshrc is already current"
    exit 0
fi

if [[ -e "$HOME/.zshrc" ]]; then
    echo "Updating .zshrc, the template has changed..."
else
    echo "Setting up .zshrc..."
fi

# This file is generated rather than stowed, so it cannot be a symlink and the only way to
# install it is to write over whatever is there. On a machine that has been used that is
# somebody's shell configuration, and the oh-my-zsh installer two steps earlier writes one of
# its own as well, so there is almost always something to lose here. It moves to the backup
# directory rather than being overwritten in place, which costs nothing and is the difference
# between a setup you can undo and one you cannot. That matters more now than it did, since
# this step rewrites on every template change rather than only on a machine that has none.
mdj_displace "$HOME/.zshrc" || true

printf '%s\n' "$GENERATED" > "$HOME/.zshrc"

echo ".zshrc configured successfully"
