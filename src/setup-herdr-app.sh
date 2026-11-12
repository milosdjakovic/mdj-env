#!/bin/bash
set -e

# Show the Herdr app's mdj layout, on a machine whose herdr-app piece is on.
#
# Herdr keeps which layout a window shows in its own state, ~/.config/herdr-app/shared.json,
# which belongs to the app and is not stowed, so a fresh machine shows Herdr's `main` until it is
# switched once. Switching is a command to the running app, so this opens the app in the
# background when it is not running, waits for it to answer, switches, and quits it again if it
# opened it. Only Herdr's untouched default is switched, `main` or nothing chosen yet. Another
# layout was picked by a person, and a rerun leaves it with a note. decisions/herdr-app-install.md
# has it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

# The installer links herdr-app here, and a shell started before .zshrc existed may not have it.
export PATH="$HOME/.local/bin:$PATH"
WANT=mdj
SHARED="$HOME/.config/herdr-app/shared.json"

if ! command -v herdr-app >/dev/null 2>&1; then
    mdj_note "the Herdr app is not installed, so its layout was not switched to $WANT, run src/install-herdr-app.sh first"
    exit 0
fi

running() { herdr-app status >/dev/null 2>&1; }
shown() {
    if running; then
        herdr-app status 2>/dev/null | sed -n 's/^ *"layout": *"\([^"]*\)".*/\1/p' | head -1
    elif [[ -f "$SHARED" ]]; then
        sed -n 's/^ *"layout": *"\([^"]*\)".*/\1/p' "$SHARED" | head -1
    fi
}

now="$(shown)"
if [[ "$now" == "$WANT" ]]; then
    echo "Herdr app already shows the $WANT layout"
    exit 0
fi
if [[ -n "$now" && "$now" != main ]]; then
    mdj_note "the Herdr app shows the $now layout, chosen by hand, so it was left alone, cmd-shift-l picks $WANT"
    exit 0
fi

opened=0
if ! running; then
    echo "Opening the Herdr app in the background to switch its layout..."
    open -g -b dev.herdr.app
    opened=1
    for _ in $(seq 1 60); do running && break; sleep 0.5; done
fi
if ! running; then
    mdj_note "the Herdr app did not answer within 30 seconds, so its layout was not switched, open it and press cmd-shift-l to pick $WANT"
    exit 0
fi

herdr-app do layout.switch "{\"name\":\"$WANT\"}" >/dev/null
sleep 1
if [[ "$(shown)" == "$WANT" ]]; then
    echo "Herdr app now shows the $WANT layout"
else
    mdj_note "the Herdr app did not take the $WANT layout, open it and press cmd-shift-l to pick it"
fi
[[ $opened == 1 ]] && herdr-app do app.quit >/dev/null 2>&1 || true
