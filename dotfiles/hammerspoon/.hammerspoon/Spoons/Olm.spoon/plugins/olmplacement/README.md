# Olm Placement

Decides which display the Olm launcher and every stage window appear on, where the mouse cursor
is or with the active window, the two modes the resolver in `lib/overlaydisplay.lua` knows. This
list is the one place a person sees or changes it.

It opens from the launcher only, as the Olm Placement row, with no key of its own, and the list
replaces the launcher's rows in place. The two options show the live one with a green circle.
Choosing one writes it at once and the list stays open with the marker moved, so switching back
and forth costs no reopening, and Backspace or Escape leaves whenever done.
