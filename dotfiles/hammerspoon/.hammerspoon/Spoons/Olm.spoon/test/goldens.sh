#!/bin/bash
#
# Every golden the keymap plan holds a phase to, in one command. keys.golden is every bound
# chord, launcher.golden the launcher's own catalog and sheets.golden what each leader's cheat
# sheet would draw. Offline by default, which needs no Hammerspoon and is what a builder runs,
# and --live against the running config, which describes main unless a worktree holds the lock.
#
# Usage
#   goldens.sh          keys.sh --offline, keys.sh --bound and views.sh --offline
#   goldens.sh --live   keys.sh and views.sh against the running config, read only

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
    run "$here/views.sh" --offline ;;
  *) echo "goldens.sh: unknown argument $1" >&2; exit 2 ;;
esac
exit $status
