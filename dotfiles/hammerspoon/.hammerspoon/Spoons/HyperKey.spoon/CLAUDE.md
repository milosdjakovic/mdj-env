# HyperKey.spoon

The decision trail and the important facts for this spoon. Cross cutting
material, the leader key model, stays in the hammerspoon `CLAUDE.md`, which links
here. The hold, tap, chord mechanics live in `ChordKey.spoon`, the engine this
spoon is a thin adapter over.

## What it is

A domain adapter that turns one physical key, Caps Lock remapped to F18, into a
Hyper trigger for app toggle style bindings, a key to function map, with a quick
tap falling back to the real Caps Lock toggle. It keeps a stable public contract,
`bind` and `isActive`, that `AppToggler` and `ClipboardHistory` depend on, so
removing the Hyper key degrades those gracefully rather than breaking them. It
owns only the binding table and the tap policy and registers its key into the
shared engine through `opts.chord`, so the state machine is never duplicated here.

## The resolver, shared with WindowLeader

A binding may require exact sub modifiers, so one key hosts two tiers, Hyper plus 4
does one thing while Hyper plus Shift plus 4 does another. Resolution compares only
the real modifiers shift, ctrl, alt, and cmd, deliberately ignoring the `fn` flag
macOS stamps onto some keys, since a raw exact check would never match. An exact
mods match beats a catch all binding with no mods, and within a tier the highest
priority wins. This is the same policy `WindowLeader` uses, kept identical so both
adapters over the one engine behave the same, which is why Hyper plus Shift plus a
key can differ from Hyper plus that key in both.

## Modal contexts

When a binding carries a `when` predicate and that predicate is live, the Hyper key
becomes modal, owned by that context, and the base bindings with no `when` are
suppressed. This is what makes a context modal rather than an overlay, so while the
clipboard is open Hyper plus A does nothing instead of toggling an app. An unknown
predicate name is treated as active, so a typo fails visibly, the key stays live,
rather than silently disabling a binding.

## The repeats flag

`bind` accepts an optional `repeats` in its opts and stores it on the binding, and
`_resolve` returns it as a second value alongside the chosen handler. `onKey` tail
returns both to `ChordKey`, so the engine can decide whether to re-run the handler
on each OS autorepeat. This spoon only carries the flag through, it makes no policy
choice. The decision of which actions repeat, the chooser nav and preview scroll
but not the toggles, lives in the composition root in `init.lua`, so `config/keys.lua`
stays pure key to action data and the action semantics are decided in one place.
See `ChordKey.spoon/CLAUDE.md` for how the engine consumes the flag and why the
timing is the OS autorepeat's own.
