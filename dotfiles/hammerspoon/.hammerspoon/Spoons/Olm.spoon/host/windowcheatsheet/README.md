# WindowCheatSheet

Draws an overlay listing every window action bound to the window leader, so the
bindings are always visible rather than memorised. It shows every row the keymap holds on the
window leader, a plugin's bindings in plan order and then each plugin's own order, then any
tool's open key moved there, so the overlay can never drift from the real keys and names no
plugin. It is a host rather than a plugin,
since the window leader it reveals is core.

It has no key of its own to open it. Hold the window leader, Right Option
remapped to a leader key, for about 0.6 seconds with no other key pressed, and it
appears. Releasing the leader or pressing a bound key hides it again.
