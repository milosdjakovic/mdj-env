#!/bin/bash
#
# Builds Olm.app from source and puts it where it runs, where the olmapp piece is on, step 1.1 of
# dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLAN-STANDALONE.md. The app lives in
# ~/.olm/app/Olm.app, beside the rest of Olm's data and out of the Applications folder, since it
# is a part of Olm rather than an app a person opens. It is registered with LaunchServices so the
# olm:// URLs reach it. Nothing starts it, and nothing in Hammerspoon uses it yet. Running this
# again rebuilds it, which costs nothing when the sources did not change.
#
# Switching the piece off stops a run from building it and removes nothing, rule 4 of AGENTS.md.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=src/lib/backup.sh
source "$ROOT/src/lib/backup.sh"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
build="$ROOT/dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/app/build.sh"

echo "==> Building Olm.app"
app="$("$build" "$HOME/.olm/app")"
status=$?
if [ "$status" -eq 2 ]; then
  mdj_note "Olm.app was not built, this machine has no command line tools. src/install-xcode-clt.sh installs them."
  exit 0
elif [ "$status" -ne 0 ]; then
  exit "$status"
fi
"$lsregister" -f "$app"
echo "    $app, registered for olm:// URLs"
