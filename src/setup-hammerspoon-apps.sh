#!/bin/bash
set -euo pipefail

# Give Hammerspoon this machine's Hyper app keys.
#
#   setup-hammerspoon-apps.sh            copy this machine's file into place
#   setup-hammerspoon-apps.sh --capture  give this machine a file of its own, from what it has now
#
# Which app a Hyper key reaches differs between machines, since not every machine has every app,
# so the keys are not in the stowed config. machines/<name>/hammerspoon-apps.lua holds a machine's
# own, and machines/default/hammerspoon-apps.lua holds the ones every machine can take, the apps
# macOS ships and the ones the Brewfile installs. This copies the one that applies here to
# ~/.hammerspoon/machine-apps.lua, which config/machine.lua reads and config/keymap.lua adds to
# its keys. The copy sits beside the stowed config/ rather than inside it, since config/ is a link
# into this checkout and a copy there would land in git, and the module's NO-FOLD keeps
# ~/.hammerspoon a real directory for the same reason. Hammerspoon's own watcher reloads the
# config when the file changes, so a changed file is live without a step of its own.
#
# --capture writes machines/<this machine>/hammerspoon-apps.lua from the file in place now, which
# is the default on a machine that has none, and refuses when the machine already has one. Edit
# the new file to add this machine's own keys, run this again without the flag, and commit it.
# Only the machine it runs on is written, never another one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_DIR="$HOME/.hammerspoon"
OUT="$CONFIG_DIR/machine-apps.lua"

machine="$("$SCRIPT_DIR/machine.sh" name)"
own="$ROOT/machines/$machine/hammerspoon-apps.lua"
default="$ROOT/machines/default/hammerspoon-apps.lua"

if [[ "${1:-}" == "--capture" ]]; then
    if [[ -f "$own" ]]; then
        echo "machines/$machine/hammerspoon-apps.lua already exists, edit it rather than capturing again"
        exit 1
    fi
    from="$OUT"
    [[ -f "$from" ]] || from="$default"
    mkdir -p "$(dirname "$own")"
    cp "$from" "$own"
    echo "Wrote machines/$machine/hammerspoon-apps.lua from $from"
    echo "Add this machine's own keys to it, run $0 to apply them, and commit it"
    exit 0
elif [[ $# -gt 0 ]]; then
    echo "usage: setup-hammerspoon-apps.sh [--capture]" >&2
    exit 2
fi

if [[ -L "$CONFIG_DIR" ]]; then
    echo "Error: ~/.hammerspoon is a symlink, so the copy would land in this checkout. Run src/setup-stow-dotfiles.sh, which makes it a real directory." >&2
    exit 1
fi
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "Error: ~/.hammerspoon is missing. Stow the hammerspoon package first." >&2
    exit 1
fi

src="$default"
[[ -f "$own" ]] && src="$own"
label="${src#"$ROOT"/}"

if [[ -f "$OUT" ]] && cmp -s "$src" "$OUT"; then
    echo "Hammerspoon app keys already match $label"
    exit 0
fi

tmp="$(mktemp "$CONFIG_DIR/.machine-apps.XXXXXX")"
cp "$src" "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$OUT"
echo "Hammerspoon app keys copied from $label"
