# WindowManager

Moves and resizes the focused window, filling a half of the screen, maximising,
centring, nudging it by pixels, switching it to the next or previous display, and
hiding every other app's windows. Every action reads the screen's usable area
rather than its raw frame, so a configured gap and margin are respected the same
way maximise is.

Switching a window to another display keeps its size rather than stretching or
shrinking it to the target screen's shape, and shrinks only on an axis that does
not actually fit there. It keeps its place on the screen too, carried across as
the same relative position rather than the same relative proportions, so a window
sitting off to one side of a small screen lands off to the same side of a large
one instead of drifting toward the middle. A window returning to a display it has
already been on lands back on exactly the frame it had there, for as long as this
config has been running.

One action has no key at all. Sizing a window to an exact pair of dimensions needs the
dimensions, which a key cannot carry, so it is reached from the launcher by typing a size,
and the plugin that owns that grammar is windowsize. This one answers what such a request
would land as, so the row can say up front when a size will not fit, and then performs it.
It is measured against the screen's visible frame rather than the gap inset canvas, since
an exact size means exactly that and a gap would quietly take pixels out of it, which the
preset sizes beside it have always done too.

There is no key of its own. Every action is bound under the window leader
instead, a bare arrow key for resizing, WASD for moving, and letters and symbols
for maximise, presets, growing, shrinking, centring, and switching displays.
Holding the leader with no other key reveals all of them on the cheat sheet.
