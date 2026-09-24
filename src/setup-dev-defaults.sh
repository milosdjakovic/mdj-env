#!/bin/bash
set -e

# Ask which editor opens development files from Finder, then hand the answer to
# set-dev-defaults.sh, which does the binding.
#
# This used to pass "Zed" unconditionally, and nothing declared Zed or installed it, so on a
# machine without Zed the step failed and set -e stopped setup.sh there. The editor is a
# personal choice rather than something this repository needs, so the step asks instead of
# declaring one. Enter skips the step, so a run of setup.sh never waits on a choice nobody
# wants to make that day. Whatever handles .md now is named, so skipping is an informed answer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

# No terminal means nobody can answer, and guessing an editor is the thing this replaced.
if [[ ! -t 0 ]]; then
    mdj_note "Default editor not set, no terminal to ask. Run src/setup-dev-defaults.sh to choose one."
    exit 0
fi

# The app that handles .md now, by name, or nothing. Spotlight turns the bundle id into a path
# without launching anything, which asking AppleScript for the name would do.
current_editor() {
    command -v duti > /dev/null 2>&1 || return 0
    local bundle path
    bundle="$(duti -x md 2>/dev/null | sed -n 3p)"
    [[ -n "$bundle" ]] || return 0
    path="$(mdfind "kMDItemCFBundleIdentifier == '$bundle'" 2>/dev/null | grep '\.app$' | head -1)"
    [[ -n "$path" ]] && basename "$path" .app
    return 0
}

CURRENT="$(current_editor)"

echo "Which app should open development files, such as .md, .json, .yaml and .sh, from Finder?"
echo "Type the exact app name as it appears in /Applications, without .app."
echo "For example Zed, Visual Studio Code, Cursor or Sublime Text."
[[ -n "$CURRENT" ]] && echo "They open in $CURRENT now."
echo "Press Enter to skip and leave them as they are."

while true; do
    read -r -p "Editor: " answer
    if [[ -z "$answer" ]]; then
        mdj_note "Default editor not set. Run src/setup-dev-defaults.sh to choose one."
        exit 0
    fi

    if osascript -e "id of app \"$answer\"" > /dev/null 2>&1; then
        break
    fi
    echo "No app named \"$answer\" on this machine. Check the name in /Applications, or press Enter to skip."
done

"$SCRIPT_DIR/set-dev-defaults.sh" "$answer"
