#!/bin/bash
set -euo pipefail

# Run one command of this repository in a new Terminal window, from the repository root.
#
#   open-in-terminal.sh [NAME=value ...] COMMAND [ARGS ...]
#   open-in-terminal.sh ./setup.sh --only kanata
#   open-in-terminal.sh MDJ_EDITOR=Zed ./setup.sh
#
# For a session with no terminal of its own, an agent's shell, that has to start a step a person
# must sit through. Such a step asks sudo for a password and walks the grants, which needs a
# terminal to type into and to press Enter in, so run from the agent's shell it would only leave
# closing notes. This opens the window and returns at once. The person answers there, and the
# window stays open afterwards so the closing notes can be read.
#
# Terminal is used because every Mac has it, and it is opened through a .command file rather
# than scripted, since scripting another application needs an Automation grant and opening a
# file does not. The file removes itself as it starts. The window gets a login shell's
# environment rather than the caller's, so nothing of the agent's session reaches it, and a
# NAME=value given first is the only way to pass a value in.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if [[ $# -eq 0 ]]; then
    echo "usage: open-in-terminal.sh [NAME=value ...] COMMAND [ARGS ...]" >&2
    exit 2
fi

line=""
for arg in "$@"; do
    line+="$(printf '%q' "$arg") "
done

dir="$(mktemp -d -t mdj-env-run)"
file="$dir/run.command"
{
    echo '#!/bin/bash'
    echo 'rm -rf "$(dirname "$0")"'
    printf 'cd %q || exit 1\n' "$ROOT"
    echo "env $line"
    echo 'status=$?'
    echo 'echo ""'
    echo 'echo "==> Finished with exit $status, this window can be closed."'
} > "$file"
chmod +x "$file"
open -a Terminal "$file"
echo "Opened a Terminal window running $* from $ROOT"
