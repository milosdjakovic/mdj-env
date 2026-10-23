#!/bin/bash
set -e

# Turn off the macOS keyboard shortcuts that take a chord this repository uses.
#
# macOS answers some chords itself, before any application or event tap sees the key, so a
# chord Olm binds is dead on a machine where the system still holds it. The one this step frees
# today is symbolic hotkey 98, Show Help menu, which sits on Command, Shift and slash. Olm's key
# panel, the list of every key an open list answers, is on Command and ? inside every list, and
# Command and ? is that same chord, so the panel's key never reaches a list until the system lets
# go of it. Measured on 2026-10-23, decisions/macos-shortcuts.md has the record.
#
# Only the enabled flag of the entry is changed. Whatever chord the entry holds is kept, so a
# machine where a person moved it keeps their choice, and an entry that does not exist yet is
# written with the system's own default chord and switched off. The domain is exported, the one
# flag changed with plutil, and the whole domain imported back, so every other shortcut in it
# is left exactly as it was. activateSettings then tells the running session to read it again,
# which is what makes the change take effect without logging out.
#
# Idempotent. A machine where the shortcut is already off is told so in one line and nothing is
# written. Run it again any time.
#
# Nothing here needs root, the domain belongs to the person running it.

DOMAIN="com.apple.symbolichotkeys"
HOTKEY="98"
NAME="Show Help menu"
ACTIVATE="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

# shellcheck source=lib/backup.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/backup.sh"

echo "==> macOS shortcuts Olm needs free"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
plist="$work/symbolichotkeys.plist"

# The domain as the running session holds it, which can be newer than the file on disk.
if ! defaults export "$DOMAIN" "$plist" 2>/dev/null; then
    echo '{}' | plutil -convert xml1 -o "$plist" -
fi

# true, false, or nothing when the entry or its flag is absent, which the system reads as on.
state="$(plutil -extract "AppleSymbolicHotKeys.$HOTKEY.enabled" raw -o - "$plist" 2>/dev/null || true)"

if [ "$state" = "false" ]; then
    echo "    $NAME, symbolic hotkey $HOTKEY, is already off, nothing changed."
    exit 0
fi

if ! plutil -extract "AppleSymbolicHotKeys" xml1 -o /dev/null "$plist" 2>/dev/null; then
    plutil -insert "AppleSymbolicHotKeys" -dictionary "$plist"
fi

if plutil -extract "AppleSymbolicHotKeys.$HOTKEY" xml1 -o /dev/null "$plist" 2>/dev/null; then
    # An entry exists, on or with no flag at all. Only the flag is set, its chord is kept.
    plutil -replace "AppleSymbolicHotKeys.$HOTKEY.enabled" -bool NO "$plist"
else
    # No entry yet. The system's default chord, slash on key code 44 with Command and Shift,
    # 1179648, written switched off.
    plutil -insert "AppleSymbolicHotKeys.$HOTKEY" -json \
        '{"enabled":false,"value":{"parameters":[47,44,1179648],"type":"standard"}}' "$plist"
fi

defaults import "$DOMAIN" "$plist"

if [ -x "$ACTIVATE" ]; then
    "$ACTIVATE" -u
    echo "    Turned off $NAME, symbolic hotkey $HOTKEY, so Command and ? reaches an open Olm list."
else
    echo "    Turned off $NAME, symbolic hotkey $HOTKEY."
    mdj_note "The $NAME shortcut is off from the next login, since activateSettings was not found to apply it now."
fi
