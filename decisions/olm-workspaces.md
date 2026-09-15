# Olm workspaces

Status. Layouts are snapshots a person takes and applies by hand, keyed by display role and
unit frame, tracked in git. Nothing automatic remains.

## Now

The workspaces plugin in `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/plugins/workspaces`
records a snapshot of every window on the current Space when asked, under a name, and places the
windows of whatever apps are open when the layout is applied. Closed apps stay closed and the
report on the shared overlay says so per app. A window is remembered by the role of its display,
built in or the first, second, or third external counted left to right, and by its frame as a
fraction of that display's visible frame, never by monitor identity and never in points. A
layout is available when every display it needs is attached. `config/workspaces.json` is
written only when a person acts and is tracked. The plugin's own `CLAUDE.md` holds the design
record and the hammerspoon module `CLAUDE.md` holds what crosses the config.

## Rejected

- **Automatic capture and restore, a watcher recording every window move under a geometry
  fingerprint and putting windows back after a dock or a wake.** 2026-08-29 to 2026-09-15,
  bc6e8ad until this change. It ran, and it was engineered hard, quiescence detection, a retry
  campaign for slow displays, a readback per placement, a grace on capture, a session layer and
  a persistent layer. It was replaced because remembering on its own meant remembering whatever
  macOS or an app last did, the file filled with frames nobody chose, and the surface for
  correcting that was a chore nobody wanted. Milos asked for it to go outright rather than be
  tuned further.
- **Keying a layout on the point geometry of the attached screens.** Same span. Exact and
  stable for one desk, and useless in front of any other monitor, since a different size is a
  different fingerprint and the frames are absolute points anyway. Replaced by display roles
  and unit rects, which was the request, remember whether a window was on the built in or the
  external display and nothing about which external.
- **Keying a layout on monitor identity, serial or UUID.** Considered 2026-08-29 and turned down
  then for the geometry key, and turned down again 2026-09-15 for roles, for the same reason on
  both dates, a window does not belong to a panel, and a person who buys a different monitor
  should not lose every layout.
- **Ignoring `config/workspaces.json` in git.** 2026-09-12, b583908, and right on that date, since
  the plugin wrote the file itself after every window move and two machines could never merge
  one. Reopened 2026-09-15. The file is written only by a person's own act now and holds roles
  and fractions rather than one desk's points, so it travels, and it is tracked again. The
  stamped copies the store moves an unreadable or legacy file aside to stay ignored by pattern.
- **Exact topology match for availability.** Considered 2026-09-15 and turned down. A layout
  taken on the built in display alone would read as unavailable the moment an external was
  plugged in, though the built in display is still there. Availability asks whether every display
  the layout needs is attached, and the list says what a layout that is not available would need.
- **Removing an app from a layout by deleting its entry.** Considered 2026-09-15 and turned down.
  Update snapshot replaces the record with what is open now, and a deleted app would come back on
  every update. The app stays with `excluded` set and keeps its windows, so updates keep the
  removals and Include again has something to place.

## Log

### 2026-08-29 11:43

bc6e8ad. The automatic plugin lands, replacing DisplayMemory and WindowMemory, which had never
been started. Geometry keyed configurations, two layers of memory, restore on quiescence.

### 2026-08-30 22:12

688dee8. `config/workspaces.json` is committed so layouts can travel between machines.

### 2026-09-03 15:58

9a0eb74. An unplug and a replug left Chrome on the built in panel and the file showed a frame
recorded under the wrong geometry. Three weaknesses fixed, then six more from a second review.
The engine is at its most elaborate here.

### 2026-09-12 16:09

b583908. The file is taken out of git, forty one lines grown to a hundred and sixty six in twelve
days with nothing typed by a person.

### 2026-09-15 20:54

Milos asks for the automatic recognition, the monitor detection, and the restore to go, and for
layouts to be snapshots taken by hand, listed with their apps and icons, pruned per app, applied
on request with closed apps left closed and a panel saying which were not open, remembered by
built in versus external display rather than by monitor, and marked available or not for the
displays attached. The rewrite lands in this change. The engine goes from twelve hundred lines of
watching to a few hundred of reading displays, taking a snapshot, and placing, with no start step
and no watcher. The built in display is recognised by the Apple silicon built in UUID with the
display name as the Intel fallback, since `hs.screen` has no built in flag and `getInfo` answers
nil on this machine. The report goes out through a new `report` root word drawn by a new
`toast.list` in `lib/hints.lua`, the same seam as `notify`.

### 2026-09-15 23:40

Tried live under the devlock. The first report listed every app in the layout with placed
beside most of them, and Milos asked for it to be the size of the Hyper cheat sheet, to list
only the apps that could not be placed, and to carry a footer with a five second countdown and
a Dismiss button. So an apply where everything landed shows nothing, the windows moving being
the feedback, and the panel exists for the closed apps alone. The Dismiss chip is the first
clickable thing on a CanvasPanel, so the atom gained an optional `onClick` on its content
rather than the plugin or the root reading the mouse. Merged to main the same evening.
