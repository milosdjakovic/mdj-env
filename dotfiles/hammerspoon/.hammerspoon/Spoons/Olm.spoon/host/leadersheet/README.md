# LeaderSheet

Draws the overlay that appears while a held leader is down, whichever leader it is. Holding Caps
Lock, the Hyper leader, shows the apps bound to their own letter, split into the ones already
running and the ones that are not, then every other chord bound on the leader. Holding the window
leader shows the window actions. Each part is supplied to it, the app sections by the app toggler
and the chords by the composition root from the keymap, so an overlay lists exactly what its
leader does and nothing else.

It has no key of its own. Holding a leader reveals its sheet and releasing the leader hides it
again. How a sheet is laid out, its columns, icons, badge width and heading, is the leader's
policy and not this host's, so a new leader gets a sheet by stating one. Drawing is delegated to
the shared overlay renderer every cheat sheet draws through.
