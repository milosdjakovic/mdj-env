#!/bin/bash
set -e

# Stow dotfiles to home directory using GNU Stow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$SCRIPT_DIR/../dotfiles"

# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

PACKAGES=(ghostty tmux nvim zsh hammerspoon claude lf lazygit herdr)

if [[ ! -d "$DOTFILES" ]]; then
    echo "Error: dotfiles directory not found at $DOTFILES"
    exit 1
fi

echo "Stowing dotfiles..."
cd "$DOTFILES"

# Keep ~/.claude/skills a real directory before stowing. Claude Code writes its
# own skills into this folder, so it must stay a real folder that stow links into
# per skill. Missing on a fresh machine, stow would fold the whole folder into one
# symlink and later runtime skills would be written into this repo. Every other
# folder is left to fold as normal, which is deliberate, so a new file inside an
# already linked package, a config file or a spoon file, appears without restowing.
mkdir -p "$HOME/.claude/skills"

# This repository wins, and the thing it wins against is kept.
#
# A machine that has been used already has real files where these symlinks belong, and stow
# refuses rather than guessing. It reports every conflict it found and then aborts all of
# them, across every package in the same invocation, so one stale file stops the whole run and
# nothing after this script gets to happen. That is the correct default for stow and the wrong
# one here, since making the machine match the repository is the entire purpose of running it.
#
# The conflicts are read back out of stow's own dry run rather than predicted, because stow
# owns the question of what it would collide with and a reimplementation of that would drift.
# Three messages carry a target path, a plain file in the way, a link stow does not own, and a
# link belonging to another package, so all three are matched.
#
# Looping, because clearing one conflict can uncover another beneath a folded directory, and
# bounded, because a loop that cannot converge should say so rather than spin. Nothing is
# deleted, every displaced file moves into the backup directory first.
resolve_conflicts() {
    local pass report targets count

    for (( pass = 1; pass <= 5; pass++ )); do
        report="$(stow -n -v -R -t "$HOME" "${PACKAGES[@]}" 2>&1 || true)"

        targets="$(printf '%s\n' "$report" | sed -n \
            -e 's/.*over existing target \(.*\) since .*/\1/p' \
            -e 's/.*existing target is not owned by stow: \(.*\)/\1/p' \
            -e 's/.*existing target is stowed to a different package: \([^ ]*\) =>.*/\1/p')"

        if [[ -z "$targets" ]]; then
            return 0
        fi

        count="$(printf '%s\n' "$targets" | grep -c . || true)"
        echo "  pass $pass, $count path(s) already in the way"

        while IFS= read -r relative; do
            [[ -n "$relative" ]] || continue
            mdj_displace "$HOME/$relative" || true
        done <<< "$targets"
    done

    echo "Error: stow still reports conflicts after 5 passes, which it should not" >&2
    stow -n -v -R -t "$HOME" "${PACKAGES[@]}" >&2 2>&1 || true
    return 1
}

resolve_conflicts

# Restow (-R) so re-running removes stale links left by renamed or deleted files
# and relinks the current tree, giving the same result on a fresh or an already
# set up machine. Package docs named CLAUDE.md are kept out of $HOME by each
# package's own .stow-local-ignore.
stow -R -t "$HOME" "${PACKAGES[@]}"

echo "Dotfiles stowed successfully"
