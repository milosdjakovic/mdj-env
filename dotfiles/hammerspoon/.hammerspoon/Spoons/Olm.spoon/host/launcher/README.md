# Launcher

The catalog every tool in this configuration registers a row into, and the surface that lets
a chosen row host another tool's own list in place, so choosing one hands over the list itself
rather than opening a second window over it. Reached on Hyper and Space, it lists installed
applications, open ones first, alongside every registered command, filtered by whatever is
typed.

A typed word can also hand the whole list to one tool. That word may produce a computed
answer, an arithmetic sum or a unit conversion appearing at the top of the list, or it may host
a whole tool's own rows in place of the catalog, which is what an alias plus a space reaches.
The alias directory lists every word that does this. Applications, window actions, and System
Settings panes each have their own word too, narrowing the same catalog rather than reaching
outside it.

Whatever was chosen last, of any kind, floats to the top of the next open, so a fresh list
still reads sensibly and a recent pick is never buried underneath the rest.

While the list is open, j and k move, the accept key runs the highlighted row, and Space
closes it.
