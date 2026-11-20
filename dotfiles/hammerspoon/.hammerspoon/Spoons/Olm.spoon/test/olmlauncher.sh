#!/bin/bash
#
# Checks the launcher's catalog built in Olm.app, step 6.1 of docs/PLAN-STANDALONE.md and
# docs/DESIGN-APP-LAUNCHER.md. It builds olm-launcher-check from app/ with the swift inside the
# command line tools, as test/olmbridge.sh builds its program, and runs it, the order of
# host/launcher/init.lua's catalog over a share and applications of its own. It reads no machine's
# applications, touches no running app and takes no lock. Exit 2 when this machine has no command
# line tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmlauncher: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$here/../app" && SDKROOT="$tools/SDKs/MacOSX.sdk" DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-launcher-check) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmlauncher, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-launcher-check"
