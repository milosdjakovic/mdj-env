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
# Exit status mirrors drygate.lua's own. A clean tree, meaning every finding is either
# genuinely absent or accepted by test/drygate-accepted.txt, exits zero. An unknown module
# and a warning both print but do not fail the gate on their own, unless --strict is given.

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

exec lua "$here/drygate.lua" "$spoon/" "${manifests[@]}"
