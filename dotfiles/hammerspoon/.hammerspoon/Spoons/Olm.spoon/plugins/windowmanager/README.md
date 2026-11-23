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

Six layouts step through their tiles round robin, each press taking the window to the next tile
and the last coming back to the first: halves left and right, halves top and bottom, thirds, two
thirds, fourths, and quarters from the top left to the bottom right. A press finds the tile the
window stands on, allowing a terminal its row and column of size, and a window on no tile goes to
the first. They ship with no key and are found in the launcher by name, and a key is a line in
config/keymap.lua. The gap parts the tiles as it parts the halves.

Named sizes are a list in Olm Settings under Window Management, Small and Recording shipped and any
number added there, each a width and a height in points or a percent of the screen, one of nine
places on the screen and a display, the one the window is on, the built in one, the first external
one or the one under the pointer. Each is an action of its own, listed in the launcher and given a key
on the same page.

There is no key of its own. Every action is bound under the window leader
instead, a bare arrow key for resizing, WASD for moving, and letters and symbols
for maximise, presets, growing, shrinking, centring, and switching displays.
Holding the leader with no other key reveals all of them on the cheat sheet.

Each action is a descriptor this plugin answers through `provides.actions`, and the keys are
the ones its `defaults.bindings` suggest. Olm binds every one of them on the window leader to
the descriptor its binding names, so the plugin never binds a key itself, and lists each as a
launcher row built from the same descriptor, which the launcher's window scope narrows to. The
exact size action and screen recording are unlisted, the first reached only through Window
Size and the second through nothing yet.
