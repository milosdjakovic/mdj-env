# ChordKey.spoon

The decision trail and the important facts for this spoon. Cross cutting
material, the leader key model and why each key is remapped to a function key,
stays in the hammerspoon `CLAUDE.md`, which links here. Thin adapters built over
this engine supply what each key means, and this file stays ignorant of which
they are.

## What it is

One shared `hs.eventtap` that turns a registered key into a hold, tap, chord
trigger. Each leader is added with `addKey`, giving its keycode plus overridable
hold and tap defaults and the callbacks `onTap`, `onHold`, `onHoldEnd`, and
`onKey`. The engine owns only the state machine, it swallows other keys while a
registered key is held, fires `onTap` on a quick release, and fires `onHold`
once the hold delay passes with no other key pressed. It names no domain, so the
adapters supply what a key means through `onKey`.

## Why one tap, not one per leader

A single tap serves every registered key, so N leaders cost one eventtap, not N.
A key can be defined and left unregistered, in which case it costs nothing until a
caller claims it. Keeping the mechanism here and the meaning in the adapters is why
adding a leader is cheap and why the adapters can share one resolver.

## Passthrough of unbound combos

With passthrough on, a held leader that resolves to no handler no longer swallows
the combo, it leaks it downstream as leader plus key so another eventtap based app
can bind what we leave free. Because the leader's own key down was already
swallowed, the engine synthesizes it once on the first unbound press, then
synthesizes the pressed key carrying its live modifiers, swallowing the real
events so the ordering is ours, and emits the matching ups on release so nothing
sticks. Synthetic events carry a non HID source id, so the same guard that ignores
a consumer's synthesized paste keeps these from looping back through the tap.

## Autorepeat, and why we inherit the OS timing

While a key is held macOS emits autorepeat key downs, after the system initial
delay and then at the system repeat rate. The engine receives them tagged with the
`keyboardEventAutorepeat` flag. The first press dispatches once. By default a
repeat is swallowed, because a chord is one discrete press and re-running a toggle
consumer would open and close it over and over while the key stays down.

A binding may opt into repeat. `onKey` returns two values, the resolved handler and
its `repeats` flag, and on a repeated key down the engine re-runs only handlers that
carry it. This is how a held nav key, such as a consumer's j or k, scrolls continuously,
exactly like a held arrow key, because the delay and rate are the OS autorepeat's
own, read live from System Settings, Keyboard, with no timing code here. We
rejected the alternative of reading `InitialKeyRepeat` and `KeyRepeat` at load and
driving our own `hs.timer`, since it duplicates what the OS already hands us, can
drift from the real setting, and would need a reload when the setting changes,
whereas honoring the OS events tracks a change with no reload. The overlay from a
long hold, if any, was already torn down on the first press, so a repeat dispatches
directly with no settle delay. Note the resolved pair must be captured without an
`and` guard, since `a and f()` truncates `f`'s two return values to one and the
`repeats` flag would be lost. Which actions actually opt in is a policy, decided in
the composition root in `init.lua`, not here.
