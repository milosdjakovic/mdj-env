#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# One stamp for the whole run, so every step that has to move something out of this
# repository's way puts it in the same directory. Exported rather than passed, because the
# steps are separate processes and each one also has to work when it is run on its own, which
# src/lib/backup.sh handles by making its own stamp when this is absent.
export MDJ_BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"

# Where a step leaves a line the closing block below has to repeat. Exported for the same
# reason as the stamp, and removed at the end, so nothing of it outlives the run. A step run
# alone finds it unset and only says its line where it happens. src/lib/backup.sh has mdj_note.
export MDJ_RUN_NOTES="$(mktemp -t mdj-env-notes)"

# Why a trap, when set -e is already doing the right thing.
#
# This script is a flat list of calls under set -e and that shape is correct. A step that fails
# should stop the run, since carrying on to stow and Neovim against a half installed machine is
# worse than stopping, and every step is idempotent so fixing the cause and running again costs
# nothing.
#
# What stopping does not do on its own is say what it cost. The failing step's own error is the
# last thing printed, usually under a hundred lines of package manager output, and every call
# below it is never reached rather than skipped, so a run that died a third of the way through
# ends up looking much like one that finished. That is not hypothetical, an outdated cask
# wanting a password did exactly this and took the remaining thirteen steps with it, silently.
#
# The trap changes no behaviour at all. It names the step that stopped the run and counts the
# ones that never ran, on stderr, so the consequence is visible without reading back up the log.
#
# The total is read out of this file rather than written down, so adding a step below cannot
# leave a hardcoded number behind to go quietly wrong.
STEP_TOTAL="$(grep -c '^step "' "${BASH_SOURCE[0]}")"
STEP_DONE=0
STEP_NOW=""

step() {
    STEP_NOW="$(basename "${1%.sh}")"
    "$@"
    STEP_DONE=$((STEP_DONE + 1))
}

# Anything a step asked of you on the way past, said again at the end where it is read. It is
# the same argument as the backup listing in the closing block, and the same failure it was
# written against. The stow step's restart line, the one time a machine needed it, went by at
# line twenty of two hundred and was found by reading the log back afterwards. Printed by the
# closing block on a run that finishes and by the trap on one that does not, since a note a
# step left before the abort is still owed, and the file goes either way.
say_notes() {
    if [[ -s "$MDJ_RUN_NOTES" ]]; then
        echo ""
        echo "    Things this run asks of you, said again here so they are not lost above:"
        sed 's|^|      |' "$MDJ_RUN_NOTES"
    fi
    rm -f "$MDJ_RUN_NOTES"
}

on_exit() {
    local code=$?
    [[ $code -eq 0 ]] && return 0
    local remaining=$(( STEP_TOTAL - STEP_DONE - 1 ))
    [[ $remaining -lt 0 ]] && remaining=0
    {
        echo ""
        echo "==> Setup ABORTED at step $((STEP_DONE + 1)) of $STEP_TOTAL, ${STEP_NOW:-startup}, exit $code"
        [[ $remaining -gt 0 ]] && echo "    $remaining later step(s) never ran, so this machine is part configured."
        echo "    The cause is above. Every step is idempotent, so fix it and run this again."
        say_notes
    } >&2
}
trap on_exit EXIT

echo "==> Starting dotfiles setup..."
echo ""

# Make sure a developer toolchain exists, before anything that compiles or wants one. The
# Homebrew installer below asks for it too, so doing it here is what stops that step waiting.
step "$SRC_DIR/install-xcode-clt.sh"

# Install Homebrew package manager
step "$SRC_DIR/install-homebrew.sh"

# Install packages from Brewfile
step "$SRC_DIR/install-homebrew-packages.sh"

# Install oh-my-zsh framework
step "$SRC_DIR/install-ohmyzsh.sh"

# Install oh-my-zsh plugins (autosuggestions, syntax highlighting, fzf-tab)
step "$SRC_DIR/install-ohmyzsh-plugins.sh"

# Stow dotfiles to home directory
step "$SRC_DIR/setup-stow-dotfiles.sh"


# Install tmux plugins via TPM
step "$SRC_DIR/install-tmux-plugins.sh"

# Setup .zshrc with Powerlevel10k
step "$SRC_DIR/setup-zshrc.sh"

# Bootstrap Neovim plugins
step "$SRC_DIR/bootstrap-nvim.sh"

# Ask which editor opens development files from Finder, and make it their default
step "$SRC_DIR/setup-dev-defaults.sh"

# Remap Caps Lock -> F18 for the Hammerspoon Hyper key
step "$SRC_DIR/setup-capslock-hyper.sh"

# Restore the file modes IVPN's daemon requires inside its own bundle, which the Homebrew
# cask does not set because it copies the app rather than running IVPN's installer. Without
# this the daemon cannot start at all on a freshly bootstrapped machine. Prompts for sudo
# only when there is something to repair, and does nothing when IVPN is not installed.
step "$SRC_DIR/setup-ivpn-permissions.sh"

# Wire the statusline script into Claude Code's settings.json
step "$SRC_DIR/setup-claude-settings.sh"

# Register the herdr module's local plugin, which stow places but cannot register
step "$SRC_DIR/setup-herdr-plugins.sh"

# Reconcile what every module declares it needs against what this repo knows how to install
# and what actually landed on the machine. It only reports, it never installs, so it runs
# last once everything above has had its chance. A structural gap fails the setup, since that
# is a defect in the repository and the same on every machine, while a tool merely absent
# here is a warning. Run it alone any time with src/check-dependencies.sh.
step "$SRC_DIR/check-dependencies.sh"

# Prove every generated theme file matches the palette it was generated from. On a fresh
# machine this regenerates nothing, since the files are committed, and it fails only when a
# committed file disagrees with the palette, which is a repository defect. Run it alone any
# time with src/check-theme.sh, and after any colour change, since it is what rewrites the
# files. theme/CLAUDE.md has the whole contract.
step "$SRC_DIR/check-theme.sh"

# A module may also own checks that only make sense inside it, kept beside the module rather
# than here because the rest of the repository has no use for the rule. They report on the
# repository rather than on this machine, so a failure is the same everywhere and fails setup.
echo ""
echo "==> Module checks"
step "$SCRIPT_DIR/dotfiles/hammerspoon/check-timers"

echo ""
echo "==> Setup complete!"
echo "    Restart your terminal to apply all changes."

# Said at the end rather than as it happens, because the steps that displace a file are spread
# through the run and a line buried in the middle of the output is a line nobody reads. This
# repository takes precedence over whatever it finds, which is the point of running it, so the
# only thing owed is telling you plainly where the old copies went.
BACKUP_DIR="$HOME/.mdj-env-backup/$MDJ_BACKUP_STAMP"
if [[ -d "$BACKUP_DIR" ]]; then
    echo ""
    echo "    Files this run replaced were kept, not deleted:"
    echo "      $BACKUP_DIR"
    ( cd "$BACKUP_DIR" && find . -type f | sed 's|^\./|        |' )
fi

say_notes
