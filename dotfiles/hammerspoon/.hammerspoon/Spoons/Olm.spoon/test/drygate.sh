#!/bin/bash
#
# The dry contract gate, standalone. Finds every manifest.lua under plugins/ and host/ and
# hands the paths to drygate.lua, the identical split dependencies-collect and
# dependencies-collect.lua already use one directory up, finding files is what a shell is
# good at and reading Lua is what Lua is good at. Never starts Hammerspoon, never reloads,
# never touches the test lock, so it is safe to run at any time, by hand or from an agent
# that has no way to start one at all.
#
# Usage
#   test/drygate.sh                 every manifest under plugins/ and host/
#   test/drygate.sh --strict        the harder stance, a module this gate could not verify
#                                    at all fails the gate too, rather than only printing
#
# The typography check rides along, see drygate-typography.lua, every font name, text size or
# line height written outside lib/ui is a finding unless the line declares type-exempt and a
# reason, and an exempted line is counted as accepted.
#
# The rename proof rides along too, see drygate-rename.lua, it runs the composition root over
# the spoon and over a copy whose plugins carry scrambled names, and any difference in what core
# decided is a finding.
#
# Exit status mirrors drygate.lua's own. A clean tree, meaning every finding is either
# genuinely absent or accepted by test/drygate-accepted.txt, exits zero. An unknown module
# and a warning both print but do not fail the gate on their own, unless --strict is given.
# A stale offline golden fails it too, see the end of this file.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
spoon="$(cd "$here/.." && pwd)"

if [ "${1:-}" = "--strict" ]; then
  export DRYGATE_STRICT=1
  shift
fi

# lua is this spoon's own dependencies-collect.lua's own choice too, dotfiles/hammerspoon/
# dependencies-module declares it, and DEPENDENCIES.map says where it comes from, so this
# script names no new dependency, it reaches for the identical tool already on PATH for
# that reason.
if ! command -v lua >/dev/null 2>&1; then
  echo "drygate.sh: lua is not on PATH. It is declared in the hammerspoon module's own" >&2
  echo "  dependencies-module, so ./src/check-dependencies.sh names where it comes from" >&2
  echo "  and setup.sh puts it there." >&2
  exit 2
fi

manifests=()
while IFS= read -r found; do
  manifests+=("$found")
done < <(find "$spoon/plugins" "$spoon/host" -type f -name manifest.lua 2>/dev/null | sort)

if [ "${#manifests[@]}" -eq 0 ]; then
  echo "drygate.sh: found no manifest.lua under $spoon/plugins or $spoon/host" >&2
  exit 2
fi

# Every Lua file the typography check reads, which is everything under the spoon but the kit
# itself and the test directory, since the kit is where a font and a size are allowed to be
# written and a fixture may carry whatever it needs.
DRYGATE_SOURCES="$(find "$spoon" -type f -name '*.lua' -not -path "$spoon/lib/ui/*" -not -path "$spoon/test/*" 2>/dev/null | sort)"
export DRYGATE_SOURCES

# The layer rule reads every Lua file outside plugins/ and test/, lib/ui included, since the
# kit is core too. The person's config lives above the spoon and is never in this set.
DRYGATE_LEAKSOURCES="$(find "$spoon" -type f -name '*.lua' -not -path "$spoon/plugins/*" -not -path "$spoon/test/*" 2>/dev/null | sort)"
export DRYGATE_LEAKSOURCES

# The rename proof, see drygate-rename.lua. Copying the spoon and making a sandbox are the
# shell's half, the copy is where the plugin directories get their scrambled names, so the tree
# under test is never touched. It runs the person's own init.lua, two levels above the spoon,
# and when there is none the proof cannot run and drygate.lua says so as a warning.
config="$(cd "$spoon/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ -f "$config/init.lua" ] && cp -R "$spoon" "$work/Olm.spoon" && mkdir "$work/sandbox"; then
  lua "$here/drygate-rename.lua" "$spoon/" "$config" "$work/Olm.spoon" "$work/sandbox" "${manifests[@]}" \
    >"$work/rename.txt" 2>&1
  DRYGATE_RENAMEPROOF="$work/rename.txt"
  export DRYGATE_RENAMEPROOF
fi

lua "$here/drygate.lua" "$spoon/" "${manifests[@]}"
gate=$?

# The offline goldens ride along last, see goldens.sh. They take a couple of seconds and no
# Hammerspoon, and they are what drifts when nothing runs them, keys.golden stayed stale across
# three commits that way. Their full diff goes to a file so the gate stays readable, and a stale
# golden fails the gate, with the one command that refreshes it safely.
if "$here/goldens.sh" >"$work/goldens.txt" 2>&1; then
  echo "goldens, every offline golden matches"
else
  echo "goldens, stale or disagreeing, every line below names one:" >&2
  grep -E 'differs|disagree|wrote nothing' "$work/goldens.txt" | sed 's/^/  /' >&2
  echo "  See the diff with test/goldens.sh. When the change is meant, refresh them all with" >&2
  echo "  test/goldens.sh --update and read every changed line before committing it." >&2
  [ "$gate" -eq 0 ] && gate=1
fi
exit "$gate"
