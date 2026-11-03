# Olm Theme

Picks the look of the chooser in use. Each chooser says what it offers, and this list shows
whichever rows the serving one offers without knowing which that is. The canvas chooser offers
every theme file under `config/themes`, the whole of every colour, kept by `lib/ui/themes.lua` and
persisted in `hs.settings` under `olmTheme`. The glass chooser carries its own palette and offers
only its highlight, Olm Highlight, the soft wash its palette gives a row, or macOS Highlight, the
accent colour set in System Settings, persisted under `olmGlassHighlight`. `lib/ui/appearance.lua`
holds both, and Olm Chooser picks which chooser serves.

It opens from the launcher only, as the Olm Theme row, with no key of its own, and the list
replaces the launcher's rows in place. The field names what the list offers, Canvas Theme or Glass
Highlight. The live choice wears Olm's filled ring and every other an empty one. Choosing one
applies it on the next draw with no reload, since every surface asks the kit for its colours each
time it draws, and the list stays open with the ring moved. A change of accent colour in System
Settings reaches macOS Highlight at once. Backspace or Escape leaves.
