# Olm window display move

Status. A display switch keeps the window's size and its place on the screen, shrinking only
an axis that does not fit, and a window returning to a screen it has already been on this
session lands back on exactly the frame it had there. The memory is in RAM only and nothing
watches for window moves to fill it.

## Now

`moveToDisplay` in the windowmanager plugin no longer calls Hammerspoon's own
`window:moveToScreen`. It computes the placement itself against the plugin's gap inset canvas
on both screens. The window keeps its pixel width and height, each clamped down to the target
canvas so only an axis that genuinely does not fit shrinks, and its centre is carried across as
a fraction of the canvas rather than its proportions, so a window that sat in the middle of one
screen arrives in the middle of the other at the size it already was.

Beside that the plugin holds one table in memory, window id to screen UUID to the frame that
window last had on that screen. The placement helper is the only writer, recording the frame on
the way out, and the only reader, restoring a remembered frame verbatim when the window returns
to a screen it knows and that frame still fits. Nothing subscribes to anything. The table dies
on every config reload, which is often, and that is the whole point of it being where it is.

Window identity is the CGWindowID behind `win:id()`, which belongs to the window rather than to
Hammerspoon, so three Chrome windows are remembered separately for as long as each one lives,
and a closed window is a stranger when it reopens.

## Rejected

- **Hammerspoon's own proportional rescaling on a display switch**, which is what
  `window:moveToScreen` does by default and what this plugin used until now. 2026-09-21. It
  preserves the fraction of the screen a window covers, which is not what a person means by
  moving a window. The two panels here differ by more than two to one in width, so a window
  sized for one is either stretched across the other or shrunk to a fraction of it. The
  terminal's own placement made it worse rather than better, since that clamps its requested
  size to whichever screen it lands on, so a full width terminal on the built in panel became a
  full width terminal on the ultrawide, and a correctly sized one on the ultrawide became a
  small one on the built in panel.
- **Persisting the per screen frames to disk, filled by a watcher recording every window
  move.** 2026-09-21, and this is the same approach `decisions/olm-workspaces.md` already
  rejected on 2026-09-15 after it had run for two and a half weeks. It was offered again in
  this session before that file was read, which is precisely the failure this directory exists
  to prevent. It stays rejected on the original reason. Remembering on its own means
  remembering whatever macOS or an app last did, and the file fills with frames nobody chose.
- **A durable key for one window of a multi window app.** 2026-09-21. Below the bundle id
  there is nothing stable to key on. A Chrome title changes on every tab switch, front to back
  order changes as you work, and the profile behind a window is not exposed anywhere worth
  trusting. So identity is exact while a window lives and absent once it closes, with nothing
  in between, and that limit is accepted rather than worked around.
- **Applying a per app fallback frame to a window never seen before.** 2026-09-21. It sounds
  right for a single window app and it is wrong for three Chrome windows, which share one
  bundle id, so all three would stack on the same rectangle every time one of them opened. A
  new window keeps wherever its own app put it and is remembered from its first move onwards.
- **Keying the table on monitor identity.** Not rejected, and named here only because
  `decisions/olm-workspaces.md` turned that key down twice and a reader will want to know why
  it is used here. The two answer different questions. A saved layout must travel to a
  different monitor, so it names a display by role. This table must not, since the frame a
  window had on a 34 inch ultrawide means nothing on a 23 inch panel. Nothing is stored and
  nothing travels, so the objection does not reach it.

- **Writing every placement through `setFrameWithWorkarounds`.** Considered 2026-09-21 and
  turned down. It is the correct write and it is not free, since it parks the window inside the
  screen it starts on to learn what size that screen will allow, which reads as a wiggle on
  every display switch. A plain write already lands exactly whenever a window is shrinking, so
  the plain write runs first and the workaround follows only when a readback shows it did not
  take.

## Log

### 2026-09-21 12:01

The measurement. `windowmanager/init.lua` ended `moveToDisplay` with `window:moveToScreen(nextScreen)`
and no flags, and Hammerspoon's own `window.lua` at line 918 answers that with
`theScreen:fromUnitRect(self:screen():toUnitRect(self:frame()))`, a pure proportional rescale.
The terminal case that prompted this, `alt` and backtick placing Ghostty at 2400 by 1350 clamped
to whichever screen it lands on, then the window leader moving it across, was the same
arithmetic seen from both ends. About 0.70 of the ultrawide's width became 0.70 of the built in
panel's, roughly a thousand pixels, and nearly the whole built in panel became nearly the whole
ultrawide.

Three layers were proposed, the fit rule, a memory in RAM, and a persisted memory with a
recorder and a restore after a display change. The third was proposed without reading
`decisions/olm-workspaces.md` first, where the same thing sits in the Rejected list from six
days earlier. Milos asked for the first two, which is what landed, and the third is recorded
above as rejected rather than as pending.

### 2026-09-21 12:42

The first live round trip failed and named its own cause. The terminal was remembered on the
ultrawide at `2400x1350 at -471,-1380`, a live read of the table confirmed exactly that, and the
window came back at `1983x1350 at -471,-1380`. The position and the height are exact and only
the width is short, and `-471` plus `1983` is `1512`, which is the built in panel's own right
edge to the pixel. So the frame being remembered was right and the frame being written was
being clamped.

The mechanism is `hs.window`'s own. `setFrame` with the default `setFrameCorrectness` writes
the whole frame in one call, and macOS evaluates that size against whatever screen the window
is still considered to be on, so a window growing as it crosses from a small screen to a large
one is cut at the boundary of the one it is leaving. Hammerspoon documents both this and the
separate fact that a terminal only resizes in whole rows and columns, and ships
`setFrameWithWorkarounds`, whose zero duration path writes the size, then the top left, then
the size again. That second write lands once the window is already on the target screen, which
is what escapes the clamp.

`_applyFrame` is the answer taken. It writes plainly, reads the frame back, and escalates to
the workaround only when an axis landed more than twenty points off what was asked. Twenty
points is about one terminal cell with room to spare and the failure it catches was four
hundred points out, so neither number is delicate against the other.
