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
# Our own external plugins, each a folder under the app's Plugins/External, are copied into
# ~/.olm/plugins, their sources and manifest only, and Olm.app builds each whose sources moved as it
# starts, docs/DESIGN-APP-PLUGINS.md. A plugin whose manifest says "test" is the runner's check and is
# never installed. The copy keeps the files' times, so an unchanged plugin is not built again.
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
plugins="$ROOT/dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/app/Plugins/External"

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

for dir in "$plugins"/*/; do
  manifest="${dir}olm-plugin.json"
  [ -f "$manifest" ] || continue
  grep -Eq '"test"[[:space:]]*:[[:space:]]*true' "$manifest" && continue
  id="$(basename "$dir")"
  dest="$HOME/.olm/plugins/$id"
  mkdir -p "$dest"
  rm -rf "$dest/Sources"
  cp -Rp "${dir}Sources" "$dest/Sources"
  cp -p "$manifest" "$dest/olm-plugin.json"
  echo "    plugin $id, in $dest"
done

old="$HOME/.olm/app/Olm.app"
if [ -d "$old" ]; then
  "$lsregister" -u "$old" >/dev/null 2>&1
  mdj_note "An older Olm.app is still in ~/.olm/app, unregistered so olm:// reaches /Applications/Olm.app. Quit it and remove that folder when you like."
fi
