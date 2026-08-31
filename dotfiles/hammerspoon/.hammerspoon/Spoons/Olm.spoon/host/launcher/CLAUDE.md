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
never learns what a row does.

Adding a row for a registered tool is now two small edits rather than the one line
this paragraph used to promise. Phase seven's third packet moved a tool's row data, its
category, its glyph, its detail, its keywords, and whether it renders a chord, off this
file and onto that tool's `row` in the composition root's registration, so the edit
there is the `row` table itself, and the edit here is one `addTool` line in
`_buildActionRows` naming the tool, which asks the registry for that row through
`rowFor` and builds it. Adding a tool row is therefore not yet one registration, since
the launcher still needs its own line and still decides where in the build that line
sits, which is what keeps the row order exactly what a fresh reload has always shown.
The four rows belonging to no registered tool, `lock`, `sleep`, the System Settings
search focus, and the alias directory, are still a plain `add` call written by hand,
since none of those names anything the registry has ever heard of.

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

That exemption is why the empty field rotates. Each source may propose one short
example line in its own `defaults.example`, the root collects them on the same walk
that assembles the sources, and this host holds a pool of its own base wording
followed by whatever arrived. `_nextPlaceholder` steps one place around that pool per
open and `show` writes the answer onto the presentation before handing it to the
stage, so the wording changes only between opens and never under a person reading
it, and no timer exists. The position is a plain counter in memory, so a reload
starts the cycle again at the base wording, which costs nothing worth a settings key.

This host writes no example and knows no source by name. A pool of one is the whole
feature absent, which is exactly what an install with no computed source, or one
whose calculator tool is missing, already gets. Adding a fourth hint is a line in
some other plugin's own manifest and no edit here.

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

It exists for the one way a word can arrive with no list left to type it into, a mouse click whose
row the accessibility tree could not resolve. That is a completion, so the chooser is already gone
by the time it runs and reopening is all that is left.

It used to be the only way, including from inside the directory itself, and that is the flicker
it was reported for. A list closing and another opening to deliver two characters is a poor way
to say the field changed. A row that means this list becomes another list is answered before it is
allowed to close now, through the atom's `intercept`, and that holds for the mouse as well as for
both keys. The main `CLAUDE.md` has why answering takes a key, and a click, away from the widget.

## Two ways to replace this list, and they are not the same thing

`seedQuery(text)` puts a word in the field. `enterPage(prefix, title)` hosts somebody else's list.
Both leave the chooser exactly where it was and both are reached through the one routed question,
but they answer different rows and confusing them was a reported defect rather than a nuance. A
row that names a WORD should seed, which is an alias directory row and nothing else, since being
handed the word is the entire purpose of that list. A row that names a LIST should host, so the
rows change and nothing else does. Typing `v ` into the field when the VPN row was chosen was the
first attempt at this and it was wrong, because choosing a tool should hand you the tool.

A PAGE IS A PREFIX THIS SPOON NEVER SHOWS. `_commandRows` puts the held prefix in front of
whatever the user typed before asking the query sources, and their answer is the whole list, so
the field holds only the typing. That is one line, and it is why hosting needed no second row
mechanism, no second matcher, no second definition of what choosing a row does, and nothing at all
from the tool being hosted. Which prefix, and whether one exists, are decided by whoever passes
it, exactly as with the text `seedQuery` takes, so this spoon still names no tool. The title is
what the field says while empty, which is the only thing telling you where you are once no word is
visible, so it names the list and the way out of it. `leavePage` is that way out, wired to the
atom's `back`, which asks only when there is nothing left to delete, so Backspace stays ordinary
editing every other time. Seeding leaves a page first, because seeding is about this spoon's own
field, and without that the page's prefix and the seeded text composed into a query neither meant.

EVERY ROW IS ASKED, not only a row a source computed, and that is a deliberate widening. Whether a
row replaces the list is not a property of where it came from, it is a decision about what the row
is for, and the only layer holding that decision is the one that named both the row and the thing
it points at. So the gate that used to sit here, a claimed row only, moved out to the root, which
answers for a scope row and for the tool rows it lists as hosted. Peeking keeps its gate, because
that question really is about a row belonging to somebody else.

`_replacementFor` answers with a CALLABLE and not a yes, and that is not decoration. It was written
that way because two things asked it, the atom when a row is taken and a shortcut hint on every
highlight move to decide what to call the primary key. The first version acted while answering, so
the hint panel hosted whatever tool the cursor was on the moment it looked, which the probe caught
as a query of `vpn` turning into the alias directory. The hint has since stopped asking, because the
word it printed described the mechanism rather than anything the user wanted, so there is one caller
today. The shape stays regardless. Collapsing it would put the effect back inside the answer and
re-arm that defect for whoever next wants to know what a row would do, which is a worse trade than
one line of indirection.

What the hint asks instead is `selectedKind`, since what the primary key should be called depends on
the sort of thing under it and nothing more. An application is opened where a command is run. The
kind is this spoon's own vocabulary, the word its dispatcher already switches on, so answering with
it exposes nothing, while what any kind is CALLED stays in the root where human wording belongs.

Promoting into the recency order happens in the closure `configure` passes the atom, for the same
reason and not by coincidence. Taking a row that replaces the list is still using the thing it
points at, and it lands under the key running it produced, so the order is what it was before any
of this, while promoting inside the question would have reordered the list by looking at it.

Three things about it are load bearing and each one was a way to get it wrong. The query is
set after the show, because showing clears the field. A refresh follows, because setting a
chooser's query fires no callback, so without it the field would read one thing and the list
would show another, which is the same trap recorded in the resolver's own notes. And the
refresh resets the highlight, which is right for a list the user has not seen yet.

A fourth was found the same way and fixed a layer down. A seeded field arrived with its text
selected, so the first character typed deleted the word that had just been handed over and you
were back in the unscoped launcher wondering what happened. That belongs to the atom, since
setting a field's text is its job and it had two callers with the same bug.

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
app directories and cached, so config load stays fast. Running state is
recomputed per open so open apps sort first, and a running app not on disk in
the scanned dirs is included when it has a dock presence, to skip background
helpers.

`start` also installs an `hs.pathwatcher` on `/Applications` and on
`HOME/Applications`, the two directories in the scan that can change without a
reboot, and only for a root that actually exists on this machine, the same
guard the disk scan itself already puts in front of a directory, since
`HOME/Applications` is common enough to be absent that asking to watch it
anyway would be asking for a defect nobody would see until the day it mattered.
`start` is declared wiring, `manifest.lua`'s own `wiring = { { method = "start"
} }`, and reading only this file's own comments once said so without it being
true. Nothing beyond `configure` runs a plugin whose manifest never says a
step exists, so this host owned no live state at all, no app watcher, no
directory watchers, and no persisted recency, until that line existed. A change
under either watched directory drops the disk scan along with both row caches,
so an app installed or removed while Hammerspoon is already running is picked
up on the next launcher open rather than waiting for a config reload, which
used to be the only way to see it unless the app happened to already be
running. `/System/Applications` is left unwatched on purpose, since it only
changes as part of an OS update, and an OS update always brings a reboot and a
fresh Hammerspoon load, so a watcher there would never see anything the reload
was not about to show anyway.

Not every change under a watched directory earns a cache drop. `hs.pathwatcher`
fires for any file event anywhere beneath the root it watches, which includes a
write inside an app bundle that is already installed, a self updating app
rewriting its own files being the ordinary case, and that must not throw away
the scan on every one of those. `isTopLevelAppChange` keeps only a path ending
in `.app`, an app bundle itself arriving, leaving, or being renamed, a path
with no further slash past the watched directory, a direct child of it, or the
watched directory's own bare path, which is what FSEvents reports instead of
any real path once its queue overflows during a very large copy. Anything
nested deeper than a direct child is a change inside a bundle that already
exists, which the installed set does not care about. Nothing rescans inside the
watcher callback itself either way, the whole point is that the cost lands on
the person's next open rather than on the filesystem event, and a burst of
several relevant changes from one install just clears an already empty cache a
few extra times for free, which costs nothing worth debouncing. `stop` tears
both watchers down and drops the disk scan cache with them, so a stopped
launcher never holds a scan that nothing is left to keep honest.

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

The timeline is fed by launcher picks alone, on the user's decision of
2026-08-07. The chooser's `onSelect` promotes whatever row was picked, through
`_promote`, and the `intercept` closure promotes a row taken as a replacement
for the list the same way, so an app, a command, a capture, a window action,
and a settings pane all join the timeline the moment they are actually chosen.
A row a query source computed still answers nil to `recencyKey` and stays out
of the timeline exactly as before. An app merely becoming frontmost is not a
pick, whether that happens through Command+Tab or through the app watcher
below, so neither promotes anything any more. The watcher stays for a
different job, refreshing the running set. It drops `_appRowsCache` on
activation, launch, and termination, and drops `_orderedRowsCache` on launch
and termination too, since only the running set changed there and no pick was
made. The timeline is stored under one `hs.settings` key, `launcherRecency`,
so it survives a reload, frequent here, and a reboot, capped small, and the
spoon's own app is never promoted so opening the launcher does not float
Hammerspoon to the top. On `start` it only loads the saved list, it no longer
seeds the frontmost app, since the app open at reload time was never a pick
either. The list itself is not cleared or migrated for this change, so an
entry an earlier build wrote from ambient focus decays naturally past the cap
as real picks accumulate, and a fresh machine with no history fills in the
same way. The key was renamed once already from the old app only
`launcherAppMRU`, so that renaming and this one both leave old data to decay
rather than migrate.

The persist on every pick is cheap, `hs.settings` is `NSUserDefaults`, which
updates in memory and flushes to disk on its own schedule, so it is not a disk
write per pick. Two caches keep the open instant. `_appRowsCache` holds the
app rows and is dropped when the running set changes. `_orderedRowsCache`
holds the fully sorted list and is dropped on any promote, so a pick sorts
again without rescanning apps and a keystroke only filters.
Deriving the order at open time from `hs.window.orderedWindows()` was rejected,
it enumerates windows through the accessibility API, which is slow enough to
lag the open, the one path this design keeps instant. The one real limitation
is correctness, not speed, it cannot know a pick from before Hammerspoon ran,
which the persistence minimizes.

Window rows carry their live `when` predicate, so the display switch rows drop
out on a single display, staying consistent with wherever else those bindings
appear.

## Icons

App rows show the real app icon. The action rows have none of their own, so each
gets a generic icon drawn from a glyph, since this Hammerspoon has no SF Symbol
API and the named system images are too sparse. Window actions share one glyph,
the chord in the subtitle telling them apart, while the other command actions
get a per-action one.

The drawing itself, once this spoon's own private `_glyphIcon`, moved to the
shared `Olm.spoon/lib/glyphicon.lua` in phase eight's third packet, once
`ActionPanel` became a genuine second caller of the exact same drawing. This
spoon keeps `_glyphIcon` as the thin caller everything here already reaches
through, delegating to an instance the composition root builds and injects as
`opts.glyphIcon`, so a glyph is still rendered to an image once through
`hs.canvas` and cached, in the exact same size and frame as before, and it
still lines up in the row with the app icons. The cache itself now lives on
the injected instance rather than on a field of this spoon, and the root hands
the panel the very same instance, so a glyph the two happen to share, the
arrow pointing back among them, is drawn once rather than twice.

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
