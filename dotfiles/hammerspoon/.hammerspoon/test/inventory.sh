#!/usr/bin/env bash
# The inventory snapshot. It takes the machine wide test lock so this checkout
# becomes the live Hammerspoon config, waits for the relaunch to actually answer
# as this worktree rather than trusting that a reload was asked for, runs the
# dump described in inventory.lua, and always puts the lock back whether it
# passed, failed, or was interrupted. The shape follows
# Spoons/Olm.spoon/plugins/browsertabs/test/suite.sh, since that harness already
# solved the lock and trap and wait discipline and there is no reason to invent
# a second version of it.
#
# This script only reads. It never edits a registry, a spoon, or a config file,
# so unlike suite.sh it needs no harness marker to switch anything on.
#
# Plain, prints the snapshot to stdout.
# --check, diffs the snapshot against the committed inventory.golden beside this
#   script, exiting zero on an empty diff and nonzero with the diff shown
#   otherwise.

set -o pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$TEST_DIR" && git rev-parse --show-toplevel)
CONFIG_DIR="$REPO/dotfiles/hammerspoon/.hammerspoon"
INVENTORY_LUA="$TEST_DIR/inventory.lua"
GOLDEN="$TEST_DIR/inventory.golden"
CACHE_DIR="$HOME/Library/Caches/hammerspoon-inventory"
SNAPSHOT_FILE="$CACHE_DIR/snapshot.txt"

CHECK=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    *) echo "inventory.sh, unknown flag $arg" >&2; exit 1 ;;
  esac
done

# Every hs call passes -q and is bounded, the way units.sh calls it and for its reason. Without -q
# the client mirrors the console back, and a client killed or wedged while mirrored stays
# registered until the ipc channel stops answering anything that mirrors, which hung this
# script's readiness wait on 2026-10-27 while a -q call answered at once. And bash runs the
# trap below only once the foreground command returns, so an unbounded hung call also held the
# test lock until someone released it by hand. Prints what the command printed, and answers 124
# when the limit ran out.
bounded() {
  local limit=$1
  shift
  local out
  out=$(mktemp)
  "$@" >"$out" 2>&1 </dev/null &
  local pid=$!
  local ticks=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge $((limit * 10)) ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      cat "$out"
      rm -f "$out"
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
  local status=$?
  cat "$out"
  rm -f "$out"
  return "$status"
}

# Puts the machine back on any exit, an interrupt, or a failure, the same three
# paths suite.sh guards, so the resting state is always main whatever happened
# above.
finish() {
  local code=$?
  # A lock this run found already held by this worktree belongs to whoever took it, often a
  # person in the middle of a manual hold, so it is left exactly as it was found.
  if [ "$TOOK_LOCK" -ne 1 ]; then
    printf '\nthe test lock was already held by this worktree, leaving it held\n' >&2
    exit "$code"
  fi
  printf '\nreleasing the test lock, returning to main\n' >&2
  ( cd "$REPO" && ./bin/hs-devlock release ) >&2 \
    || printf 'the lock would not release, run bin/hs-devlock release by hand\n' >&2
  exit "$code"
}

# hs-devlock prints its own status lines to stdout, and stdout here is reserved
# for the snapshot or the diff, the one thing a caller of this script should ever
# be able to pipe or redirect and trust. So every hs-devlock call below is
# redirected to stderr, the same channel this script's own narration already
# uses.
printf 'taking the test lock, this makes this checkout the live Hammerspoon config\n' >&2
ACQUIRED="$( cd "$REPO" && ./bin/hs-devlock acquire )" \
  || { printf '%s\n' "$ACQUIRED" >&2; printf 'the lock is held elsewhere, rerun once it frees or take it with --wait by hand\n' >&2; exit 1; }
printf '%s\n' "$ACQUIRED" >&2
# hs-devlock answers an acquire by a worktree that already holds the lock with this line and
# keeps the hold as it was, so only a run that did not see it took the lock and owns its release.
TOOK_LOCK=1
case "$ACQUIRED" in *"already held by this worktree, kept"*) TOOK_LOCK=0 ;; esac
trap finish EXIT INT TERM

# Waits for the relaunch to actually answer as this worktree's own config,
# polling rather than sleeping a guessed number of seconds, since a reload asked
# for and never taken is a known silent failure otherwise. This query carries no
# angle bracket, so sending it inline is safe, the hard rule about never passing
# inline Lua to the hs tool is about a stray less than or greater than sign
# wedging the client, and there is none here.
waited=0
live_ok=""
while [ "$waited" -lt 30 ]; do
  live_ok=$(bounded 3 hs -q -c "return (hs.configdir == '$CONFIG_DIR')" 2>/dev/null)
  [ "$live_ok" = "true" ] && break
  sleep 1
  waited=$(( waited + 1 ))
done
if [ "$live_ok" != "true" ]; then
  printf 'inventory.sh, the live config never became this worktree, saw configdir %s\n' \
    "$(bounded 3 hs -q -c "return hs.configdir" 2>/dev/null)" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"
rm -f "$SNAPSHOT_FILE"

# The only Lua that crosses the shell boundary for the dump itself, one dofile
# call and nothing else. Everything the dump needs to decide, where to write and
# what to read, lives inside inventory.lua rather than being passed in here.
hs_out=$(bounded 30 hs -q -c "dofile('$INVENTORY_LUA')" 2>&1)

if [ ! -s "$SNAPSHOT_FILE" ]; then
  printf 'inventory.sh, the dump produced no snapshot, hs reported\n%s\n' "$hs_out" >&2
  exit 1
fi

if [ "$CHECK" -eq 1 ]; then
  diff -u "$GOLDEN" "$SNAPSHOT_FILE"
  exit $?
fi

cat "$SNAPSHOT_FILE"
