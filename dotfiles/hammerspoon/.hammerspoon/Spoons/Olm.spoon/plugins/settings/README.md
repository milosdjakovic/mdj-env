# OLM settings

A friendly settings surface for choices that already live elsewhere in this config, with three
pages today. The first is where the OLM launcher appears, deciding which display the launcher
and every stage window land on, cursor or active window, the two modes the resolver in
`lib/overlaydisplay.lua` knows. The second is the colour theme, one choice among the theme
files under `config/themes`, kept by `lib/ui/themes.lua`. This page is the one place a person
sees or changes either. The third is the plugin switch, deciding which plugins run, with one
row per plugin under `plugins`.

It opens from the launcher only, as a row named OLM settings, with no leader key and no
shortcut of its own. Choosing it pushes the settings list onto the shared stage in place.
The top level shows up to three rows. Where the OLM launcher appears has a subtitle naming the live
choice. Theme has a subtitle naming the live theme. Plugins appears only when the root delivered the
plugin switch words, and its subtitle counts what is off. Choosing a row pushes a child page,
Back first, then the options, the current one marked with a green circle. On the theme page
there is one row per theme file, named for the file. Choosing an option writes the choice at
once and the page stays open with the marker moved, so switching back and forth costs no
reopening, and Backspace or Escape leaves whenever done.

A theme applies on the next draw, with no reload, since every surface asks the kit for its
colours each time it draws. The persisted choice lives in `hs.settings` under `olmTheme`. The
three words that carry it in, `themeName`, `themeNames` and `setTheme`, are published by the
root over the themes store, the same way the placement words are published over the overlay
resolver.

The Plugins page lists one row per plugin, sorted by title, a green circle when it is on and a
red one when it is off, with a subtitle saying so in words. A plugin switched off in config says
so and cannot be changed from here, and one that is off because a plugin it requires is off
names that plugin and comes back with it. Choosing any other row stages the change and nothing
else. The page stays open, the highlight stays on the row, the circle moves to the state after
apply and the subtitle says off after apply or on after apply, and a plugin that goes off or
comes back with it says so on its own row. Choosing the row again returns it to how it is now
and drops the staged change. While anything is staged an Apply now row sits right after Back,
naming every plugin that changes. Whether a plugin runs is decided once per load, so the staged
set is applied with one reload, either when the whole OLM window goes away by any route, escape,
a click away or a choice that closes it, or when Apply now is chosen. Going Back to the top
level is not a close and applies nothing. After a dismissal nothing reopens, since dismissing
means done, and one routine line after the reload names what changed. After Apply now the page
reopens on the plugin last chosen. Staged choices are held in memory until then, so a reload
from anything else, or quitting Hammerspoon, drops them. A refusal is said through the routine
feedback line rather than an alert. This is the
only page with a docked pane. For the highlighted plugin it shows the title and version, the
author, license and homepage when declared, what the plugin needs in short groups, and a line
naming what else goes off or comes back with it, measured against everything else staged and
taken from the root's own dry run of the plan. With nothing highlighted, on Back or Apply now,
the pane shows the shared empty state. The four root words behind it, `pluginCatalog`,
`pluginCascade`, `stagePluginSwitch` and `applyPluginSwitches`, come from
`lib/pluginswitch.lua`, and the place reopened after Apply now is a note this plugin hands the
root about itself, its own name, the step to this page and the plugin to highlight. `pluginspage.lua` builds the rows and the detail block as plain
data and kit nodes, and the shared docked pane, `lib/dockedpane.lua`, granted by `pane = true`,
is the canvas that draws them.
