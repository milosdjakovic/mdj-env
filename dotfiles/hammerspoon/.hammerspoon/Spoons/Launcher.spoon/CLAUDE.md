# Launcher.spoon

The decision trail and the important facts for this spoon. Cross cutting
material stays in the hammerspoon `CLAUDE.md`, which links here. The picker
checklist and the spoon lifecycle contract this file refers to live there.

## What it is

A filterable app switcher and command runner, the built-in one, wired straight
to the Chooser atom with no external launcher handoff. It lists every installed
application, open ones first then not running, and below them the injected
command actions. Its open binding is a base binding, suppressed while a modal
context owns the opening key, so it always opens this launcher. An app that has
a toggle shortcut shows it, the rest are launchable by name, and typing filters
by name or shortcut. The native accept key, or the shared accept action, runs
the highlighted row.

## Why a coordinator, not inline wiring

It lives in `Launcher.spoon`, a coordinator, because it combines many plain
spoons into one feature and owns real state, the app scan caches and an
`hs.application.watcher`, so it outgrew inline wiring in the root. It is a layer
two coordinator in the sense of the lifecycle contract in the hammerspoon
`CLAUDE.md`, built over the Chooser atom, the same widget behind the other list
tools, and it names no domain spoon. The root injects every collaborator through
`configure`, the Chooser factory, the pure `keys` and `apps` data, injected
window action descriptors, a chord glyph resolver, injected settings pane
descriptors, the shared predicate registry, the docked shortcut panel, and a
small `actions` table of leaf closures that do name concrete domain behaviors
(app focus or cycle, a URL toggle, a screen capture, a settings pane open, and
the show functions the base bindings call). So the mapping of the pure
`config/keys.lua` data onto behavior is still decided in one place, the root,
while the row building, matching, app enumeration, and dispatch structure live
in the spoon.

## Rows are data, never functions

Each row carries only a small serializable descriptor, its kind plus a name or
bundle id, never a function. This matters because the Chooser hands every row to
`hs.chooser`, which serialises it to a native object, and a function there
cannot be converted, so a row holding one is silently dropped and the list comes
up empty. One dispatcher turns the descriptor back into the right call, so this
is the Command pattern with the command encoded as data, and the launcher still
never learns what a row does. Adding a row is a new entry in the build, never a
change to the presenter.

## App enumeration and caching

The installed app list is scanned once, lazily on first open, from the standard
app directories and cached, so config load stays fast and a newly installed app
appears after the next reload, which is automatic on file change. Running state
is recomputed per open so open apps sort first, and a running app not on disk in
the scanned dirs is included when it has a dock presence, to skip background
helpers.

## Recency ordering, one timeline across every row kind

The last thing used bubbles to the top whether it was an app or a command. There
is one most-recently-used timeline, not an app-only one, keyed by a
kind-qualified item key (`app:<bundleID>`, `capture:<name>`, `special:<name>`,
`window:<name>`, `settingsPane:<url>`) so an app and a command never collide.
Every used row of any kind sorts above every unused one, used rows most-recent
first, and unused rows keep their natural order, which is open apps first then
alphabetical for apps and the curated order for the action and settings rows. So
an untouched list still reads sensibly while the last pick sits on top. The
interleaving is decided once in `_orderedRows`, above the per-kind builders,
which is why `_appRows` now sorts only naturally and no longer knows about
recency.

Two observers feed that one timeline with equal weight, both through `_promote`.
The app watcher's `activated` event promotes the focused app, the same signal
Command+Tab follows, so open+Enter still lands on the last app and macOS-driven
switches keep apps fresh at the top. The chooser's `onSelect` promotes whatever
row was picked, so commands, captures, window actions, and settings panes join
the timeline the moment they are chosen. macOS exposes no public read of the
Command+Tab list, so this Observer shape, the same pattern other watchers here
use, is how the app half is replicated. The equal weight is a deliberate choice, so a command
sinks below apps as you switch apps after picking it, and it is found by typing
by then anyway; a stickier tier for launcher picks was considered and left out as
unearned. The timeline is stored under one `hs.settings` key
(`launcherRecency`), so it survives a reload (frequent here) and a reboot, capped
small, and the spoon's own app is never promoted so opening the launcher does not
float Hammerspoon to the top. On `start` it loads the saved list and seeds the
current frontmost app, so the top row is right before the first switch, and a
fresh machine with no history fills in as things are used. The key was renamed
from the old app-only `launcherAppMRU`, so old bundle-id data is ignored rather
than migrated and the order relearns within normal use.

The persist on every activation is cheap, `hs.settings` is `NSUserDefaults`,
which updates in memory and flushes to disk on its own schedule, so it is not a
disk write per switch. Two caches keep the open instant: `_appRowsCache` holds
the app rows and is dropped when the running set changes and on an app activation,
and `_orderedRowsCache` holds the fully sorted list and is dropped on any promote, so
a selection re-sorts without rescanning apps and a keystroke only filters.
Deriving the order at open time from `hs.window.orderedWindows()` was rejected,
it enumerates windows through the accessibility API, which is slow enough to lag
the open, the one path this design keeps instant. This is also why unplugging the
macOS signal would not buy performance, the watcher is nearly free and the only
costly work is the one-time disk scan; dropping it would only change semantics.
The one real limitation is correctness, not speed, it cannot know history from
before Hammerspoon ran, which the persistence and the frontmost seed minimize.

Window rows carry their live `when` predicate, so the display switch rows drop
out on a single display, staying consistent with wherever else those bindings
appear.

## Icons

App rows show the real app icon. The action rows have none of their own, so each
gets a generic icon drawn from a glyph, since this Hammerspoon has no SF Symbol
API and the named system images are too sparse. The glyph is rendered to an
image once through `hs.canvas` and cached, so it lines up in the row with the
app icons. Window actions share one glyph, the chord in the subtitle telling
them apart, while the other command actions get a per-action one.

## Picker integration

The launcher follows the picker checklist in the hammerspoon `CLAUDE.md` like
any other list tool. The spoon exposes its dot called navigation adapter through
`surface()`, which the root drops into the shared `choosers` list, and the
`launcherOpen` predicate reads `spoon.Launcher:isShowing()` directly. It has a
`launcher` context block giving it the shared next, previous, and accept
navigation with a close action (the open key doubles as the close, the same
pattern another list tool uses). Like the other list tools it docks the deferred
shortcut panel (`shortcutPanelFor("launcher")`) through the three chooser
callbacks, which spell the shortcuts out on the same canvas once the user pauses.
The native arrows, typing, accept, and cancel keys work whenever the opening key
is released. The chosen row runs deferred by a short timer, so it fires only
after the chooser tears down and
macOS restores focus to the window that was frontmost before the launcher
opened, which the window actions need since they act on the focused window.
