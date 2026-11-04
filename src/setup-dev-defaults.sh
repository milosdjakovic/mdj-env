#!/bin/bash
set -e

# Report whether development files open in this machine's editor, and change nothing.
#
# The editor is a row in machines/<name>/pieces, `editor`, holding the app's bundle id or none.
# This step reads every handler against it through `set-dev-defaults.sh --check` and, where
# they differ, leaves a closing note naming the command that applies it. It never applies it
# itself, because on macOS 27 every type whose handler moves raises its own dialog, up to forty
# at once, and a setup run that does that on a whim is the bombardment this was rebuilt to end.
# Applying is `src/set-dev-defaults.sh`, run deliberately. decisions/dev-defaults.md has why.
#
# It used to ask which editor on every run and apply the answer, and before that it passed
# "Zed" unconditionally. Neither is wanted. The choice is a fact about a machine, so it lives
# where every other such fact lives, and asking it again each run was what turned a stray
# answer into forty dialogs.
#
#   --list   print the apps that can open development files, one name per line, and exit,
#            the candidates for the editor row.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

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
# can open the types, which is complete but carries the viewers again. An editor that registers only as a
# Viewer is still accepted by bundle id in the editor row. This runs through osascript rather
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

EDITOR_ROW="$("$SCRIPT_DIR/machine.sh" get editor)"
MACHINE="$("$SCRIPT_DIR/machine.sh" name)"

if [[ "$EDITOR_ROW" == "none" ]]; then
    echo "No editor is chosen for $MACHINE, so development file handlers are left as they are"
    exit 0
fi

# --check exits 3 on a difference, 0 when everything matches, anything else is a fault.
# Only the first line is shown in a setup run, the count. The full list is one --check away.
status=0
report="$("$SCRIPT_DIR/set-dev-defaults.sh" --check "$EDITOR_ROW")" || status=$?
printf "%s\n" "$report" | head -1
case "$status" in
    0) ;;
    3) mdj_note "Development files do not all open in the editor machines/$MACHINE/pieces names. Run src/set-dev-defaults.sh to apply it, which raises one macOS dialog per type, then src/set-dev-defaults.sh --check to confirm." ;;
    *) exit "$status" ;;
esac
