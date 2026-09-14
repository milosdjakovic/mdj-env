#!/bin/bash
set -e

# Repair the file modes IVPN's daemon demands inside its own app bundle.
#
# The IVPN agent validates a handful of files at startup and refuses to run if any of them
# is readable by group or other, the test being (mode & 077) == 0. IVPN's own .pkg installer
# lays them down as 600. The Homebrew cask does not use that installer, it ships only the
# App artifact and copies IVPN.app out of a DMG, and that copy normalizes the modes to 644.
# So a machine bootstrapped from this repository's Brewfile gets a daemon that cannot start.
#
# The failure is silent from every angle that is easy to look at. launchd loads the
# privileged helper and spawns it happily, the helper passes its own codesign and ownership
# checks and logs that it is launching the agent, and then the agent exits 1 within a
# millisecond. It never writes /Library/Application Support/IVPN/port.txt, which is the only
# thing the GUI polls for, so the app reports "Error connecting to IVPN daemon" and points at
# Login Items, which is not the problem. The agent's own log is off by default, so nothing
# anywhere states the real reason until it is run by hand with -logging.
#
# 600 is the vendor's own intended state for these files, not something invented here, so
# this restores what the pkg installer would have done rather than modifying the app. File
# modes are not part of the code signature's resource seal, so the bundle stays valid and
# notarized.
#
# The same repair also restores the CLI: the agent creates /usr/local/bin/ivpn when it
# starts, so while the daemon is dead the ivpn command does not exist either, and the Olm
# VPN plugin's IVPN backend has nothing to resolve.

APP="/Applications/IVPN.app"
ETC="$APP/Contents/Resources/etc"

# The files the agent validates under this rule. Named one by one rather than repaired as a
# blanket chmod over the directory, since the rest of that directory is the vendor's business
# and a wide chmod inside a signed bundle is a bigger claim than this script has any reason
# to make. A file that is absent is skipped, so a future version dropping one is not an error.
FILES=(ca.crt ta.key dnscrypt-proxy-template.toml)

# IVPN is an optional dependency, declared that way by the vpn plugin because a person is
# expected to have whichever VPN they actually pay for. A machine without it is not a fault.
if [ ! -d "$APP" ]; then
    echo "IVPN not installed; no bundle permissions to repair"
    exit 0
fi

needs=()
for f in "${FILES[@]}"; do
    path="$ETC/$f"
    [ -e "$path" ] || continue
    # %Lp is the permission bits alone, in octal. 8# forces base 8 so 644 is not read as
    # six hundred and forty four. A nonzero AND against 077 means group or other has access.
    mode="$(stat -f "%Lp" "$path")"
    if (( 8#$mode & 8#077 )); then
        needs+=("$path")
    fi
done

if [ ${#needs[@]} -eq 0 ]; then
    echo "IVPN bundle permissions already correct"
    exit 0
fi

echo "==> Repairing IVPN bundle permissions (${#needs[@]} file(s) readable by group/other)..."
for path in "${needs[@]}"; do
    echo "    ${path#"$APP/"}"
done
echo "    These are root-owned inside /Applications, so this step needs sudo."

sudo chmod 600 "${needs[@]}"

# Take the fix live rather than leaving it to the next launch. The helper is demand-launched
# over mach IPC by the GUI, so a broken daemon is in a respawn loop and would pick the repair
# up on its own within seconds, but only while the app happens to be running. Kicking the job
# makes this deterministic when it is loaded, and there is nothing to kick on a fresh machine
# where IVPN has never been opened and the helper has not been installed yet. Best effort
# either way, since the repair above is the part that matters and a failure to restart is not
# a reason to fail the setup. The sudo timestamp from the chmod is still valid, so this does
# not prompt a second time.
if launchctl print system/net.ivpn.client.Helper >/dev/null 2>&1; then
    echo "    Restarting the IVPN daemon..."
    sudo launchctl kickstart -k system/net.ivpn.client.Helper >/dev/null 2>&1 || true
fi

echo "IVPN bundle permissions repaired"
