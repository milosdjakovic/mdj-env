# AppToggler

Brings an application forward, and cycles through its windows when it is already
the frontmost app, so pressing the chord repeatedly walks the app's windows and
wraps to the first. It never hides anything. A toggle can instead open straight to
one settings pane by its url rather than plainly focusing an app, which is how the
System Settings toggle lands on General.

Each app is bound to its own chord on the Hyper leader, holding Caps Lock and
pressing the app's own letter. The whole set also appears as rows in the
launcher's application list, reached by typing a or app to narrow to only those
rows.

There are no other keys. A show and hide behaviour also lives here, where a second
press really does hide the app, but nothing inside Olm binds it. The terminal
handler, which sits outside Olm, is its only caller.
