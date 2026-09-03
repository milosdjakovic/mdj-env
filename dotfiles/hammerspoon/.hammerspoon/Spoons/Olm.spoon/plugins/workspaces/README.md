# Workspaces

Remembers where windows belong for each display configuration and puts them back on
its own. A configuration is the geometry of the attached screens, so the same desk is
the same desk however the monitors are plugged in, and two different desks that happen
to present the same rectangles are treated as one. Moving a window teaches it where
that window goes, and within a login every window on the current Space is remembered
where it was last seen under a configuration, whether it was dragged there or not.
Docking, undocking, waking, and restarting all put the windows back once the display
geometry has stopped moving. An app launched fresh lands where it was last left, as
long as it has one window.

Two layers of memory sit behind that. Within one login every individual window is
restored to its exact frame, multi window apps included. Across a restart one frame per
app survives, in a JSON file under the config directory that only this tool writes.

Opens from the launcher as Workspaces, with no dedicated chord and no alias of its own.
It is a place to look at what was remembered and to correct it, never how a restore is
triggered, since the engine does that unasked. Each configuration offers Rename, Delete
behind a confirm, Apps for the list of what is remembered there with Forget on each, and
Restore now on the configuration attached right now.

While the list is open, j and k move, i selects the highlighted row or drills into it,
and x closes the whole thing. Back is the first row of every level.
