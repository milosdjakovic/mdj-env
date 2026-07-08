#!/bin/bash

# Remap Caps Lock -> F18 at the HID level so Hammerspoon's HyperKey spoon can
# use it as a Hyper key (hold) with a tap-to-toggle-Caps-Lock fallback.
#
# Caps Lock is a toggle key and emits no usable key-down/key-up to an eventtap,
# so it cannot drive hold-vs-tap on its own. Remapping it to F18 (a normal,
# otherwise-unused key) gives Hammerspoon clean events to measure. hidutil is
# native macOS and runs as a one-shot (no background process, ~0 RAM); the
# LaunchAgent just re-applies the mapping at each login.
#
# TRADE-OFFS (important):
#   * This remap is machine-wide: Caps Lock is F18 in EVERY app, not just
#     Hammerspoon. Anything else that relied on Caps Lock is affected.
#   * Caps Lock toggling now DEPENDS ON HAMMERSPOON running. The remap is
#     applied at login unconditionally; Hammerspoon (HyperKey.spoon) is what
#     turns a quick F18 tap back into a Caps Lock toggle. If Hammerspoon is not
#     running, tapping Caps Lock does nothing until it starts again.
#
# TO UNDO completely:
#   launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.mdj.capslock-hyper.plist
#   rm ~/Library/LaunchAgents/com.mdj.capslock-hyper.plist
#   hidutil property --set '{"UserKeyMapping":[]}'   # clears the live remap

set -e

LABEL="com.mdj.capslock-hyper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Caps Lock (0x700000039) -> F18 (0x70000006D)
MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'

echo "==> Setting up Caps Lock -> F18 Hyper remap..."

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>$MAPPING</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST_EOF

# Reload the agent (idempotent: bootout ignores "not loaded")
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# Apply immediately so a reboot/login is not required
/usr/bin/hidutil property --set "$MAPPING" >/dev/null

echo "    Caps Lock is now F18. Hammerspoon (HyperKey.spoon) handles hold vs tap."
