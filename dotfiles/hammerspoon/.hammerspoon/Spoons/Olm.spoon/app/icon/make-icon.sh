#!/bin/bash
#
# Redraws app/Olm.icns from make-icon.swift beside this file, with the command line tools' swift and
# macOS's iconutil. Run by hand when the icon changes, then commit Olm.icns.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
SDKROOT="$tools/SDKs/MacOSX.sdk" DEVELOPER_DIR="$tools" "$tools/usr/bin/swiftc" -O "$here/make-icon.swift" -o "$work/make-icon"
"$work/make-icon" "$work/Olm.iconset"
iconutil -c icns "$work/Olm.iconset" -o "$here/../Olm.icns"
echo "$here/../Olm.icns"
