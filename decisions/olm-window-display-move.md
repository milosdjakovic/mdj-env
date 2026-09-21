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
