#!/bin/bash
set -e

# Install packages from Brewfile via Homebrew

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/../Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
    echo "Error: Brewfile not found at $BREWFILE"
    exit 1
fi

# Present, not newest.
#
# This step's guarantee is that everything the Brewfile declares is on the machine, and that is
# the whole of it. Moving something already present to a newer version is a different job, and
# it is one a person chooses rather than one a setup run performs on the way past.
#
# The two were the same command until a cask upgrade wanted a password. The machine had the
# declared thing, so the guarantee was already met, and the run still aborted and left fourteen
# later steps unrun over a version bump none of them cared about. The same argument settled the
# Neovim bootstrap, where updating every plugin was a side effect of setting a machine up and
# is now a deliberate act performed on purpose and recorded.
#
# So upgrading is its own act, taken when it is the thing being done, and
# decisions/homebrew-upgrades.md has the reasoning.

# An app Homebrew did not install is left exactly where it is.
#
# brew bundle installs every cask with --adopt and offers no way to turn that off. Adopting
# claims an app already in /Applications as part of the install, and when a later part of the
# same install fails, Homebrew's rollback removes everything the install claimed, the adopted
# app included. So a cask that asks for a password nobody can type deleted a Docker.app it
# had never installed, on the second run of this script, with no copy in the Trash. The app was
# already present, which is all this step promises, so such a cask is skipped rather than
# adopted, and a rerun can never remove something it did not put there.
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

# Every Brewfile cask Homebrew has not installed whose app already sits in an app directory,
# one per line as the token, a tab, and the app. Without jq the artifacts cannot be read, so
# every cask not yet installed is held back with an empty app, until a later run once the
# Brewfile has put jq on the machine. Holding back is safe, adopting blind is not.
unmanaged_casks() {
    local wanted installed missing
    wanted="$(brew bundle list --cask --file="$BREWFILE" 2>/dev/null)"
    installed="$(brew list --cask -1 2>/dev/null)"
    missing="$(comm -23 <(sort <<< "$wanted") <(sort <<< "$installed") | grep . || true)"
    [[ -n "$missing" ]] || return 0

    if ! command -v jq > /dev/null 2>&1; then
        sed 's/$/\t/' <<< "$missing"
        return 0
    fi

    local token app
    # shellcheck disable=SC2086
    brew info --cask --json=v2 $missing |
        jq -r '.casks[] | .token as $t | .artifacts[] | .app? // empty
               | (.[1].target? // .[0]) | "\($t)\t\(split("/") | last)"' |
        while IFS=$'\t' read -r token app; do
            if [[ -e "/Applications/$app" || -e "$HOME/Applications/$app" ]]; then
                printf '%s\t%s\n' "$token" "$app"
            fi
        done
}

SKIP=""
while IFS=$'\t' read -r token app; do
    [[ -n "$token" ]] || continue
    [[ " $SKIP " == *" $token "* ]] && continue
    SKIP="${SKIP:+$SKIP }$token"
    if [[ -n "$app" ]]; then
        mdj_note "Cask $token skipped, $app is already installed but not by Homebrew, so it was left alone."
    else
        mdj_note "Cask $token held back, jq was missing so its app could not be checked. Run setup.sh again."
    fi
done <<< "$(unmanaged_casks)"

echo "Installing packages from Brewfile..."
HOMEBREW_BUNDLE_CASK_SKIP="${HOMEBREW_BUNDLE_CASK_SKIP:+$HOMEBREW_BUNDLE_CASK_SKIP }$SKIP" \
    brew bundle --no-upgrade --file="$BREWFILE"

echo "Packages installed successfully"
