#!/bin/bash
#
# Builds Olm.app from source and puts it where it runs, where the olmapp piece is on, step 1.1 of
# dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLAN-STANDALONE.md. The app lives in
# /Applications/Olm.app, an app a person opens like any other, and was built into ~/.olm/app until
# 2026-11-23. It is registered with LaunchServices so the olm:// URLs reach it. Running this again
# rebuilds it, which costs nothing when the sources did not change.
#
# A copy left in ~/.olm/app by an older run shares the bundle id, so it is unregistered, which
# keeps olm:// on the new copy, and left on disk, with a closing note saying it can be removed.
#
# Switching the piece off stops a run from building it and removes nothing, rule 4 of AGENTS.md.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=src/lib/backup.sh
source "$ROOT/src/lib/backup.sh"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
build="$ROOT/dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/app/build.sh"

echo "==> Building Olm.app"
app="$("$build" "/Applications")"
status=$?
if [ "$status" -eq 2 ]; then
  mdj_note "Olm.app was not built, this machine has no command line tools. src/install-xcode-clt.sh installs them."
  exit 0
elif [ "$status" -ne 0 ]; then
  exit "$status"
fi
"$lsregister" -f "$app"
echo "    $app, registered for olm:// URLs"

old="$HOME/.olm/app/Olm.app"
if [ -d "$old" ]; then
  "$lsregister" -u "$old" >/dev/null 2>&1
  mdj_note "An older Olm.app is still in ~/.olm/app, unregistered so olm:// reaches /Applications/Olm.app. Quit it and remove that folder when you like."
fi
