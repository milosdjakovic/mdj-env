#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# `./setup.sh --only PIECE` applies one optional piece and nothing else, for the moment a machine
# has just been given it with `src/machine.sh set`. It runs the steps every piece stands on, the
# packages and the links, then only the steps that belong to that piece, then that module's
# grants and the reconciler. The piece's own step alone would stop short, since only the package
# step installs what the piece needs.
ONLY=""
if [[ "${1:-}" == --only ]]; then
    ONLY="${2:-}"
    if [[ -z "$ONLY" ]]; then
        echo "usage: setup.sh [--only PIECE]" >&2
        exit 2
    fi
elif [[ $# -gt 0 ]]; then
    echo "usage: setup.sh [--only PIECE]" >&2
    exit 2
fi
# What every piece stands on, by step name, the only steps an --only run takes besides its own.
ONLY_CORE=" install-homebrew-packages setup-stow-dotfiles setup-grants check-dependencies "

# One stamp for the whole run, so every step that has to move something out of this
# repository's way puts it in the same directory. Exported rather than passed, because the
# steps are separate processes and each one also has to work when it is run on its own, which
# src/lib/backup.sh handles by making its own stamp when this is absent.
export MDJ_BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"

# Where a step leaves a line the closing block below has to repeat. Exported for the same
# reason as the stamp, and removed at the end, so nothing of it outlives the run. A step run
# alone finds it unset and only says its line where it happens. src/lib/backup.sh has mdj_note.
export MDJ_RUN_NOTES="$(mktemp -t mdj-env-notes)"

# shellcheck source=src/lib/backup.sh
source "$SRC_DIR/lib/backup.sh"
# shellcheck source=src/lib/brew.sh
source "$SRC_DIR/lib/brew.sh"

# A step that would guide its own grants when run alone leaves them to the grants step near the
# end of this run instead, so a person is walked through each grant once, in one place.
export MDJ_GRANTS_LATER=1

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
STEP_TOTAL="$(grep -cE '^step(_if [a-z]+ [a-z]+)? "' "${BASH_SOURCE[0]}")"
STEP_DONE=0
STEP_NOW=""

step() {
    STEP_NOW="$(basename "${1%.sh}")"
    if [[ -n "$ONLY" && " $ONLY_CORE " != *" $STEP_NOW "* && "${STEP_PIECE:-}" != "$ONLY" ]]; then
        STEP_DONE=$((STEP_DONE + 1))
        return 0
    fi
    "$@"
    STEP_DONE=$((STEP_DONE + 1))
}

# A step that belongs to one optional piece runs only when machines/ gives this machine that
# value for it, as in `step_if mise on`. A skip counts as done, since the run did all it should.
step_if() {
    local key="$1" want="$2"
    shift 2
    if [[ "$("$SRC_DIR/machine.sh" get "$key")" == "$want" ]]; then
        STEP_PIECE="$key" step "$@"
    elif [[ -n "$ONLY" && "$key" != "$ONLY" ]]; then
        STEP_DONE=$((STEP_DONE + 1))
    else
        echo "==> Skipping $(basename "${1%.sh}"), $key is not $want on $("$SRC_DIR/machine.sh" name)"
        STEP_DONE=$((STEP_DONE + 1))
    fi
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

# One password for the whole run. Several steps need root, the command line tools, a cask
# whose installer asks, the kanata daemons and the IVPN repair, and each used to ask on its own,
# minutes apart, so a run left alone stopped at the second prompt and waited for nobody. With a
# terminal, sudo asks once before the first step, and a background loop refreshes the timestamp
# until the run ends. Every later sudo in the run, a step's own or Homebrew's, then finds a
# valid timestamp and asks nothing, which is the whole change. A step that checks with sudo -n
# whether it may ask, as the kanata step and the command line tools step do, now goes ahead
# where it would have asked, which is the run doing what it was always going to do, one prompt
# earlier. Without a terminal nothing here runs, and every step behaves as it did.
#
# The timestamp is dropped when the run ends, so the terminal is not left holding root for
# another five minutes on the strength of a password typed for setup.
SUDO_HOLDER=""
hold_sudo() {
    [[ -t 0 ]] || return 0
    echo "==> One password for the whole run"
    if ! sudo -v; then
        echo "    sudo took no password, so each step that needs root asks for itself."
        echo ""
        return 0
    fi
    ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null || exit 0; sleep 50; done ) &
    SUDO_HOLDER=$!
    echo "    Kept until this run ends, so no later step asks again."
    echo ""
}
release_sudo() {
    [[ -n "$SUDO_HOLDER" ]] || return 0
    kill "$SUDO_HOLDER" 2>/dev/null
    # Collected, so the shell does not print a notice that a job it started was terminated.
    wait "$SUDO_HOLDER" 2>/dev/null
    SUDO_HOLDER=""
    sudo -k
    return 0
}

on_exit() {
    local code=$?
    # Before the password is dropped, since handing Homebrew back needs it.
    mdj_brew_return
    release_sudo
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

if [[ -n "$ONLY" ]]; then
    value="$("$SRC_DIR/machine.sh" get "$ONLY")" || { trap - EXIT; rm -f "$MDJ_RUN_NOTES"; exit 1; }
    if [[ "$value" == off || "$value" == none ]]; then
        echo "$ONLY is $value on $("$SRC_DIR/machine.sh" name), so there is nothing to apply. src/machine.sh set $ONLY on gives it to this machine." >&2
        # Nothing ran, so the abort summary would only say twenty steps were lost.
        trap - EXIT
        rm -f "$MDJ_RUN_NOTES"
        exit 1
    fi
    echo "==> Only $ONLY, with the packages, the links, its grants and the check"
    echo ""
fi

# Which optional pieces this machine takes, from machines/. A machine with no rows takes the
# defaults, and the closing block says so, since a new machine is exactly when that is missed.
MACHINE="$("$SRC_DIR/machine.sh" name)"
echo "==> Machine $MACHINE"
for key in $("$SRC_DIR/machine.sh" keys); do
    echo "    $key = $("$SRC_DIR/machine.sh" get "$key")"
done
echo ""
if ! "$SRC_DIR/machine.sh" listed; then
    echo "$MACHINE has no pieces file under machines/ and took every default, capture it to change that" >> "$MDJ_RUN_NOTES"
fi

# Files a tool reads besides the config this repository links, left on this machine from before
# it, are asked about here rather than when the stow step reaches them, since that is minutes
# into the run and a question there holds everything after it until somebody comes back. The
# stow step owns the scan and the question, this only asks it early and passes the answer on.
# A run with no terminal takes MDJ_SHADOWS instead, and AGENTS.md says who asks for it.
if [[ -z "${MDJ_SHADOWS:-}" && -t 0 ]]; then
    MDJ_SHADOWS="$("$SRC_DIR/setup-stow-dotfiles.sh" --ask-shadows)"
    export MDJ_SHADOWS
    [[ -n "$MDJ_SHADOWS" ]] && echo ""
fi

hold_sudo

# Make sure the command line tools carry an SDK for this macOS, before anything that compiles
# or wants one. Homebrew refuses a formula without a bottle otherwise, so this runs first.
step "$SRC_DIR/install-xcode-clt.sh"

# Install Homebrew package manager
step "$SRC_DIR/install-homebrew.sh"

# Homebrew that belongs to another account is borrowed for the whole run and returned when it
# ends, however it ends, so every step installs as this account. A step run alone borrows for
# itself. src/lib/brew.sh has the loan, and decisions/homebrew-owner.md the reasoning. A loan
# that cannot be taken, with no terminal for the password, leaves the package step to fail.
mdj_brew_borrow || true

# Install packages from Brewfile
step "$SRC_DIR/install-homebrew-packages.sh"

# Install oh-my-zsh framework
step "$SRC_DIR/install-ohmyzsh.sh"

# Install oh-my-zsh plugins (autosuggestions, syntax highlighting, fzf-tab)
step "$SRC_DIR/install-ohmyzsh-plugins.sh"

# Install Claude Code from the native installer, which keeps itself updated
step "$SRC_DIR/install-claude-code.sh"

# Stow dotfiles to home directory
step "$SRC_DIR/setup-stow-dotfiles.sh"


# Install the runtimes the mise module lists, python, ruby, node, go, rust and uv
step_if mise on "$SRC_DIR/install-mise-tools.sh"

# Install tmux plugins via TPM
step "$SRC_DIR/install-tmux-plugins.sh"

# Setup .zshrc with Powerlevel10k
step "$SRC_DIR/setup-zshrc.sh"

# Bootstrap Neovim plugins
step "$SRC_DIR/bootstrap-nvim.sh"

# Ask which editor opens development files from Finder, and make it their default
step "$SRC_DIR/setup-dev-defaults.sh"

# Remap Caps Lock -> F18 for the Hammerspoon Hyper key
step_if hammerspoon on "$SRC_DIR/setup-capslock-hyper.sh"

# Turn off the macOS shortcuts that take a chord Olm uses, Show Help menu on Command and ?, which
# Olm's key panel answers inside every list. Changes only the one flag, says so, and does nothing
# when it is already off. decisions/macos-shortcuts.md has why.
step_if hammerspoon on "$SRC_DIR/setup-macos-shortcuts.sh"

# Install the Karabiner driver kanata types through, at the version dotfiles/kanata/DRIVER pairs
# with the installed kanata, and run both as launchd daemons. Needs root, which the run already
# holds. Its grants are left to the grants step below, which is what MDJ_GRANTS_LATER says.
step_if kanata on "$SRC_DIR/setup-kanata.sh"

# Restore the file modes IVPN's daemon requires inside its own bundle, which the Homebrew
# cask does not set because it copies the app rather than running IVPN's installer. Without
# this the daemon cannot start at all on a freshly bootstrapped machine. Prompts for sudo
# only when there is something to repair, and does nothing when IVPN is not installed.
step_if vpn ivpn "$SRC_DIR/setup-ivpn-permissions.sh"

# Wire the statusline script into Claude Code's settings.json
step "$SRC_DIR/setup-claude-settings.sh"

# Register the herdr module's local plugin, which stow places but cannot register
step_if herdr on "$SRC_DIR/setup-herdr-plugins.sh"

# Every permission a module declares and macOS has not given yet. With a terminal each required
# one is opened where it is given and waited for, a few minutes at most, with Enter to skip, and
# what is still missing goes into the closing notes. Without one it only leaves those notes. It
# runs after every step that installs or starts something a grant applies to, and before the
# check below, so the check reads the grants as they now are. Run it alone with
# src/setup-grants.sh, and decisions/setup-grants.md has the reasoning.
step "$SRC_DIR/setup-grants.sh" ${ONLY:+"$ONLY"}

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
# files. theme/AGENTS.md has the whole contract.
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
