# DockAutoHide.spoon (Olm plugin)

The decision trail for this plugin. Cross cutting material about the launcher, QueryScope,
and the dependency contract stays in the hammerspoon `CLAUDE.md`, the Launcher `CLAUDE.md`,
and the QueryScope `CLAUDE.md`, which link here.

## What it is

A page of two rows, hiding first then delay, hosted inside the launcher rather than a
chooser of its own. Choosing either row flips it in place, the chooser stays open, and the
row's own wording changes because it was recomputed rather than patched, the same freshness
every hosted page has since nothing here is ever cached.

## Why it has no key

StageManager was meant to be its companion and was removed from the config entirely before
this plugin was written, so this covers the Dock alone, two settings rather than a family of
them. The old standalone spoon carried a hotkey, and this plugin drops it rather than
carrying it forward, since the launcher row already answers the whole need and a dedicated
chord would only be one more binding to remember for the same action.

## The outer row is a doorway, the inner rows name the action

The launcher's own catalog carries one row for this tool, reading the plain noun Dock,
matching every other hosted tool's outer row. Choosing it steps into the page rather than
doing anything itself, the same as caffeinate, VPN, and the rest of `hostedInPlace`. That
doorway is root policy, `config/keys.lua` and the root's `hostedInPlace` table, and this
plugin never sees it.

The two rows inside the page are what this plugin owns, and each names the action choosing
it takes rather than the state the Dock happens to be in, so choosing a row never asks
anyone to work out the opposite of what it says. The hiding row reads Turn Dock Hiding On
when hiding is off and Turn Dock Hiding Off when it is on, the wording that existed before
this plugin was a page at all. The delay row reads Make the Dock Instant when the delay is
not instant and Restore the Default Dock Delay when it is, and its subtitle says the Dock
restarts, since a visible relaunch should never be a surprise. `rows()` builds both fresh on
every call, which is the whole reason this plugin needs no title provider or seam of its
own, a live title only needs to be read when the row is built.

## The delay's default is an absent key, not a number

`delayIsInstant` answers true only when `autohide-delay` is present and reads zero.
`makeDelayInstant` writes it as zero. `restoreDefaultDelay` deletes the key rather than
writing a number, because the original value is unknowable on a machine where it has
already been overridden, and an absent key is the genuine default state, proven on
2026-08-09 by finding `autohide-delay` present and zero here while the unrelated
`autohide-time-modifier` animation key was simply absent, a different state from zero
rather than the same one written differently. This plugin touches `autohide-delay` only.
`autohide-time-modifier` governs the hide and show animation, the user has never set it,
and nothing here reads or writes it.

## Hiding and delay apply themselves through two different doors, and neither is a guess

Both were checked empirically on 2026-08-09 on the user's live machine, with the state read
back before and after and returned to exactly what it started as.

Hiding is felt at once because System Events has a lever for it. Autohide started on. A
plain `defaults write` setting it off changed the stored preference at once, confirmed by
reading it straight back, but the running Dock did not notice, confirmed by asking System
Events for the live value, which kept answering true. Only after also telling System Events
to set autohide did the live read agree with the write. So the two calls are not redundant,
they answer two different questions, `defaults write` is what a fresh read of the
preference, or a Dock process that restarts on its own, would see, and the System Events
call is what makes the change visible on the Dock already running. Both stay, exactly as
the original standalone spoon already had them.

The delay has no such lever. Asking System Events for the dock preferences properties on
this machine returned autohide and a number of other properties and no delay of any kind,
so there is nothing to push a delay change through. A delay change is therefore invisible
until the Dock re reads its preferences on its own, which only happens when it restarts, so
`makeDelayInstant` and `restoreDefaultDelay` both restart the Dock through `killall` after
writing or deleting the key. Confirmed the same date, a written value persisted across a
restart and a deleted key read back absent exactly like `autohide-time-modifier` does, and
the Dock came back up cleanly both times. Hiding keeps its System Events push and never
restarts anything, since it already has a working lever and a restart would only cost a
visible flicker for no reason.

## Dependencies are declared, not assumed

`defaults`, `osascript`, and `killall` are all declared `required` beside this plugin,
resolved through the shared dependency door and asked for by name in `configure` rather
than being probed for or written as a bare string anywhere in this file. All three ship
with every macOS install, so the required policy names what would genuinely break without
them rather than guarding against a practical absence on any machine this runs on.

## What it does not do

It never restarts the Dock for a hiding change, since the System Events push already makes
that visible without paying the cost of a relaunch. It carries no toggle boolean and no
validation loop of its own, since the tool is small enough that the launcher page proves
itself by being used.
