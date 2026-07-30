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
  ( cd "$REPO" && ./bin/hs-devlock release ) || printf 'the lock would not release, run bin/hs-devlock release by hand\n'
  exit $code
}

printf 'taking the test lock, this makes this checkout the live Hammerspoon config\n'
( cd "$REPO" && ./bin/hs-devlock acquire ) || { printf 'the lock is held elsewhere\n'; exit 1; }
trap finish EXIT INT TERM

printf 'switching the harness on and reloading\n'
touch "$MARKER"
( cd "$REPO" && ./bin/hs-devlock acquire ) > /dev/null 2>&1
osascript -e 'tell application "Hammerspoon" to quit' > /dev/null 2>&1
sleep 2
open -g -a Hammerspoon
wait_for_agent || { printf 'the harness never came up\n'; exit 1; }

"$TEST_DIR/run.sh" "$@"
