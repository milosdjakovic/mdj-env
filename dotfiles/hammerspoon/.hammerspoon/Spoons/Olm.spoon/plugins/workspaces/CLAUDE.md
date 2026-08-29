# Workspaces

Why this plugin is shaped this way. The code sits beside this file, so this records the
decisions, not the lines.

## What it replaces, and the defect that made it worth replacing

DisplayMemory remembered which display one app's window was last on. WindowMemory remembered
every window's frame for the current set of monitors. Both are deleted and this is the one
plugin that took over from them.

They were not replaced because their ideas were wrong. Their guard logic is the best part of
this engine and was carried over almost intact. They were replaced because neither ever ran.
Neither manifest declared a `wiring` step, and neither plugin was one of the fixed leader
engines the last pipeline stage starts, so `start()` was never called on either of them, no
watcher ever subscribed, and every check in the tree reported a clean wiring run for the whole
time. That is the reason this plugin's manifest carries its `wiring` block with a comment
saying what it is for. A plugin without one is a plugin that does nothing, quietly, forever.

## The fingerprint is geometry, never monitor identity

The configuration key is every screen's `fullFrame()` in points, sorted by origin x then origin
y, each written as `x,y,WxH` and joined. The retired plugins keyed on sorted screen UUIDs
instead, which is monitor identity.

Geometry wins for three reasons. It encodes both the apparent sizes and the arrangement, which
is the entire input to the question of where a window should sit, so the key is exactly as
specific as the problem is. It is stable against everything that ought not to matter, vendor,
model, pixel resolution behind a scaling factor, and plug order, all of which change the UUID
set and none of which change where a window belongs. And it cannot confuse two identical
monitors, because a window is keyed to a position in point space rather than to a panel, so
left is simply the rectangle with the smaller x.

The cost was named and accepted rather than discovered. Two geometrically identical desks in
different buildings share one configuration. That is the correct trade, since anything a window
placement depends on is identical between them, and the alternative was a key that changes when
a monitor is replaced by the same model.

A fingerprint nobody has seen before silently becomes a new configuration with a generated name
derived from the geometry, the primary screen's size plus each other screen's size and whether
it reads as above, below, left, or right of the primary. The generator is deterministic and
takes no input beyond the sorted rectangles, so two machines at the same desk generate the same
words. Arriving somewhere new costs nobody a setup step, which is the whole promise.

## Two layers, because one memory cannot answer both questions

The session layer is in memory only, per fingerprint, window id to frame. A window id stays
meaningful for as long as the window lives, so within one login this restores every individual
window to its exact frame, multi window apps included. It is never persisted, because a window
id means nothing after a reboot and a fresh window can be handed an id an old entry still names,
so a persisted table would place the wrong window, which is a worse memory than none.

The persistent layer is the JSON store, per fingerprint, app bundle id to one frame, the frame
of the window the person last moved. A bundle id survives everything, so this is what drives
post reboot restore and fresh launch placement.

One frame per app is a deliberate simplification of this first version and the limitation worth
recording. A multi window app gets exact treatment only from the session layer. Across a restart
it gets one frame, and the engine applies it only when that app has exactly one standard window,
because one frame cannot say which of three Finder windows it meant and guessing would be worse
than declining. The natural next version keys the persistent layer by app plus window title or
by app plus an ordinal, and neither is obviously right, which is why neither is here yet.

The session layer wins wherever it has an answer. So exactness is used whenever it is available
and durability covers the rest, and the two never contend because the lookup order settles it.

## Quiescence, not a fixed settle, and why that keeps DisplayProfiles at arm's length

The engine is one state machine with two modes. In steady state it records moves. In an episode
it is deaf and waiting.

An episode opens on any screen watcher fire and on system did wake. While it is open, an idle
timer of about a second is reset by every further screen event and every window move, because
during a display change macOS shuffles every window for a second or two and those moves are
noise rather than intent. The restore runs when that timer finally expires, which is to say once
the geometry has actually gone quiet, and a hard ceiling from the moment the episode opened
guarantees progress if something keeps resetting it.

Waiting for quiet rather than for a fixed delay is what orders this plugin after DisplayProfiles
with no coupling to it at all. Every displayplacer change DisplayProfiles makes is itself a
screen event that resets the idle timer, so the arrangement always lands before the windows do,
and neither plugin names the other anywhere. An earlier version of this idea, in WindowMemory,
first tried an explicit settled hook on DisplayProfiles and it placed windows too early, because
macOS keeps moving them through the transition and a slow monitor fires more changes later. The
hook also had exactly one caller, which the design rules would have flagged as indirection that
had not earned itself. Dropping it entirely was the simplification, and it survived the rewrite.

A safety backstop spanning the whole worst case episode clears the flag even if no restore ever
runs, so a missed signal can never wedge recording off permanently.

## The focused window rule

A move is recorded only when the moved window is the focused window. This is the one guard that
is new rather than harvested, and it exists because the two old guards do not separate a person
dragging a window from macOS moving one. The episode flag covers the display change case, but a
window can be shoved around outside an episode too, by an app repositioning itself, by a Space
switch, or by another tool. A person moving a window is holding it, so it is focused. That single
condition removes most of what would otherwise be recorded as intent.

It also has a consequence worth knowing. A window moved by a script, by a window manager
binding, or by any means that does not focus it first is not recorded. Within this config the
window manager's own moves do focus the window they act on, so they are recorded, which is what
was wanted.

## The compare and skip tolerance, and the episode flag

Both harvested from WindowMemory, both resting on real state rather than on a clock.

A move is recorded only when the new frame differs from the stored one by more than about five
points. A move that merely confirms what was just applied is never worth writing, so the
asynchronous echo of the engine's own placement is ignored without timing anything and the write
is idempotent. The tolerance also keeps a one or two pixel nudge, from an app snapping its own
window, from reading as a real move.

The episode flag handles the different problem the tolerance cannot, that during a display change
the frames genuinely differ from what is stored, so without the flag the garbage would be
recorded before the restore could correct it.

There is a third, smaller suppression for the placement the engine makes outside an episode, when
a freshly launched window is put where it belongs. That is held as a counter with one pending
release per placement rather than as a single flag, because several apps can be launching at once
and a later placement must not release an earlier one's suppression.

## A slow waking display, and why one pass is not enough

Also harvested. An external monitor can report as connected the instant its cable is live and only
start displaying seconds later, so a single restore fired after the settle lands while the display
is still black. A window whose remembered frame sits on it would be placed onto coordinates that
map to no live screen, and macOS clamps it onto whatever display is awake.

So a window is placed only when its frame's center lands on a screen attached right now, and a
pass that had to defer any window schedules another a couple of seconds later, up to a bounded
number. The retries are safe to repeat because compare and skip makes a pass that changes nothing
a no op, and the episode stays open across the whole campaign so the shuffle is never recorded.
A fresh disturbance arriving mid campaign cancels it, since that campaign belongs to geometry that
has just changed again.

## Deliberately independent of DisplayProfiles

DisplayProfiles owns the physical arrangement through displayplacer. Workspaces owns where windows
sit inside whatever arrangement resulted. Workspaces never talks to displayplacer, never reads
DisplayProfiles, and declares no sibling need on it. Ordering emerges from the idle timer, as
described above.

Keeping them apart also keeps their failure modes apart. Without displayplacer, DisplayProfiles
manages nothing and Workspaces is unaffected. Without a store path, Workspaces degrades to the
session layer and DisplayProfiles is unaffected.

## Storage, and what the cache costs

The store holds one JSON file under the config directory, read once and cached, with every
mutation marking the cache dirty and the engine deciding when to flush. That is what lets a burst
of window moves during a drag coalesce into one write instead of rewriting the whole file on every
event.

The cost is that a hand edit to the file, or one arriving through git, is not seen until the next
reload. That is the same trade the DisplayProfiles store already documents and it is correct, a
data file should not force a code reload.

The file lives inside the watched tree, so a write would ordinarily trip the pathwatcher. The
composition root's auto reload ignore list already covers any JSON under config by pattern rather
than by name, so this plugin needed no entry added for it and knows nothing about any of that.

There is no host key in the file, unlike the DisplayProfiles store beside it. DisplayProfiles keys
by host because an arrangement names physical panels that belong to one desk. A fingerprint here is
pure geometry, so two machines showing the same rectangles genuinely are the same configuration as
far as window placement is concerned, which is the collision that was accepted when the fingerprint
was chosen. Keying by host as well would contradict the choice rather than refine it.

## No alias, and why that is a decision rather than an omission

An alias only becomes a typed word through a scope, and a scope row completes rather than pushing a
level, since QueryScope discards whatever `run` answers. Every row at this tool's top level means
go into this configuration and look at it, which is a push. There is no honest thing a scope row
could complete with here, and an alias declared with no scope behind it is a word that resolves to
nothing. So the tool is reached from the launcher by its name and nothing else, exactly as
DisplayProfiles is.

## No restow

These files live inside an already symlinked spoon, so they resolve through the existing link. Only
adding a whole new spoon needs a restow.
