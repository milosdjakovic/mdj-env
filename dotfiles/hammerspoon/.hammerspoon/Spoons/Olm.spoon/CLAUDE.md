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
clipboard take both with it.

**Why register refuses rather than raises.** One bad descriptor must not empty the launcher, the
same reasoning behind a query source that raises being dropped for a keystroke rather than
crashing the chooser. Every refusal is one log line at warning naming the tool and the reason,
and `register` answers true when it registered, false when it refused, so a caller can react if
it ever wants to, though the composition root does not. Four refusals exist, a missing or non
string name, a second registration under a name already taken since first registration wins, a
`commands` key colliding with any name already indexed whether a tool name or another tool's
command since the flat index dispatch reads makes such a collision ambiguity rather than a
preference, and an `apiVersion` that is missing, not an integer, or unequal to the core's.

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
