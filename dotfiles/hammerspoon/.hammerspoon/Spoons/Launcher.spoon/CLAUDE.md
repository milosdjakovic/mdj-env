# Launcher.spoon

The decision trail and the important facts for this spoon. Cross cutting
material stays in the hammerspoon `CLAUDE.md`, which links here. The picker
checklist and the spoon lifecycle contract this file refers to live there.

## What it is

Hyper+Space opens a filterable app switcher and command runner, the built-in
one, wired straight to the Chooser atom with no external launcher handoff. It
lists every installed application, open ones first then not running, and below
them the Hyper and window leader actions. Hyper+Space is a base HyperKey
binding, suppressed while a modal context owns Hyper, so it always opens this
launcher. An app that has a Hyper toggle shows its shortcut, the rest are
launchable by name, and typing filters by name or shortcut. Return, or Hyper+i,
runs the highlighted row.

## Why a coordinator, not inline wiring

It lives in `Launcher.spoon`, a coordinator, because it combines many plain
spoons into one feature and owns real state, the app scan caches and an
`hs.application.watcher`, so it outgrew inline wiring in the root. It is a layer
two coordinator in the sense of the lifecycle contract in the hammerspoon
`CLAUDE.md`, built over the Chooser atom, the same widget behind the clipboard
and the VPN locations, and it names no domain spoon. The root injects every
collaborator through `configure`, the Chooser factory, the pure `keys` and
`apps` data, `WindowManager:actions()`, a chord glyph resolver, the System
Settings pane descriptors, the shared predicate registry, the docked shortcut
panel, and a small `actions` table of leaf closures that do name the domain
spoons (`AppToggler:focusOrCycle` / `toggleURL`, `Capture:capture`,
`SystemSettings:open`, and the show functions the base Hyper bindings call). So
the mapping of the pure `config/keys.lua` data onto behavior is still decided in
one place, the root, while the row building, matching, app enumeration, and
dispatch structure live in the spoon.

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

## Recency ordering, replicating Command+Tab

Open apps are ordered by recency, the same order Command+Tab shows, then open
apps never yet focused and finally not-running apps, both alphabetical. macOS
exposes no public read of the Command+Tab list, so the launcher replicates it as
an Observer over a persisted most-recently-used policy, the same shape as
DisplayMemory. The app watcher it already owns also handles `activated`, moving
that app to the front of an MRU list of bundle ids and invalidating the row
cache, so the next open re-sorts. The list is stored under one `hs.settings` key
so it survives a reload (frequent here) and a reboot, capped small, and the
spoon's own activation is ignored so opening the launcher never floats
Hammerspoon to the top. On `start` it loads the saved list and seeds the current
frontmost app, so the top row is right before the first switch, and a fresh
machine with no history fills in as apps are focused.

The persist on every activation is cheap, `hs.settings` is `NSUserDefaults`,
which updates in memory and flushes to disk on its own schedule, so it is not a
disk write per switch. Deriving the order at open time from
`hs.window.orderedWindows()` was rejected, it enumerates windows through the
accessibility API, which is slow enough to lag the open, the one path this
design keeps instant. Doing the tiny work in the background on each switch and
keeping the open a cache hit is the right trade. The only real limitation is
correctness, not speed, it cannot know history from before Hammerspoon ran,
which the persistence and the frontmost seed already minimize.

Window rows carry their live `when` predicate, so the display switch rows drop
out on a single display, matching the cheat sheet.

## Icons

App rows show the real app icon. The action rows have none of their own, so each
gets a generic icon drawn from a glyph, since this Hammerspoon has no SF Symbol
API and the named system images are too sparse. The glyph is rendered to an
image once through `hs.canvas` and cached, so it lines up in the row with the
app icons. Window actions share one glyph, the chord in the subtitle telling
them apart, while capture and the system actions get a per-action one.

## Picker integration

The launcher follows the picker checklist in the hammerspoon `CLAUDE.md` like
any other list tool. The spoon exposes its dot called navigation adapter through
`surface()`, which the root drops into the shared `choosers` list, and the
`launcherOpen` predicate reads `spoon.Launcher:isShowing()` directly. It has a
`launcher` context block giving it the shared j, k, and i navigation with Space
to close (the open key doubles as the close, the way the clipboard's X does).
Like menu search and VPN it docks the deferred shortcut panel
(`shortcutPanelFor("launcher")`) through the three chooser callbacks, which
spell the shortcuts out on the same canvas once the user pauses. Native arrows,
typing, Return, and Escape work whenever Hyper is released. The chosen row runs
deferred by a short timer, so it fires only after the chooser tears down and
macOS restores focus to the window that was frontmost before the launcher
opened, which the window actions need since they act on the focused window.
