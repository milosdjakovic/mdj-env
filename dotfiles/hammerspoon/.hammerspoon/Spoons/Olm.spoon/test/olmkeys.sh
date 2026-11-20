#!/bin/bash
#
# Checks Olm.app's keys with no keyboard, step 5.1 of docs/PLAN-STANDALONE.md and
# docs/DESIGN-APP-KEYS.md. It builds olm-keys-check from app/ with the swift inside the command line
# tools, as test/olmbridge.sh builds its program, and runs it, the resolver against the rules of
# lib/leader.lua and the shadow's pairing through a keymap in a temporary folder. It hears no
# keyboard, touches no running app and takes no lock. Exit 2 when this machine has no command line
# tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmkeys: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$here/../app" && SDKROOT="$tools/SDKs/MacOSX.sdk" DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-keys-check) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmkeys, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-keys-check"
