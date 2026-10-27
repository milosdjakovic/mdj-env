# Olm Theme

Picks the colour theme every Olm list, pane and sheet is drawn in, one row per theme file under
`config/themes`, kept by `lib/ui/themes.lua`. The persisted choice lives in `hs.settings` under
`olmTheme`.

It opens from the launcher only, as the Olm Theme row, with no key of its own, and the list
replaces the launcher's rows in place. The live theme carries a green circle. Choosing a theme
applies it on the next draw with no reload, since every surface asks the kit for its colours each
time it draws, and the list stays open with the marker moved. Backspace or Escape leaves.
