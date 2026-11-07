#!/bin/bash
#
# Step 1.1's check of Olm.app, docs/PLAN-STANDALONE.md. It builds the app into a cache folder,
# starts it in the background with a ping, and checks four things. The ping is answered, a second
# ping reaches the same single instance, the app shows no Dock icon, and once it is quit Hammerspoon
# still answers. It shows no window and takes no key, so it does not need the test lock. It ends by
# taking the bundle out of LaunchServices again, so the run leaves no olm:// handler behind.
# Exit 2 when this machine cannot build the app.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
out="$HOME/.olm/cache/olmapp-test"
ping="$HOME/.olm/run/ping"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

app="$("$here/../app/build.sh" "$out")"
status=$?
if [ "$status" -ne 0 ]; then
  exit "$status"
fi
exe="$app/Contents/MacOS/Olm"

failures=0
check() {
  if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; failures=$((failures + 1)); fi
}

# Waits up to five seconds for the ping file to hold the nonce.
answered() {
  local i
  for i in $(seq 50); do
    [ "$(cat "$ping" 2>/dev/null)" = "$1" ] && return 0
    perl -e 'select(undef, undef, undef, 0.1)'
  done
  return 1
}

pids() { pgrep -f "^$exe" || true; }

cleanup() {
  for pid in $(pids); do kill "$pid" 2>/dev/null; done
  "$lsregister" -u "$app" >/dev/null 2>&1
}
trap cleanup EXIT

cleanup
rm -f "$ping"
first="t$$a$RANDOM"
open -g -a "$app" "olm://ping?nonce=$first"
answered "$first"
check $? "the app answers a ping"

second="t$$b$RANDOM"
open -g -a "$app" "olm://ping?nonce=$second"
answered "$second"
check $? "a second ping is answered"
[ "$(pids | wc -l | tr -d ' ')" = 1 ]
check $? "one instance answers both"

# A copy started by hand, not through LaunchServices, leaves at once.
perl -e 'alarm 5; exec @ARGV' "$exe" >/dev/null 2>&1
check $? "a second copy started by hand leaves by itself"

pid="$(pids | head -1)"
lsappinfo info -only applicationType "$pid" 2>/dev/null | grep -q UIElement
check $? "the app has no Dock icon"

rm -f "$ping"
open -g -a "$app" "olm://ping?nonce=bad%20nonce"
open -g -a "$app" "olm://run?what=anything"
perl -e 'select(undef, undef, undef, 0.5)'
[ ! -e "$ping" ]
check $? "a bad nonce and an unknown URL write nothing"

for p in $(pids); do kill "$p"; done
for i in $(seq 30); do [ -z "$(pids)" ] && break; perl -e 'select(undef, undef, undef, 0.1)'; done
[ -z "$(pids)" ]
check $? "the app quits"

# hs reads stdin when it has no terminal and waits on it, so stdin is closed for it.
if command -v hs >/dev/null 2>&1; then
  [ "$(perl -e 'alarm 5; exec @ARGV' hs -q -c 'return 1+1' 2>/dev/null </dev/null)" = 2 ]
  check $? "Hammerspoon still answers once the app has quit"
fi

[ "$failures" = 0 ] || { echo "olmapp, $failures FAILED"; exit 1; }
echo "olmapp, all passed"
