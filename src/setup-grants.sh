#!/bin/bash
set -uo pipefail

# Walk every permission a module declares and that is not given yet, and for each one open the
# place it is given and wait while a person gives it.
#
#   setup-grants.sh            every module that is on here
#   setup-grants.sh MODULE...  only those, which is how src/setup-kanata.sh asks for its own
#
# No script can click a grant. macOS keeps that for a person, and the one route around it, a
# configuration profile pushed by device management, does not exist on a personal machine. So
# the most a script can do is take the person to the exact row and notice when it is done, which
# turns a grant from a sentence to act on later into a click made now, during the run that needed
# it, with nothing to search for and no second run to confirm it.
#
# This file is the composition root for src/lib/grants.sh. It decides whether a person is there,
# and the library does the rest without knowing a module. With a terminal a required grant is
# guided. Without one, nothing opens, and every grant not given becomes a closing note, which is
# what a run said before this step existed. An optional grant is only ever a note, since the
# module runs without it and the person may not want it. decisions/setup-grants.md has why.
#
# It changes nothing and needs no password. Every grant it reads is answered by the module that
# declared it, through that module's grants-probe, for the reason the root AGENTS.md gives.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"
# shellcheck source=lib/grants.sh
source "$SCRIPT_DIR/lib/grants.sh"

interactive=0
[[ -t 0 ]] && interactive=1

echo "==> Grants a person has to give"

# Read whole before any grant is guided, so a wait that reads the terminal never shares its input
# with the list it is walking.
grants=()
while IFS= read -r line; do
    [[ -n "$line" ]] && grants+=("$line")
done < <(grants_declared "$@")

declared=${#grants[@]}
given=0
for line in ${grants[@]+"${grants[@]}"}; do
    IFS='|' read -r module name locator policy consumer <<< "$line"
    grants_guide "$module" "$name" "$locator" "$policy" "$consumer" "$interactive"
    [[ $? -eq 0 ]] && given=$((given + 1))
done

if [[ $declared -eq 0 ]]; then
    echo "  nothing that is on here declares a grant"
elif [[ $given -eq $declared ]]; then
    echo "  all $declared declared grants are given"
else
    echo "  $given of $declared declared grants are given, the closing notes say what is left"
fi
exit 0
