#!/bin/bash
#
# Checks bringing an app forward in Olm.app, step 6.2 of docs/PLAN-STANDALONE.md and
# docs/DESIGN-APP-APPS.md. It builds olm-apps-check from app/ with the swift inside the command line
# tools, as test/olmbridge.sh builds its program, and runs it, the decision, the placement geometry,
# the press and the shadow's counts. It touches no running app and no window and takes no lock. Exit 2
# when this machine has no command line tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmapps: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$here/../app" && SDKROOT="$tools/SDKs/MacOSX.sdk" DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-apps-check) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmapps, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-apps-check"
