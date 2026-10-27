# Olm Plugins

Decides which plugins run, with one row per plugin under `plugins`. It opens from the launcher
only, as the Olm Plugins row, with no key of its own, and the list replaces the launcher's rows in
place. It was the third page of the OLM settings plugin until 2026-10-27, when that plugin was
split into Olm Placement, Olm Theme and this, so each opens its list straight from its own row.

The list has one row per plugin, sorted by title, a green circle when it is on and a
red one when it is off, with a subtitle saying so in words. A plugin switched off in config says
so and cannot be changed from here, and one that is off because a plugin it requires is off
names that plugin and comes back with it. Choosing any other row stages the change and nothing
else. The page stays open, the highlight stays on the row, the circle moves to the state after
apply and the subtitle says off after apply or on after apply, and a plugin that goes off or
comes back with it says so on its own row. Choosing the row again returns it to how it is now
and drops the staged change. While anything is staged an Apply now row leads the list,
naming every plugin that changes. Whether a plugin runs is decided once per load, so the staged
set is applied with one reload, either when the whole OLM window goes away by any route, escape,
a click away or a choice that closes it, or when Apply now is chosen. After a dismissal nothing reopens, since dismissing
means done, and one routine line after the reload names what changed. After Apply now the list
reopens on the plugin last chosen. Staged choices are held in memory until then, so a reload
from anything else, or quitting Hammerspoon, drops them. A refusal is said through the routine
feedback line rather than an alert. A docked pane follows the
highlight. For the highlighted plugin it shows the title and version, its description, the
author, license and homepage when declared, what the plugin needs in short groups, and a line
naming what else goes off or comes back with it, measured against everything else staged and
taken from the root's own dry run of the plan. On Apply now,
the pane shows the shared empty state. The four root words behind it, `pluginCatalog`,
`pluginCascade`, `stagePluginSwitch` and `applyPluginSwitches`, come from
`lib/pluginswitch.lua`, and the place reopened after Apply now is a note this plugin hands the
root about itself, its own name and the plugin to highlight. `pluginspage.lua` builds the rows and the detail block as plain
data and kit nodes, and the shared docked pane, `lib/dockedpane.lua`, granted by `pane = true`,
is the canvas that draws them.
