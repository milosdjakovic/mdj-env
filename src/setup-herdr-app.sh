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

# The mdj mods draw every interface icon from one Lucide set, dotfiles/herdr-app/icons. An svg's
# stroke scales with the size it is drawn at, so one stroke in the file drew a 10px icon thinner than
# a 14px one. So each size a mod draws at gets its own folder, mods/mdj-icons/<size>, whose files
# carry the stroke that makes every line LINE layout px wide whatever the size, 24 / size * LINE in
# the 24 unit viewBox. A mod names the folder for the size it draws, mods/mdj-icons/14/plus.svg.
# Herdr draws nothing for an svg that is a symlink, so these are real files, in a folder that belongs
# to this repository and is brought in line with the source. decisions/herdr-app-layout.md has it.
LINE=1
SIZES="10 11 12 13 14 15 16"
ICONS_SRC="$SCRIPT_DIR/../dotfiles/herdr-app/icons"
ICONS_DST="$HOME/.config/herdr-app/mods/mdj-icons"
icons_changed=0
mkdir -p "$ICONS_DST"
# The single folder the first version of this step wrote, before strokes were per size.
for old in "$ICONS_DST"/*.svg; do [[ -e "$old" ]] && { rm "$old"; icons_changed=1; }; done
for size in $SIZES; do
    stroke="$(awk -v s="$size" -v l="$LINE" 'BEGIN { printf "%.3f", 24 / s * l }')"
    mkdir -p "$ICONS_DST/$size"
    for src in "$ICONS_SRC"/*.svg; do
        dst="$ICONS_DST/$size/$(basename "$src")"
        tmp="$(mktemp)"
        sed -E "s/stroke-width=\"[^\"]*\"/stroke-width=\"$stroke\"/" "$src" > "$tmp"
        if cmp -s "$tmp" "$dst"; then rm "$tmp"; else mv "$tmp" "$dst"; icons_changed=1; fi
    done
    for dst in "$ICONS_DST/$size"/*.svg; do
        [[ -e "$dst" && ! -e "$ICONS_SRC/$(basename "$dst")" ]] && { rm "$dst"; icons_changed=1; }
    done
done
if [[ $icons_changed == 1 ]]; then echo "Herdr app icons written into $ICONS_DST"; else echo "Herdr app icons already current"; fi

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
