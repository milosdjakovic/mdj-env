#!/bin/bash
set -e

# Choose which editor opens development files from Finder, then hand the answer to
# set-dev-defaults.sh, which does the binding.
#
# This used to pass "Zed" unconditionally, and nothing declared Zed or installed it, so on a
# machine without Zed the step failed and set -e stopped setup.sh there. The editor is a
# personal choice rather than something this repository needs, so the step asks instead of
# declaring one. Enter skips the step, so a run of setup.sh never waits on a choice nobody
# wants to make that day. Whatever handles .md now is named, so skipping is an informed answer.
#
# The answer arrives one of two ways. MDJ_EDITOR carries it through a run with no terminal,
# which is how an agent runs setup.sh, since it can ask before the run but cannot answer a
# prompt during one. Otherwise the step asks, and with neither it skips with a note.
#
#   --list   print the apps that can open development files, one name per line, and exit.
#            The prompt below and anyone asking before a run read the same list.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

SKIP_NOTE='Default editor not set. Run src/setup-dev-defaults.sh to choose one, or src/set-dev-defaults.sh "App Name" where there is no terminal.'

# The apps that can edit development files, most capable first, by name.
#
# Launch Services owns this question, so no list of editors is kept here to go stale. It is
# asked which apps registered as an Editor of each type below, since a browser, a notes app or
# a chat app that can open a .md registers as a Viewer and has no place in this list. An app is
# kept when it edits more than half of the types, which drops one that claims the Editor role
# for a single type it cannot edit. Ghostty is the case that showed it, registering as an
# Editor of shell scripts so that double clicking one runs it in a terminal. An app nested
# inside another bundle, such as Instruments inside Xcode, is left out too.
#
# The role query is deprecated since macOS 12 with no replacement that keeps the role, and it
# still answers on macOS 27. If it ever answers nothing, the list falls back to every app that
# can open the types, which is complete but carries the viewers again. Typing a name at the
# prompt covers an editor that registers only as a Viewer. This runs through osascript rather
# than a compiled helper, so it needs no toolchain.
list_editors() {
    local probes
    probes="$(mktemp -d)"
    osascript -l JavaScript - "$probes" 2>/dev/null << 'JXA' || true
ObjC.import("AppKit");
ObjC.import("CoreServices");
var EXTENSIONS = ["md", "py", "json", "sh", "c", "java", "swift"];
var ROLE_EDITOR = 4; // kLSRolesEditor
var ws = $.NSWorkspace.sharedWorkspace;

function nameOf(url) {
    if (!url || url.isNil()) return null;
    var path = url.path.js;
    var parent = path.slice(0, path.lastIndexOf("/"));
    if (parent.indexOf(".app/") !== -1 || /\.app$/.test(parent)) return null;
    return path.slice(path.lastIndexOf("/") + 1).replace(/\.app$/, "");
}

function editorsOf(file) {
    if (typeof $.LSCopyAllRoleHandlersForContentType !== "function") return [];
    var uti = ws.typeOfFileError(file, null).js;
    var ref = $.LSCopyAllRoleHandlersForContentType($(uti), ROLE_EDITOR);
    var ids = ref ? ObjC.deepUnwrap(ObjC.castRefToObject(ref)) || [] : [];
    return ids.map(function (id) { return nameOf(ws.URLForApplicationWithBundleIdentifier(id)); });
}

function openersOf(file) {
    var apps = ws.URLsForApplicationsToOpenURL($.NSURL.fileURLWithPath(file));
    var names = [];
    for (var i = 0; i < apps.count; i++) names.push(nameOf(apps.objectAtIndex(i)));
    return names;
}

// Each type is asked about through an empty probe file, since the type an extension resolves to
// is whatever Launch Services says for a file that has it.
function tally(dir, ask) {
    var count = {};
    EXTENSIONS.forEach(function (ext) {
        var file = dir + "/probe." + ext;
        $.NSFileManager.defaultManager.createFileAtPathContentsAttributes(file, $(), $());
        var once = {};
        ask(file).forEach(function (name) {
            if (name && !once[name]) { once[name] = true; count[name] = (count[name] || 0) + 1; }
        });
    });
    return count;
}

function run(argv) {
    var count = tally(argv[0], editorsOf);
    if (Object.keys(count).length === 0) count = tally(argv[0], openersOf);
    return Object.keys(count).filter(function (name) {
        return count[name] * 2 > EXTENSIONS.length;
    }).sort(function (a, b) {
        return count[b] - count[a] || a.localeCompare(b);
    }).join("\n");
}
JXA
    rm -rf "$probes"
}

if [[ "${1:-}" == "--list" ]]; then
    list_editors
    exit 0
fi

# The one check both routes share, since set-dev-defaults.sh would fail later and less legibly.
require_app() {
    if ! osascript -e "id of app \"$1\"" > /dev/null 2>&1; then
        echo "No app named \"$1\" on this machine. src/setup-dev-defaults.sh --list names the candidates." >&2
        exit 1
    fi
}

if [[ -n "${MDJ_EDITOR:-}" ]]; then
    require_app "$MDJ_EDITOR"
    "$SCRIPT_DIR/set-dev-defaults.sh" "$MDJ_EDITOR"
    exit 0
fi

# No terminal and no answer means nobody can answer, and guessing an editor is the thing this
# replaced.
if [[ ! -t 0 ]]; then
    mdj_note "$SKIP_NOTE"
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
CANDIDATES=()
while IFS= read -r name; do
    [[ -n "$name" ]] && CANDIDATES+=("$name")
done < <(list_editors)

echo "Which app should open development files, such as .md, .json, .yaml and .sh, from Finder?"
[[ -n "$CURRENT" ]] && echo "They open in $CURRENT now."
for i in "${!CANDIDATES[@]}"; do
    mark=""
    [[ "${CANDIDATES[$i]}" == "$CURRENT" ]] && mark=", now"
    printf '  %2d  %s%s\n' "$((i + 1))" "${CANDIDATES[$i]}" "$mark"
done
if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    echo "Type a number, or an app name as it appears in /Applications without .app."
else
    echo "Type the app name as it appears in /Applications, without .app."
fi
echo "Press Enter to skip and leave them as they are."

while true; do
    # End of input, a Ctrl D, stops the step and so the run, since Enter is already the way to
    # pass the question by. It says so, where a bare read under set -e used to stop in silence.
    if ! read -r -p "Editor: " answer; then
        echo
        echo "Stopped at the editor question." >&2
        exit 1
    fi
    if [[ -z "$answer" ]]; then
        mdj_note "$SKIP_NOTE"
        exit 0
    fi

    if [[ "$answer" =~ ^[0-9]+$ ]]; then
        if (( answer >= 1 && answer <= ${#CANDIDATES[@]} )); then
            answer="${CANDIDATES[$((answer - 1))]}"
            break
        fi
        echo "No entry $answer in the list. Pick a number shown, or press Enter to skip."
        continue
    fi

    if osascript -e "id of app \"$answer\"" > /dev/null 2>&1; then
        break
    fi
    echo "No app named \"$answer\" on this machine. Check the name in /Applications, or press Enter to skip."
done

"$SCRIPT_DIR/set-dev-defaults.sh" "$answer"
