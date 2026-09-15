# Workspaces

Layouts you take and put back. A snapshot records where every window on the current Space
sits, grouped by app, and becomes a named layout. Applying a layout places the windows of the
apps that are open now and leaves everything else alone. An app that is closed stays closed,
and a report on the shared overlay lists every app in the layout with its icon and says which
were placed and which were not open.

A layout remembers which display each window was on by role, the built in display or the
first, second, or third external one counted left to right, never which monitor, and each
frame as a fraction of that display. So a layout taken in front of one external monitor
applies in front of a different one, and the list says which layouts apply here, given the
displays attached right now, and what a layout that does not would need.

Opens from the launcher as Workspaces, with no dedicated chord and no alias. New snapshot
leads the list, then every layout, the ones that apply here first. Inside a layout, Apply
places the windows, Apps lists what it recorded with Remove on each and Include again on the
removed, Update snapshot replaces the record with what is open now while keeping the removals,
and Rename and Delete do what they say.

While the list is open, j and k move, i selects the highlighted row or drills into it, and x
closes the whole thing. Back is the first row of every level.
