# Launcher.spoon

The decision trail and the important facts for this spoon. Cross cutting
material stays in the hammerspoon `AGENTS.md`, which links here. The picker
checklist and the spoon lifecycle contract this file refers to live there.

## What it is

A filterable app switcher and command runner, the built-in one, wired straight
to the Chooser atom with no external launcher handoff. It lists every installed
application, open ones first then not running, and below them the injected
command actions. Its open binding is a base binding, suppressed while a modal
context owns the opening key, so it always opens this launcher. An app some
plugin bound a chord for shows it, the rest are launchable by name, and typing filters
by name or shortcut. The native accept key, or the shared accept action, runs
the highlighted row.

## Why a coordinator, not inline wiring

It lives in `Launcher.spoon`, a coordinator, because it combines many plain
spoons into one feature and owns real state, the app scan caches and an
`hs.application.watcher`, so it outgrew inline wiring in the root. It is a layer
two coordinator in the sense of the lifecycle contract in the hammerspoon
`AGENTS.md`, built over the Chooser atom, the same widget behind the other list
tools, and it names no domain spoon and no plugin. The root injects every
collaborator through `configure`, the stage, the merged app details other
plugins supply for an app row, a chord glyph resolver and the leader display names, the shared predicate
registry, the tool registry, the rows other plugins contribute with the runners
that take them back, and a small `actions` table of leaf closures that close
over core alone (app focus or cycle and a URL toggle through `lib/appfocus.lua`,
a copy, the query scope's run and peek, and the bare system commands). So the
row building, matching, app enumeration, and dispatch structure live in the
spoon, and what any contributed row does lives with the plugin that built it.

Until phase three of the core split, 2026-10-16, the manifest declared seven
siblings on four plugins for those leaves, the window manager's action map, the
app toggler's two app calls, capture's run, and System Settings' rows, open and
search focus, and the root built a table of closures over them. A host in core
naming plugins is the coupling the split exists to remove, so each became either
a contribution any plugin may declare or a core lib, and the manifest has no
siblings now. `decisions/olm-core-split.md` at the repository root has the
record.

The app rows read person data until the split finished. The person's toggle list
and app registry reached this host so it could put a Hyper chord on an app row's
subtitle, the same leak phase four removed from the Hyper sheet. A plugin that
binds an app's chord now declares `provides.launcherAppDetails`, the host asks the
set `launcherAppDetails`, and the root hands it one function, `appDetails`,
merging every supplier by bundle id. It is asked each time the app rows are
built. The app catalog itself is the host's own disk scan, which is launcher
policy and needs no person data, so the host declares neither `toggles` nor
`apps`. With the app toggler switched off an app row carries no chord.

## Rows are data, never functions

Each row carries only a small serializable descriptor, its kind plus a name or
bundle id, never a function. This matters because the Chooser hands every row to
`hs.chooser`, which serialises it to a native object, and a function there
cannot be converted, so a row holding one is silently dropped and the list comes
up empty. One dispatcher turns the descriptor back into the right call, so this
is the Command pattern with the command encoded as data, and the launcher still
never learns what a row does.

Adding a row for a registered tool is one registration and no edit here. A tool's row
data, its category, its icon, its detail, its keywords, and whether it renders a chord,
lives on that tool's `row` in its registration, and `_buildActionRows` asks the registry
for every row it holds, in the registry's own order, through `listing` and `rowFor`. The
one `addTool` line per tool this paragraph used to describe is gone, and those registry
rows lead the catalog ahead of every contributed and declared row.
The three rows belonging to no registered tool and no plugin, `lock`, `sleep`, and the
alias directory, are declared in this host's own manifest as `specialRows`, since none of
those names anything the registry has ever heard of. The System Settings search row was a
fourth until phase three of the core split, and it is that plugin's own contributed row now.

## Rows other plugins contribute, and the owner that runs them

A plugin whose actions deserve rows in this catalog, rather than one row for the plugin as a
whole, declares `provides.launcherRows`, a member answering plain row descriptors, and
`provides.launcherRun`, a member handed a chosen row's item. Capture, the window manager and
System Settings do today. The manifest asks the set for both, `needs.set.launcherRows` and
`needs.set.launcherRun`, so the plugins join by declaring and this host names none of them.
A plugin may declare `launcherRun` alone, which is what Window Size does, since its one row is
computed from a typed size and reaches the list as a query row instead.

The root turns the set answers into two values this host receives, `rowSuppliers`, one function
per contributor answering that plugin's rows, and `runners`, keyed by owner identity. Every row
a supplier answers, and every row a query source answers, comes back with the plugin's identity
stamped on its item as `owner` and on the row as `iconOwner`, so the icon key is read against
the plugin that named it and a chosen row is routed by one plain string. `_runItem` asks first
whether the item has an owner with a runner and runs it through that runner, on the same short
delay every row waits for after the chooser closes. Only then does the kind switch run, and
the kinds this host still owns are `app`, `special` for registry tools and its own declared
rows, `calc` and `scope`. A computed sum carries an owner and no runner, so it falls through to
`calc` exactly as before. An owned row whose owner runs nothing never reaches `special` or
`scope`, since both act on a tool's name and an owner must not reach another tool through a
word it chose. The root also writes the owner over whatever a row arrived with, so a plugin
cannot route a row into somebody else's runner, and an owned row is never asked for an alias
hint nor taken by the root's intercept for a registered tool or a scope of the same name.

A contributed row is `{ title, subTitle?, group?, chord?, icon, keywords?, when?, order?,
item }`. The item names its `kind` and a `name`, and may state `key`, the identifying string
the launcher remembers it by in place of the name, and `remember = false`, which keeps it out
of recency and the query memory altogether. Row identity is the row's own business, so this
host keys every row it did not build as the kind joined to the key or the name, and only its own
kinds keep rules of their own, an app by its bundle id, a computed or scoped row never. Every row
that existed before the change keeps exactly the key it was persisted under, `capture` and the
action name, `window` and the action name, `settingsPane` and the url stated as its key,
`special` and `searchSettings`, and a typed window size states `remember = false` where this host
used to recognise one by its size field. Two contributed rows answering one kind and one key are
named at build with both owners, since they would share a memory and nothing would say so. A row
names its chord as parts rather than as words, `group` the word before it and `chord = {
leader, key, mods }` with the leader as a role, so the subtitle is spelled by `_chordSuffix`
with the one shared speller and the leader display name the root passes for every role, and
reads byte for byte what it read when this host built the row itself. A row with a finished
`subTitle` keeps it as it stands.

The order of an untouched list is a declared number, not something this host works out. Each
contributor states `defaults.launcherOrder` in its own manifest, a person may move it in
`config/plugins.lua` like any default, and the root stamps it on every row the plugin answers
that does not state its own `order`. This host's own declared rows take its own
`defaults.launcherOrder`. `_buildActionRows` puts the registry's rows first and then sorts the
rest by that number, a row with none after every numbered one, a tie keeping the suppliers in
the set's own order, each supplier's rows in the order it answered them, and this host's own rows
last. The shipped numbers are capture 10, the settings search row 20 by its own `order`, this
host's alias directory, lock and sleep 30, the window manager 40 and the System Settings panes
50, which is exactly the order the list had before. Nothing reads a kind word or a plugin name
to decide a place. A first attempt grouped rows by kind with the groups in the order the kind
words sort and a `directory` mark for the panes, which reproduced the order by coincidence of
spelling, and it was replaced by these numbers the same day. The `directory` mark went with it,
since the panes sit last by their number alone and the app rows always lead the catalog anyway.
A supplier that raises is dropped with a log line rather than costing the list every other row.

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

Four details make it work. A source returns an icon rather than an image, a key into its own
manifest icons or a table spec, and the root wraps each source so the rows it answers come back
stamped with their owner, so a source draws nothing and there is one icon cache rather than one per source. A computed row sets
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
example line in its own `defaults.example`, or a list of several when one plugin
covers more than one capability worth teaching, and the root collects and flattens
whatever arrived on the same walk that assembles the sources. This host holds a pool
of its own base wording followed by every line that arrived. `_nextPlaceholder` picks
a uniformly random entry from that pool per open, never the entry `_placeholderLast`
remembers as the immediately previous open's own pick, and `show` writes the answer
onto the presentation before handing it to the stage, so the wording changes only
between opens and never under a person reading it, and no timer exists.

Random rather than a fixed cycle on purpose, and the reason is what the fixed cycle
actually did in practice rather than what it promised. A cycle answers its first
position after every single reload, which was always the plain base wording, and a
reload is frequent enough here that a person could go a long time without ever
seeing a computed source's own line. Random means the very first open after a
reload is as likely to land on `Try 100 eur to usd` as on the base wording, the base
wording being one ordinary entry in the pool rather than a guaranteed opener. The one
thing kept from the old cycle is that two opens in a row still never repeat, `math.random`
is asked again until it disagrees with `_placeholderLast` rather than being trusted on
the first draw, which is cheap since the pool is a handful of strings and a person would
read an accidental repeat as the feature doing nothing. `start` seeds `math.random` once
with `math.randomseed(os.time())`, the same call `plugins/clipboard/manager/init.lua`'s
own `start` already makes, so the sequence is not identical after every single reload.
`_placeholderLast` is deliberately not persisted, a reload forgetting the previous pick
costing nothing since the very next open draws fresh regardless. A pool of one, the
ordinary shape when no computed source is present, has nothing to avoid repeating and
answers itself every time, reading exactly as this field always did before any of this
existed.

This host writes no example and knows no source by name. A pool of one is the whole
feature absent, which is exactly what an install with no computed source, or one
whose calculator tool is missing, already gets. Adding another hint, or a whole new
source, is a line in some other plugin's own manifest and no edit here.

## A source may claim the query, which is the whole of scoping

A source can return a second value saying its rows are the entire list, and the
catalog is then not shown at all. That one bit is how a typed word hands the list to
one tool, and it is deliberately the only thing the launcher knows about it. It never
learns what made a source claim a query, what the rows now belong to, or that aliases
exist. `QueryScope.spoon` is the source that claims, and its own `AGENTS.md` holds
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

The question is asked by name, and the name is the plugin's identity, the one its manifest declares and `config/plugins.lua` keys by, which
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
both keys. The main `AGENTS.md` has why answering takes a key, and a click, away from the widget.

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
built on the first open and cached, joining the app scan that was already lazy there. A
contributed row is asked of its supplier at that moment too, which matters for System
Settings, whose pane list is empty until its own configure has run.

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
out is a row this launcher built. A contributed row handed back through `runItem` still carries
its owner, so it reaches its plugin's runner exactly as it would have from the full list, and
the dispatcher gains no case and learns nothing new.

## App enumeration and caching

The installed app list is scanned from the standard app directories and cached.
Running state is recomputed per open so open apps sort first, and a running app
not on disk in the scanned dirs is included when it has a dock presence, to skip
background helpers.

The scan is the launcher's one genuinely expensive step, measured at 356ms warm
over 146 apps and worse on a cold filesystem, almost all of it reading a plist
per bundle and rendering an icon per bundle. It used to run lazily inside the
first `_appRows`, which is inside the first row build, which is inside `show`,
ahead of the window being placed, so the first open after every load stalled the
main thread for the whole scan before anything appeared. `_warmAppScan` moves
that cost onto a timer instead. `start` schedules one a few seconds after the
load, by which point nothing is racing it, and the first real open finds the
cache already filled. The lazy read in `_appRows` is untouched and still scans
for itself when it finds no cache, so a warm up that has not fired yet, or one
whose result was dropped a moment ago, costs correctness nothing and only costs
that one open its old speed. The warm up is a head start, not a second source of
truth.

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
the scan on every one of those.

`isTopLevelAppChange` is what draws that line, and its first version drew it
wrong in a way worth recording. It asked whether the path ended in `.app`
before it asked anything about depth, and answered yes when it did, at any
depth. That reads as an app bundle itself arriving, leaving, or being renamed,
and it is not what it says, because an app bundle contains other app bundles.
`/Applications` on this machine holds 217 of them, Xcode carrying thirty,
Chrome twelve, Docker, 1Password, Arc, Figma and Claude their own handful each.
So a self updating app rewriting its own helpers, the single most ordinary
event under this directory, matched the very check written to exclude it,
dropped the whole disk scan, and handed the next open a 299ms rescan on the
main thread inside `show`.

Depth is asked first now. A path is noise the moment any ancestor component is
an `.app`, which is what a change inside a bundle that already exists actually
means. A `.app` that is not inside another `.app` still counts at any depth,
since the scan descends into vendor subfolders and an app one level down in one
of those is a real arrival. A direct child that is not a bundle counts too,
since an installer commonly writes a temporary name and renames it into place.
The watched directory's own bare path counts as well, which is what FSEvents
reports instead of any real path once its queue overflows during a very large
copy. The watcher callback itself
still never scans, it drops the caches and then asks `_warmAppScan` for a
rebuild on a longer delay than `start` uses, because an installer writing an app
bundle fires many times while that bundle is still half written and a scan taken
mid write reads a bundle that is not there yet. One timer, restarted on every
call, is what turns a whole install's burst into a single scan after the writing
stops. `stop` tears both watchers down, stops any pending warm up, and drops the
disk scan cache with them, so a stopped launcher never holds a scan that nothing
is left to keep honest and never has one land on it afterwards.

## Recency ordering, one timeline across every row kind

The last thing used bubbles to the top whether it was an app or a command. There
is one most-recently-used timeline, not an app-only one, keyed by a
kind-qualified item key (`app:<bundleID>`, `capture:<name>`, `special:<name>`,
`window:<name>`, `settingsPane:<url>`) so an app and a command never collide.
The key is the kind and the row's own `key` or its name, never the owner, so a
row a plugin contributes is remembered under the same key the launcher used when
it built that row itself, a pane stating its url as its key, and a pick persisted
before phase three of the core split still floats its row.
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

## What orders the list once something is typed

The timeline above is what an untouched list opens on and it ends there. The
moment a character is typed a second memory takes over, and the two answer
different questions on purpose. The timeline says what was picked last. The
association store, `lib/queryassoc.lua` under the settings key
`launcherQueryAssoc`, says what a particular query has come to mean.

The reason there is a second memory at all is that the first one was invisible
here. This list used to let the chooser atom score and sort it, and the atom
breaks a tie on arrival order, which is exactly the timeline order. That tie
never happened. Two rows matching equally well still differ by hundredths of a
point over incidental things, chiefly how long a subtitle is, since the scorer
charges a fraction for every character after the last one it matched. Typing
`ma` scores Mail at 21.86 and Maps at 21.72, identical matches separated only by
`Not running` being nine characters longer than `Open`. So the order you saw
while typing was the text score alone and nothing you did ever changed it.

`_rankCatalog` now does that work. On an empty query it hands the rows straight
back, untouched, which is what keeps the resting list exactly as it was. Once
something is typed it scores every row through the one rank engine,
`lib/chooser/rank.lua`, handed over by the root as `rank`, and drops the misses,
exactly as the atom does, and then orders the survivors with anything this query
has been used to pick before leading, the rest by the engine's own order, score
first and the resting position breaking a tie so the timeline still shows
through underneath. The presentation therefore carries `matcher = false`, which is the
presentation's own field and not the manifest's, the manifest naming which
strategy to inject rather than whether the atom should use it.

A pick is recorded against the query that was in the field and against every
prefix of it two characters or longer, so the shorter searches improve on the
way to the longer ones. A single character is recorded only when it was the
whole query, never taught from a longer one, so typing a long distinctive name
cannot quietly take over `a`, `s` or `w`, which the catalog scopes answer to.
Recording uses the same `recencyKey` the timeline does, so a computed row, a
scope row and a typed window size are never recorded, and nothing is recorded
while a page is hosted since the rows on screen are then another tool's.

Strength is one decaying number per pair rather than a count, on an event clock
counted per query rather than a wall clock. A count cannot tell a preference
apart from a change of habit and makes a long history impossible to overturn.
Here a score converges on a ceiling, so the picks needed to overturn a settled
favourite are the same handful whatever its history, four at the shipped decay.
The leader is sticky by a margin, which costs nothing in speed and roughly
halves how often the top row changes where two rows are used about equally. The
three numbers are `ranking` in the manifest defaults and each carries its own
note there.

The guard worth knowing about is `nearness`. Because every remembered spelling
answers for the longer queries it begins, a pick made at `ma` is consulted when
you type `mail` too, and Maps really does match `mail` by spending the scorer's
typo allowance on the letter it cannot place. Left unconditional, that ordered
Maps above Mail while Mail was spelled out in full. So a remembered pick decides
only among rows that scored close to the best one, as a proportion rather than a
number of points since the score grows with every character. Measured, `mail`
puts Maps at 28.6% of Mail, `map` puts Mail at 65% of Maps, and `ma` puts them
at 99.4% of each other, so the default of 0.9 sits a long way from both edges.
Since the shared search ranks four levels of match and carries the level as a
large step in the score, the proportion is taken of the score inside the level,
the number those measurements were made on, and measured down from the best
row's score by its size so a best score below zero cannot invert it. A pick may
lead at any level unless the best row matches every word at a word start and
the pick does not, which is the Mail and Maps guard stated as a kind of match.

Pruning is deliberately partial. An application that has gone is proven gone by
the disk scan, so its pairs are dropped in `_pruneAssociations`, hung off the
same warm scan timer that already knows. Everything else is left alone, because
a row can disappear because its tool was switched off rather than removed and
this host cannot tell those apart, and deleting a year of history on that
ambiguity is worse than carrying a number no row will ever claim. The decay
forgets it anyway within a couple of dozen picks of that query.

`test/ranking.lua` proves all of it in plain Lua with no Hammerspoon and no
lock, which matters here more than elsewhere because this host is the dry gate's
permanent unknown and nothing else checks any of it before a live load.

## Icons

App rows show the real app icon. The action rows have none of their own, so each
names an icon and Olm draws it in the active set. A registered tool's row names a key into
that plugin's own manifest icons, with the owner taken from the registry listing, so a
command's row reads its owning plugin's icons. The rows this host states itself, its special
rows and the three catalog scopes, name keys of the launcher's own manifest icons, `lock`,
`sleep`, `aliases`, `apps`, `windows` and `settingsPanes`, the last named for its scope rather
than `settings`, which is also a plugin's identity. A contributed row reads against its
owner, stamped by the root. Window actions share the window manager's own `windows` icon, the
chord in the subtitle telling them apart, and the settings search row wears System Settings'
own `search`. Both icons were the launcher's until phase three of the core split, and the
plugins declare the same emoji and SF Symbol, so the pictures did not change.

This spoon draws no icon. Since 2026 10 15 a row it builds keeps `icon` and `iconOwner` as data,
the owner defaulting to the launcher's own identity, `opts.iconOwner`, and the chooser draws the
picture when it paints, through the resolver in `lib/icons/rows.lua` over the one engine in
`lib/icons`. The rows here are cached across shows, so a picture drawn when the cache was built
kept the colour of the half the system was in then, and a light and dark switch left the icons
wrong. Only a real picture, an app icon, is held in `image`, and every row copy in this file
passes `icon` and `iconOwner` along with it. An icon is drawn once per colour by the engine, in
the same size and frame as before, and it still lines up in the row with the app icons.

## Picker integration

The launcher follows the picker checklist in the hammerspoon `AGENTS.md` like
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
