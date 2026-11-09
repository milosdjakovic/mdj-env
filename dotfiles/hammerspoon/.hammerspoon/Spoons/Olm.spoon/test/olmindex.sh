#!/bin/bash
#
# Checks Olm.app's file index, step 1.3c of docs/PLAN-STANDALONE.md. It compiles the index helper
# from the file search plugin's own source, the way app/build.sh bundles it, builds olm-index-check
# from app/, and runs it, which makes a small folder, indexes it and asks it the way the app does.
# It shows nothing and writes only under the temporary folder and the build cache. Exit 2 when this
# machine has no command line tools.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tools="/Library/Developer/CommandLineTools"
if [ ! -x "$tools/usr/bin/swift" ]; then
  echo "olmindex: no command line tools here, skipped"
  exit 2
fi
scratch="$HOME/.olm/cache/olmapp-package"
mkdir -p "$scratch"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
helper="$scratch/fileindex-check"
source="$here/../plugins/filesearch/sources/fileindex.swift"
# The shared search the helper is compiled with, as app/build.sh and the Lua side compile it.
matcher="$here/../app/Sources/OlmSearch/Match.swift"
if [ ! -x "$helper" ] || [ "$source" -nt "$helper" ] || [ "$matcher" -nt "$helper" ]; then
  if ! DEVELOPER_DIR="$tools" "$tools/usr/bin/swiftc" -sdk "$tools/SDKs/MacOSX.sdk" -O "$source" "$matcher" -o "$helper" >"$out" 2>&1; then
    grep -E 'error' "$out" | head -20
    echo "olmindex, the helper's build FAILED"
    exit 1
  fi
fi
if ! (cd "$here/../app" && DEVELOPER_DIR="$tools" "$tools/usr/bin/swift" build --build-system native \
  --scratch-path "$scratch" --product olm-index-check) >"$out" 2>&1; then
  grep -E 'error' "$out" | head -20
  echo "olmindex, the build FAILED"
  exit 1
fi
"$scratch/debug/olm-index-check" "$helper"
