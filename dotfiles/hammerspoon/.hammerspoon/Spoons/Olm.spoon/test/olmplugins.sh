#!/bin/bash
#
# Checks Olm.app's runner for external plugins, step 4.1 of docs/PLAN-STANDALONE.md and
# docs/DESIGN-APP-PLUGINS.md. It builds olm-plugin-check from app/ with the swift inside the command
# line tools, as test/olmbridge.sh builds its program, and runs it. That builds the test plugin under
# app/Plugins/External/misbehave into ~/.olm/cache/plugin-check, runs it in its sandbox through the
# real runner, has it answer slowly, hang, spin, burn the processor, leak, crash and flood, and checks
# what the runner did about each while timing the main thread. It touches no running app and takes
# no lock, but it asks the Mullvad daemon for its status and takes about eighty seconds, so it is run
# on its own, before a change to app/Sources/OlmPlugins, rather than inside suite.sh dry. Exit 2 when
# this machine has no command line tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmplugins: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if ! (cd "$here/../app" && SDKROOT="$tools/SDKs/MacOSX.sdk" DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-plugin-check) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmplugins, the build FAILED"
  exit 1
fi
# Foundation's own cache complaints, from a sandboxed plugin denied ~/Library/Caches, are left out.
"$scratch/debug/olm-plugin-check" "$@" 2>&1 | grep -v -e 'NetworkStorageDB' -e 'there is no SQL cache' -e 'read-connection to the DB'
exit "${PIPESTATUS[0]}"
