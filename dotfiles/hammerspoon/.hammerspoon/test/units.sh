#!/usr/bin/env bash
# The pure Lua unit runner. It drives every case under test/cases/ through the running
# Hammerspoon's own Lua interpreter, over the hs command line tool and hs.ipc, and it
# takes no test lock, since a case only dofiles a module straight out of this checkout
# and never needs this checkout to be the live config at all.
#
# No Lua source ever crosses the shell boundary here except a dofile call carrying absolute
# paths, the readiness probe included, since an angle bracket sitting in inline Lua wedges
# the hs client for good. Every path below is resolved from this script's own location at
# run time, never written down as a literal.
#
# Every hs call passes -q and is bounded. A case writes what it prints to a results file
# through test/lib/run-case.lua rather than having the console mirrored back to the client,
# since a killed client that was being mirrored to stayed registered and flooded the console
# with recursion warnings until the ipc channel wedged. With nothing mirrored a hung call can
# be killed safely. Each call runs in the background and is killed after a limit, the probe
# after PING_TIMEOUT seconds and each case after CASE_TIMEOUT, both overridable from the
# environment. A case that times out is followed by a scheduled reload, a wait of up to
# RECOVER_TIMEOUT seconds for the probe to answer again, and one retry of that case. A second
# timeout, or a Hammerspoon that does not answer again, stops the run.

set -o pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SELF_DIR" && git rev-parse --show-toplevel)
TEST_DIR="$REPO_ROOT/dotfiles/hammerspoon/.hammerspoon/test"
CASES_DIR="$TEST_DIR/cases"
PING_FILE="$TEST_DIR/lib/ping.lua"
RUN_CASE_FILE="$TEST_DIR/lib/run-case.lua"
RELOAD_FILE="$TEST_DIR/lib/reload.lua"
RESULTS_FILE=$(mktemp)
trap 'rm -f "$RESULTS_FILE"' EXIT
PING_TIMEOUT=${PING_TIMEOUT:-5}
CASE_TIMEOUT=${CASE_TIMEOUT:-60}

# bounded SECONDS COMMAND... prints what the command printed and returns its status, or kills
# it after SECONDS and returns 124, the status timeout(1) uses, since timeout is not on macOS.
bounded() {
  local limit=$1
  shift
  local out
  out=$(mktemp)
  "$@" >"$out" 2>&1 &
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

if ! command -v hs >/dev/null 2>&1; then
  echo "Hammerspoon must be running with its hs command line tool on PATH, hs was not found."
  exit 1
fi

# recover reloads Hammerspoon on a fresh run loop tick, since a reload called inside the ipc
# request tears down the port answering it, then waits for the probe to answer pong again.
# Returns nonzero when the channel does not come back within RECOVER_TIMEOUT seconds.
RECOVER_TIMEOUT=${RECOVER_TIMEOUT:-30}
recover() {
  bounded 5 hs -q -c "return dofile('$RELOAD_FILE')" >/dev/null
  local waited=0
  while [ "$waited" -lt "$RECOVER_TIMEOUT" ]; do
    sleep 2
    waited=$((waited + 2))
    if [ "$(bounded "$PING_TIMEOUT" hs -q -c "return dofile('$PING_FILE')")" = "pong" ]; then
      return 0
    fi
  done
  return 1
}

ping_output=$(bounded "$PING_TIMEOUT" hs -q -c "return dofile('$PING_FILE')")
ping_status=$?
if [ "$ping_status" -eq 124 ]; then
  echo "Hammerspoon did not answer the hs command line tool within $PING_TIMEOUT seconds, its ipc reply went missing, reload it and run again"
  exit 1
fi
if [ "$ping_status" -ne 0 ] || [ "$ping_output" != "pong" ]; then
  echo "Hammerspoon must be running, the hs command line tool did not answer, $ping_output"
  exit 1
fi

case_files=()
while IFS= read -r -d '' found; do
  case_files+=("$found")
done < <(find "$CASES_DIR" -type f -name '*.lua' -print0 | sort -z)

if [ ${#case_files[@]} -eq 0 ]; then
  echo "No case files found under $CASES_DIR"
  exit 1
fi

total_passed=0
total_failed=0
failure_lines=()

for case_file in "${case_files[@]}"; do
  case_name=$(basename "$case_file")
  run_case() {
    : >"$RESULTS_FILE"
    bounded "$CASE_TIMEOUT" hs -q -c "return dofile('$RUN_CASE_FILE')('$case_file', '$RESULTS_FILE')" >/dev/null
  }
  run_case
  status=$?

  if [ "$status" -eq 124 ]; then
    echo "$case_name did not answer within $CASE_TIMEOUT seconds, reloading Hammerspoon to clear the ipc channel and trying it once more" >&2
    if ! recover; then
      total_failed=$((total_failed + 1))
      failure_lines+=("$case_name, the case did not answer and Hammerspoon did not answer again within $RECOVER_TIMEOUT seconds of a reload, so the run stopped here")
      break
    fi
    run_case
    status=$?
    if [ "$status" -eq 124 ]; then
      total_failed=$((total_failed + 1))
      failure_lines+=("$case_name, the case did not answer within $CASE_TIMEOUT seconds twice, so the run stopped here")
      break
    fi
  fi
  output=$(cat "$RESULTS_FILE")
  error_line=$(grep -m 1 '^ERROR ' <<<"$output")
  if [ "$status" -ne 0 ] || [ -n "$error_line" ]; then
    total_failed=$((total_failed + 1))
    failure_lines+=("$case_name, the case did not run cleanly, ${error_line#ERROR }")
    continue
  fi

  while IFS= read -r line; do
    case "$line" in
      PASS\ *)
        total_passed=$((total_passed + 1))
        ;;
      FAIL\ *)
        total_failed=$((total_failed + 1))
        failure_lines+=("$case_name, ${line#FAIL }")
        ;;
    esac
  done <<< "$output"
done

for line in "${failure_lines[@]}"; do
  echo "FAIL $line"
done

total=$((total_passed + total_failed))
echo "$total assertions ran, $total_passed passed, $total_failed failed"

if [ "$total_failed" -gt 0 ]; then
  exit 1
fi

exit 0
