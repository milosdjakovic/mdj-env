# OLM settings

A friendly settings surface for choices that already live elsewhere in this config, with one
page today, where the OLM launcher appears, deciding which display the launcher and every
stage window land on, cursor or active window, the two modes the resolver in
`lib/overlaydisplay.lua` knows. This page is the one place a person sees or changes either.

It opens from the launcher only, as a row named OLM settings, with no leader key and no
shortcut of its own. Choosing it pushes the settings list onto the shared stage in place.
The top level shows one row, Where the OLM launcher appears, its subtitle naming the live
choice. Choosing that row pushes a child page, Back first, then the two options, the current
one marked with a green circle. Choosing an option writes the choice at once and the page
stays open with the marker moved, so switching back and forth costs no reopening, and
Backspace or Escape leaves whenever done.
