# AGENTS.md

This file records the decisions and measured findings behind olm's core libs, the shared
mechanisms under `lib/` that a plugin receives through its own `configure` and never reaches
for itself. One section per lib, holding what a future reader would otherwise have to
rediscover by measuring. The authoring rules live in `docs/PLUGIN-AUTHORING.md`, the field
reference in `docs/PLUGIN-CONTRACT.md`, and the workflow for building or changing a plugin in
the repository's `olm-plugin` skill.

## Names, one word per part of the chooser

These are the words for the parts a person sees, settled on 2026-10-29 by Milos. Use them in
conversation, in docs, in comments and in commit messages, and never a synonym. Code that predates
them keeps its identifiers, and the old word each one replaced is listed so a reader can find it.

- **chooser** is the whole window, one shape of glass holding everything below. Never the window,
  the panel or the picker when the whole thing is meant.
- **field** is where a person types, at the top of the chooser.
- **list** is the rows under the field. A row under the cursor is the highlighted row.
- **pane** is the right side, beside the list, when a list shows one. It was the docked pane and
  the companion, and `companion` is still its rect in the geometry.
- **bar** is the bottom of the chooser, floating over the list and the pane. It was the action bar
  and the footer, and `footer` is still its model and its rect. The bar holds two groups, the
  **keys group** on the left and the **actions group** on the right.
- **key panel** is what the keys group opens, every key the list answers. **action panel** is what
  the actions group opens, the list's verbs.
- **outer padding** and **inner padding** are the two spacing values, `spacing.outer` and
  `spacing.inner` in `config/settings.lua`, see Corners in `docs/DESIGN-UI-KIT.md`.

## Goldens, refreshed in the commit that moves them

The goldens under `test/` record every bound chord, the launcher's catalog and each cheat sheet,
and `test/goldens.sh` compares all of them offline in a couple of seconds. They drift the moment
a commit changes a manifest's keys, a launcher row or a description without running it, and
`keys.golden` stayed stale across three commits in October 2026 that way, each one leaving the
next a diff it had not caused. So the dry gate runs them last and fails on any that is stale.

A change that moves what a golden records refreshes it in the same commit, with
`test/goldens.sh --update`, and every changed line is read in `git diff` before it is committed,
since a golden written unread proves nothing. Never refresh with the live `keys.sh --update` or
`views.sh --update`. The first adds the raw hotkey lines only the live probe sees, and both read
whatever config was last loaded, which before a reload is the old one.

`keys.golden` is checked twice, against the keymap projection and against what the binder bound,
and the two must agree line for line. When they disagree no golden can satisfy both, so the
update refuses to write. That is the read model in `lib/keymap.lua` and the binder drifting
apart, and it is fixed there, never by patching the golden by hand.
`decisions/olm-keymap.md` has the case that taught it.

## Paste, the insertion primitives

`lib/paste.lua` is the shared insertion engine, carved out of the insertion half of
`ClipboardHistory.spoon/manager/monitor.lua` in phase three of the build plan. Everything below
was measured rather than reasoned about, most of it while chasing a fault that turned out to be
somewhere other than where it looked, so it travels with the code it describes. The clipboard
features these primitives enabled, the append accumulator and the sequential paste walk, are not
described here. Their trail stays in the module level `AGENTS.md` beside the rest of the
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

`lib/registry.lua` is the keyed store behind every launcher row, alias, chord, and open
predicate, one descriptor per tool, Strategy with the strategy chosen at runtime by a string.
The store itself reads no configuration and names no tool. A descriptor is built from each
plugin's manifest by `lib/registrar.lua` and registered exactly once, from inside
`lib/wire.lua` at the register stage of the pipeline, after every plugin's wiring has run, so
the module a descriptor is checked against is the real finished one. No hand written
registration call exists anywhere, and adding a tool costs a manifest, never an edit to a
composition root. `docs/PLUGIN-CONTRACT.md` is the field by field truth for what a descriptor
may carry.

Three decisions from the original build still govern the lib and are worth keeping here.

**Refusing rather than raising.** One bad descriptor must not empty the launcher, so every
malformed field is refused with one console line naming the tool and the reason, and the whole
registration is dropped. The plugin loses its row, its key, and its list rather than getting a
silently wrong one, and the rest of the config keeps working.

**The equality version check.** `apiVersion` is compared for equality, not for at least,
because the contract has changed meaning without changing shape before. A tool built against a
different contract is refused loudly rather than run on luck. The registrar stamps the core's
own value onto every descriptor it builds, so this check cannot fail for a manifest built
plugin and guards a descriptor assembled anywhere else. The check that does stop a manifest
plugin runs earlier, in `lib/plugins.lua` as the manifests are read, against the `apiVersion`
each manifest declares, and both compare against the spoon's own `obj.apiVersion`, the one copy
of the number. `decisions/olm-manifest-header.md` at the repository root has why.

**Identity stays off the descriptor.** The keys, the leader each role lands on, whether a plugin
is switched off, and the alias words live above this spoon in the config tree, `config/keymap.lua`
for every key and alias and `config/plugins.lua` for a plugin's data and its switch under
`.hammerspoon`, or in the saved set the Olm Plugins page writes, never on the descriptor, so a tool knows what it does and the person's config knows how it is reached.
That split is why a rebind, a rename, or switching a plugin off never touches a plugin. Switching
off is one switch, `lib/pluginswitch.lua`, and the registry activates every tool that registered.

An earlier version of this section was the phase by phase build log of the registry before the
manifest pipeline existed, hand written registration calls, a hand kept predicate list, and a
launcher whose row order was a list of add calls. That architecture is gone, replaced by the
registrar and the wiring pipeline, and the log remains readable in this file's git history.

## Leader, one adapter per leader in use

`lib/leader.lua` is the one leader adapter since phase 3 of the keymap plan, replacing
`lib/hyperkey.lua` and `lib/windowleader.lua`, which were near copies differing in policy. The
root builds one instance per entry of one leaders table, `SHIPPED_LEADERS` in `root/compose.lua`
with the person's `leaders` section of `config/keymap.lua` laid over it, keeps those some bound row
of the keymap uses, HYPER and META on
this machine, plus one plain leader for a keymap row with no leader, and loops over them naming
none. Which held leaders are in use is `lib/keymap.lua`'s `leadersInUse`, every leader a bound
global row or a list key sits on, and the remap, the engines the binder reaches, the sheets and
the leaders hosting list keys all read that one answer, so a chord on `super` claims Right Command and
moving every window default off META frees Right Option. An entry stating `mods` is
the modifier trigger handed that set as its base, with the policy its entry states and no tap, and
an entry stating `key` is the held trigger. The reader in `lib/keymap.lua` tells the two apart by the
field, refuses both or neither, lays a person's entry over the shipped one of the same name in two
halves, the trigger fields replacing together and the behaviour fields merging one by one, and
reserves no name. A bare list is read as `mods` with a routine note. A shipped name may change
kind, so `hyper = { mods = { "shift", "ctrl", "alt", "cmd" } }` makes Hyper a modifier leader, the
Karabiner form. It then leaves the held allocation, so Caps Lock is not remapped, and keeps its
shipped `ranked`, `sheet` and `sheetLayout`. A role and the list role may land on any leader, held
or modifier. Every leader's identity is its name upper cased inside the root, `HYPER`, whichever
kind it is, which is what the roles, the remap record and the sheet heading spell, while a chord
spells it lowercase. One scheme for both kinds is what keeps a role naming the same leader when
Hyper changes kind. The physical key stays in the entry, and `lib/keyremap.lua` says which
function key the engine listens on for each held leader, `KeyRemap.allocate`. That file keeps the
allow list of keys a held leader may name, `USAGE`, which is Caps Lock, Right Command, Right Option,
Right Control and F13 to F20, so admitting another key is one row there and the reader in
`lib/keymap.lua` holds no list of its own. The reader is handed the allow list and `allocate` as
options, since only the root names the remap, and it drops the person's trigger of every entry the
allocation cannot place, the shipped one coming back or a new name being ignored, and asks again
until nothing is left to drop. F13 to F20 are used directly, the other keys are remapped to the
entry's `remapTo`, else their preferred key, else the first free one, and a leader's function key
is a fact of the whole table and never of the leaders in use on a load. The root gets the final
allocation from the reader, remaps only the leaders that have a target, and hands the held trigger
the physical key. A quick tap toggles Caps Lock only when that key is `capsLock`, decided in
`lib/leader/triggers/held.lua`, the one place the adapter names Caps Lock, and `tapTogglesCapsLock`
is retired with a problem line. What
physically means a leader is a trigger, a Strategy behind four functions, start, bound, isActive
and owns. `lib/leader/triggers/held.lua` registers one function key into the shared ChordKey
engine, and `lib/leader/triggers/modifier.lua` claims each binding as an `hs.hotkey` on a base
set of real modifiers plus the binding's own. The plain leader is the modifier trigger with an
empty base set, so a plain combo such as Option and backtick is claimed exactly as the binder
used to claim it, with three arguments and no repeat callback unless the binding repeats. The root
is the only place a trigger is named, so a third kind is a file plus a line there.

A leader may listen on a held key and a set of modifiers at once, which is how HYPER and META ship
since phase 1 of `docs/PLAN-MACHINES.md`. HYPER is Caps Lock and shift, ctrl, alt and cmd, META is
Right Option and shift, ctrl and alt, so a machine without kanata reaches them through F18 and F16
and a machine with kanata through the modifiers it sends, and Olm is told neither. The entry writes
`triggers = { { key = ... }, { mods = ... } }`, and the reader holds it as an entry with both `key`
and `mods`, listed and allocated among the held leaders, so its roles, list keys, remap and sheet by
keycode are a held leader's. A person's entry writing `key` or `mods` alone replaces both halves
with that one, and one writing `triggers` replaces both with its list. A list holds at most one key
and one set of mods, with any `remapTo` inside the key trigger, and anything else is a problem line
naming the entry, the shipped default kept. The root builds such a leader on
`lib/leader/triggers/composite.lua`, handed a held trigger and a modifier trigger it built itself,
and the composite answers the contract per method. `start` starts both, a half that fails says one
line and the other keeps working, and the leader fails only when both do. `bound` hands every
binding to both. The modifier half is built with `skipOverlap`, so a binding asking for a modifier
its set already holds, Hyper and Shift and 4 for one, is neither claimed nor warned about, since the
held half still reaches it, and the composite says the count once at start as a routine line.
`isActive` and `owns` are either half, which is the half pressed, since phase 0 measured that one
press never arrives as both. Sealing over an open list is per press, so every trigger hands itself
to `_onKey` as `via` and the adapter reads `sealsOverLists` off the trigger that heard the key. An
F18 press seals as a held leader always has, and a press of the modifiers seals only when its
leader hosts a list key, as a modifier leader does. The composite states no sealing of its own. One
sheet serves both halves, filed under the keycode, and two guards keep one press to one sheet. The
adapter's reveal does nothing while its sheet is already up, and the modifier trigger takes down
only a sheet it put up itself, so a modifier pressed under F18, or F18's own autorepeat, never
hides the held half's sheet. Over the default chooser a composite is a held leader in use, so the
field yields a key its modifier half owns and the claimed hotkey resolves it, a list key acting and
a global key the bound no op. A combination its modifier half never claimed passes on to the app,
where a modifier leader sealing over the same list would have swallowed it. The cost is that every
machine, kanata or not, claims machine wide the four and three modifier combinations its HYPER and
META rows add up to. `test/leaders.lua` pins the composite, `test/keymap-person.lua` the reader,
and `test/keymap-fixture-composite.lua` with its golden shows both forms bound through the real root.

How a leader behaves is its policy, the behaviour fields written beside `mods` or `key` in its
entry, `SHIPPED_LEADERS` in `root/compose.lua` and the person's section over it, checked by
`lib/leader.lua`'s `checkPolicy`. `policy.leaderCatalog` and `policy.leaderPolicy` are retired and a
config still setting either gets a problem line pointing at the leaders section. Every field is a boolean,
a number or a table, so there is no closed set of words to publish. `sheet` says a hold reveals
the leader's cheat sheet, drawn by the one `host/leadersheet`, and `sheetLayout` is the table beside it
that lays it out, `title`, `columns`, `colWidth`, `iconSize`, `gap`, `groupGap` and `badgeWidth`,
with `lib/leader.lua`'s `sheetLayout` filling a leader that states none with the renderer's own
two columns. No shipped layout states a title. The heading over a sheet's rows that name no group
follows the role the leader holds, `policy.roleTitles` keyed by role and read by `lib/leader.lua`'s
`sheetHeading`, so whichever leader holds the window role reads WINDOW MANAGEMENT, HYPER holding
the app role reads ACTIONS, and a leader holding no role reads as its own name, SUPER or META.
A title a person states in one leader's layout still wins there. A person's `roleTitles` is merged
by role through `leader.roleTitles` rather than the defaults merge, which would read an empty table
as a list replacing the shipped titles. Behaviour is the leader's whichever kind it is. `ranked`
is the resolver's and applies to a modifier leader unchanged. `drivenRepeat` on a modifier leader
hands a repeating handler its depth, 0 on the press and one more per autorepeat of the hotkey,
reset on each press. A `sheet` on a modifier leader is opt in and is revealed by the modifier trigger, which
runs one observing `hs.eventtap` over flags changes and key downs, always answering false. Once exactly the
base set of shift, ctrl, alt and cmd has been held for the hold delay, with fn and caps lock not counted and no key
pressed, it asks the adapter to show the sheet, and any key or change of the set takes it down. A short poll of
the live modifiers runs while the sheet is up, since a tap can miss events under secure input. A leader with no
sheet, or an empty base set, runs no tap. The sheet host finds that sheet by the leader's name, since it has no
keycode. `ranked` is HYPER's,
`drivenRepeat` is META's, and SUPER ships META's policy because it is the documented other home
of the window role. `ranked` is the global tier rule below. What a leader does over an open list
and which leader a list key sits on are not policy since phase A of the list keys addendum in
`docs/PLAN-KEYMAP.md`, so `contexts`, `quietOverLists` and `sealedOverLists` are refused by name
with what replaced each. `checkPolicy` names a field of the wrong type or one no
leader reads in one problem line and leaves it at its default, a layout field out of range or a
layout with no sheet included. A leader that states a sheet gets one with no edit to any host, and
`test/leadersheet.lua` pins the host and the validation.

Four findings from the merge are worth keeping.

**The two tier rules stayed different, on purpose.** On a `ranked` leader, HYPER, the best
priority wins within a tier and a gated binding drops out of its tier, so Shift and J gated off
leaves the plain J to answer. On every other leader the first matching exact global binding
answers and a gated one is swallowed there, and among catch alls the last bound wins. Both are
pinned by `test/leaders.lua`, and unifying them would have changed which binding answers a press
on one of the two leaders for no gain, since the keymap refuses two global rows on one chord.
List bindings are a layer of their own and ranked on every leader, since every list shares its
move keys and a first match would let a closed list's gated binding swallow the open list's. The
field was `contexts` until phase A of the list keys addendum, which also chose the leader list
keys bound on, and it was renamed for the one thing it still decides.

**Exactly two behaviours changed.** A key whose matching bindings are all gated off is swallowed
as a bound no op on every leader, where Hyper left it unbound and with passthrough on leaked it
to the app in front as F18 and the key. And an unknown predicate name warns once per leader. On
this machine the keys that flip outside a list are Hyper and H, Q and Y, file search's own list
keys. Inside an open list one rule covers every held leader since phase A of the list keys
addendum. The leader answers only its bindings for the open list and swallows every other key, so
with the launcher open Hyper and A, B, C or E are all swallowed while the launcher's keys act, and
META, which binds no list key here, is inert, the chooser field yielding every key under a held
leader in use so none is typed. The rule seals a leader whose trigger answers `sealsOverLists`,
which the held trigger always does. The modifier trigger does when its leader hosts a list key, a
fact the root knows only once `applyLists` has run and hands over at build. Over the legacy
chooser a hotkey that fires then resolves to the bound no op. Over the default chooser the field's
tap sees a chord before any hotkey and a claimed chord never reaches one, so the root's `listKeys`
claims, as a no op, a key down the field watcher did not take whose own flags hold the whole set of
a sealing modifier leader in use, through the leader's `owns`, which the modifier trigger answers
from the event's flags when handed an event. So Hyper as four modifiers and a digit, an arrow or
Return picks and moves nothing. The plain leader and a modifier leader hosting no list key fire
over a list as anywhere. Outside lists an unbound key still passes through.
It replaced HYPER's `sealedOverLists` and META's and SUPER's `quietOverLists`.

**No hold reveals a sheet over an open list, on any leader.** Hyper's reveal lived in the root
and checked for an open list itself, and the window leader's went quiet through its gate, so
both already held back there. The adapter keeps that one rule for every leader.

**A plain combo resolves against the combination it was claimed on.** The modifier shape inside
the old hyperkey read the hardware modifiers when the callback ran, so a finger lifted a moment
early could turn a press into nothing. `hs.hotkey` fires only on exactly the claimed
combination, so the claimed set is the truth and the trigger resolves against it.

A descriptor saying `afterRelease = true` runs only once the leader that fired it is released,
through the leader's own `afterRelease`, and a launcher row for it waits until no held leader is
down. Capture's actions say it, which retired capture's own wait on Hyper and its `hyperKey`
lib. The clipboard still asks a lib, because whether its open waits is the chosen provider's
answer at the moment of the press, and the lib it asks for, `leader`, is a view answering only
whether any held leader is down. The composed record publishes the leaders in use as
`_composed.leaders`, keyed by the name a keymap row spells each with, for the key probe and the
inventory, and the dry gate's bound recording taps the adapter's own `bind`, which every
instance reaches through its metatable, and its `start`, so a combo a named leader claims through
`hs.hotkey` is recorded once under that leader's name.

## The person's keymap

`config/keymap.lua` reaches the root as `cfg.keymap`, and no plugin ever reads it. `lib/keymap.lua`
reads it in `readConfig`, every entry it cannot read a problem line naming the entry, and lays the
keys over the defaults inside `build`. The rules are three. An action named in `keys` takes
exactly its listed chords and loses every row it had, copying its gate, label, repeat and function
from the first row it had, so a moved action behaves as it did. A row the person set wins a slot a
default holds, and the default is dropped with one routine `Olm keymap` console line, never bound
beside it and never a problem, which replaced the one exemption the collision check kept. And
`false` frees a global chord, dropping whatever holds it. Since phase 7 `config/plugins.lua` holds
no key, its `key`, `mods`, `leader`, `bindings`, `surface` and `aliases` each refused by
`keymap.refusePluginKeys` with a problem line naming `config/keymap.lua`, so a keymap entry is the
only row of the person's. Since phase
6 an app toggle is an action like any other, one per app, whose behaviour a style in
`config/toggles.lua` may change without minting a second id. `fn` is refused on a held leader, which compares only the other four
modifiers, the keypad plus is `pad+` and the main row plus `shift+=`. A key `lib/keycodes.lua` calls
standalone, the Globe key, may be named alone by both readers, a plugin's row and the person's chord,
`readConfig` taking `standalone` from the root, and a global row with no leader that states no
modifiers means none, since `hs.hotkey` binds one exact combination and the binder binds it so. A named leader no chord uses
is a routine note. A keymap that fails to build keeps the roles' leaders and every leader a list
key names in use, `keymap.fallbackLeaders`. Two of the
person's own on one slot are a collision named by entry. An entry naming a plugin that exists and
is switched off this load is a note rather than a problem, since switching a plugin off takes its
keys with it. The slot of a row on a named modifier leader is the whole combination with no
leader, so `nav+T` and `ctrl+shift+T` are one slot. A modifier Hyper has no sub modifiers to give,
so a row asking for Shift or Command beside it, Hyper and Shift and 4 for one, cannot be told from
the plain row, the modifier trigger says so once and the collision check names the pair. A held
leader that also listens on modifiers is checked a second way, since its modifier half claims each
global row again as its set united with the row's own modifiers. Two such rows on different leaders
that come to one physical combination, a META row adding cmd and a Hyper row on the same key, or one
and a plain combo or a modifier leader's row on that combination, are one problem line naming both,
`keymap.collisions` with the root's `compositeLeaders`. A row its modifier half leaves to the held
key claims nothing there. The shipped manifests made no such pair when it landed. `roles`
is merged over app on HYPER and window on META by hand, since `lib/defaults.lua`'s merge reads an empty table as a list that replaces. The
`aliases` section is merged over the person's overrides before the plan resolves, so the
resolver, the registrar's collision check and every row hint read one answer. `cfg.leaders` is
retired and named.

The `lists` section holds the keys live while a list is open, read by `readConfig` into one entry
list per list name and `all`, and laid over the built lists by `keymap.applyLists` in the root,
right after the plan resolves and before the action bar, the action panel, the keymap and the
contexts read them, so all of them read one answer. It first places every default binding, one
naming no leader, on the leader the `list` role lands on, `keymap.LIST_ROLE`, HYPER unless the
`roles` section moves it, so every reader after it spells and binds a binding's own leader and
`w.contexts` binds each on the held leader it names, a list key on a modifier leader being a field key. The shared verbs carry `shared` on their
binding, `primary`, `secondary`, `selectNext`, `selectPrev`, `close`, `openActionPanel` and
`showKeys`, and `lib/surface.lua`
builds them on the keys of Olm's own `all` layer, `keymap.listDefaults`, handed in through the
resolver's `listKeys`, so that file holds no key and the dry gate refuses one written there. A
manifest's own key, an `extra` row's or a `close.key`, is that list's default, and `all` moves and
frees only a binding marked `layerKey`, one whose key came from Olm's own layer, so such a key
moves only when the person names that list. `all` is laid first and each list's own table over
it, a list's own table deciding every binding its entries resolve to, by action or shared verb,
and every slot it names. An entry naming an action a need this machine lacks left out, the block's
`unmet`, is a routine note. Inside one list the keys section's rules hold, an action named takes exactly its chords, a chord
on a default's slot drops that default with a routine line, and `false` frees a slot. Two entries
of one table on one slot are refused together. A list chord opens with any held leader, its slot
is its leader, modifiers and key. One opening with no held leader, modifiers alone or a leader
the person named, is a field key, binding leader `false` or the named leader, its slot the whole
combination with no leader. `w.contexts` binds it on no engine, `nav.fieldKeys` builds the watcher
the default chooser's field asks after the leader yield, and the composed record lists them as
`fieldKeys`, which a fixture golden writes as `field` lines. `applyLists` refuses one that would
type a character, no modifier or Shift alone on a printable key, and one the default provider's
`uses` says the field or the chooser already reads, and one naming `fn`, which the watcher does not
compare. Option on a printable key is accepted with a routine note, since the chord then acts in
that list in place of typing its character. The watcher swallows the autorepeat of an action that
does not repeat, claims a key whose binding raised, and warns once for a list no predicate answers.
Any list chord may shadow a global chord, since the keymap checks collisions
per layer, and a binding listed
with `chord = false` is no person setting. A moved binding names its entry, and its keymap row is
the person's. `test/keymap-person.lua` pins the layer, and `test/keymap-fixture-lists.lua`,
`test/keymap-fixture-listrole.lua` and `test/keymap-fixture-listleaders.lua` with their goldens
prove it through the real root.
`test/keymap-person.lua` pins every rule in plain Lua, and `test/keymap-fixture.lua` and
`test/keymap-fixture-roles.lua` with their goldens prove the person's case through the real root.

## Labels, open lists and the row intercept, the mechanism that left the root

Three small libs were closures inside `root/compose.lua` until 2026-10-21, and moved out because
each is mechanism rather than wiring, as the keymap plan's last section named. Each is pure, takes
no hs, and knows only the collaborators its caller hands it, so the root keeps the concrete calls
and the libs keep the rules. `test/rootmechanism.lua` pins all three over fakes.

`lib/labels.lua` is the one spelling of a chord, a leader's name, a space and the key glyph, and of
a set of aliases, the words in brackets. `chordLabel(glyphFor)` answers the speller every surface is
handed, and the glyph helper is the shared cheat sheet renderer's, handed in rather than loaded
because the spoon publishes that renderer once. The launcher and the action bar both spell a chord
through it, and a launcher row and the alias directory both spell aliases through it, which is
what ended one key reading two ways.

`lib/listopen.lua` answers whether a list is open, `isShowing(contextName, deps)` for one and
`anyShowing(deps)` for any, walking the context owners the predicates route through. An owner that
presents on the shared stage is asked of the stage first, and any other through the surface its
manifest names, both calling conventions tried. The registry it asks for a presentation is built
after the leaders that close over the answer, so `presentationFor` is a function asked at each
call rather than a table taken at build.

`lib/rowintercept.lua` answers what choosing a launcher row does in place of closing the launcher,
a contributed row left to its owner, the Aliases row seeding its word, a tool on the stage pushed,
and a scope row acting or seeding its word. Its contract is six functions, and the scope pair is
absent when no scope host loaded. The query the Aliases row stands for stays in the root, since the
row's name is root policy, and so does `aliasHint`, which asks the scope host for a tool's aliases.

`lib/keypage.lua` is the OLM keys page, every chord Olm binds listed read only. It is Olm's own list
and no plugin's, reached by the launcher's own OLM keys row, declared beside the Aliases row in the
launcher's `specialRows`. The root answers that row in `rowIntercept` where a registered tool's
presentation is answered, pushing the page onto the stage over the open launcher, so the list
becomes the keys list in place and Back or Backspace on an empty field pops back. The page carries
the launcher's name, the stage's rule for a level pushed over a list, so its icons are the
launcher's. Its rows are `lib/hints.lua`'s `keyEntries`, words only, built on the first open and
kept for the load, a row listed exactly when `lib/binder.lua`'s `bindable` says it is bound. A key
row answers stay and does nothing. `test/keypage.lua` pins it.

## The action bar, one footer row inside the default chooser

Every list on the stage carries one footer row at the bottom of the default chooser's own canvas,
always visible, `docs/PLAN-ACTION-BAR.md`. It replaced the docked shortcut hint pane on 2026-10-23,
a separate `CanvasPanel` under the list that appeared after an 800 ms pause, and nothing of that
pane is left, no `shortcutsPanel` policy, no per plugin panel triple and no `shortcutPanelFor`.
`decisions/olm-chooser-keys.md` has the decision and what was turned down.

The model and the paint stay apart. `lib/hints.lua`'s `footerModel(contextName, plan, deps)` is
pure data, `right` the bar's right side, the primary's label on the Return glyph, the secondary's
on its chord when the list declares one and its gate is open, and Actions on the action panel's
chord, `keys` every other key the list answers in declaration order followed by the keys the field
reads for itself, Back only where Backspace leaves a pushed level and the list lists no Backspace
binding of its own, and Command with a digit, and `state` one comparable string. While the action
panel is open over the list the model describes the panel, Return labelled with the highlighted
panel row's title or Run, no secondary, and only the shared keys and Back in the key panel. It reads the
bindings, the live gates and the label lookup `rowsFor` reads, so the bar, its key panel and the
action panel cannot disagree. A label is the level's own `labels` first, then `liveLabels`, then
the binding's description, then Open for the primary and the action spelled as words otherwise.

The default provider is the chooser engine, `lib/chooser/engine/init.lua`, composed with the
canvas view, `lib/chooser/providers/default/canvas.lua`, joined at `lib/chooser/view.lua`, and
`docs/CONTRACT-PICKER.md` says which half owns what. The engine takes the model through one per
instance collaborator, `config.footer`, and `footer.lua` beside the view draws it through the kit, the caption role for its hint labels, as Milos
chose, and the hint badge with its glyph in the section role, both 14 points, the divider
along the bar's top edge and the background colour role behind the key panel. The bar's height is
the hint badge with the small space step above and below it, and geometry gives it a footer rect
under the list, subtracted from the rows a screen can hold. The engine asks the model on every
show, after every highlight move and on a quarter second poll, the timer's handle kept, and owns
the key panel's open state, and the canvas view owns the key button's hit test and the panel's rect. The key button is the
outline keyboard icon, Olm's own `keys` in the action panel's manifest drawn through the injected
icon engine at the kit's `hint` icon size, the section line height, with the ? glyph only where no
engine is injected. It stands alone at rest and sits on one highlight across the icon and its chord
badge while the pointer is over it or its panel is open, the state a row takes under the pointer, and the view's `_onMouseMove` redraws only as the
pointer crosses its edge. A press on the bar never hides
the list, a press on (?) toggles the panel, and the panel's rect is on no row and takes no scroll.
Every list key that acts closes it, through the dispatch table's `onAction`, which the root points at
the stage's `closeKeys` for every action but `showKeys`, and so does every field key, a new query
and a refresh from the top. Escape over an open panel closes the panel and leaves the list, and the
autorepeat of that held Escape is swallowed so it never closes the list too. With no footer handed in
the provider draws no bar and keeps every row, so it stays usable alone, and the legacy chooser
draws none.

The root builds one footer for the stage over `stageModule:current()`, the way the stage panel
did, and hands it through the stage's manifest need `footer`. The stage passes it to its instance,
remembers the item last highlighted outside the action panel, and answers `labels()`, the current
presentation's `labels` member asked with that item, and `toggleKeys()`, which the shared
`showKeys` verb's dispatch exception calls. A presentation's `labels` is a registrar member like
`searchText`, and a child presentation hands its own function.

Two shared verbs came with it, both in `keymap.listDefaults`. `secondary` is a field key on
Command and Return and Command and keypad Enter with leader false, the list listDefaults shape,
built right after the primary only for a surface declaring `secondary`, so both keep choosing the row
in every other list. Every field key is inert while the action panel is open, since the root hands
the field's watcher each list's predicate wrapped to answer false then, so Command and Return there
chooses the panel row. A shared binding's kind is weak in `actionKinds`, filling only an action no
other binding classified, so a secondary named like another list's verb never hides that verb.
`showKeys` is Command and ?, slash with Command and Shift, and Command and slash beside it, two
field keys on no leader like the secondary's, in every list, listed once and spelled ⌘? because the
shared glyph speller folds Shift and slash into a question mark. The bar draws that chord as a badge
beside the (?) glyph, `footerModel`'s `keysChord`, which follows a person's move and is absent when
both keys are freed, and the glyph and the badge light and hit as one button. It is not a Hyper key since macOS takes Hyper and slash before any event tap, and it
reaches a list only where the Show Help menu shortcut is off, which `src/setup-macos-shortcuts.sh`
sees to. Both move and free in the `lists` section like
every shared verb. The action panel lists Back, the primary, the secondary and then the verbs.
The primary row reads Return and the secondary row Command and Return, the keys a person presses,
and the key panel spells the primary as Return alone. Every row carries an icon. A
surface's `primary` and `secondary` may name one of the manifest's icons like an extra row, and one
naming none takes Olm's own, `primary` and `secondary` in the action panel's manifest beside `back`.

## Secure focus, a list opened over a password field

A password field turns on macOS secure input, which hides every key from every event tap, and the
default chooser reads keys through a tap, so a list opened then would be drawn and deaf. The
default provider takes an optional `focusHold` in its configure, held by the engine, asked once per open after the
surface shows and released on teardown after the surface hides and before `onClose`. The root
passes `lib/securefocus.lua`, the one file that knows the mechanism, a native `hs.chooser` with no
rows moved off screen, which is the only thing measured to take focus from Safari. While such a
list is open secure input is off, so any tap on the machine could read what is typed into it, and
that lasts only while the list is open. Chrome keeps secure input on whichever application is
active, measured 2026-10-27, so the hold is handed a sink by the provider and, while secure input
stays on, relays the chooser's typed text into the field and claims the list's non typing keys
through `hs.hotkey`, feeding each to the field as a key event through the view's `feedKey` and `Field:feed`, and claims
nothing while it is off, the root handing it every list key bound with no leader beside the fixed
set. The hold also answers a mirror the provider tells the field's text, so text the list writes
itself, a scope's word, reaches the chooser and typing carries on from it. `test/securefocus.lua`
pins the lib over fakes. The provider has no plain test harness,
only the live probe, so the call order is checked live. `decisions/olm-chooser-keys.md` has the
measurements.

## The docked pane, one lifecycle over two drawing backends

`lib/dockedpane.lua` owns everything a docked companion pane does, the lazy build, the inner rect,
the dock, the guards, the surface first, the scroll and its clamp, the thumb, the empty state,
show, hide and destroy, and a plugin hands it only a describer or a painter. Whatever is
described or painted is reduced there to two lists of `hs.canvas` element tables, the surface
and the content, in the pane's own coordinates, and those two lists are the whole contract with
the drawing backend, a Strategy the root injects as `deps.backend`. The backend is a factory
called once at the first paint, and what it answers keeps five methods and no rule.
`place(frame)` moves it to the companion rect in screen coordinates, `render(surface, content)`
draws both lists in place of what was there, `show()` and `hide()` bring it up and take it down,
and `destroy()` tears it down on close.

A backend may also answer `scrollsNatively()`, meaning its view scrolls on its own, and then it
keeps `scrollBy(points)` too. For such a backend a scrolling pane's content is laid out once at
its full height, unshifted and cut only at the viewport grown by the overflow, and handed over as
`render(surface, content, scroll)` with `scroll = { height, visible, reset, thumb }`, the whole
height, the pane's own, whether the content changed so the view goes back to the top, and whether
the pane asked for a thumb. `lib/dockedpane.lua` then keeps no offset, clamps nothing, draws no
thumb and runs no scroll timer, and `pane.scrollBy` calls the backend's, so a key that pages the
pane still pages it. A redraw of the same content, a repaint, a redock or a show with
`keepScroll`, keeps the view where it is, and new content resets it, exactly when the canvas path
resets its offset. A painter is called once to learn its overflow and again with
`view.viewport` grown by it, so a painter that cuts at the viewport hands over everything, and a
painter's fixed header, the file search preview's, scrolls with the body under such a backend.

There are two. `lib/dockedpane/canvas.lua` paints both lists on one `hs.canvas` at the floating
level with click activation off, exactly what every pane drew before the backend existed.
`lib/chooser/providers/swift/pane.lua`, over `native/Pane.swift` in the swift chooser's own
library, draws the content on glass and replaces the surface with glass at the surface's corner
radius, since the surface's fill painted over glass would hide it. The glass is drawn in the
chooser panel's own window. With a companion that window and one `NSGlassEffectView` span the
canvas rect, the engine's gap and the companion rect at the surface radius, the list's content on
the canvas rect, the pane's region on the companion rect, and a hairline in the kit's border
colour and border width centred in the gap from the top down to the action bar, so the list and
the pane are one surface that appears and vanishes together, with no window animation. The action
bar runs under the list, the gap and the pane alike, since the swift view answers `spansFooter`
and `geometry.resolve` then widens the footer rect across the span and stops the companion rect
at the bar's top edge, so a pane is laid out at the height it is shown. The default chooser
answers nothing and keeps the bar under the canvas alone. With no companion the
window is the canvas rect alone. A pane knows no chooser, so the one seam is `chooserHosting` in
`native/Entry.swift`, which matches the pane's rect to the companion rect a visible chooser panel
last reported. When none matches, the pane stands in a window of its own, a nonactivating panel
that never becomes key, at the canvas pane's level. A press in the gap lands on glass and is
inside, keeping the list and the keyboard as a press on the pane does, and the Lua view's rule
treats the span from the canvas to the companion as inside while there is a companion, the one
place it differs from the canvas, which hides for a press there. It scrolls natively, the drawn
elements in a flipped document view inside an `NSScrollView` with no scroller unless the pane
asked for a thumb, then the overlay style, and only the elements that reach the area being drawn
are drawn. A scroll over the pane in the chooser's window is left to that scroll view, since
`View:_onScroll` in `providers/swift/view.lua` asks the panel through `hostsPane` and claims
nothing while the panel holds a shown pane. That method is the one place the tap and the hosting
meet. A pane in its own window is claimed by the tap as before and comes back as `scrollBy`. The
scroll view moves between its own window's glass and the chooser's region, and a glass places
its content view by constraints and keeps naming it after it leaves, so `holdPane` in
`native/Surface.swift` gives it its autoresizing mask back and `Surface.release` drops the glass's
claim. Without the first an `NSScrollView`, which carries constraints of its own, was sized to
nothing by the first layout after a redock and the pane drew blank. `test/swiftpane.sh` builds the
library's own sources into a program that shows no window and pins that view tree, and
`suite.sh dry` runs it. `paneDebug` on the library, reached as `paneDebug(id)` on the swift
provider module, answers read only where a pane is hosted, its frames, the document and the clip.
Pictures in the list, the action bar and the pane are drawn on whole pixels at the backing scale
through `Crisp` in `native/List.swift`, never scaled by Core Animation. It
draws `rectangle` and `segments`
filled, stroked or clipped, `image`, `text` as a string or an `hs.styledtext`, and `resetClip`,
with the canvas's semantics and defaults. Any other type, action, scaling or attribute leaves
that element out and is named once in the console. It is torn down with the chooser panels by
the library's reload sentinel, and a pane never calls back into Lua.

The root chooses, in `dockedPaneBackend` beside `wireSwiftChooser`, and no plugin and no line of
`lib/dockedpane.lua` names a backend. A pane gets the native one only while the swift provider is
the chosen one and its library is loaded, which is fixed for the session, and the canvas one
otherwise, so a pane under the default chooser is exactly what it was. `test/panebackends.lua`
drives one pane over both backends with the same describer and painter, and pins that the native
one is handed the very content list the canvas paints over its surface, and for a scrolling pane
that the canvas one scrolls as it always did while the native one gets the full height content
unshifted, scrolls through the library and keeps its place across a redraw of the same content.

## CanvasPanel, the same two backends

`lib/panel.lua` is the second consumer of that contract. It keeps every rule it owns, placement,
sizing, reveal timing, the surface style resolved for the current half, and reduces each show to
the surface and the content shifted by its padding, then places, renders and shows a backend the
root injects through `CanvasPanel.configure({ backend })`. With none injected a panel draws
nothing and says so once. The root's `wirePanelBackend`, beside `dockedPaneBackend`, hands it a
factory that asks `dockedPaneBackend` at each panel's first show, so a panel follows the chooser
that serves exactly as a pane does. A panel calls the factory with a second argument a pane never
passes, its window, `{ level, onClick, activates }`, and `isShowing()` is the one backend method
only a panel asks. On the canvas this makes the very hs.canvas the panel used to make, at its
level, popUpMenu unless it says otherwise, with a mouse callback only for content that answers
`onClick`, and with hs.canvas's own click activation left on. On the native backend it is a
`PaneConfig` window in `native/Pane.swift`, never drawn into a chooser's window, at the panel's
level, ordered front on every show as hs.canvas is, never key, never main, never activating, click
through without `onClick`, and with it a mouse up is hit tested against the elements built with id
and trackMouseUp and the id, or `_canvas_`, goes to a Lua function the library holds for that panel
alone. The surface becomes glass at its corner radius, which follows the system appearance, while
the content's colours come from the kit on each show as before. The users are the cheat sheet
behind every leader sheet and the message, colour and report toasts in `root/compose.lua`, all
centred, and only the report toast takes a click. `test/panelbackends.lua` pins that the canvas
backend draws what the old code drew and that the native one is handed the same lists, and
`test/swiftpane.sh` pins the panel window, its hit test and its drawing at backing scale 2.

## The swift chooser, the engine under a native panel

`swift` is the third picker provider, beside `default` and `legacy`, and it is the chooser engine
composed with a native view rather than a second set of rules. `lib/chooser/providers/swift/init.lua`
composes `lib/chooser/engine/init.lua` with `providers/swift/view.lua`, and the view is a Humble
Object over a Swift library whose sources are `providers/swift/native/`. The library draws a
nonactivating panel that becomes key without activating Hammerspoon, on `NSGlassEffectView` where
the system has it and a visual effect view where it does not, with a native `NSTextField`, an
`NSTableView` list and an action bar of two floating glass groups with its key panel, see the
action bar section of `docs/DESIGN-UI-KIT.md`. The Lua view turns the engine's scene
into plain data, colours, fonts, sizes, the radius and the space steps from the kit's tokens and
every rectangle and row metric from the engine's geometry, so neither half writes a colour or a font
by hand, and the panel sits exactly on the canvas rect with the docked pane beside it, which is
drawn on the panel's own glass beside the list, see the docked pane section above, and every
CanvasPanel is drawn on glass by the same library while it serves, see the CanvasPanel section. The native list owns its scroll and its highlight. The arrows,
the pointer and a trackpad move them in AppKit, and Lua hears both afterwards, coalesced, and sends
either back only when the engine moved it, a new list or a list key. Every key or press Lua acts on
first flushes what it has not heard, so Return chooses the row on screen. Icons follow the scroll too. The list
asks Lua for the icons of the rows on screen and of the rows its velocity is carrying it into, a
dozen at most per ask, during a scroll as well, and an idle prefetch fills the rest. A cursor update
ends at the list, since setting the cursor on every frame of a scroll went through the
accessibility cursor generator and was a third of the main thread. `perf` on the provider module
starts and reads a probe of main thread stalls and slow Lua calls, `Perf` in `native/Entry.swift`. Swift runs
the view contract's key order, asking Lua synchronously before its field edits, and hands each key
over as its event's bytes, which `hs.eventtap.event.newEventFromData` turns back into the event the
engine reads. A press outside the panel is heard by event monitors and decided in Lua against the
canvas view's own rects, a press in the companion keeping the list and asking the panel for key
again, and losing key never hides it. A scroll over the companion is claimed by a scroll wheel tap
the Lua view runs while it is up, as the canvas view's mouse tap claims it, unless the panel's
window holds a shown native pane, which scrolls itself. Only the Control keys
the canvas field keymap reads reach the native field, named once in `providers/swift/fieldkeys.lua`,
and every other Control chord is a leftover, so Cocoa can never put a line break in the field. The
provider's `uses` answers from the same file, and the root checks list keys against the provider
that serves.

It builds itself. `lib/swiftbuild.lua` compiles `native/` with the `swiftc` inside the command line
tools into `~/.olm/cache/swiftchooser/`, the file and the Swift module named by a hash of every
input, since a loaded image is never unloaded and a rebuild under the same name would never be
seen, and `package.loadlib` loads it into Hammerspoon's own process. A successful build removes all
but the newest three libraries of the name. The compiler is `swiftc-clt` in `root/manifest.lua`,
resolved through the dependency door, rather than `/usr/bin/swiftc`, a shim that raises Apple's
install dialog when the tools are missing. Before anything runs, `swiftbuild.toolchain` checks what
`src/install-xcode-clt.sh` calls present, clang beside the compiler and an SDK for the running
macOS, on disk only, and without them the default chooser serves with one console line. A panel
belongs to the Lua state that made it. The library's module table holds a sentinel userdata whose
`__gc` stops, hides and forgets every panel and the callback when that state closes, which
LuaSkin's `destroyLuaState` does with `lua_close` on every reload, whether or not the next state
loads this library again, and a callback is refused whenever the main Lua state is not the one it
was registered on. The provider decides once, at configure time, because the one shared picker is
built at startup. A library already built for the current sources serves the session. Without one
the build starts in the background, the default provider serves, one console line says the swift
chooser takes over from the next reload, and a failed build or load serves default and logs the
error.

It is handed no focus hold. The canvas never takes key, so the default provider is handed
`lib/securefocus.lua`'s hold, which shows a hidden `hs.chooser` over a password field, and that
would take key from this panel. The swift provider loads its own copy of the engine, so the default
provider's copy keeps the hold for the fallback. Whether typing reaches the panel while another
application holds secure input is measured live, not assumed.

To try it, set `chooser.provider` to `chooserProviders.swift` in `config/settings.lua` and reload,
then reload once more when the console says the library is built. The shipped value stays
`default`. `test/swiftview.lua` drives the Lua view under the engine over a fake library and pins
the fallback, and `decisions/olm-swift-chooser.md` has the measurements and what was turned down.

## Secure notice, a held leader pressed under secure input

A held leader is a function key read by the ChordKey tap, deaf while any application holds secure
input. `lib/securenotice.lua` claims each held leader's function key in use as a plain `hs.hotkey`
while secure input is on and nothing while it is off, and a press draws one message through the
root's `notify` naming the holder, read from `ioreg` declared in `root/manifest.lua`. The output is
read as it streams, since `ioreg` writes more than a pipe holds and blocks otherwise. A posted key
fires no hotkey, so a live check calls the press handler rather than posting F18.
`test/securenotice.lua` pins it over fakes, and `decisions/olm-leader-keys.md` has the
measurements.

## Icons, the SF Symbol source renders out of process at the screen's scale

The engine in `lib/icons` and its two sources are described in `decisions/olm-icons.md`. What an
agent needs to keep true is where the sf source draws and its pixel rule.

Hammerspoon's process never runs JXA, for an icon or for anything else, and the dry gate refuses a call of `hs.osascript.javascript` or `hs.osascript._osascript` anywhere in the spoon, `test/drygate-jxa.lua`. The clipboard's file reader leaked the same way until 2026-10-29, and reads a copied file's real path off the pasteboard now. Calling `hs.osascript.javascript` for a symbol
leaks a JavaScriptCore context group per call, which grew the process past 1 GB, so the sf source
keeps every picture as a PNG in the storage cache directory for icons, `sf-<symbol>-72pt-<scale>x-
<rrggbbaa>.png`, and loads it from there. A missing one answers nil and pending, which the engine
does not cache, and joins a queue that one `osascript -l JavaScript` run renders through `hs.task`
in the background. The tool is declared in `root/manifest.lua` and its path comes from the door.
When a run finishes, the root calls `iconsChanged` on every chooser provider, which repaints the
lists on screen. At load the root hands the source every symbol the manifests declare. Never call
`hs.osascript` or `hs.execute` from an icon source, and never wait for a render on the main thread.

A symbol is drawn by the script into a square bitmap that is 72 points on a side and 72 times the
scale in pixels, with its size in points written into the PNG, so the image
`hs.image.imageFromPath` loads reports 72 points and carries more pixels. The scale is the largest
`scale` among `hs.screen.allScreens()` current modes, at least 1 and at most 4, read on every draw.
`hs.image:setSize` in its default form changes the size in points and keeps the bitmap, so sizing
the result to a row's points never costs pixels. The scale is in the file name and is the source's
`variant`, so a picture drawn at 1x is not served after a 2x screen is attached. The cache
directory is safe to delete, which costs one run. Do not draw the symbol through an `hs.canvas`
snapshot again, its pixels follow the canvas and not the screen.

The swift chooser's view resolves a row's icon only from a page above the viewport to a page below
it, read from the list model the engine moves on every native scroll, the way the canvas list
resolves an icon only for a row it paints. Resolving every row when rows are sent is what turned
one launcher open into a render of the whole catalog. The emoji source is not affected, since it
draws through `hs.canvas` with no JavaScript and the default chooser paints a glyph as a text
element.
