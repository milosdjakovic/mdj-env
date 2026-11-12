#!/bin/bash
set -e

# Install the Herdr desktop app from its own installer, on a machine whose herdr-app piece is on.
#
# The installer checks the download against the SHA-256 in Herdr's release manifest, puts
# Herdr.app in ~/Applications, links `herdr-app` into ~/.local/bin, and installs herdr-core (`hc`)
# only when there is none. Running it again updates the app, and the app keeps itself and the
# core current from then on, so this step installs once and never runs it again, the same way
# install-herdr.sh treats herdr. decisions/herdr-app-install.md has it.

# Found by bundle id rather than by path, so an app moved into /Applications by hand still counts.
installed() {
    [[ -d "$HOME/Applications/Herdr.app" || -d /Applications/Herdr.app ]] && return 0
    [[ -n "$(mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" 2>/dev/null | head -1)" ]]
}

if installed; then
    echo "Herdr app already installed, it updates itself"
else
    echo "Installing the Herdr app..."
    curl -fsSL https://releases.herdr.dev/app/install.sh | sh
    echo "Herdr app installed"
fi
