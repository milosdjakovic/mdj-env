# Settings

A friendly settings surface for choices that already live elsewhere in this config, with one
page today, window placement, deciding which display the launcher and every stage window
land on, cursor or active window, the two everyday picks over the resolver's own three modes
in `lib/overlaydisplay.lua`. Fixed pinning stays on the existing Overlay Display picker, since
a pin is keyed by display arrangement and this page has no way to name one.

It opens from the launcher only, as a row named Settings, with no leader key and no shortcut
of its own. Choosing it pushes the settings list onto the shared stage in place. The top level
shows one row, Window placement, its subtitle naming the live choice. Choosing that row pushes
a child page, Back first, then the two options, the current one marked with a green circle. When
the live mode is a pin, set through the Overlay Display picker, neither option is current, so an
inert row between Back and the options names the pin instead. Choosing an option writes the
choice at once and the page stays open with the marker moved, so switching back and forth costs
no reopening, and Backspace or Escape leaves whenever done.
