# OLM settings

A friendly settings surface for choices that already live elsewhere in this config, with two
pages today. The first is where the OLM launcher appears, deciding which display the launcher
and every stage window land on, cursor or active window, the two modes the resolver in
`lib/overlaydisplay.lua` knows. The second is the colour theme, one choice among the theme
files under `config/themes`, kept by `lib/ui/themes.lua`. This page is the one place a person
sees or changes either.

It opens from the launcher only, as a row named OLM settings, with no leader key and no
shortcut of its own. Choosing it pushes the settings list onto the shared stage in place.
The top level shows two rows. Where the OLM launcher appears has a subtitle naming the live
choice. Theme has a subtitle naming the live theme. Choosing either row pushes a child page,
Back first, then the options, the current one marked with a green circle. On the theme page
there is one row per theme file, named for the file. Choosing an option writes the choice at
once and the page stays open with the marker moved, so switching back and forth costs no
reopening, and Backspace or Escape leaves whenever done.

A theme applies on the next draw, with no reload, since every surface asks the kit for its
colours each time it draws. The persisted choice lives in `hs.settings` under `olmTheme`. The
three words that carry it in, `themeName`, `themeNames` and `setTheme`, are published by the
root over the themes store, the same way the placement words are published over the overlay
resolver.
