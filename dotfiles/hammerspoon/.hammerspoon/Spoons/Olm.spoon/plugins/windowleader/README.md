# WindowLeader

The window management leader itself, the key you hold before pressing an arrow, a
letter, or a symbol to move or resize a window. It is whichever key config names
as the window leader, Right Option by default, remapped to a spare function key
so it can be held down the same way Caps Lock is held for the app toggles.

It opens nothing on its own. Holding it and pressing a bound key runs that key's
window action, and holding it alone for about 0.6 seconds with no other key
reveals the window cheat sheet instead.

While any Olm list is open the whole leader stays quiet, no cheat sheet on hold
and every bound key inert though still swallowed, so a window action can never
move or resize what sits underneath the list being read. The gate arrives
injected from the composition root and this plugin never learns what it watches.
