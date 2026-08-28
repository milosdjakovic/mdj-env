#!/bin/bash
#
# Run the Olm suite against the live configuration and print the report.
#
# The shape of this script is decided by one Hammerspoon fact. Opening a chooser from inside
# an `hs -c` call kills the ipc port, so the run cannot be a call that returns an answer. It
# is a call that SCHEDULES the run and returns at once, after which this script waits for a
# report file to appear. That is why there is a poll loop here rather than a single command.
#
# The lock is taken only if it is not already held by this worktree. A person testing by hand
# has usually acquired it already, and stealing it from under them to run a suite, then
# handing back a config they did not ask for, would be worse than reusing what is there.
#
# Usage
#   suite.sh                  every tier
#   suite.sh dry [--strict]   plain lua, no Hammerspoon, no lock, see drygate.sh below
#   suite.sh structure        the checks that need no screen, fast, safe to run any time
#   suite.sh surface          open and close every picker, takes over the screen briefly
#   suite.sh behaviour        the hand written per plugin scenarios
#   suite.sh input            posted leader chords, proving keys and not just actions

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
spoon="$(cd "$here/.." && pwd)"

tiers="${1:-all}"

# dry is answered before any of the machinery below runs, on purpose. Every other tier
# needs a live Hammerspoon and the lock that guards one, and dry exists specifically so a
# builder agent with neither can still catch a bad declaration, drygate.sh's own header
# says the rest. Answered here, by name, rather than folded into the lock and report
# dance below, so it stays true that this tier never starts Hammerspoon and never touches
# the lock, not merely that it happens to finish before either would matter.
if [ "$tiers" = "dry" ]; then
  shift
  exec "$here/drygate.sh" "$@"
fi

# The config directory is two levels up from the spoon, and the checkout this spoon lives in
# is five, Olm.spoon then Spoons then .hammerspoon then hammerspoon then dotfiles.
config="$(cd "$spoon/../.." && pwd)"
worktree="$(cd "$spoon/../../../../.." && pwd)"
# The lock script lives in whichever checkout has one. A worktree carries its own copy, and
# when it does not, the checkout beside it does, since worktrees sit next to the repository.
devlock="$worktree/bin/hs-devlock"
[ -x "$devlock" ] || devlock="$(cd "$worktree/../.." 2>/dev/null && pwd)/mdj-env/bin/hs-devlock"

report="${TMPDIR:-/tmp}/olm-test-report.txt"

took_lock=0
cleanup() {
  if [ "$took_lock" -eq 1 ]; then
    echo "releasing the lock, putting your own config back"
    "$devlock" release >/dev/null 2>&1
  fi
}
trap cleanup EXIT

# Only take the lock if this worktree is not already the live config, so a hands on session
# that already acquired it keeps its hold and gets it back untouched.
live="$(hs -c 'return hs.configdir' 2>/dev/null | tail -1)"
if [ "$live" != "$config" ]; then
  if [ ! -x "$devlock" ]; then
    echo "cannot find hs-devlock, and this worktree is not the live config" >&2
    exit 1
  fi
  echo "putting this worktree live for the run"
  "$devlock" acquire || exit 1
  took_lock=1
  sleep 5
fi

rm -f "$report"

echo "starting the run, tiers, $tiers"
hs -c "local r = dofile('$spoon/test/runner.lua')
       local tiers = nil
       if '$tiers' ~= 'all' then tiers = { ['$tiers'] = true } end
       return r.run(spoon.Olm, { out = '$report', tiers = tiers }) .. ' scenarios queued'" 2>&1 | tail -1

# The run writes its report only when every scenario has finished, so the file appearing is
# the completion signal. Two minutes is far longer than a full run needs and exists only so a
# wedged Hammerspoon ends this script rather than hanging a terminal.
waited=0
while [ ! -f "$report" ]; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge 120 ]; then
    echo "the run never finished, no report after ${waited}s" >&2
    echo "check the Hammerspoon console, a raise before the first scenario leaves no file" >&2
    exit 1
  fi
done

echo
cat "$report"

# A failure count of zero is the only success. The manual items are not failures, they are
# work for a person, and a run with nothing but those still exits clean.
if grep -qE '^[0-9]+ passed, 0 failed' "$report"; then
  exit 0
fi
exit 1
