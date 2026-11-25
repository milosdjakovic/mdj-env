#!/bin/bash
#
# Builds Olm.app from the package beside this file and wraps it into a bundle at the folder given,
# step 1.1 of docs/PLAN-STANDALONE.md. `build.sh DIR` leaves DIR/Olm.app, and prints its path.
#
# It builds with the swift inside the command line tools, the toolchain the swift chooser already
# needs, and passes the older native build system, since the default one fails to start in macOS
# 27's tools, the same as test/swiftpackage.sh. Exit 2 when this machine has no command line tools.
# The build goes to a cache outside the checkout, so nothing is written beside the sources. The
# bundle is signed with this Mac's own certificate when the caller names one, OLM_SIGN_KEYCHAIN,
# OLM_SIGN_PASSWORD_FILE and OLM_SIGN_IDENTITY, which src/setup-olmapp.sh does, so its requirement
# names the bundle id and the certificate and a rebuild keeps the permissions the last one was
# given. Otherwise it is signed ad hoc with a requirement naming the bundle id alone, which is
# what a check building into a folder of its own wants.
#
# SDKROOT names the tools' SDK for the build. Without it the link recorded the deployment target,
# 14.0, as the SDK the app was built against, and macOS then draws every window of the app in the
# look from before Liquid Glass, which is what the Olm Settings window showed in its S.2 trial on
# 2026-11-20. Hammerspoon records SDK 26, so the app now draws in the same era it does.

set -uo pipefail

out="${1:-}"
if [ -z "$out" ]; then
  echo "usage: build.sh DIR" >&2
  exit 64
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmapp: no command line tools here, not built" >&2
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch" "$out"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! (cd "$here" && SDKROOT="$tools/SDKs/MacOSX.sdk" DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  -c release --scratch-path "$scratch" --product Olm) >"$log" 2>&1; then
  grep -E 'error' "$log" | head -20 >&2
  echo "olmapp: the build FAILED" >&2
  exit 1
fi

# The bundle is put together beside the target and moved over it in one rename, so a running copy
# never sees a bundle half written.
app="$out/Olm.app"
stage="$out/.Olm.app.new"
rm -rf "$stage"
mkdir -p "$stage/Contents/MacOS"
cp "$scratch/release/Olm" "$stage/Contents/MacOS/Olm"
cp "$here/Info.plist" "$stage/Contents/Info.plist"
# File search's index helper, compiled from the plugin's own source so the app and the Lua side
# ask the same program, the file search plugin's Plugins/FileSearch/Index.swift. It is compiled
# with the shared search, Sources/OlmSearch/Match.swift, so it keeps a name exactly when the list
# would, as the Lua side compiles it.
mkdir -p "$stage/Contents/Resources"
# The app's icon, drawn by icon/make-icon.sh and committed, Info.plist's CFBundleIconFile.
cp "$here/Olm.icns" "$stage/Contents/Resources/Olm.icns"
# OlmPluginKit's source, compiled into every external plugin the app builds, docs/DESIGN-APP-PLUGINS.md.
cp "$here/PluginKit/OlmPluginKit.swift" "$stage/Contents/Resources/OlmPluginKit.swift"
# Olm's own external plugins, sealed by the app's signature, so a folder in ~/.olm/plugins holding the
# same files is known to be Olm's and runs without asking, PluginGate. One marked "test" is left out.
for dir in "$here"/Plugins/External/*/; do
  grep -Eq '"test"[[:space:]]*:[[:space:]]*true' "${dir}olm-plugin.json" && continue
  dest="$stage/Contents/Resources/Plugins/$(basename "$dir")"
  mkdir -p "$dest"
  cp -Rp "${dir}Sources" "$dest/Sources"
  cp -p "${dir}olm-plugin.json" "$dest/olm-plugin.json"
done
if ! DEVELOPER_DIR="$tools" "$tools/usr/bin/swiftc" -sdk "$tools/SDKs/MacOSX.sdk" -O "$here/../plugins/filesearch/sources/fileindex.swift" \
  "$here/Sources/OlmSearch/Match.swift" -o "$stage/Contents/Resources/fileindex" >"$log" 2>&1; then
  grep -E 'error' "$log" | head -20 >&2
  echo "olmapp: the index helper's build FAILED" >&2
  rm -rf "$stage"
  exit 1
fi
# With this Mac's certificate the requirement codesign makes is the bundle id and the certificate's
# hash, so only a program signed with its key matches the permissions Olm holds, step 2 of the
# permissions plan in docs/DESIGN-APP-PLUGINS.md. The keychain is unlocked first, since codesign
# asks for a locked one's password in a dialog, and a keychain that does not unlock stops the build
# rather than signing ad hoc, which would lose every permission given to the certificate.
# Without one, ad hoc with a requirement naming the bundle id, step 1.4j. Ad hoc alone makes the
# requirement the build's hash, so the privacy system took every build for a new app.
if [ -n "${OLM_SIGN_KEYCHAIN:-}" ]; then
  if ! security unlock-keychain -p "$(cat "${OLM_SIGN_PASSWORD_FILE:-/dev/null}")" "$OLM_SIGN_KEYCHAIN" >"$log" 2>&1; then
    echo "olmapp: the signing keychain $OLM_SIGN_KEYCHAIN did not unlock, not signed" >&2
    rm -rf "$stage"
    exit 1
  fi
  sign=(codesign --force --keychain "$OLM_SIGN_KEYCHAIN" --sign "${OLM_SIGN_IDENTITY:?}" --identifier local.olm.Olm "$stage")
else
  sign=(codesign --force --sign - --identifier local.olm.Olm \
    --requirements '=designated => identifier "local.olm.Olm"' "$stage")
fi
if ! "${sign[@]}" >"$log" 2>&1; then
  cat "$log" >&2
  echo "olmapp: signing FAILED" >&2
  rm -rf "$stage"
  exit 1
fi
rm -rf "$app"
mv "$stage" "$app"
echo "$app"
