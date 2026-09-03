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

A move reaches the persistent layer only when the moved window was the focused window. This is
the one guard that is new rather than harvested, and it exists because the two old guards do not
separate a person dragging a window from macOS moving one. The episode flag covers the display
change case, but a window can be shoved around outside an episode too, by an app repositioning
itself, by a Space switch, or by another tool. A person moving a window is holding it, so it is
focused. That single condition removes most of what would otherwise be recorded as intent, and
one frame per app should reflect what a person actually chose rather than whatever an app or a
script last put there.

The session layer does not ask this question at all. Its job is putting a window back exactly
where it last sat, whether a person dragged it there or an app placed itself, so every placeable
window's move is recorded there regardless of focus. Leaving out the windows nobody ever touched
was the gap that let a Chrome window sit at the wrong frame after an unplug, recorded below, so
the rule that used to gate both layers now gates only the one that needs it.

It also has a consequence worth knowing. A window moved by a script, by a window manager
binding, or by any means that does not focus it first is never recorded into the persistent
layer. Within this config the window manager's own moves do focus the window they act on, so
they are recorded there too, which is what was wanted. The session layer has no such gap any
more, and records that window's move either way.

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

The center test alone was not enough. A display already connected is already sitting in the
attached list well before it is actually displaying, so a placement onto it passes the center
test and macOS still clamps it onto whatever panel is awake, and nothing about that pass ever
found out. The readback is what actually detects that refusal, asking the window for its frame
again right after setting it and counting a placement as landed only when the answer matches, so
a display that never wakes and a display that flatly refuses a placement now share the identical
retry rather than only the first of them ever being caught.

## Three weaknesses one Chrome frame exposed

An unplug and a replug left some windows on the built in panel instead of back on the external
display, and the stored file showed why. Under the two display configuration, Chrome was
remembered at exactly the built in panel's full visible frame, which is what a window looks like
once macOS has clamped it there. A shuffle frame had been recorded under the wrong geometry, and
three separate weaknesses could each produce that on their own.

A placement macOS refuses was invisible. Setting a frame and never asking whether it landed meant
a display that reports as connected before it is actually displaying, already sitting in the
attached list, could take a placement that macOS then clamped onto the built in panel, and
nothing about that pass ever knew. The fix asks the window for its frame back right after setting
it and only counts a placement as landed when the answer matches, so a refusal now behaves
exactly like a display that was merely slow, and both share the same retry. The trade is one
extra read per placement, which is cheap next to walking the whole window list the pass already
pays for.

Capture had no look behind. A move was written the instant it arrived, and the screen watcher
usually opens an episode before the filter's own half second delay hands a shuffled move onward,
but the watcher is documented as unreliable across sleep, so a shuffle that beat the episode to
the filter was written under the stale fingerprint with a built in frame, which could well have
been the Chrome entry above, though any of the three weaknesses here could equally have written
it. The fix stages a move for a short grace and commits it only once nothing has changed
underneath it, checked by recomputing the fingerprint live rather than trusting a cached one only
an episode ever refreshes, dropping the stage instead when a disturbance arrives first or the live
geometry no longer matches what was staged. The trade is that every ordinary drag now waits a
second before its own memory is final, which is not a delay anybody dragging a window would ever
notice.

Windows that were never dragged had no memory. Both layers recorded moves alone, and only of the
focused window, so a window an app placed itself, or one nobody ever touched under a
configuration, was unknown there and stayed wherever macOS threw it. The fix records every
placeable window's move into the session layer regardless of focus, and fills whatever gap is
still left the moment an episode closes, from wherever that window actually sits. The persistent
layer keeps the focused window rule as its own definition of intent, since one frame per app
should reflect what a person chose rather than whatever an app last put there, so the trade sits
entirely inside the session layer, which was already the layer with the least to lose.

The first shape of that fill had a hole of its own. A window whose only memory came from the
store, never the session, has no session entry either, so if its placement was refused or
deferred for the whole campaign, the fill would have written its wrong current frame as if that
were the memory, and a wrong session entry wins over a correct store one on every later dock
under that fingerprint, silently undoing the very frame the store was right about. The fix has
the last restore pass remember which ids it could not place, refused or deferred, and the fill
skips every one of them, so a window only ever earns a filled entry by resting in a frame nothing
was still trying to change.

## A second review found six more holes

Six more weaknesses surfaced once the first three fixes were read adversarially against the code,
each closed in the same file.

The fill was not the only place _unplaced needed to matter. A stage that commits after the
campaign closes can carry the exact same wrong frame the fill was already refusing to write, since
a window stuck in the wrong frame by a refused or deferred placement keeps producing frame events
of its own once recording resumes, an echo of the campaign rather than a person. _commit now drops
a stage for an id still in _unplaced unless the stage carried intent, since a person actually
dragging that window afterward is real and worth believing over a campaign that already gave up,
while an echo or a small nudge is not. This is also why the fill no longer clears the set when it
finishes, only the next disturb does, since the protection has to last through the steady state
that follows, not only through the moment the campaign closes.

Deciding landed by tolerance alone was still wrong even with the readback in place. An app with a
grid of its own, a terminal snapping to cell boundaries or a window enforcing a minimum size,
answers every readback outside the five point tolerance forever, and nothing about that is macOS
refusing anything, it is the app being exactly the size or position it always insists on. A retry
campaign that could not tell the difference fought a window like that across the whole worst case
span with recording deaf the entire time, for a placement nothing was ever going to change. _place
now asks which screen holds the center of the frame it asked for and which screen holds the center
of what it actually got, and counts the two as landed together whenever they agree, refused only
when they land on different screens or the readback lands on none at all.

A newborn's placement is no longer fire and forget. When _place answers refused, the id goes into
_unplaced exactly the way a restore pass refusal does, so a newborn's clamped frame is never
mistaken for its memory either. There is deliberately no retry campaign for a newborn the way a
restore pass has one, since a person is more likely to be watching a window they just opened than
one already settled, and a silent multi second fight is a worse thing to be visible during than a
placement that simply did not happen. Separately, MUTE_TAIL was too short to do its own job. The
window filter delays every move event by half a second and restarts that delay on each further
notification before handing one onward, so the old three tenths of a second mute had already
expired before the very event it existed to suppress could ever arrive. It is a full second now.

The safety backstop used to be able to fire in the middle of a live campaign and force close an
episode a retry or a closing tail was already about to finish properly, racing whichever one got
there first. It now checks for exactly that, a pending retry or a pending tail, and re arms itself
for another full span instead of closing anything when either is found. When it does force close,
because nothing is pending, it stops and clears every timer this episode owns, the ceiling, the
retry, and the tail, so nothing is inherited by whatever opens next and this same close can never
fire twice. The one exception is the idle timer, stopped but kept, since it is the one timer
created once in start and reused for the engine's whole life rather than one this episode owns
outright, and clearing it would leave nothing able to ever restart quiescence detection again.

A doAfter timer does not run while the machine is asleep, it fires as soon as the machine wakes
with however much wall clock time has actually passed, so a ceiling or a safety armed just before
a long sleep can fire long after the interval it was given ever intended to measure, and resolving
or force closing on that basis would be acting on a timeout that went stale during sleep rather
than one that ever meaningfully expired. Both timers now record their own due time in wall clock
seconds when armed, and a firing more than five seconds late is treated as exactly that, sleep
having intervened, re arming a fresh span and, for the ceiling, bumping instead of resolving, so
the wait for quiet or the backstop simply starts over rather than acting on a stale clock.

A window born mid episode used to be ignored outright, which meant it was never placed at all
rather than merely waited on, silently joining the pile of things the shuffle disturbs and staying
wherever it happened to open. _onBorn no longer checks for an open episode, it always schedules,
and _placeNewborn is the one that waits, re arming its own timer a quiet beat plus a birth delay
later, up to a bounded number of times, until the episode it found open has closed. The fill knows
about this too, skipping any id still waiting in _births, since pinning a newborn at whatever frame
it happened to open with, before its own placement ever ran, would teach the session the wrong
thing a moment before the right one was about to arrive.

## Windows on another Space are invisible to this, and that is open

hs.window.allWindows() answers only the windows on the current Space, so a window sitting on
another Space is invisible to every pass here. The restore pass's own prune drops its session
entry as if the window had closed, since nothing distinguishes a window on another Space from one
actually gone, and the baseline fill cannot put it back either, since it walks the exact same
list. A window kept on a Space nobody is looking at when a dock or an unplug happens quietly loses
whatever this engine ever remembered for it. This is named rather than fixed, since asking
hs.window.allWindows to answer for every Space is not a switch this build can flip, and the honest
fix needs a different way of enumerating windows that does not exist here yet.

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
composition root's auto reload ignore list covers any JSON under config by pattern rather than by
name, so this plugin needs no entry of its own and knows nothing about any of that.

That sentence was written before it was true, and the correction is the one defect on this build
that no static check could have caught. `hs.json.write` is atomic, so it does not write the file,
it writes a sibling temp named for the target plus an sb suffix and renames that into place. The
shipped pattern was anchored to end at `.json`, so the temp path matched nothing, the watcher saw
a path nothing ignored, and every captured move reloaded the whole configuration about two seconds
later. The pattern and the path both read as obviously right, which is exactly why the anchor is
the thing somebody would put back while tidying, and the comment in `root/compose.lua` now says so
at length. The same bug was latent in the DisplayProfiles store, which writes the same way into
the same directory and had simply never fired, because no profile has ever been captured on this
machine.

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

## One window sweep per restore pass

`hs.window.get(id)` reads like a lookup and is not one. It walks the whole window list on every
call, which the shipped `window.lua` says outright. The first version of `_restoreOnce` pruned the
session table with one `get` per remembered id, so a desk with thirty remembered windows paid
thirty full sweeps before the pass even started, and a retry campaign multiplied that by seven,
all synchronous on the main thread during exactly the second when a person has just docked and is
watching.

So a pass now takes one `hs.window.allWindows()` snapshot, builds an id to window map from it, and
does both the prune and the placement walk off that map. Pruning against the snapshot is precisely
what pruning through `hs.window.get` already meant, since that is the list it was searching, so
nothing about the behaviour changed. The screen frames and the per app standard window count are
cached per pass for the same reason, the screens because they cannot change mid pass without a
screen event that opens a fresh episode anyway, and the window count because an app with four
windows would otherwise walk its own window list once per candidate for an answer that is the same
every time.

The birth path had the same shape of waste. Every window born anywhere on the machine reached it,
and it scheduled a timer for each one before asking whether the app was remembered at all. It now
asks the store first, which turns an ordinary window opening into two table lookups, and it carries
the window object the filter already handed it rather than paying another sweep to look the same
window up again by id. `placeable` asks a window for its id first, which is how an object that
outlived its window is caught half a second later.

## A file a person may edit is a file that may be wrong

Two failures were possible here and both were silent in the worst way.

A single hand edited frame with a missing or non numeric field raised inside the restore timer.
That raise escaped the pass, so the episode never closed, the flag stayed set, recording never came
back, and every later episode repeated the same crash. One mistyped number disabled the whole
plugin until a reload. The store now validates every frame it hands out, all four values present
and all four numbers, and answers nil otherwise, so a bad entry costs that one window its placement
and nothing else. The surface asks the store for the same judgement rather than making a second one
of its own, and prints through a rounding helper besides, since `string.format` with a percent d
refuses a fraction rather than rounding it.

A file that exists and will not parse was discarded, and then two seconds later the debounced write
replaced it with a nearly empty table. That is the only copy of everything a person ever remembered,
gone, with a discovery lag of weeks. The file is now moved aside under a name stamped with the time,
which can never collide with an earlier rescue, and one line says exactly where it went. When even
the move fails, the store seals itself, reading as empty for the rest of the session and refusing
every write, because a memory that stops working is recoverable and one that was overwritten is not.

## One creator of configurations

`setAppFrame` used to reach `ensure` so a move could always be recorded. It had no name to give and
none of its callers could have one, a window move knowing nothing about screens, so `ensure` fell
back to the raw fingerprint string. That was invisible until somebody deleted the configuration they
were standing in, moved a window, and watched it come back named `0,0,1512x982`.

The store now refuses to create. `ensure` is reached from the engine and from nowhere else, so every
configuration is named from its geometry. Deleting the attached configuration means forget what it
remembered, never make it cease to exist, since which screens are attached is a fact rather than a
preference, so the engine puts it straight back, empty and freshly named, through the same one door.

Generated names describe geometry, and two fingerprints can describe the same geometry, two desks
whose external monitor sits a few points further along being the everyday case. A name already
taken by a different configuration gets a counter appended rather than being handed out twice, since
two identical rows are a list nobody can act on. Renaming either one is what makes the counter go
away.

## The active marker never redraws under a hand

The marker moving also reorders the top level, since the attached configuration leads it. So a
background redraw while somebody is part way down the list would move rows out from under them,
which the authoring guide names outright as the thing not to do. `stageSelectedRow` answers whether
the highlight is still on row one and anything past it defers.

Deferring costs nothing to remember here, unlike the menu search cache which has to hold its landed
answer until the next open. Every level is rebuilt from the api the next time it is shown, so the
correction arrives with the next open on its own.
