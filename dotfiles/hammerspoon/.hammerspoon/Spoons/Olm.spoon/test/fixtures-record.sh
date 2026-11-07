#!/bin/bash
#
# Records every calls fixture again, steps 0.3b to 0.3e of docs/PLAN-STANDALONE.md. Each one is the
# calls an existing test made into a module, see fixtures-record.lua, so a change made on purpose
# to the bottom bar, the keymap, the remap or the list keys is recorded again here, the way
# goldens.sh --update refreshes the goldens, and every changed line is read before it is committed.
# The bottom bar is recorded from keymap-person.lua, which reads config/keymap.lua, so a change to
# the person's keymap is recorded again here too, as it is refreshed in keys.golden.
#
# The fixture keymaps run through the dry gate's own composition run, drygate-composerun.lua, with
# the keycode table in fixtures/keys/keycodes.lua, since the run's stand in invents a code the
# first time a name is asked, which a recording cannot carry. Each run's output is compared with
# that keymap's golden, so recording is shown to change nothing the run does.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
spoon="$(cd "$here/.." && pwd -P)"
config="$(cd "$spoon/../.." && pwd -P)"
. "$here/embedded-lua.sh"
cd "$spoon" || exit 1

status=0
record() { "$OLM_LUA" test/fixtures-record.lua "$@" 2>&1 | grep -E '^(recorded|dropped)' | sed 's/^/  /' || true; }

echo "fixtures-record, the remap, the keymap rules and the bottom bar"
record test/fixtures/keys/remap.json test/keyremap.lua lib/keyremap.lua=allocate
record test/fixtures/keys/rules.json test/keymap.lua 'lib/keymap.lua=*'
record test/fixtures/bar/person.json test/keymap-person.lua lib/hints.lua=bottomBarModel

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for f in keymap-fixture keymap-fixture-roles keymap-fixture-lists keymap-fixture-listrole \
  keymap-fixture-listleaders keymap-fixture-heldkeys keymap-fixture-modhyper; do
  mkdir -p "$work/$f"
  echo "fixtures-record, $f"
  DRYGATE_KEYCODES="$spoon/test/fixtures/keys/keycodes.lua" DRYGATE_BINDS=fixture \
    DRYGATE_KEYMAP_FIXTURE="$spoon/test/$f.lua" "$OLM_LUA" test/fixtures-record.lua \
    "test/fixtures/keys/$f.json" test/drygate-composerun.lua \
    'lib/keymap.lua=readConfig,build,applyLists,fieldMods,leadersInUse,fallbackLeaders,navigationProblems' \
    lib/nav.lua=fieldKeys lib/keyremap.lua=allocate -- "$spoon/" "$config" "$work/$f" \
    >"$work/$f.out" 2>"$work/$f.err"
  grep -E '^(recorded|dropped)' "$work/$f.err" | sed 's/^/  /'
  if ! diff -q "$work/$f.out" "test/$f.keys.golden" >/dev/null; then
    echo "  the run under the recorder differs from test/$f.keys.golden, so this recording is not trusted" >&2
    status=1
  fi
done
exit $status
