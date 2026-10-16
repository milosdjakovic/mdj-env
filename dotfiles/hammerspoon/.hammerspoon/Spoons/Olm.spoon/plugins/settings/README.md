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
names that plugin and comes back with it. Choosing any other row switches it at once and the
page stays where it is. The switch is saved and one reload is scheduled, since whether a plugin
runs is decided once per load, so the circle moves now and the plugin itself follows with the
reload. A refusal is said through the routine feedback line rather than an alert. This is the
only page with a docked pane. For the highlighted plugin it shows the title and version, the
author, license and homepage when declared, what the plugin needs in short groups, and a line
naming what else goes off or comes back with it, taken from the root's own dry run of the plan.
With nothing highlighted, on Back, the pane shows the shared empty state. The four root words
behind it, `pluginCatalog`, `disabledPlugins`, `pluginCascade` and `setPluginDisabled`, come
from `lib/pluginswitch.lua`. `pluginspage.lua` builds the rows and the detail block as plain
data and kit nodes, and `pane.lua` is the canvas that draws them.
