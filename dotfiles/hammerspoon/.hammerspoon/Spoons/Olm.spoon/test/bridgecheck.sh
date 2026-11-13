#!/bin/bash
#
# The live check of step 2.2, test/bridgecheck.swift built and run against the running
# Hammerspoon, whose config must have the bridge's socket setting on. It stands in for Olm.app on
# ~/.olm/run/bridge.sock, so Olm.app must not be listening there, and it needs only the command
# line tools. Exit 2 when this machine has no compiler, the code the other gates use for a machine
# that cannot run them.
#
#   test/bridgecheck.sh [query]

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
compiler="$tools/usr/bin/swiftc"
major="$(sw_vers -productVersion | cut -d. -f1)"
sdk="$(ls -d "$tools/SDKs/MacOSX$major"*.sdk 2>/dev/null | sort | tail -n 1)"
if [ ! -x "$compiler" ] || [ -z "$sdk" ]; then
  echo "bridgecheck: no command line tools with a macOS $major SDK here, skipped"
  exit 2
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cp "$here/bridgecheck.swift" "$out/main.swift"
if ! "$compiler" -O -sdk "$sdk" -o "$out/bridgecheck" "$out/main.swift" 2>"$out/build.log"; then
  cat "$out/build.log"
  echo "bridgecheck: the client did not build"
  exit 1
fi
[ "${BRIDGECHECK_BUILD_ONLY:-}" = 1 ] && { echo "bridgecheck: built"; exit 0; }
"$out/bridgecheck" "$@"
