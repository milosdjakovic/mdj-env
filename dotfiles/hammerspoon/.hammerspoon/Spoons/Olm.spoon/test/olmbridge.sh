#!/bin/bash
#
# Checks Olm.app's end of the bridge with no Hammerspoon, step 2.3 of docs/PLAN-STANDALONE.md. It
# builds olm-bridge-check from app/ with the swift inside the command line tools, as
# test/olmfixtures.sh builds its program, and runs it, which listens on a socket of its own in a
# temporary folder and answers itself as Hammerspoon would. It touches no running app and takes no
# lock. Exit 2 when this machine has no command line tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmbridge: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$here/../app" && DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-bridge-check) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmbridge, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-bridge-check"
