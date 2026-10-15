#!/usr/bin/env bash
# The entry point. It makes this checkout's config live, switches the harness on, runs the cases,
# and then puts every one of those things back whether the suite passed, failed, or was interrupted.
#
# The three steps exist because only one Hammerspoon config can run at a time on a machine, the
# harness must never be part of a normal config, and a suite that leaves either of those changed
# has broken the machine it was supposed to be checking.

set -o pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$TEST_DIR" && git rev-parse --show-toplevel)
MARKER=$TEST_DIR/ENABLED

# Wait for the config to come back after a relaunch, by asking the harness rather than by sleeping
# a guessed number of seconds.
wait_for_agent() {
  # shellcheck source=lib/hs.sh
  source "$TEST_DIR/lib/hs.sh"
  HS_REPLY_DIR=${TMPDIR:-/tmp}/browsertabs-suite.$$
  mkdir -p "$HS_REPLY_DIR"
  local waited=0
  while [ "$waited" -lt 30 ]; do
    [ "$(hs_cmd ping | jq -r '.ok' 2>/dev/null)" = "true" ] && { rm -rf "$HS_REPLY_DIR"; return 0; }
    sleep 1
    waited=$(( waited + 1 ))
  done
  rm -rf "$HS_REPLY_DIR"
  return 1
}

finish() {
  local code=$?
  printf '\nputting the machine back\n'
  rm -f "$MARKER"
  # A lock this run found already held by this worktree belongs to whoever took it, often a
  # person in the middle of a manual hold, so it is left exactly as it was found.
  if [ "$TOOK_LOCK" -eq 1 ]; then
    ( cd "$REPO" && ./bin/hs-devlock release ) || printf 'the lock would not release, run bin/hs-devlock release by hand\n'
  else
    printf 'the test lock was already held by this worktree, leaving it held\n'
  fi
  exit $code
}

# The marker goes down before the lock is taken, since acquiring is what relaunches Hammerspoon and
# the harness has to already be there for that load to pick it up. Doing it the other way round
# meant a second relaunch for no reason.
printf 'switching the harness on\n'
touch "$MARKER"

# Held until an explicit release rather than on the short timeout, because a full suite runs for
# something like twenty minutes and a lock that expires underneath it would hand the machine's
# config to somebody else mid round.
printf 'taking the test lock, this makes this checkout the live Hammerspoon config\n'
ACQUIRED="$( cd "$REPO" && ./bin/hs-devlock acquire --manual )" \
  || { printf '%s\n' "$ACQUIRED"; printf 'the lock is held elsewhere\n'; exit 1; }
printf '%s\n' "$ACQUIRED"
# hs-devlock answers an acquire by a worktree that already holds the lock with this line and
# keeps the hold as it was, so only a run that did not see it took the lock and owns its release.
TOOK_LOCK=1
case "$ACQUIRED" in *"already held by this worktree, kept"*) TOOK_LOCK=0 ;; esac
trap finish EXIT INT TERM

wait_for_agent || { printf 'the harness never came up\n'; exit 1; }

"$TEST_DIR/run.sh" "$@"
