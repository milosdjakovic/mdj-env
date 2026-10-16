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
#
# A case that fails for a reason that is not the case is retried too. The live config reloads
# itself whenever any file under the config directory changes, and anything else that calls
# hs.reload does the same, and every reload tears down the ipc port. A call in flight then
# either hangs, which the timeout above catches, or makes the hs client exit nonzero at once,
# and the second shape used to fail every case that ran inside the reload window, six or seven
# in a row, each with no reason. That is a property of the machine at that moment and never of
# a case, so a nonzero exit is followed by a wait for the probe, with no reload of our own since
# the other one already happened, and one retry of that case. Only a case that fails again is
# reported, and the report says what the client returned. A case that raised inside Lua writes
# an ERROR line and is never retried, since that is a defect in the case.
#
# Whenever the run stops early, a last line after the counts names the case and the reason, so
# a tail of the output still says where it stopped.

set -o pipefail

# Nothing here may read the caller's standard input. Every hs call is bound to the null device
# instead, since a run started from a terminal or a tool session that holds a live stdin
# wedged after the first lost reply. The client then never exited, the runner killed it at
# each timeout, the recovery reload went unanswered and every probe hung for the whole
# recovery window, while the same run with stdin on the null device recovered in seconds.
exec </dev/null

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

if ! command -v hs >/dev/null 2>&1; then
  echo "Hammerspoon must be running with its hs command line tool on PATH, hs was not found."
  exit 1
fi

# recover reloads Hammerspoon on a fresh run loop tick, since a reload called inside the ipc
# request tears down the port answering it, then waits for the probe to answer pong again.
# Returns nonzero when the channel does not come back within RECOVER_TIMEOUT seconds.
RECOVER_TIMEOUT=${RECOVER_TIMEOUT:-30}

# wait_ready waits up to RECOVER_TIMEOUT seconds for the probe to answer pong, without asking
# for a reload, for the case where something else already reloaded Hammerspoon.
wait_ready() {
  local waited=0
  while [ "$waited" -lt "$RECOVER_TIMEOUT" ]; do
    if [ "$(bounded "$PING_TIMEOUT" hs -q -c "return dofile('$PING_FILE')")" = "pong" ]; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

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
stop_line=""

for case_file in "${case_files[@]}"; do
  case_name=$(basename "$case_file")
  run_case() {
    : >"$RESULTS_FILE"
    hs_output=$(bounded "$CASE_TIMEOUT" hs -q -c "return dofile('$RUN_CASE_FILE')('$case_file', '$RESULTS_FILE')")
    return $?
  }
  run_case
  status=$?

  if [ "$status" -eq 124 ]; then
    echo "$case_name did not answer within $CASE_TIMEOUT seconds, reloading Hammerspoon to clear the ipc channel and trying it once more" >&2
    if ! recover; then
      total_failed=$((total_failed + 1))
      stop_line="the run stopped at $case_name, the case did not answer and Hammerspoon did not answer again within $RECOVER_TIMEOUT seconds of a reload"
      failure_lines+=("$case_name, $stop_line")
      break
    fi
    run_case
    status=$?
    if [ "$status" -eq 124 ]; then
      total_failed=$((total_failed + 1))
      stop_line="the run stopped at $case_name, the case did not answer within $CASE_TIMEOUT seconds twice, once before a reload and once after it"
      failure_lines+=("$case_name, $stop_line")
      break
    fi
  elif [ "$status" -ne 0 ] && ! grep -q '^ERROR ' "$RESULTS_FILE"; then
    # The client gave up without the case ever reporting, which is a reload that was not ours
    # taking the port down under the call. Wait for the new instance and run the case again.
    echo "$case_name lost its ipc channel, hs exited with status $status, waiting for Hammerspoon and trying it once more" >&2
    if ! wait_ready; then
      total_failed=$((total_failed + 1))
      stop_line="the run stopped at $case_name, hs exited with status $status and Hammerspoon did not answer again within $RECOVER_TIMEOUT seconds"
      failure_lines+=("$case_name, $stop_line")
      break
    fi
    run_case
    status=$?
    if [ "$status" -eq 124 ]; then
      total_failed=$((total_failed + 1))
      stop_line="the run stopped at $case_name, the retry after a lost channel did not answer within $CASE_TIMEOUT seconds"
      failure_lines+=("$case_name, $stop_line")
      break
    fi
  fi
  output=$(cat "$RESULTS_FILE")
  error_line=$(grep -m 1 '^ERROR ' <<<"$output")
  if [ "$status" -ne 0 ] || [ -n "$error_line" ]; then
    total_failed=$((total_failed + 1))
    reason=${error_line#ERROR }
    if [ -z "$reason" ]; then
      reason="hs exited with status $status and the case wrote no result, hs said ${hs_output:-nothing}"
    fi
    failure_lines+=("$case_name, the case did not run cleanly, $reason")
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
if [ -n "$stop_line" ]; then
  echo "STOPPED EARLY, $stop_line"
fi

if [ "$total_failed" -gt 0 ]; then
  exit 1
fi

exit 0
