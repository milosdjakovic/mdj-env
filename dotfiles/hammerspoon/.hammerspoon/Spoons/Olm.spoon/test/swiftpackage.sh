#!/bin/bash
#
# Builds the swift chooser's sources as the Swift package beside them, with no LuaSkin and no Lua,
# and runs olm-chooser-smoke, which shows a list from a fake source with no window, step 0.6 of
# docs/PLAN-STANDALONE.md. It builds with the swift inside the command line tools, the toolchain the
# root declares as swiftc-clt, so it needs nothing the Hammerspoon build does not. Exit 2 when this
# machine has none, the code the other gates use for a machine that cannot run them.
#
# Two facts about that toolchain, found on 2026-11-07 with macOS 27's tools. Its default build
# system fails to start, so this passes the older native one, which works and is deprecated. And it
# ships neither XCTest nor Swift Testing, so the check is an executable rather than a test target,
# and `swift test` waits for a full Xcode, decisions/olm-standalone.md.
#
# The build goes to a cache outside the checkout, so nothing is written beside the sources and an
# unchanged second run builds nothing.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
package="$here/../lib/chooser/providers/swift"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "swiftpackage: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/swiftchooser-package"
mkdir -p "$scratch"

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$package" && DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-chooser-smoke) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "swiftpackage, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-chooser-smoke"
