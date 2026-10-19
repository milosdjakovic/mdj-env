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
# The live config is whichever checkout is stowed. A worktree that is not live describes main,
# so to check a branch, take the test lock first with bin/hs-devlock and release it afterwards.
#
# Usage
#   keys.sh            dump and diff against keys.golden, exit 0 when identical, 1 on a difference
#   keys.sh --update   dump and overwrite keys.golden with the result
#   keys.sh --out FILE dump to FILE and stop, no diff

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
golden="$here/keys.golden"
mode="diff"
out=""

case "${1:-}" in
  --update) mode="update" ;;
  --out) mode="out"; out="${2:?--out needs a file}" ;;
  "") ;;
  *) echo "keys.sh: unknown argument $1" >&2; exit 2 ;;
esac

[ -n "$out" ] || out="$(mktemp "${TMPDIR:-/tmp}/olm-keys.XXXXXX")"
rm -f "$out"

( hs -q -c "OLM_KEYS_OUT = \"$out\"; return dofile(\"$here/keys-probe.lua\")" >/dev/null 2>&1 &
  p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 0.5
    [ -s "$out" ] && break
  done
  kill "$p" 2>/dev/null ) 2>/dev/null

if [ ! -s "$out" ]; then
  echo "keys.sh: the probe wrote nothing, is Hammerspoon running and answering" >&2
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
