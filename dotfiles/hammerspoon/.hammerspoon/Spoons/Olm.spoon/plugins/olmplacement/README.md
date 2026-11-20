# Olm Placement

Decides which display the Olm launcher and every stage window appear on, where the mouse cursor
is or with the active window, the two modes the resolver in `lib/overlaydisplay.lua` knows. This
list is the one place a person sees or changes it.

The same choice is the Placement setting in Olm Settings, which took this list's launcher row on
2026-11-20. The list opens only on a key a person gives `olmplacement.open` in `config/keymap.lua`,
which is how a machine without Olm.app changes it. The two options wear Olm's radio pair, the live one filled.
Choosing one writes it at once and the list stays open with the marker moved, so switching back
and forth costs no reopening, and Backspace or Escape leaves whenever done.
