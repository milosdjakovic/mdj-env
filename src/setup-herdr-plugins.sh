#!/bin/bash
set -e

# Register the herdr module's local plugin with herdr.
#
# The three popups in that module are a plugin rather than plain keybindings, because a
# keybinding popup carries no title and herdr then labels its border with the literal word
# popup. A plugin pane requires a title, which is what gives them their names. The cost of
# that shape is this script. Stow puts the files in place, but a plugin also has to be
# registered, and herdr keeps that registration in its own global state rather than in
# config.toml, so a fresh machine has the files and no plugin until something links them.
#
# The plugin is linked rather than installed, since install is for GitHub sources and would
# copy the files into a managed checkout, which would fork them away from this repository.
# Linking points herdr at the stowed path, so an edit here is live with no reinstall.

PLUGIN_ID="mdj-tools"
PLUGIN_DIR="$HOME/.config/herdr/tools"

if ! command -v herdr >/dev/null 2>&1; then
    echo "herdr is not installed, skipping its plugin"
    exit 0
fi

if [ ! -f "$PLUGIN_DIR/herdr-plugin.toml" ]; then
    echo "herdr plugin manifest is not stowed at $PLUGIN_DIR, skipping"
    exit 0
fi

if herdr plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" \
    '.result.plugins[]? | select(.plugin_id == $id)' >/dev/null 2>&1; then
    echo "herdr plugin $PLUGIN_ID already registered"
    exit 0
fi

echo "Linking herdr plugin $PLUGIN_ID..."
herdr plugin link "$PLUGIN_DIR" >/dev/null
echo "herdr plugin $PLUGIN_ID linked successfully"
