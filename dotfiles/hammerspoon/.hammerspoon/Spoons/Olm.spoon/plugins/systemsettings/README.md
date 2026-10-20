# SystemSettings

Turns every System Settings pane into a launcher row, each one opening straight
to that pane rather than to the settings app's own front page. A separate row,
Search Settings, drops you into the settings app's own search field for anything
the pane list does not reach.

Every pane is also an action, named by the pane with everything that is not a
letter or a digit taken out, `systemsettings.General` or `systemsettings.WiFi`,
which a person puts on a key in `config/keymap.lua`. Running one opens the pane,
and hides System Settings only when it is in front and the pane this plugin last
opened, by a key or a row, is that same pane, so a second press of a pane's key
hides it and a press while another pane shows goes to this one. That is how
Hyper and comma reaches General. Each action names System Settings as its app,
so its chord shows on the launcher's System Settings row, and its row on a cheat
sheet reads as the pane's name and settings, General settings.

The pane rows in the launcher are not those actions. A row opens its pane and
never hides the app, since a pane picked from the launcher while System Settings
is in front must still navigate there, and the toggle a key runs would hide it.
So the rows stay rows, remembered by the pane's url as they always were.

There is no dedicated chord shipped, every pane appears among the launcher's
ordinary rows, and typing s or system narrows the list to only those panes.
