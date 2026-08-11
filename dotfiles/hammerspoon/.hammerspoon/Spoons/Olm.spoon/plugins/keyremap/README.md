# KeyRemap

Remaps physical keys at the hardware level so an otherwise unused key can act as
a leader for other tools. Caps Lock, Right Option, and Right Command become
spare function keys the moment something else in this config actually uses them,
and revert to their ordinary selves the moment Hammerspoon quits or reloads.

It runs once at load with no key of its own and nothing to open. Every leader it
enables, the Hyper key and the window leader among them, is a tool described in
its own file.
