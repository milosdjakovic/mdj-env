# DockAutoHide.spoon (Olm plugin)

The decision trail for this plugin. Cross cutting material about the launcher and the
dependency contract stays in the hammerspoon `CLAUDE.md` and in the Launcher `CLAUDE.md`,
which link here.

## What it is

A thin front end onto the Dock's own auto hide preference. It reads whether hiding is
currently on, and it turns hiding on, off, or the opposite of whatever it currently is.
Reached from the launcher only, through one row, with no chooser and no picker of its own.

## Why it has no key

StageManager was meant to be its companion and was removed from the config entirely before
this plugin was written, so this covers the Dock alone, one system toggle rather than a
family of them. The old standalone spoon carried a hotkey, and this plugin drops it rather
than carrying it forward, since one row reached through the launcher already answers the
whole need and a dedicated chord would only be one more binding to remember for the same
action.

## The row names the action, not the state

The launcher row reads Turn Dock Hiding On while hiding is off, and Turn Dock Hiding Off
while hiding is on, so the row always says what choosing it will do rather than making
whoever reads it work out the opposite of the current state. `rowTitle` answers that wording
from live state, and it is the only place either string is written, so changing the wording
later is one edit here and nowhere else.

## The launcher's title provider seam

The launcher itself never learns what a Dock is. `Launcher:configure` takes an injected
`actions.titles` table, keyed the same way `actions.special` already is, each value a
function answering the display string for that row right now. The root wires
`titles.dockAutoHide` to this plugin's `rowTitle`, so the launcher only knows it may ask a
registered provider for a row's title, and this plugin is the only thing that ever answers
for this row. The full seam, including why the answer is memoized against the launcher's own
open counter rather than asked on every keystroke, is described in the Launcher `CLAUDE.md`.
The plain string in `config/keys.lua` is the fallback shown when no provider is registered,
which is not the ordinary path today since the root always registers one, but the string
still has to read sensibly on its own for whatever calls the row before that wiring runs.

## The finding behind writing both defaults and osascript

Read empirically on 2026-08-09 on the user's live machine, with the state read back before
and after and returned to exactly what it started as. Autohide started on. A plain `defaults
write` setting it off changed the stored preference at once, confirmed by reading it straight
back, but the running Dock did not notice, confirmed by asking System Events for the live
value, which kept answering true. Only after also telling System Events to set autohide did
the live read agree with the write. So the two calls are not redundant, they answer two
different questions. `defaults write` is what a fresh read of the preference, or a Dock
process that restarts on its own, would see. The System Events call is what makes the change
visible on the Dock that is already running, without waiting for either. Both stay for that
reason, exactly as the original standalone spoon already had them, and this is the proof that
removing either one would be a real regression rather than a tidy simplification.

## Dependencies are declared, not assumed

`defaults` and `osascript` are both declared `required` beside this plugin, resolved through
the shared dependency door and asked for by name in `configure` rather than being probed for
or written as a bare string anywhere in this file. Both ship with every macOS install, so the
required policy names what would genuinely break without them rather than guarding against a
practical absence on any machine this runs on.

## What it does not do

It never restarts the Dock process itself. The original spoon never did either, and the
System Events call the empirical check above found necessary is what stands in for a restart
without paying the cost of one. It carries no toggle boolean and no validation loop of its
own, since the tool is small enough that the launcher row proves itself by being used.
