# HyperCheatSheet

Draws the overlay that appears while Caps Lock, the Hyper leader, is held, listing every app
bound to its own letter, split into the ones already running and the ones that are not,
followed by whatever other Hyper bound commands the composition root appends below the app
grid as their own named sections. It reads the same app toggle list the bindings themselves
read, so the overlay can never show a key that does not actually work.

It has no key of its own. Holding the leader reveals it and releasing the leader hides it
again. Drawing is delegated to the shared overlay renderer both cheat sheets draw through, so
this spoon only builds the row model, resolving each app's icon and name once so the overlay
opens instantly.
