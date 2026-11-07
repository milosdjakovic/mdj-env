#!/bin/bash
#
# Runs the shared fixtures through Olm.app's Swift ports, docs/PLAN-STANDALONE.md rule 4. It builds
# olm-fixtures from app/ with the swift inside the command line tools, the same way
# test/swiftpackage.sh builds the chooser's package, and runs it over test/fixtures. A kind the app
# has not ported yet is reported as not ported and is no failure. Exit 2 when this machine has no
# command line tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmfixtures: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$here/../app" && DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-fixtures) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmfixtures, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-fixtures" "$here/fixtures"
