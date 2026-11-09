#!/bin/bash
#
# Builds Olm.app from the package beside this file and wraps it into a bundle at the folder given,
# step 1.1 of docs/PLAN-STANDALONE.md. `build.sh DIR` leaves DIR/Olm.app, and prints its path.
#
# It builds with the swift inside the command line tools, the toolchain the swift chooser already
# needs, and passes the older native build system, since the default one fails to start in macOS
# 27's tools, the same as test/swiftpackage.sh. Exit 2 when this machine has no command line tools.
# The build goes to a cache outside the checkout, so nothing is written beside the sources. The
# bundle is signed ad hoc, which is what lets macOS run a bundle built on this machine, with a
# requirement naming its bundle id so a rebuild keeps the permissions the last one was given.

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
if ! (cd "$here" && DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
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
if ! DEVELOPER_DIR="$tools" "$tools/usr/bin/swiftc" -sdk "$tools/SDKs/MacOSX.sdk" -O "$here/../plugins/filesearch/sources/fileindex.swift" \
  "$here/Sources/OlmSearch/Match.swift" -o "$stage/Contents/Resources/fileindex" >"$log" 2>&1; then
  grep -E 'error' "$log" | head -20 >&2
  echo "olmapp: the index helper's build FAILED" >&2
  rm -rf "$stage"
  exit 1
fi
# Signed ad hoc with a designated requirement naming the bundle id, step 1.4j. Ad hoc alone makes
# the requirement the build's hash, so the privacy system took every build for a new app and forgot
# the folder permissions on each one.
if ! codesign --force --sign - --identifier local.olm.Olm \
  --requirements '=designated => identifier "local.olm.Olm"' "$stage" >"$log" 2>&1; then
  cat "$log" >&2
  echo "olmapp: signing FAILED" >&2
  rm -rf "$stage"
  exit 1
fi
rm -rf "$app"
mv "$stage" "$app"
echo "$app"
