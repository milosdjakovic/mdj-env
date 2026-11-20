# Olm Chooser

Picks which chooser draws every Olm list, Glass, the native panel on macOS glass, or Canvas, the
panel Olm draws itself. Each chooser provider declares its own title and how far it can be themed,
and this list reads only the titles, so it never learns a provider's name. The choice is persisted
in `hs.settings` under `olmChooser` and wins over `chooser.provider` in `config/settings.lua`,
which stays the default for a machine that never chose. What each chooser lets a person change is
the Olm Theme list, a theme on the canvas and a highlight on the glass.

The same choice is the Chooser setting in Olm Settings, which took this list's launcher row on
2026-11-20. The list opens only on a key a person gives `olmchooser.open` in `config/keymap.lua`,
which is how a machine without Olm.app changes it. The chooser in use wears Olm's filled ring. Choosing the
other one reloads Olm, since the chooser is decided once per load, and the next list opens in it.
Backspace or Escape leaves.
