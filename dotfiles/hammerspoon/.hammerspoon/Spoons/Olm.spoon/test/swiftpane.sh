#!/bin/bash
#
# Builds test/swiftpane.swift with the swift chooser's own sources and runs it, showing no window.
# It needs what the provider builds with, the compiler inside the command line tools with an SDK
# for the running macOS, and Hammerspoon's LuaSkin framework to link against. Exit 2 when this
# machine has either missing, the code the other gates use for a machine that cannot run them.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
native="$here/../lib/chooser/providers/swift/native"
module_root="$(cd "$here/../../../.." && pwd -P)"

# The compiler the root declares as swiftc-clt, and the newest SDK for this macOS beside it, the
# same choice lib/swiftbuild.lua's toolchain makes.
tools="/Library/Developer/CommandLineTools"
compiler="$tools/usr/bin/swiftc"
major="$(sw_vers -productVersion | cut -d. -f1)"
sdk="$(ls -d "$tools/SDKs/MacOSX$major"*.sdk 2>/dev/null | sort | tail -n 1)"
if [ ! -x "$compiler" ] || [ ! -x "$tools/usr/bin/clang" ] || [ -z "$sdk" ]; then
  echo "swiftpane: no command line tools with a macOS $major SDK here, skipped"
  exit 2
fi

# The application, found the way runtime-probe finds it, from the module's own declaration.
bundle_id="$(awk -F'|' '/^[[:space:]]*#/ { next } { k = $2; gsub(/[[:space:]]/, "", k) } k == "app" { v = $3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit }' "$module_root/dependencies-module")"
app="$(osascript -e "POSIX path of (path to application id \"$bundle_id\")" 2>/dev/null)"
if [ -z "$app" ] || [ ! -d "$app/Contents/Frameworks/LuaSkin.framework" ]; then
  echo "swiftpane: Hammerspoon is not installed here, skipped"
  exit 2
fi
frameworks="${app%/}/Contents/Frameworks"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
sources=()
for name in Lua Model Surface List Bar Panel Pane Entry; do sources+=("$native/$name.swift"); done
# Top level code runs only from a file named main.swift.
cp "$here/swiftpane.swift" "$out/main.swift"
if ! "$compiler" -O -sdk "$sdk" -module-name OlmSwiftPaneTest -import-objc-header "$native/bridge.h" \
  -F "$frameworks" -framework LuaSkin -Xlinker -rpath -Xlinker "$frameworks" \
  "${sources[@]}" "$out/main.swift" -o "$out/swiftpane"; then
  echo "swiftpane, the build FAILED"
  exit 1
fi
"$out/swiftpane"
