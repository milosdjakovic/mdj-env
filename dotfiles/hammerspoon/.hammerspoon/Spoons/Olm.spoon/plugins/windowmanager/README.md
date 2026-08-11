# WindowManager

Moves and resizes the focused window, filling a half of the screen, maximising,
centring, nudging it by pixels, switching it to the next or previous display, and
hiding every other app's windows. Every action reads the screen's usable area
rather than its raw frame, so a configured gap and margin are respected the same
way maximise is.

There is no key of its own. Every action is bound under the window leader
instead, a bare arrow key for resizing, WASD for moving, and letters and symbols
for maximise, presets, growing, shrinking, centring, and switching displays.
Holding the leader with no other key reveals all of them on the cheat sheet.
