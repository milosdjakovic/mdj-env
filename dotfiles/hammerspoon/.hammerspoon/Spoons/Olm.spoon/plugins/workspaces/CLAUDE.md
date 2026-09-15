# Workspaces

Why this plugin is shaped this way. The code sits beside this file, so this records the
decisions, not the lines. The repository level record, with everything the earlier version of
this plugin tried and the reasons it was replaced, is `decisions/olm-workspaces.md` at the
repository root, and it is the file to read before proposing anything here.

## Snapshots a person takes, never a record the plugin keeps

The earlier plugin in this directory watched every window move, remembered it under a
fingerprint of the attached screens, and put windows back on its own after a dock or a wake. It
was replaced because remembering on its own meant remembering whatever macOS or an app last did,
and the correction surface for that was a chore. This one remembers only what a person asked it
to, when they asked, and applies only when asked. There is no watcher, no episode, no settle
timer, and no start step, and the manifest says so rather than leaving it to be noticed.

The contract on apply is narrow on purpose. A layout says where windows go, never which windows
should exist. Nothing is launched, closed, hidden, or minimised, and an app that is not running
is reported as not open and left that way.

## Displays are roles, frames are fractions

A window is recorded on `internal`, `external`, `external2`, and so on, the built in panel and
the externals counted left to right by position. Not the monitor, not its serial, not its size.
The frame is a unit rect of that display's visible frame. Together those make a layout taken in
front of one monitor apply in front of another of a different size, a different dock, or a
different menu bar height.

The built in panel is recognised by its display UUID, which Apple gives every Apple silicon
built in panel as one constant rather than a per machine value, with the display name as the
fallback for an Intel machine. `hs.screen` exposes no built in flag and `getInfo` answers nil
here, so those two signals are what there is.

## Available means every display it needs is attached

A layout is available when every role its included windows sit on is attached now, not when the
topology matches what it was taken under. A layout taken on the built in display alone applies
just as well with an external plugged in, since the built in display is still there. The list
puts available layouts first, marks the rest, and says what each would need.

## Removing an app excludes it rather than deleting it

An app removed from a layout stays in the file with `excluded` set and keeps its windows. That is
what lets Update snapshot keep the removals, since an update replaces the record with what is
open now and an excluded app is carried over as excluded rather than resurrected, and it is what
lets Include again have something to place without a fresh snapshot.

## Matching windows by title first, then by order

An app with several windows records each with its title. On apply, a recorded window pairs with
a live one whose title matches exactly, so two Chrome windows go back to their own places rather
than swapping, and whatever is left pairs in order front to back on both sides, since a title
that changed with the tab is still most likely the same window in the same place in the stack.

## Saving a snapshot leaves and arrives in one press

Save on the name level pops that level from inside `select` and then answers the new layout's
own child, so the stage lands on the layout just taken with Apps one row away, ready to prune,
and Backspace from there goes to the list rather than back to a name field for a snapshot that
already exists. `Stage:_intercept` runs `onSelect` and pushes whatever comes back, and a pop
before the return simply changes what the child stacks on. Every other leaving row rides its
level's `intercept` and `stagePop`, the shape DisplayProfiles settled.

## The report is the root's, not this plugin's

An apply reports through the `report` word the composition root publishes, a titled list of
rows with icons drawn on the shared overlay by `lib/hints.lua`'s own `toast.list`, the same
seam `notify` and `showColor` already use. The plugin never builds a panel. Without the word
the windows are placed regardless and the console carries the same lines.

## Storage

The file is `layouts.json` in this plugin's own directory under the olm data root, asked for
through `lib/storage.lua`'s `dataDir`, the same door speedtest's history goes through, and the
directory is made on the first write so a plugin that never stores anything leaves nothing
behind. A layout is this machine's own record of its desk and its apps, taken by hand but
personal all the same, so it is not configuration and never reaches git. It sat inside the
config tree for one evening as a tracked file, and the earlier automatic store sat there git
ignored for two weeks before that, and both were the same mistake, a machine's own record
inside the configuration tree. A file that will not parse or is not this shape is moved aside
under a stamped name rather than replaced. Being outside the config tree, a write never touches
the pathwatcher.

## Windows on another Space are invisible, and that is open

`hs.window.allWindows` answers only the current Space, so a snapshot records the current Space
and an apply through `hs.application:allWindows` may pair a recorded window with one on another
Space. Named rather than fixed, as before.

## No restow

These files live inside an already symlinked spoon, so they resolve through the existing link.
