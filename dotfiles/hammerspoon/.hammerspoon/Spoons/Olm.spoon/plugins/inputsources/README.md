# Input Sources

Lists the keyboard layouts enabled in System Settings by recent use, the one in use first and
marked by a green circle, and makes the chosen one current.

A tap of fn cycles the list the way Command and Tab does, through the `cycle` row in its manifest.
The first tap shows the list bare, rows only, on the layout used before, each further tap moves
down and wraps, and the list switches to the highlighted layout a moment after the last tap. An
arrow keeps it open for a choice, Escape closes it without switching, and any other key switches
and lands in the app underneath in the new layout. Olm does all of that, the plugin only answers
its rows and its choice. With the plugin switched off in `config/plugins.lua`, nothing binds the
Globe key and a tap of fn does whatever the Globe key setting in System Settings says. The same
list opens in full, searchable, from its launcher row or its alias and a space, and the Previous
Input Source action has a launcher row of its own.

In the list, choosing a row switches to it and closes the list.
