# WindowMemory

Why this spoon is shaped this way. The code sits beside this file, so this records the
decisions, not the lines.

## What it is

It is DisplayMemory widened from one app to all windows, and from a remembered display to a
remembered frame. As any standard window moves or resizes it records the frame under the
current location, and when the location changes it puts every window back. The location is
the same notion DisplayProfiles and DisplayMemory already use, the set of attached displays,
injected as a `scope` so the spoon never decides what a location is.

## Session scoped, and why that is the whole point

The memory lives in one in memory table and is never written to `hs.settings`. This is
deliberate, not a shortcut. A window id is only meaningful within a login. Sleep, wake,
docking, undocking, and unplugging a monitor all keep every window alive with the same id,
so within a session a stored frame maps back to exactly the right window with no guessing. A
reboot or an app relaunch destroys that id, and a fresh window can later be handed an id that
an old entry still names, so a persisted table would place the wrong window. Persisting would
buy a worse guess, not a better memory, so the spoon does not persist and the session scope
falls out for free. A Hammerspoon reload empties the table, which is acceptable, it refills
the moment windows move and there is nothing stale to mismatch.

The one thing this does not cover is opening an app fresh onto the right display after a
reboot. That stays with DisplayMemory and TerminalHandler for the terminal, which store a
display rather than a frame and place the window when it opens, so the two layers divide the
problem cleanly and never contend. Within a session WindowMemory also restores the terminal's
full frame, a superset of what DisplayMemory tracks, and the compare and skip guard absorbs
any overlap.

## Two guards, both resting on real state

Recording and restoring could chase each other, because a restore moves windows and a move is
what recording listens for. The fix is not a lock, since Hammerspoon runs everything on one
thread and callbacks run to completion, so there is no concurrency to mutex. Two guards do it,
and both decide from state rather than from a clock.

The compare and skip test is the steady state guard. A move is recorded only when the new
frame differs from the stored one by more than a small pixel tolerance. A move that merely
confirms what we just applied is never worth writing, so the asynchronous echo of our own
setFrame calls is ignored without timing anything, and the write is idempotent. The tolerance
also keeps a one or two pixel nudge, from an app snapping its own window, from reading as a
real move. DisplayProfiles uses the same idea when it declines to reapply the arrangement
already applied.

The episode flag handles the different problem of a display change, where macOS shuffles every
window for a second or two before settling. Those moves are noise, so from the moment a screen
change or wake arrives the flag is set and recording stops, and it is cleared only when the
triggered restore has actually finished, plus a short tail for the trailing echoes. The flag
is bounded by the real completion of the restore, and a backstop timer force clears it if a
restore never runs, so a missed signal can never wedge recording off. Compare and skip alone
could not cover this, because during the shuffle the frames genuinely differ from what is
stored, so without the flag the garbage would be recorded before the restore could correct it.

## Ordering after the display geometry, without depending on DisplayProfiles

A frame is only meaningful once the displays are arranged, so restore must run after the
geometry has settled, including after DisplayProfiles has reapplied its arrangement. An earlier
version wired restore to an explicit DisplayProfiles settled hook, but that placed windows the
instant DisplayProfiles finished, which was too early. macOS keeps moving windows through the
transition, an external can appear briefly at a default position before displayplacer corrects
it, and a slow monitor fires more changes later, so a single placement at that one moment left
the terminal jumping to an intermediate spot and then again to the right one.

The spoon instead waits for the geometry to go quiet. Its settle timer is re-armed on every
screen change, so it only fires once nothing has moved for the whole delay. This needs no
knowledge of DisplayProfiles at all, because the displayplacer changes DisplayProfiles makes
are themselves screen changes that re-arm the timer, so the restore naturally lands after them.
A small margin over DisplayProfiles' own settle keeps DisplayProfiles winning the first race on
a shared burst, so its arrangement is applied and then re-arms us, rather than the two firing
together. The result is one placement at the end instead of one per intermediate layout, which
is what removed most of the clunkiness. It still owns a wake watcher, since a wake that did not
change the display set fires no screen change, and that case is the terminal on wake lag this
spoon closes. Dropping the coupling entirely was the simplification, the shared screen change
signal already sequences the two.

Removing DisplayProfiles from the picture also removed a hook that had a single caller, which
the design rules would have flagged as indirection not yet earning its keep.

## A slow waking display, and why one restore is not enough

A settled screen change is not the same as a ready display. An external monitor can report as
connected the instant its cable is live and only start actually displaying seconds later, so a
single restore fired after the settle delay lands while the display is still black. A window
whose stored frame sits on that display then gets placed onto coordinates that map to no live
screen, and macOS clamps it onto whatever display is awake, which is the terminal jumping to
the bottom of the built in panel that this behaviour was first seen as. Nothing re-placed it
once the real display came up, because the restore had already run once.

Two changes make restore survive this, and both are general rather than a terminal special
case, since the victim is only ever whichever window's display is the slow one. First, a
window is placed only when its stored frame lands on a screen attached right now, tested by the
frame's center. When that display is missing the window is left where it is rather than
mangled onto the wrong one. Second, a pass that had to defer any window schedules another pass
a couple of seconds later, up to a bounded number, so a display that finishes waking late still
gets its windows once it appears. The retries are safe to repeat because the compare and skip
guard makes a pass that changes nothing a no op, and the episode stays open across the whole
campaign so the shuffle is never recorded. Within a scope every stored window's display was
attached when it was recorded, so a missing display always means not ready yet, never gone for
good, which is why waiting is the right response and the bound is only a backstop.

## One file, not the engine and providers layout

There is one behavior and no interchangeable backend, so the spoon is a single file rather
than the composition root, engine, provider split Capture and DisplayProfiles use. A provider
layer with one implementation would be indirection with a single caller, the ceremony the
design rules reject. It stays a reusable mechanism with policy injected, the scope, the
tolerance, and the settle timing, so the split that matters, mechanism versus policy, is still
there without extra files.

## What it deliberately does not do

It does not persist across a reboot or an app relaunch, which would need best effort matching
by app, title, and order and would place the wrong window often enough to be worse than
nothing. It does not manage minimized or fullscreen windows, or windows on another Space that
are not visible, since it can only place what it can see. It does not offer a manual save and
load named layout, though the same in memory store could later back a chooser the way
DisplayProfiles does. And it excludes Hammerspoon's own windows through the filter, so overlays
and choosers are never recorded.

## No restow

These files live inside a spoon dir, but the spoon itself is new, so landing it on main needs a
restow, because `~/.hammerspoon/Spoons` holds one symlink per spoon. Testing from a worktree
through the dev lock does not, since the lock points Hammerspoon at the worktree config
directly and the spoon resolves from the worktree's own Spoons dir.
