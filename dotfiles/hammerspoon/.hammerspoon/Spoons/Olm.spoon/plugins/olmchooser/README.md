# Olm Chooser

Picks which chooser draws every Olm list, Glass, the native panel on macOS glass, or Canvas, the
panel Olm draws itself. Each chooser provider declares its own title and how far it can be themed,
and this list reads only the titles, so it never learns a provider's name. The choice is persisted
in `hs.settings` under `olmChooser` and wins over `chooser.provider` in `config/settings.lua`,
which stays the default for a machine that never chose. What each chooser lets a person change is
the Olm Theme list, a theme on the canvas and a highlight on the glass.

It opens from the launcher only, as the Olm Chooser row, with no key of its own, and the list
replaces the launcher's rows in place. The chooser in use wears Olm's filled ring. Choosing the
other one reloads Olm, since the chooser is decided once per load, and the next list opens in it.
Backspace or Escape leaves.
