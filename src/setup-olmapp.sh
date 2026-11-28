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
# It is signed with a certificate made once on this Mac, src/lib/olm-signing.sh, so the permissions
# Olm holds for its plugins match only a program signed with this Mac's key. A certificate that
# cannot be made leaves the app signed as before, by its bundle id, with a closing note.
#
# Every plugin of ours is core, built into the app, since 2026-11-28, so nothing is copied into
# ~/.olm/plugins, which holds only plugins someone installed, docs/DESIGN-APP-PLUGINS.md. Olm.app
# moves an external copy of one of ours left there by an older run into the Trash as it starts.
#
# The olm command, inside the app, is linked as ~/.local/bin/olm, where setup-zshrc.sh puts the PATH first.
#
# Switching the piece off stops a run from building it and removes nothing, rule 4 of AGENTS.md.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=src/lib/backup.sh
source "$ROOT/src/lib/backup.sh"
# shellcheck source=src/lib/olm-signing.sh
source "$ROOT/src/lib/olm-signing.sh"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
build="$ROOT/dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/app/build.sh"

if ! olm_signing_ready; then
  mdj_note "Olm.app is signed by its bundle id alone, the signing certificate could not be made in ~/.olm/state/signing."
fi
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

# The olm command inside the app, linked onto the PATH, docs/DESIGN-APP-PLUGINS.md The olm command. A
# file of another's at that name is left alone and said, since this step removes nothing.
cli="$HOME/.local/bin/olm"
mkdir -p "$HOME/.local/bin"
if [ -L "$cli" ] || [ ! -e "$cli" ]; then
  ln -sfn "$app/Contents/Resources/bin/olm" "$cli"
  echo "    olm command, in $cli"
else
  mdj_note "~/.local/bin/olm is a file this step did not put there, so the olm command was not linked. Move it aside and run src/setup-olmapp.sh again."
fi

old="$HOME/.olm/app/Olm.app"
if [ -d "$old" ]; then
  "$lsregister" -u "$old" >/dev/null 2>&1
  mdj_note "An older Olm.app is still in ~/.olm/app, unregistered so olm:// reaches /Applications/Olm.app. Quit it and remove that folder when you like."
fi
