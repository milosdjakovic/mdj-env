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

## Query row sources, the composable half of the list

Most rows are a fixed catalog, apps and commands, filtered by what is typed. Some
rows are instead *computed* from what is typed, an arithmetic result or a unit
conversion, and those come from injected query row sources. A source is any table
answering `rows(query)`, the root supplies an ordered list of them, and their rows
lead the list ahead of everything else. The launcher composes them and learns
nothing about what any of them computes, which is the same shape as the leaf action
dispatch, only for producing rows rather than running them.

Two sources ship, `Arithmetic` and `Convert`, and they are two spoons rather than
one calculator because they fail differently. Arithmetic is native Lua and can
never be unavailable. Conversion needs a tool from outside Hammerspoon, declares it
required, and is therefore left out of this list entirely when that tool is absent,
so no conversion row ever appears while arithmetic keeps working. Unplugging the
whole feature is passing no sources, and adding a third is a new spoon plus one line
in the root, with no change here.

Four details make it work. A source returns a glyph rather than an image and the
launcher renders it through the same cache the action rows use, so a source draws
nothing and there is one glyph cache rather than one per source. A computed row sets
`filterText` to the raw query, so the shared matcher scores it against what was
typed rather than against the answer it produced, which is what keeps a result at
the top instead of being dropped for not resembling its own expression. A source
that raises is dropped for that keystroke with a log line, so a bad source cannot
empty the list. And `refresh()` exists for a source whose answer arrives late, which
the root wires to that source's own result callback, so the row lands without the
user typing again.

A computed row is deliberately kept out of the recency timeline. It exists only for
the query that produced it, so `recencyKey` returns nil for it. Without that every
result would share one key and float to the top of an empty launcher, which is the
last thing a fresh open should show. It is also exempt from the two discoverability
mandates, since it is not a bound shortcut and typing is the only way a computed row
could be found at all.

## A source may claim the query, which is the whole of scoping

A source can return a second value saying its rows are the entire list, and the
catalog is then not shown at all. That one bit is how a typed word hands the list to
one tool, and it is deliberately the only thing the launcher knows about it. It never
learns what made a source claim a query, what the rows now belong to, or that aliases
exist. `QueryScope.spoon` is the source that claims, and its own `CLAUDE.md` holds
the grammar and the reasoning.

Three consequences live here rather than there. A claim discards whatever earlier
sources contributed and stops the loop, so a claimed query means one thing however
the root ordered its sources, which is why ordering the claiming source first is
clarity rather than correctness. A claimed row carries a descriptor naming whoever
made it plus that thing's own opaque payload, and one injected action hands both
back, so the dispatcher routes it without learning what the payload means, exactly as
a computed result reaches an injected `copy`. And a claimed row is kept out of the
recency timeline for the same reason a computed one is, it belongs to the query that
produced it, so remembering it would float a stale answer to the top of the next
fresh open.

A claimed row can also be asked about rather than taken. `peekSelected` hands the highlighted
descriptor back out through an injected action, the same shape as running one, so this learns no
more about a peek than it does about a run. Only a claimed row has anywhere to send the question,
since an app or a command is already fully described by its own row, and `canPeekSelected` asks
the same injected side whether there is anything to show so the binding can be gated on live state
and stay out of the hints while the highlight sits on a row with nothing behind it. Whatever a
peek opens can outlive the keystroke, so the launcher's close is where it is put away, composed in
the root rather than known here.

The alias hint on a tool's own row is the launcher's side of discoverability, and it is
one injected question rather than anything this spoon knows. `add` asks `aliasHint` about
every command row it builds, passing the row's own descriptor name, and appends whatever
comes back. So no call site here mentions aliases, giving a tool one takes no edit in this
file, and the usual answer is empty. A tool with no aliases gains nothing, so the hint
appears only where scoping is real.

Asking per row rather than at each site is the whole point, because the version that was
written out by hand had been forgotten on file search, which had an alias and advertised
nothing. A hint a row can be left out of is a hint that will be.

The question is asked by name, and the name is the tool's key in `config/keys.lua`, which
is also what the row's descriptor carries and what the scope is registered under. One
identity behind the row, the scope, and the hint, so there is nothing for three strings to
disagree about. Only a `special` row is asked, since only a command row can be a tool, which
also means a window action or a capture sharing a name with a scope cannot inherit a hint
that was never about it.

What the answer says is not decided here either. The launcher gets a fragment and appends
it, so the wording lives in the composition root beside the other human text, and the
resolver behind it hands out lists and knows nothing about how they read.

A scope over a group of rows has no single row to carry a hint, which is what the alias
directory answers. Applications, window actions, System Settings panes, and menu search are
found there rather than on a row, and the directory reaches this launcher the same way
anything else does, as a row and as a query scope.

## An open may arrive with the field already filled

`show` takes an optional query, which is the same open with typing already done. It attaches
no meaning to the text, so this is not a way to open one tool, and whether that text happens
to name a scope is between whoever passed it and the resolver.

It exists because choosing a row closes a native chooser whatever produced the row, so a row
whose whole purpose is to put a word in this field cannot do it to a list that is still open.
Reopening is the mechanism rather than a workaround for one, and the alias directory is the
consumer.

Three things about it are load bearing and each one was a way to get it wrong. The query is
set after the show, because showing clears the field. A refresh follows, because setting a
chooser's query fires no callback, so without it the field would read one thing and the list
would show another, which is the same trap recorded in the resolver's own notes. And the
refresh resets the highlight, which is right for a list the user has not seen yet.

No timer is needed here. Every row already runs deferred until the chooser has torn down, which
is the same wait a reopen needs, so a reopen asked for by a row is late enough by the time it
happens.

What that wait does not guarantee is focus, and this is where the reopen had a real defect.
An open records the app it covers by asking which app is frontmost, and after a round trip
that answer came back as Hammerspoon, because our own chooser still held focus a tenth of a
second after the previous one closed. Nothing looked wrong. The list was right, the field was
right, and the only visible symptom would have been menu search reached through the directory
listing Hammerspoon's own menus instead of the menus of the app you were in.

So the covered app is never recorded as this app. When macOS answers with ourselves it is
because our own window has focus, which means the previous answer is still the true one, since
the app underneath did not change while we were in front of it. Keeping it is correct rather
than merely safe. This is the same self exclusion the recency timeline already makes, for the
same reason, and it hardens any two opens in quick succession rather than only this one.
Verified live, reaching menu search through the directory lists the covered app's menus.

## Static rows are built on first use, not at configure

The command rows and the settings pane rows used to be built in `configure`, and they are now
built on the first open and cached, joining the app scan that was already lazy there.

The reason is not performance, it is that they ask questions of collaborators. The alias hint
is answered by a resolver the root configures after this spoon, because that resolver adapts
tools wired later, so a row built at configure time asks too early and prints nothing forever.
Waiting also means a row states what is true now rather than what was true at load, which is
what a hint has to be once the words behind it can change while Hammerspoon runs.

The cost lands on the first open beside the app directory scan, which is far larger, and every
open after it is served from the cache. So the rule for anything added to these rows is that it
may ask a live question, and the rule for the root is that nothing needs reordering to make it
answerable.

## A scope may narrow this catalog instead of reaching a tool, through two public methods

`rowsOfKind` hands out the built rows of one kind, predicate gated and recency ordered exactly
as the full list is, and `runItem` is the public door onto the dispatcher. Together they let a
scope be a narrowing of this catalog rather than a route out of it, which is what the window and
settings scopes are.

The alternative was for the composition root to rebuild those rows from the same data it injects
here, and it is worth saying why that is worse. The rows would then be built twice, so a narrowed
list could disagree with the whole list about a title, about the hidden keywords a row answers
to, about which rows a predicate has gated out, and about what choosing one does. None of those
would fail loudly. Reusing the rows costs two small methods and makes the disagreement
impossible.

This is the one place a scope reaches back in here, and it stays honest because what comes back
out is a descriptor of this launcher's own making. `runItem` never sees a foreign payload, so the
dispatcher gains no case and learns nothing new.

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
