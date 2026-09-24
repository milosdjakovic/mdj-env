#!/bin/bash
set -e

# Make sure this machine has the Xcode command line tools, and that they carry an SDK for the
# macOS it is running.
#
# Neovim's treesitter builds every parser from source on first open, and the Hammerspoon
# module compiles two small Swift helpers, the eyedropper's colour sampler and the browser
# permission probe. Homebrew needs the same thing for a reason that is easier to miss. A
# formula with no bottle counts as a build from source even when its install only copies a
# downloaded binary, and before any build from source Homebrew refuses to continue unless the
# toolchain has an SDK for the running macOS. It reads that SDK from the command line tools
# whenever they are installed, and falls back to Xcode only when they are not, whatever
# xcode-select points at.
#
# So the condition this step guarantees is exactly the one Homebrew checks. It used to ask
# xcode-select -p whether any developer directory was active, and an Xcode or a set of command
# line tools from before the last macOS upgrade answers yes. A second machine passed this
# step that way and then failed in the Homebrew step, with a message about Xcode that pointed
# nowhere near the cause.
#
# It runs first in setup.sh because everything later that compiles wants it, Homebrew
# included. It is the one step that stops the run when it cannot finish, since every later
# step that needs the toolchain would otherwise fail somewhere less legible.

CLT_DIR="/Library/Developer/CommandLineTools"
MACOS_MAJOR="$(/usr/bin/sw_vers -productVersion | cut -d. -f1)"

# The command line tools are installed and carry an SDK for this major version of macOS, the
# name Homebrew's own SDK locator looks for.
clt_ready() {
    [[ -x "$CLT_DIR/usr/bin/clang" ]] || return 1
    compgen -G "$CLT_DIR/SDKs/MacOSX${MACOS_MAJOR}*.sdk" > /dev/null
}

if clt_ready; then
    echo "Command line tools present with the macOS $MACOS_MAJOR SDK"
    exit 0
fi

if [[ -x "$CLT_DIR/usr/bin/clang" ]]; then
    echo "The command line tools here have no macOS $MACOS_MAJOR SDK, updating them..."
else
    echo "Installing the Xcode command line tools..."
fi

# Headless first, which is how Homebrew's own installer does it. The placeholder file is what
# makes softwareupdate list the command line tools at all, and the newest label it lists is
# the one for this macOS. Installing needs root, so it is tried only when a password can be
# typed or sudo already holds one.
PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
if [[ -t 0 ]] || /usr/bin/sudo -n true 2>/dev/null; then
    touch "$PLACEHOLDER"
    trap 'rm -f "$PLACEHOLDER"' EXIT
    label="$(/usr/sbin/softwareupdate -l 2>/dev/null |
        grep -B 1 -E 'Command Line Tools' |
        awk -F'*' '/^ *\*/ {print $2}' |
        sed -e 's/^ *Label: //' -e 's/^ *//' |
        sort -V |
        tail -n 1)"
    rm -f "$PLACEHOLDER"

    if [[ -n "$label" ]]; then
        echo "Installing $label, which asks for your password..."
        /usr/bin/sudo /usr/sbin/softwareupdate -i "$label" || true
    fi
fi

if clt_ready; then
    echo "Command line tools present with the macOS $MACOS_MAJOR SDK"
    exit 0
fi

# Apple's dialog is the fallback, for when softwareupdate lists nothing or the install failed.
# Someone has to click it, so it is raised and waited for only when there is a terminal.
if [[ -t 0 ]]; then
    echo "Falling back to Apple's installer, expect a dialog..."
    # Answers non zero when the tools are already there in some form, which is the update
    # case, so the wait below is what decides what actually happened.
    /usr/bin/xcode-select --install 2>/dev/null || true

    WAIT_SECONDS=900
    POLL_SECONDS=10
    echo "Waiting for it to finish, up to $((WAIT_SECONDS / 60)) minutes. Ctrl C stops waiting."
    waited=0
    while (( waited < WAIT_SECONDS )); do
        if clt_ready; then
            echo ""
            echo "Command line tools present with the macOS $MACOS_MAJOR SDK"
            exit 0
        fi
        sleep "$POLL_SECONDS"
        waited=$(( waited + POLL_SECONDS ))
        printf '.'
    done
    echo ""
fi

echo "Error: the command line tools with the macOS $MACOS_MAJOR SDK are not on this machine."
echo "       Run ./setup.sh again from a terminal so the install can ask for your password,"
echo "       or install them from System Settings, General, Software Update."
exit 1
