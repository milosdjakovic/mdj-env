#!/bin/bash
#
# Every golden the keymap plan holds a phase to, in one command. keys.golden is every bound
# chord, launcher.golden the launcher's own catalog and sheets.golden what each leader's cheat
# sheet would draw. Offline by default, which needs no Hammerspoon and is what a builder runs,
# and --live against the running config, which describes main unless a worktree holds the lock.
#
# Usage
#   goldens.sh          keys.sh --offline, keys.sh --bound and views.sh --offline, then the
#                       keymap fixtures, keys.sh --fixture for each, the lists, list role, list
#                       leaders and modifier Hyper fixtures among them, and the composite one
#                       with its modifier claims written too,
#                       and views.sh --fixture for the person's case and the modifier Hyper one,
#                       every one against its own committed golden
#   goldens.sh --live   keys.sh and views.sh against the running config, read only
#   goldens.sh --update every offline golden rewritten from the offline runs, the one way to
#                       refresh them after a change that moves what they record. keys.golden is
#                       written only when the keymap projection and the binder agree, see
#                       keys.sh. Read every changed line with git diff before committing it,
#                       since a golden written without reading it proves nothing.

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
run() { "$@" || status=1; }

case "${1:-}" in
  --live)
    run "$here/keys.sh"
    run "$here/views.sh" ;;
  "")
    run "$here/keys.sh" --offline
    run "$here/keys.sh" --bound
    run "$here/views.sh" --offline
    run "$here/keys.sh" --fixture keymap-fixture
    run "$here/keys.sh" --fixture keymap-fixture-roles
    run "$here/keys.sh" --fixture keymap-fixture-lists
    run "$here/keys.sh" --fixture keymap-fixture-listrole
    run "$here/keys.sh" --fixture keymap-fixture-listleaders
    run "$here/keys.sh" --fixture keymap-fixture-heldkeys
    run "$here/keys.sh" --fixture keymap-fixture-modhyper
    DRYGATE_CLAIMS=1 run "$here/keys.sh" --fixture keymap-fixture-composite
    run "$here/views.sh" --fixture keymap-fixture
    run "$here/views.sh" --fixture keymap-fixture-modhyper ;;
  --update)
    run "$here/keys.sh" --offline --update
    run "$here/views.sh" --offline --update
    for f in keymap-fixture keymap-fixture-roles keymap-fixture-lists keymap-fixture-listrole \
      keymap-fixture-listleaders keymap-fixture-heldkeys keymap-fixture-modhyper; do
      run "$here/keys.sh" --fixture "$f" --update
    done
    DRYGATE_CLAIMS=1 run "$here/keys.sh" --fixture keymap-fixture-composite --update
    run "$here/views.sh" --fixture keymap-fixture --update
    run "$here/views.sh" --fixture keymap-fixture-modhyper --update ;;
  *) echo "goldens.sh: unknown argument $1" >&2; exit 2 ;;
esac
exit $status
