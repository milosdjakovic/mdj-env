#!/usr/bin/env bash
# Runs the stage two parity probes against the running Hammerspoon, with no reload and no
# test lock. Each probe builds one shared surface through the old code and the new and
# compares the two, see parity-lib.lua.
#
#   test/parity.sh <scratch dir> [git ref]
#
# The old code is the given ref, HEAD unless named, exported from git into the scratch
# directory, since the old files load their siblings by relative path. Results are written
# to files in that directory and printed from there, since a reply through the hs command
# line tool can go missing. Only a dofile call carrying a path crosses into hs.

set -o pipefail

WORK=${1:?"usage, parity.sh <scratch dir> [git ref]"}
REF=${2:-HEAD}
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SELF_DIR" && git rev-parse --show-toplevel)
SPOON_REL=$(cd -- "$SELF_DIR/.." && pwd)
SPOON_REL=${SPOON_REL#"$REPO_ROOT"/}

mkdir -p "$WORK"
WORK=$(cd -- "$WORK" && pwd)
OLD="$WORK/parity-old"
rm -rf "$OLD"
mkdir -p "$OLD"
git -C "$REPO_ROOT" archive "$REF" "$SPOON_REL/lib" "$SPOON_REL/root" | tar -x -C "$OLD" || exit 1

status=0
for probe in emptystate hints cheatsheet canvasprovider; do
  out="$WORK/parity-$probe.out"
  args="$WORK/parity-$probe-args.lua"
  rm -f "$out"
  printf 'PARITY_ARGS = { old = "%s/%s/", out = "%s" }\ndofile("%s/parity-%s.lua")\n' \
    "$OLD" "$SPOON_REL" "$out" "$SELF_DIR" "$probe" > "$args"
  hs -c "dofile('$args')" >/dev/null 2>&1 &
  client=$!
  for _ in $(seq 1 120); do
    grep -q '^DONE$' "$out" 2>/dev/null && break
    sleep 0.5
  done
  kill "$client" 2>/dev/null
  echo "== $probe"
  if ! grep -q '^DONE$' "$out" 2>/dev/null; then
    echo "the probe did not finish"
    status=1
  fi
  grep -v '^DONE$' "$out" 2>/dev/null
  grep -q '^DIFF\|^ERROR' "$out" 2>/dev/null && status=1
done
exit $status
