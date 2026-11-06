# Olm Plugins

Decides which plugins run, with one row per plugin under `plugins`. It opens from the launcher
only, as the Olm Plugins row, with no key of its own, and the list replaces the launcher's rows in
place. It was the third page of the Olm Settings plugin until 2026-10-27, when that plugin was
split into Olm Placement, Olm Theme and this, so each opens its list straight from its own row.

The list has one row per plugin, sorted by title, Olm's checked box when it is on and the
empty one when it is off, with a subtitle saying so in words. A plugin switched off in config says
so and cannot be changed from here, and one that is off because a plugin it requires is off
names that plugin and comes back with it. Choosing any other row stages the change and nothing
else. The page stays open, the highlight stays on the row, the box moves to the state after
apply and the subtitle says Turns off when Olm closes or Turns on when Olm closes, and a plugin that goes off or
comes back with it says so on its own row. Choosing the row again returns it to how it is now
and drops the staged change. There is no apply row, Milos's call on 2026-11-05. Whether a plugin
runs is decided once per load, so the staged set is applied with one reload when the whole Olm
window goes away by any route, escape, a click away or a choice that closes it. Nothing reopens,
since dismissing means done, and one routine line after the reload names what changed. Staged choices are held in memory until then, so a reload
from anything else, or quitting Hammerspoon, drops them. A refusal is said through the routine
feedback line rather than an alert. A preview pane follows the
highlight. For the highlighted plugin it shows the title and version, its description, the
author, license and homepage when declared, what the plugin needs in short groups, and a line
naming what else goes off or comes back with it, measured against everything else staged and
taken from the root's own dry run of the plan. The three root words behind it, `pluginCatalog`,
`pluginCascade` and `stagePluginSwitch`, come from `lib/pluginswitch.lua`. `pluginspage.lua` builds the rows and the detail block as plain
data and kit nodes, and the shared preview pane, `lib/previewpane.lua`, granted by `previewPane = true`,
is the canvas that draws them.
