#!/bin/bash
#
# Dump every chord the running configuration has bound and compare it with the committed
# golden, so a phase that moves binding code can prove it left the key set alone.
#
# This only READS the live Hammerspoon. It takes no lock, reloads nothing and posts no key. The
# call is bounded the way every hs call here must be, run in the background and killed after a
# few seconds, with -q so the console is not flooded. The probe writes to a file because a large
# reply over the port gets lost, see keys-probe.lua for the line format and what it cannot see.
#
# --offline needs no Hammerspoon at all. It runs the composition root under the dry gate's stub,
# see drygate-composerun.lua, writes the keymap it built in the golden's format and diffs that.
# The stub cannot tell the real keycode table, so a key is only lowercased unless DRYGATE_KEYCODES
# names a Lua file returning one dumped from a live session, and it cannot see which tools are
# installed, so it reports every one present.
#
# The live config is whichever checkout is stowed. A worktree that is not live describes main,
# so to check a branch, take the test lock first with bin/hs-devlock and release it afterwards.
#
# Usage
#   keys.sh            dump and diff against keys.golden, exit 0 when identical, 1 on a difference
#   keys.sh --update   dump and overwrite keys.golden with the result
#   keys.sh --out FILE dump to FILE and stop, no diff
#   keys.sh --offline  the keymap projection from a stubbed run of the root, no Hammerspoon needed
#   keys.sh --offline --update
#                      write keys.golden from the offline projection, the way to refresh it after a
#                      change. It records what the binder bound as well and refuses to write when
#                      the two disagree, since no golden can then satisfy both, and that is a defect
#                      in the core to fix, never a golden to patch by hand. The live --update is not
#                      this, it adds the raw hotkey lines only the live probe sees.
#   keys.sh --bound    what the binder actually bound in a stubbed run of the root, every call into
#                      the two leader engines' bind and into hs.hotkey.bind recorded and written in
#                      the golden's format, diffed against keys.golden. The keymap projection proves
#                      the read model is complete, this proves the binder binds exactly that.
#   keys.sh --bound-order [SPOON]
#                      the same recording grouped by engine and key in call order, which is what
#                      decides two bindings on one key. Given another spoon directory, a copy of
#                      main for instance, both are recorded against this config and diffed, and
#                      with none the recording is printed.
#   keys.sh --fixture NAME [--update]
#                      the bound recording again, with the keymap test/NAME.lua handed to Olm in
#                      place of config/keymap.lua, followed by one line naming the catalog leaders
#                      the remap was applied with, diffed against test/NAME.keys.golden, or written
#                      to it with --update. This is the offline proof of a person's keymap, which
#                      keys moved, which were freed and which held leaders it puts in use.
#   keys.sh --keymap   write the keymap's own rows in the golden's format and diff those against
#                      keys.golden. It reads the keymap the live root built, so it needs the
#                      config that contains the keymap to be the live one, which for a worktree
#                      means the test lock. A match proves the read model is complete.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
golden="$here/keys.golden"
mode="diff"
out=""
other=""
probe_mode=""
fixture=""
fixture_update=""
offline_update=""

case "${1:-}" in
  --update) mode="update" ;;
  --out) mode="out"; out="${2:?--out needs a file}" ;;
  --keymap) probe_mode="keymap" ;;
  --offline) mode="offline"; offline_update="${2:-}" ;;
  --bound) mode="bound" ;;
  --bound-order) mode="boundorder"; other="${2:-}" ;;
  --fixture) mode="fixture"; fixture="${2:?--fixture needs a fixture name}"; fixture_update="${3:-}" ;;
  "") ;;
  *) echo "keys.sh: unknown argument $1" >&2; exit 2 ;;
esac

# The bound modes, see drygate-composerun.lua's own header. Each run needs a sandbox of its own.
record_bound() {
  local spoonDir="$1" what="$2" into="$3" keymapFixture="${4:-}" config sb
  config="$(cd "$here/../../.." && pwd)"
  sb="$(mktemp -d)"
  DRYGATE_BINDS="$what" DRYGATE_KEYMAP_FIXTURE="$keymapFixture" lua "$here/drygate-composerun.lua" "$spoonDir/" "$config" "$sb" >"$into" 2>"$into.err"
  local status=$?
  rm -rf "$sb"
  return $status
}

if [ "$mode" = "fixture" ]; then
  spoon="$(cd "$here/.." && pwd)"
  source_file="$here/$fixture.lua"
  fixture_golden="$here/$fixture.keys.golden"
  [ -f "$source_file" ] || { echo "keys.sh: no fixture at test/$fixture.lua" >&2; exit 2; }
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  record_bound "$spoon" fixture "$work/fixture.txt" "$source_file"
  if [ ! -s "$work/fixture.txt" ]; then
    echo "keys.sh: the fixture recording wrote nothing" >&2
    tail -5 "$work/fixture.txt.err" >&2
    exit 2
  fi
  if [ "$fixture_update" = "--update" ]; then
    cp "$work/fixture.txt" "$fixture_golden"
    echo "keys.sh: wrote test/$fixture.keys.golden, $(wc -l < "$fixture_golden" | tr -d ' ') lines"
    exit 0
  fi
  if diff -u "$fixture_golden" "$work/fixture.txt"; then
    echo "keys.sh: what the binder bound under test/$fixture.lua matches its golden, $(wc -l < "$fixture_golden" | tr -d ' ') lines"
    exit 0
  fi
  echo "keys.sh: what the binder bound under test/$fixture.lua differs from its golden" >&2
  exit 1
fi

if [ "$mode" = "bound" ] || [ "$mode" = "boundorder" ]; then
  spoon="$(cd "$here/.." && pwd)"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  if [ "$mode" = "bound" ]; then
    record_bound "$spoon" golden "$work/bound.txt"
    if [ ! -s "$work/bound.txt" ]; then
      echo "keys.sh: the bound recording wrote nothing" >&2
      tail -5 "$work/bound.txt.err" >&2
      exit 2
    fi
    if diff -u "$golden" "$work/bound.txt"; then
      echo "keys.sh: what the binder bound offline matches keys.golden, $(wc -l < "$golden" | tr -d ' ') lines"
      exit 0
    fi
    echo "keys.sh: what the binder bound offline differs from keys.golden" >&2
    exit 1
  fi
  record_bound "$spoon" order "$work/here.txt"
  if [ -z "$other" ]; then cat "$work/here.txt"; exit 0; fi
  record_bound "$(cd "$other" && pwd)" order "$work/other.txt"
  if diff -u "$work/other.txt" "$work/here.txt"; then
    echo "keys.sh: every engine receives its bindings in the same order in both spoons, $(wc -l < "$work/here.txt" | tr -d ' ') lines"
    exit 0
  fi
  echo "keys.sh: the binding order differs between the two spoons" >&2
  exit 1
fi

if [ "$mode" = "offline" ]; then
  spoon="$(cd "$here/.." && pwd)"
  config="$(cd "$spoon/../.." && pwd)"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  DRYGATE_KEYMAP=1 lua "$here/drygate-composerun.lua" "$spoon/" "$config" "$work" >"$work/keymap.txt" 2>"$work/err.txt"
  if [ ! -s "$work/keymap.txt" ]; then
    echo "keys.sh: the offline run wrote nothing" >&2
    tail -5 "$work/err.txt" >&2
    exit 2
  fi
  if [ "$offline_update" = "--update" ]; then
    record_bound "$spoon" golden "$work/bound.txt"
    if ! diff -u "$work/keymap.txt" "$work/bound.txt"; then
      echo "keys.sh: the keymap projection and what the binder bound disagree, above, so no golden" >&2
      echo "  can satisfy both. The read model in lib/keymap.lua and the binder have drifted apart," >&2
      echo "  fix that rather than the golden. keys.golden is unchanged." >&2
      exit 1
    fi
    cp "$work/keymap.txt" "$golden"
    echo "keys.sh: wrote keys.golden, $(wc -l < "$golden" | tr -d ' ') lines, projection and binder agreeing"
    exit 0
  fi
  if diff -u "$golden" "$work/keymap.txt"; then
    echo "keys.sh: the offline keymap projection matches keys.golden, $(wc -l < "$golden" | tr -d ' ') lines"
    exit 0
  fi
  echo "keys.sh: the offline keymap projection differs from keys.golden" >&2
  exit 1
fi

[ -n "$out" ] || out="$(mktemp "${TMPDIR:-/tmp}/olm-keys.XXXXXX")"
rm -f "$out"

( hs -q -c "OLM_KEYS_OUT = \"$out\"; OLM_KEYS_MODE = \"$probe_mode\"; return dofile(\"$here/keys-probe.lua\")" >/dev/null 2>&1 &
  p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 0.5
    [ -s "$out" ] && break
  done
  kill "$p" 2>/dev/null ) 2>/dev/null

if [ ! -s "$out" ]; then
  echo "keys.sh: the probe wrote nothing, is Hammerspoon running and answering, and for keymap is the config with the keymap live" >&2
  exit 2
fi

case "$mode" in
  out) echo "$out" ;;
  update) cp "$out" "$golden"; rm -f "$out"; echo "keys.sh: wrote $golden, $(wc -l < "$golden" | tr -d ' ') lines" ;;
  diff)
    if diff -u "$golden" "$out"; then
      echo "keys.sh: the live key set matches keys.golden, $(wc -l < "$golden" | tr -d ' ') lines"
      rm -f "$out"
    else
      echo "keys.sh: the live key set differs from keys.golden, dump kept at $out" >&2
      exit 1
    fi ;;
esac
