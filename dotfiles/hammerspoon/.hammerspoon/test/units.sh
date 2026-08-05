#!/usr/bin/env bash
# The pure Lua unit runner. It drives every case under test/cases/ through the running
# Hammerspoon's own Lua interpreter, over the hs command line tool and hs.ipc, and it
# takes no test lock, since a case only dofiles a module straight out of this checkout
# and never needs this checkout to be the live config at all.
#
# No Lua source ever crosses the shell boundary here except a dofile call carrying an
# absolute path, the readiness probe included, since an angle bracket sitting in inline
# Lua wedges the hs client for good. Every path below is resolved from this script's own
# location at run time, never written down as a literal.

set -o pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SELF_DIR" && git rev-parse --show-toplevel)
TEST_DIR="$REPO_ROOT/dotfiles/hammerspoon/.hammerspoon/test"
CASES_DIR="$TEST_DIR/cases"
PING_FILE="$TEST_DIR/lib/ping.lua"

if ! command -v hs >/dev/null 2>&1; then
  echo "Hammerspoon must be running with its hs command line tool on PATH, hs was not found."
  exit 1
fi

ping_output=$(hs -c "dofile('$PING_FILE')" 2>&1)
ping_status=$?
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
  output=$(hs -c "dofile('$case_file')" 2>&1)
  status=$?

  if [ "$status" -ne 0 ]; then
    total_failed=$((total_failed + 1))
    failure_lines+=("$case_name, the case did not run cleanly, $output")
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
