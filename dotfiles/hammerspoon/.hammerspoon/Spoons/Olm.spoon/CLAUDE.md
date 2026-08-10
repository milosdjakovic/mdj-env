# CLAUDE.md

This file records the decisions behind olm's core libs, the shared mechanisms under `lib/`
that a plugin reaches through `Olm.lib`. One section per lib, holding what a future reader
would otherwise have to rediscover by measuring. The interaction rules, the core membership
test, and the packaging decision live in the design at
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md` until the
phase that moves them here.

## Paste, the insertion primitives

`lib/paste.lua` is the shared insertion engine, carved out of the insertion half of
`ClipboardHistory.spoon/manager/monitor.lua` in phase three of the build plan. Everything below
was measured rather than reasoned about, most of it while chasing a fault that turned out to be
somewhere other than where it looked, so it travels with the code it describes. The clipboard
features these primitives enabled, the append accumulator and the sequential paste walk, are not
described here. Their trail stays in the module level `CLAUDE.md` beside the rest of the
clipboard, and this section is only the properties of the primitives underneath them.

The two names below that are not in this file are `session.lua` and `ui.lua`, both in the
clipboard plugin at `Olm.spoon/plugins/clipboard/manager/`, which are the callers most of these
findings were measured through.

**Direct insertion against a paste.** A walk through a list does not paste text at all, it hands
it straight to the focused field through `insertText`, which sets `AXSelectedText` on the focused
accessibility element. That lands three to fourteen milliseconds after the press, measured, and
involves neither the pasteboard nor the keyboard, so there is nothing to serialise on, nothing to
put back, and nothing to wait out, and taps land as fast as they come. A paste can never be that,
and not because of anything on our side. The unavoidable cost in a paste is the receiving app
reading the pasteboard, its work on its own clock, and until it has nothing may write there
again. Anything that is not text, and any field that refuses `AXSelectedText`, falls back to a
real paste and pays that cost, because there is no other way in for those.

**What a fallback paste asks for.** It reorders nothing, so a caller stepping through a list
reads that list without rewriting the order it is reading. That used to be a `reorder` option on
the paste itself and is now simply something the caller does or does not do afterwards, since
what a paste means for the list it came out of was never the engine's business. It puts the
clipboard back once the burst is over, so however far it has gone a plain paste still means what
it meant before. It restores to one snapshot taken when the walk began rather than one per step,
since a per step snapshot would capture the previous step's own content. Steps also serialise on
a settle callback, because two overlapping pastes would have the first one's restore land on top
of the second one's content.

**One primitive underneath all of it.** Every paste path funnels through `pasteOp`, with
restoring and the settle callback passed in as options rather than baked in, which is what let
the walk reuse the proven path instead of growing a second one. `pasteText` is a synthetic op
through that same primitive.

**The restore guard.** Every restore in this file, the one right after a plain paste, the one
that waits out a quiet window, and the one wrapped around a selection read by Cmd+C, answers to
one guard, `pasteboardStillOurs`, rather than to changeCount alone. An unmoved count still means
nothing has touched the pasteboard since the write, and the restore is plainly safe on that
alone, exactly as it always was. A moved count used to be read as proof on its own that a real
copy had claimed the pasteboard, and that reading is naive, because the very case `selfSigs`
already exists for, a receiving app rewriting the pasteboard with the same content when it takes
our paste, moves the count a second time while carrying nothing new. So a moved count now falls
through to content instead of ending the question there, asking whether what sits on the
pasteboard right now still is the thing the recorded signature describes, rather than only
whether the count changed. That signature travels out of `writeEntry` alongside the boolean that
says whether anything was written, since the restore that fires later is what needs it, and a
value returned only for the caller that asks for it costs nothing to every caller that already
ignored it. Getting the question wrong in one direction abandons a restore that was never
actually at risk and leaves our own pasted text sitting on the user's clipboard, which is the
very thing the restore exists to prevent. Getting it wrong the other way is worse, since writing
the old clipboard over a genuine copy does not merely misfile it, it destroys it outright, and
the user loses something they just copied with nothing left to recover. That asymmetry is why the
ambiguous case is resolved by content rather than by a guess. A write with no signature, an
image, has no second opinion available and still answers to the count alone exactly as it always
did. When a restore is abandoned the recorded count is deliberately left alone, so a poll on a
capture side sees the new content as a change and captures it as the fresh entry it really is,
rather than the restore hiding it the way a successful restore hides its own write. The signature
is read back narrowly, the same way it was written, rather than through a full capture reader
chain, since the only question a restore ever asks is whether this one write, or its echo, is
still there, never what kind of thing arrived instead. The same guard covers all three restores
named above, and the quiet window one waits the longest, so it is the likeliest place a genuine
copy actually lands before a restore would otherwise overwrite it.

**A synthetic stroke against a held chord.** Both clipboard keys that use these primitives post
their synthetic stroke while the chord that asked for it is still physically held, which is a
hazard none of the earlier keystroke paths faced, since every one of them fires either after a
chooser closed or from Hyper, and Hyper is Caps Lock through ChordKey so it holds nothing down.
The append failed on every press with nothing selected, while the identical read through
TextCase, on Hyper, worked every time, which made the held modifiers look certain. They were not,
and the wrong turn cost more than the fix, so the measurements are recorded here.

A posted stroke does not carry the held modifiers. An event tap sees exactly the modifiers asked
for, held keys and all, and a real app copies and pastes happily with a chord asserted, and a probe
that pasted through three delivery mechanisms during a genuine physical hold had all three arrive,
including the plain `keyStroke`. So nothing waits for a release, and neither key needs one.

That does not mean a synthetic stroke against a held chord cannot be relied on, only that a delay
cannot make it reliable. The walk sent one Cmd+V per step into Antinote, with the log showing every
write, every stroke and `held=alt+ctrl` each time, and not one of them pasted anything through
`keyStroke`. The app was not being asked too early, it was refusing a stroke posted to the system
while the chord asking for it was still held. What answers that is where the stroke lands rather
than when. A probe posting the same stroke straight to the frontmost application, built with
`hs.eventtap.event.newKeyEvent` in place of `keyStroke`, pasted consistently in that same terminal
at every speed tried, with the same keys held every time, after the identical stroke through
`keyStroke` had been refused on every attempt. `lib/paste.lua` posts there now, reaching for the
frontmost application at the moment of the stroke and keeping `keyStroke` only as the fallback for
the one case where there is no frontmost application to post to. So a physically held chord no
longer needs its keys lifted for either key to land, and the Cmd+C that reads a selection gets the
same correction through the same funnel with no separate work.

**The beat before a stroke.** What does interfere is posting the stroke in the same instant the
key that asked for it is still being delivered, and that alone was the bug. The paste path always
waited `pasteDelay` before its Cmd+V and never showed the fault, the read path posted its Cmd+C
immediately and always did. `copyDelay` in `lib/paste.lua` is that missing beat. The failure is
invisible from inside, the pasteboard write succeeds and only the app's response is missing, so a
read that times out logs the frontmost app and the modifiers held, because nothing selected and
the app ignored us are otherwise the same event.

Two other attempted fixes were removed and are worth not repeating. Clearing the held modifiers by
posting key events on their keycodes does nothing at all, since the modifier state is derived from
`flagsChanged` events alone. Clearing it properly with a hand built `flagsChanged` event does move
the state but cannot be timed, because the app processes the stroke well after the restore has
already run.

**The queue and the receiving app's clock.** Presses that land inside an unsettled paste are
queued rather than dropped, capped at a handful. A paste takes about a quarter of a second to
settle and tapping faster than that is ordinary, so dropping was what made a fast burst look like
it pasted only part of what was asked for. They still never overlap, since two pastes in flight
would have the first one's restore land on top of the second one's content, and a walk that ends
discards whatever was queued for it. The queue itself is the caller's, in the clipboard's
`session.lua`, since a queue belongs to whatever is being walked.

Queueing them exposed the constraint the drops had been hiding, and it is the receiving app's
clock, not ours. The gap between our Cmd+V and the next write of any kind is all the time that app
has to read what we pasted, and an app slower than that reads whatever replaced it, so it pastes
the wrong entry or nothing. Draining a queued press the instant a paste settled left only the
settle delay, and a burst went back to delivering part of itself, which is the same symptom the
drops caused and a different cause. `sequenceDrainDelay` is the gap, one number, and the restore at
the end of a burst waits a hair longer than it so a step already queued wins the tie and cancels
it, which is also what leaves a burst with one restore instead of one between every pair. Both
sides of that pair come from the one number, which lives in the clipboard's `session.lua` because
the caller is what knows the cadence. That number is passed in as `restoreWhenQuiet` rather than
found here, and this file deliberately holds no default for it. The behaviour is a property of
these primitives, which is why the paragraph is in this file, while the value is a property of the
caller pressing the key, which is why it is not.

All of that applies only to an image or a file, since text no longer goes through the
pasteboard. It stays because those still do, and because it is the general shape of the problem.
Half a second an entry is what a paste costs and it reads as sluggish, which is the other half of
why text does not use one.

**Measuring it.** None of this is visible from inside, the write always succeeds and only the
app's response is missing, so raising the log level makes the engine and its callers print one
timeline with millisecond stamps, the press, the queue depth, each write, each Cmd+V, each settle
and the restore. Every trace line here carries the same hundred second clock the clipboard's own
modules use, which is what lets three files read as a single timeline. From the clipboard,
`spoon.ClipboardHistory.manager.setLogLevel("debug")` raises this engine's logger along with its
own two, since the engine is where the write and the keystroke and the restore actually happen
and a timeline missing it would be missing the middle. Every theory about these keys that was
argued rather than measured turned out wrong, so measure. The same switch shows a paste of ours
mistaken for a copy, which would end a walk for no visible reason, since the clipboard's
`noteCapture` logs every capture it is told about.

**Two hazards from probing this live.** A synchronous AppleScript from Hammerspoon to an app that
is launching or activating can deadlock, TextEdit waiting on the main thread we are blocking,
which freezes every hotkey in the config until the AppleEvent times out, and killing the app only
makes the pending event relaunch it into the same deadlock. Drive a paste into an `hs.chooser`
query field instead, a real focused text field inside our own process whose contents can be read
back. And check the screen is unlocked before measuring delivery, since a locked screen leaves
`loginwindow` frontmost and every paste goes there, which looks exactly like a paste that did not
land.

## Registry, the tool dispatch

`lib/registry.lua`, phase seven of the build plan, packet one of four. A registry keyed by name,
backing dispatch by name, Strategy with the strategy chosen at runtime by a string. It is a
factory in the same style as `lib/recency.lua`, `M.new(opts)` handing back an independent
instance whose functions are dot called, never colon called, since there is no metatable and no
self. It names no tool, reads no configuration, and imports nothing from the tree beyond
`hs.logger`, which is what makes it the first part of this config testable in the unit runner
rather than only live, in `test/cases/registry.lua`.

**The descriptor.** One table per tool, handed to `register`. `name` is the tool's own key in
`config/keys.lua`, a string, required. `apiVersion` is the integer the tool was built against,
required. `open` is a function of no arguments, what running this tool's launcher row does,
optional, because a tool may exist only as a scope in a later packet. `commands` is a map of name
to function, extra named actions belonging to this tool rather than tools of their own, optional.
The clipboard is the one tool using this today, owning append copy and paste next, and putting
them here rather than registering them as tools of their own is what makes deactivating the
clipboard take both with it. `surface` and `hosted`, both optional, joined in the second packet
and are the subject of their own sections below.

**Why register refuses rather than raises.** One bad descriptor must not empty the launcher, the
same reasoning behind a query source that raises being dropped for a keystroke rather than
crashing the chooser. Every refusal is one log line at warning naming the tool and the reason,
and `register` answers true when it registered, false when it refused, so a caller can react if
it ever wants to, though the composition root does not. Six refusals exist, a missing or non
string name, a second registration under a name already taken since first registration wins, a
`commands` key colliding with any name already indexed whether a tool name or another tool's
command since the flat index dispatch reads makes such a collision ambiguity rather than a
preference, an `apiVersion` that is missing, not an integer, or unequal to the core's, and a
`surface` that is present and is not a function.

**Why the version check is equality.** The core version is injected at construction, passed in as
`opts.apiVersion` rather than read from `spoon.Olm`, since the registry must not reach for the
spoon that contains it. Equality rather than a range, because `obj.apiVersion` is bumped only on
a breaking change, which makes every difference in either direction a mismatch by definition. The
composition root writes the literal integer on each registration rather than reading
`spoon.Olm.apiVersion` into it, since a registration copying the core's own number can never
mismatch and the check would then be theatre, a defect it could catch only by lying about having
one.

**Why the root registers rather than the plugin.** A plugin here never reaches for `spoon.Olm`
and only ever receives its slice through its own `configure`, a rule the tree already keeps and
this file keeps too, so no plugin calls `register` on its own behalf. The composition root calls
it once for each tool, since the root is the only layer that knows a concrete tool exists at all.
A third party plugin from the search path would call the same door itself, one door, two callers,
and the door does not care which one knocked.

**`all()` and what it is for.** `all()` lists every registered tool name in registration order
with its active flag, and, since this packet, whether it declared a `surface` and whether it
declared `hosted`, all for diagnostics only. Both new fields report presence on the descriptor
rather than a resolved value, so the answer never depends on the moment it was asked, which is
what lets `test/inventory.lua` read it live and hold the shape of every descriptor in the
committed golden rather than only its name and its active flag.

**What inactive means today, and what it does not yet mean.** `activate(names)` takes a list of
tool names and is called once after every registration. A registered tool whose name is in the
list is active, one not in the list is registered and inactive, and a name in the list that
nothing registered produces one warning line naming it and is otherwise ignored, since a typo in
a roster should be visible and harmless rather than fatal. `run(name)` answers false and `get`
answers nil for an inactive tool, every other read behaves as if it were never asked. That is the
whole of what inactive means in this packet. It does not yet unbind a chord, remove a launcher
row, or stop a plugin's own `configure` or `start` from running. Packets three and four are what
finish that promise, and reading more into it before then is the half kept promise this file
warns against.

**Why the launcher looks in two places.** `host/launcher/init.lua`'s `_runItem` asks the registry
first and falls back to the injected `actions.special` table only when the registry did not run
anything. Two sources is not a leak. A registered name is a tool. What stays in
`actions.special`, `lock`, `sleep`, and the System Settings search focus, is a bare command with
no tool behind it, and the design's own rule is to resist making everything a plugin, so one
lookup for each kind of thing is honest. The order only matters because a name cannot be claimed
by both, which registration itself already refuses.

**The two fields the second packet adds.** `surface`, optional, a function of no arguments
returning this tool's navigation adapter, the object answering `isShowing` and whatever
navigation methods its context binds. `hosted`, optional, a plain boolean, true when choosing
this tool's launcher row should host its list in place rather than open its own picker. Nothing
else joined the descriptor with them, not a scope, not a predicate, not a chord, since a field
with no consumer yet is the indirection the design principles this file already follows reject.

**Why `surface` is a function, and the measurement that forced it.** A scan of the composition
root found that `spoon.Emoji:surface()` and `spoon.TextCase:surface()` both hand back a field
their own `configure` built, and both of those `configure` calls run far below the registration
block. Writing `surface = spoon.Emoji:surface()` at registration time would have called the
method before that field existed and captured nothing at all, permanently and silently, so the
tool would simply never receive a navigation key again with no warning anywhere. Wrapping every
`surface` in a closure and resolving it inside `surfaces` rather than at `register` time is what
avoids that, and every registration obeys the discipline uniformly, including the seven tools
whose surface is already a stable module reference and would have survived either spelling,
because a rule that holds for most of a set and silently fails two members of it is worse than a
rule with no exceptions to remember.

**The `surfaces` accessor.** `surfaces(spec)` takes an ordered list and answers an ordered list.
A string entry names a registered tool and resolves to that tool's surface when the tool is
active and has one. Only one of the ways a string can fail to resolve stays quiet on purpose, a
tool that is registered but inactive, since that is what inactive already means everywhere else
in this file. The other three all warn naming the tool and skip. Nothing registered under that
name at all warns. An active tool that declared no `surface` warns too, a case a first pass at
this accessor let fall off the end of the check in silence, which was wrong, naming a tool in a
navigation list with nothing to navigate is a mistake and not the same silence inactive earns. And
a named tool's surface resolving to something missing, or present but with no `isShowing`, warns
the same way, so the exact hazard the closure discipline above guards against is loud the moment
it would otherwise have been invisible. Resolution happens inside this call and never at
registration, which is the same discipline stated a second way.

**What the mixed spec list means.** Any entry in `spec` that is not a string passes straight
through unexamined. A string names something this registry knows about. Anything else is an
object the composition root holds and this registry has never heard of, and passing it through
untouched is the whole of what the registry owes it. The root's own `choosers` list uses this to
carry `spoon.Launcher:surface()`, `menuSearchSurface`, and `overlayDisplaySurface` in their old
positions, none of which has a descriptor here yet.

**Why the order of that list is preserved rather than derived.** The root's `activeChooser` walks
`choosers` and answers with the first surface that says it is showing. Two of these could in
principle be up at once, and nothing in the tree proves otherwise, so the order decides which one
answers if that ever happens. Preserving the exact order the table held before this packet costs
one ordered list handed to `surfaces` and removes the question entirely, so the root never
reorders that list to suit the registry and never sorts it.

**Why the alias directory is named by hand for now.** The `hosted` bit for nine of the ten
entries `hostedInPlace` used to hold now lives on the tool's own descriptor, read through
`registry.get` so an inactive tool answers the same nil it answers every other read. The alias
directory is the exception. It is not a tool with a picker at all, it is a scope, so it carries no
descriptor for this registry to ask, and the root's `actions.rowIntercept` still checks its name
directly with one comment saying so. A later packet in this phase is where scopes join the
registry too, and that is where this name check moves with them.

**Why the twelve open predicates were left alone.** Twelve predicates exist in the composition
root, one per chooser entry, and each restates the same fact a surface already states, whether
that entry's `isShowing` answers true. Folding them into the registry is the obvious next step
and this packet deliberately does not take it. A predicate that silently always answers false
disables a tool's navigation with no gate anywhere that would catch it, and stacking that risk on
top of the ordering hazard `surface` already carries would leave a failure nobody could bisect by
looking at only one of the two. The predicates stay exactly as written, and the root says so
beside them.

**The descriptor gains a row, phase seven's third packet.** `row`, optional, is a table
describing this tool's launcher row, the presentation data the launcher used to hold in thirteen
hand written calls, its category, its glyph, its detail or its chord, and its keywords. A tool
with no `row` gets no row on the launcher, which is what a tool reachable only as a scope wants.
`category` is the one required field once `row` is present at all, the word before the separator
in the subtitle the launcher renders, `Tools`, `System`, `Network`, `Clipboard`, `Displays`, or
`Text` today. Everything else inside `row` is opaque to this module and meaningful only to the
launcher on the other end of `rowFor`.

**Why `keysName` exists, and why only one tool writes it.** `keysName`, optional, names the key in
`config/keys.lua` a row reads its description and chord from, defaulting to the tool's own name.
Only `clipboard` writes it, since its row reads `keys.clipboardHistory` while the tool is
registered under `clipboard`, and every other tool's registered name already is its own key in
that file, which is the whole reason `name` was chosen to be that key back in the first packet.
Writing `keysName` anywhere else would paper over a second tool disagreeing with its own key
rather than fixing the disagreement, so it stays written in exactly the one place that needs it.

**Why `chord` exists for exactly two commands, and must not spread.** `chord`, optional, is either
absent, which is every tool's row and renders a Hyper chord label, or a string naming a different
rendering. `appendCopy` and `pasteNext` are the only two rows that carry it, since both are a
modifier combination rather than a Hyper chord and their subtitle is built from that combination
directly rather than from the shared chord label helper. A third row reaching for `chord` would be
a sign that this field grew into a general purpose escape hatch rather than the one narrow
exception it was written for, and the two rows that have it are named here so that stays checkable.

**A command may carry its own row, the same shape as a tool's.** A `commands` value may be a
table carrying its function under `fn` plus its own optional `row`, rather than a bare function,
which is how `appendCopy` and `pasteNext` keep a launcher row while remaining commands of the
clipboard rather than tools of their own. Both row shapes, a tool's and a command's, are validated
by the one function inside `register`, and a malformed row anywhere in a descriptor refuses the
whole registration, naming the owning tool, since a registration commits atomically or not at
all.

**`rowFor(name)`, the accessor this packet adds.** It answers the row of an active tool or of a
command of an active tool, or nil, resolved through the same flat index `run` already reads, so a
command's row is found under the command's own name and an inactive tool answers nil for itself
and for every command it owns. That last part is what makes an inactive tool's launcher row
actually disappear, the promise the first packet's header comment deferred, paid here, even
though nothing is deactivated by default today so there is nothing yet to see disappear.

**Why the launcher's row order was preserved rather than derived.** The thirteen `add` calls
became thirteen `addTool` calls, each left in the exact position its `add` call held, call for
call, with nothing regrouped. A used row floats on recency ahead of everything else, so this order
only governs the untouched rows a fresh install or a fresh reload actually shows, which is
precisely the list changing it would change. Deriving the order from the registry instead was
rejected for that reason, not for difficulty, since the registration order the root happens to
write is not a promise about what a person should see first.

**What this leaves unfinished.** Adding a tool still costs one `addTool` line in the launcher,
so a row's data left the launcher but the decision of which rows exist and in what order did not,
this is not yet one registration. Removing that last line would move the whole row order into the
composition root, which would take the capture loop and the window loop with it since they build
inside the same function, and that is a decision for a later packet to weigh rather than a thing
to fold in here without being asked.

**Why the registrations moved, and what that bought, phase seven's fourth packet.** A scope's
`rows` and `run` are the very functions this file assigns far below the old registration point,
`scopeMenuRows` and `scopeMenuRun` chief among them, and their own `local` statement sits below
that point too, so naming them in a closure written there would silently resolve to a nil global
rather than the function meant. Every earlier packet in this phase solved the same hazard with a
closure, since `open` and `surface` name something built later but the name itself already
exists above the registration. A scope cannot be solved that way, because the name does not yet
exist at all. The answer is to move the registrations rather than add more closure discipline, so
`registry.register`, `registry.activate`, and `spoon.Olm.registry = registry` all sit immediately
above `queryScopes` now, where every declaration a tool or a scope could need already exists.
`registry.new` stays where it stood, since `spoon.Launcher:configure` needs the instance early to
inject and only stores the reference, ordinary composition root sequencing, building the
container where a collaborator needs it and filling it once everything it describes exists. The
move cost nothing at runtime, since nothing reads the registry during load, `rowIntercept` and
`addTool` both hold it as an upvalue and call it later, and it bought two things beyond removing
the hazard, the emoji scope's condition, `spoon.Emoji:lists()`, can be asked right at registration
because that facade has already chosen a backend by then, and menu search stops needing anything
special to be registered at all.

**The descriptor gains a scope, and why the identity fields are not on it.** `scope`, optional, is
a table carrying exactly the fields the composition root's own `scope(name, opts)` helper passes
through, `matcher`, `rows`, `run`, `peek`, `redirect`, and `act`. The identity fields that helper
adds on top, `name`, `title`, `glyph`, and `aliases`, are deliberately absent, since three of them
are read out of `config/keys.lua` and this registry reads no configuration at all, the same rule
that keeps `name` the tool's only identity everywhere else in this file. Validated the way `row`
already is. A `scope` present and not a table is refused, naming the tool. `rows` and `run` are
required once a scope is present, since `QueryScope`'s own admissible function requires both and
would otherwise refuse the assembled scope later with a line naming the scope rather than the
registration that produced it, a worse place to learn about the same mistake. `matcher` is the one
field that is not a function when present, false on four scopes today, so false or a function is
accepted and anything else is refused. `peek`, `redirect`, and `act` each accept only a function
or absence, every refusal naming the tool and the field that was wrong.

**`scopeFor(name)`, the accessor this packet adds.** It answers the scope table of an active tool
or nil, in the same shape `rowFor` already answers, resolved through the same flat index, so an
inactive tool, an unknown name, and a command name all answer nil, a command's answer nil because
nothing in this packet gives a command its own scope, only a tool's own entry carries one.

**Why menu search could not be registered before this packet, and can now.** It has a surface, a
scope, an open predicate, and a chord, everything a registered tool has except a launcher row,
which is exactly what a tool that is reachable only as a scope is meant to look like. What blocked
it was never a missing capability, it was that `openBuiltinMenuSearch`, `menuSearchSurface`,
`scopeMenuRows`, and `scopeMenuRun` were all still unassigned forward declared locals at the old
registration point, hundreds of lines above where they are actually filled in. The move above
puts the registration block below every one of those assignments, so menu search's closures name
the real functions rather than the nil the forward declared locals would have answered. It is the
twelfth registered tool now, with no `row`, since it has none today and giving it one would be a
visible change to the launcher this packet does not make, and no `hosted`, since it is not hosted
today either.

**`settings.toolActivation` grows to twelve, and why missing this step would fail silently.**
Menu search joins the other eleven in the default activation list. A registered tool absent from
that list is inactive, and an inactive tool answers nil to `surfaceFor`, `rowFor`, and `scopeFor`
alike, so menu search would lose its navigation keys and its scope in the same stroke with nothing
raising, logging, or failing a gate, since every one of those reads already treats an inactive
tool's silence as the correct answer everywhere else.

**Why the scope order is preserved rather than derived.** `queryScopes` now builds from an ordered
spec, the same shape `registry.surfaces` already takes, a string naming a registered tool and
anything else an object the registry never heard of. The order is kept entry for entry against the
table this spec replaces, because `QueryScope` gives a colliding alias to whichever scope claims
it first, so this order decides who owns a word, and deriving it from registration order instead
would make that decision depend on where in the root a tool happened to be registered rather than
on a choice anyone made on purpose. The four that stay as plain objects in the spec are the three
`launcherCatalogScope` scopes, `apps`, `windowActions`, and `settingsPanes`, which narrow the
launcher's own catalog rather than reaching a tool, and the alias directory, a scope about scopes
with no tool behind it, so none of the four has anywhere to register.

**`scopes(spec)`, the same door a second time.** A first pass at the fold read the spec through
`scopeFor` directly in the root's own loop, which worked but could not tell an unregistered name
apart from a registered tool that is simply inactive or, for emoji, active but carrying no scope
this run, so all three answered the same nil and all three stayed equally silent. That is wrong for
the first of the three, since naming something this registry has never heard of is exactly the
mistake `surfaces(spec)` already warns about by name, and a reader who learns that this registry
warns on that mistake in one place and not in the other learns nothing reliable from either.
`scopes(spec)` resolves inside the registry instead, mirroring `surfaces(spec)` exactly, warning by
name for an unregistered entry and staying silent for the two legitimate cases, inactive and active
with no scope declared. A resolved tool answers `{ name = entry, opts = descriptor.scope }` rather
than a finished scope, since joining the identity fields from `config/keys.lua` is the root's own
`scope(name, opts)` helper's job and stays there, this module still reading no configuration at
all. The root's own loop is left with exactly one job, mapping a `{ name, opts }` entry through
that helper and passing anything else straight through.

**The inventory measures what QueryScope actually assembled, not only what a tool declares.**
`all()`'s `scope` field, and the cross check below it, both report presence on a descriptor,
whether a tool says it carries a scope. That is not the same fact as whether the scope actually
made it into the live list `QueryScope` runs against, since a spec entry naming something the
registry has never heard of resolves to nothing and is skipped, which a descriptor's own `scope`
field cannot see happen. `test/inventory.lua` reads `spoon.QueryScope:catalog()` live for exactly
this reason, one line per scope actually entered, its name and its aliases, so a broken spec entry
shows up as a missing or a moved alias in a committed file rather than as a snapshot that keeps
swearing everything is fine.

**The cross check, and why it is a snapshot rather than a warning.** Folding scopes into the
registry means a tool marked `hosted` with no scope behind it becomes visible for the first time,
where before this packet those two facts lived in different tables with nothing comparing them and
the only symptom was a row that opened a picker instead of hosting, which reads as ordinary
behaviour rather than a defect. A warning at assembly time is the obvious answer and it is wrong,
because the emoji scope registers only when its backend owns a list, so with the Character Viewer
fronted, emoji is legitimately hosted with no scope, and a warning would cry wolf on the one case
this design deliberately built. So `all()` records `scope` presence beside `surface` and `hosted`
instead, which puts it in `test/inventory.golden` through `test/inventory.lua`. A tool that is
hosted with no scope then reads as `hosted=true scope=false` in a committed file, so the
legitimate case is visible and stable and any real drift is a diff against the golden rather than
a log line nobody reads. This was considered and the warning rejected, written down here so nobody
adds one later thinking it was merely overlooked.
