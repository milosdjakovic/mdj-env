#!/bin/bash
#
# What the launcher's own catalog holds and what each leader's cheat sheet would draw, compared
# with the committed goldens, so a phase that moves where rows and labels come from can prove it
# left both alone. The sibling of keys.sh, which does the same for every bound chord.
#
# The live modes only READ the running Hammerspoon. They take no lock, reload nothing, post no
# key, open no list and show no sheet. Each call is bounded the way every hs call here must be,
# run in the background and killed after a few seconds, with -q so the console is not flooded,
# and each probe writes to a file because a large reply over the port gets lost. The live config
# is whichever checkout is stowed, so a worktree that is not live describes main.
#
# --offline needs no Hammerspoon. It runs the composition root under the dry gate's stub, see
# drygate-composerun.lua, and writes the same projections the live probes write, so the two
#
# Usage
#   views.sh            live, diff both against launcher.golden and sheets.golden
#   views.sh --update   live, overwrite both goldens
#   views.sh --offline  the offline projections of both, diffed against the goldens
#   views.sh --offline --update
#                       write both goldens from the offline projections, the way to refresh them
#                       after a change, since the live --update reads whatever config was last
#                       loaded and saves a stale one when the reload has not happened yet
#   views.sh --fixture NAME [--update]
#                       the offline projections again with the keymap test/NAME.lua handed to Olm
#                       in place of config/keymap.lua, diffed against test/NAME.launcher.golden and
#                       test/NAME.sheets.golden, or written to them with --update, which proves the
#                       launcher rows and the sheets spell the chords that keymap moved

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
spoon="$(cd "$here/.." && pwd)"
config="$(cd "$spoon/../.." && pwd)"
mode="diff"
fixture=""
fixture_update=""

case "${1:-}" in
  --update) mode="update" ;;
  --offline) mode="offline"; fixture_update="${2:-}" ;;
  --fixture) mode="fixture"; fixture="${2:?--fixture needs a fixture name}"; fixture_update="${3:-}" ;;
  "") ;;
  *) echo "views.sh: unknown argument $1" >&2; exit 2 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
status=0

compare() {
  local name="$1" got="$2" how="$3"
  if diff -u "$here/$name.golden" "$got"; then
    echo "views.sh: the $how $name projection matches $name.golden, $(wc -l < "$here/$name.golden" | tr -d ' ') lines"
  else
    echo "views.sh: the $how $name projection differs from $name.golden" >&2
    status=1
  fi
}

if [ "$mode" = "offline" ] || [ "$mode" = "fixture" ]; then
  keymapFixture=""
  prefix=""
  if [ "$mode" = "fixture" ]; then
    keymapFixture="$here/$fixture.lua"
    prefix="$fixture."
    [ -f "$keymapFixture" ] || { echo "views.sh: no fixture at test/$fixture.lua" >&2; exit 2; }
  fi
  for view in launcher sheets; do
    mkdir -p "$work/sb-$view"
    DRYGATE_VIEWS="$view" DRYGATE_KEYMAP_FIXTURE="$keymapFixture" lua "$here/drygate-composerun.lua" "$spoon/" "$config" "$work/sb-$view" >"$work/$view.txt" 2>"$work/$view.err"
    if [ ! -s "$work/$view.txt" ]; then
      echo "views.sh: the offline $view run wrote nothing" >&2
      grep -v '^log ' "$work/$view.err" | tail -5 >&2
      status=2
    elif [ "$fixture_update" = "--update" ]; then
      cp "$work/$view.txt" "$here/$prefix$view.golden"
      echo "views.sh: wrote test/$prefix$view.golden"
    else
      compare "$prefix$view" "$work/$view.txt" "offline"
    fi
  done
  exit $status
fi

probe() {
  local file="$1" out="$2" extra="$3"
  rm -f "$out"
  ( hs -q -c "OLM_VIEW_OUT = \"$out\"; $extra return dofile(\"$here/$file\")" >/dev/null 2>&1 &
    p=$!
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
      sleep 0.5
      [ -s "$out" ] && break
    done
    kill "$p" 2>/dev/null ) 2>/dev/null
  if [ ! -s "$out" ]; then
    echo "views.sh: $file wrote nothing, is Hammerspoon running and answering" >&2
    exit 2
  fi
}

probe launcher-probe.lua "$work/launcher.txt" ""
probe sheets-probe.lua "$work/sheets.txt" ""

if [ "$mode" = "update" ]; then
  cp "$work/launcher.txt" "$here/launcher.golden"
  cp "$work/sheets.txt" "$here/sheets.golden"
  echo "views.sh: wrote launcher.golden and sheets.golden"
  exit 0
fi
compare launcher "$work/launcher.txt" "live"
compare sheets "$work/sheets.txt" "live"
exit $status
