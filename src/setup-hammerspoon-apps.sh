#!/bin/bash
set -euo pipefail

# Give Hammerspoon this machine's own data, its Hyper app keys and its display profiles.
#
#   setup-hammerspoon-apps.sh            copy this machine's files into place
#   setup-hammerspoon-apps.sh --capture  give this machine files of its own, from what it has now
#   setup-hammerspoon-apps.sh --discard  copy over a file that was edited by hand, losing the edit
#
# Which app a Hyper key reaches and how the monitors are arranged differ between machines, so
# neither is in the stowed config. machines/<name>/hammerspoon-<kind>.lua holds a machine's own,
# and machines/default/hammerspoon-<kind>.lua what a machine with none takes, for apps the ones
# macOS ships and the Brewfile installs, for displays nothing. Each kind is copied to
# ~/.hammerspoon/machine-<kind>.lua, which config/machine.lua reads. The copies sit beside the
# stowed config/ rather than inside it, since config/ is a link into this checkout and a copy there
# would land in git, and the module's NO-FOLD keeps ~/.hammerspoon a real directory for the same
# reason. Hammerspoon's own watcher reloads the config when a copy changes.
#
# A copy is this repository's output, so a change made to it by hand would be lost on the next
# run. Each copy is remembered beside it as .machine-<kind>.copied, and a copy that differs from
# what was last written is refused rather than overwritten, naming the file to move the change
# into. --discard overwrites it anyway. An app key written into config/keymap.lua is said the same
# way, since it reaches every machine rather than this one. Both are closing notes rather than
# failures, so a setup run goes on, and a run alone exits nonzero so the refusal is not missed.
#
# --capture writes machines/<this machine>/hammerspoon-<kind>.lua from the copy in place now, the
# default on a machine that never had one, for each kind this machine has no file of yet. Edit the
# new file, run this again without the flag, and commit it. Only the machine it runs on is
# written, never another one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_DIR="$HOME/.hammerspoon"
KEYMAP="$ROOT/dotfiles/hammerspoon/.hammerspoon/config/keymap.lua"
KINDS="apps displays"

# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

machine="$("$SCRIPT_DIR/machine.sh" name)"

mode=""
case "${1:-}" in
    "") ;;
    --capture | --discard) mode="$1" ;;
    *) echo "usage: setup-hammerspoon-apps.sh [--capture | --discard]" >&2; exit 2 ;;
esac

if [[ "$mode" == "--capture" ]]; then
    wrote=0
    for kind in $KINDS; do
        own="$ROOT/machines/$machine/hammerspoon-$kind.lua"
        if [[ -f "$own" ]]; then
            echo "machines/$machine/hammerspoon-$kind.lua already exists, edit it rather than capturing again"
            continue
        fi
        from="$CONFIG_DIR/machine-$kind.lua"
        [[ -f "$from" ]] || from="$ROOT/machines/default/hammerspoon-$kind.lua"
        mkdir -p "$(dirname "$own")"
        cp "$from" "$own"
        echo "Wrote machines/$machine/hammerspoon-$kind.lua from $from"
        wrote=1
    done
    if [[ $wrote -eq 1 ]]; then
        echo "Add this machine's own lines to it, run $0 to apply them, and commit it"
    fi
    exit 0
fi

if [[ -L "$CONFIG_DIR" ]]; then
    echo "Error: ~/.hammerspoon is a symlink, so a copy would land in this checkout. Run src/setup-stow-dotfiles.sh, which makes it a real directory." >&2
    exit 1
fi
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "Error: ~/.hammerspoon is missing. Stow the hammerspoon package first." >&2
    exit 1
fi

refused=0
for kind in $KINDS; do
    src="$ROOT/machines/default/hammerspoon-$kind.lua"
    own="$ROOT/machines/$machine/hammerspoon-$kind.lua"
    [[ -f "$own" ]] && src="$own"
    label="${src#"$ROOT"/}"
    out="$CONFIG_DIR/machine-$kind.lua"
    stamp="$CONFIG_DIR/.machine-$kind.copied"

    if [[ -f "$out" ]] && cmp -s "$src" "$out"; then
        echo "Hammerspoon $kind already match $label"
        cp "$src" "$stamp"
        continue
    fi

    # A copy that is neither what was last written nor absent was changed by hand.
    if [[ -f "$out" && "$mode" != "--discard" ]] && ! { [[ -f "$stamp" ]] && cmp -s "$stamp" "$out"; }; then
        mdj_note "~/.hammerspoon/machine-$kind.lua was edited by hand and was left as it is. Move the change into machines/$machine/hammerspoon-$kind.lua, after src/setup-hammerspoon-apps.sh --capture if that file does not exist, and run src/setup-hammerspoon-apps.sh again, or drop it with src/setup-hammerspoon-apps.sh --discard"
        refused=1
        continue
    fi

    tmp="$(mktemp "$CONFIG_DIR/.machine-$kind.XXXXXX")"
    cp "$src" "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$out"
    cp "$src" "$stamp"
    echo "Hammerspoon $kind copied from $label"
done

# An app key in the shared keymap reaches every machine, which is what these files exist to avoid.
if grep -nE '^[[:space:]]*\["[^"]+"\][[:space:]]*=[[:space:]]*"apptoggler\.' "$KEYMAP" > /dev/null; then
    lines="$(grep -nE '^[[:space:]]*\["[^"]+"\][[:space:]]*=[[:space:]]*"apptoggler\.' "$KEYMAP" | cut -d: -f1 | paste -sd, -)"
    mdj_note "config/keymap.lua binds an app directly on line $lines, which reaches every machine. Move it into machines/$machine/hammerspoon-apps.lua and run src/setup-hammerspoon-apps.sh, or remove it"
    refused=1
fi

# Inside setup.sh the notes carry the refusal, alone the exit status does too.
[[ -n "${MDJ_RUN_NOTES:-}" ]] && exit 0
exit $refused
