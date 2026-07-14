#!/bin/bash

# Remap three keys to unused function keys at the HID level so Hammerspoon can
# drive them via eventtaps (hold-to-activate), without stamping modifier flags:
#
#   Caps Lock     -> F18   HyperKey.spoon     (app toggles; tap = toggle Caps Lock)
#   Right Command -> F17   WindowLeader.spoon (SUPER: all window ops, resize + move)
#   Right Option  -> F16   WindowLeader.spoon (META: defined but deactivated)
#
# Why remap at all? Caps Lock is a toggle key and emits no usable key-down/up.
# Right Command / Right Option ARE real modifiers, but (a) a held modifier stamps
# its flag onto every keystroke, and (b) hs.hotkey cannot tell left from right
# (both report as `cmd`/`alt`). Remapping each to a plain, otherwise-unused
# function key gives Hammerspoon clean, side-specific events to measure and
# swallow. hidutil is native macOS and runs as a one-shot (no background
# process, ~0 RAM); the LaunchAgent just re-applies the mapping at each login.
#
# All three mappings MUST live in a single UserKeyMapping set -- `hidutil
# property --set` replaces the whole table, so separate agents would clobber
# each other.
#
# TRADE-OFFS (important):
#   * These remaps are machine-wide: Caps Lock is F18, Right Command is F17 and
#     Right Option is F16 in EVERY app. The right-side modifiers lose their
#     normal function everywhere (the LEFT Command/Option keep working fully).
#   * The remapped keys only DO anything while Hammerspoon runs. The remap is
#     applied at login unconditionally; the spoons are what turn F18/F17/F16
#     events back into useful behavior. Without Hammerspoon, Caps Lock tap does
#     nothing and the window leaders are inert.
#
# TO UNDO completely:
#   launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.mdj.capslock-hyper.plist
#   rm ~/Library/LaunchAgents/com.mdj.capslock-hyper.plist
#   hidutil property --set '{"UserKeyMapping":[]}'   # clears the live remap

set -e

LABEL="com.mdj.capslock-hyper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Caps Lock (0x700000039) -> F18 (0x70000006D)
# Right Command (0x7000000E7) -> F17 (0x70000006C)
# Right Option (0x7000000E6) -> F16 (0x70000006B)
MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D},{"HIDKeyboardModifierMappingSrc":0x7000000E7,"HIDKeyboardModifierMappingDst":0x70000006C},{"HIDKeyboardModifierMappingSrc":0x7000000E6,"HIDKeyboardModifierMappingDst":0x70000006B}]}'

echo "==> Setting up Hyper/leader key remaps (Caps->F18, RCmd->F17, ROpt->F16)..."

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

echo "    Caps Lock->F18, Right Command->F17, Right Option->F16."
echo "    Hammerspoon (HyperKey / WindowLeader spoons) turns these into actions."
