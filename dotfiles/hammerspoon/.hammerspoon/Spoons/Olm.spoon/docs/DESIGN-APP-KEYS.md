# Keys in Olm.app

Written on 2026-11-20 for stage 5 of `docs/PLAN-STANDALONE.md`, once Milos said go to keys coming
before the rest of stage 4. Nothing stands alone while Hammerspoon binds the keys, so this note
says how the app comes to hear them, own them, and draw their cheat sheets, one step at a time
with Hammerspoon binding every key until a step moves one.

## What is ported and what is read

**The keymap stays compiled in Lua until stage 8.** `lib/keymap.lua` reads `config/keymap.lua`,
lays the person's keys over every manifest's defaults, checks collisions and answers the bound rows
the binder walks. That is nearly two thousand lines of policy over Lua files, and the app does not
need it to hear a key. Hammerspoon writes what it compiled, the bound rows and the leaders in use,
to `~/.olm/run/keymap.json` on every load, and the app reads that. Who compiles the keymap once
Hammerspoon is gone is stage 8's question, where Olm Settings or a file the app reads takes over.

**The engine is ported.** What turns a press into an action is the app's: the three triggers,
a held key, a set of modifiers and the composite of both, the resolver's two tier rules from
`lib/leader.lua`, `ranked` and the first exact match, a row's gate answered live, and later the
hold that reveals a sheet, the tap that toggles Caps Lock and the two repeat modes. The keys
fixtures of 0.3c to 0.3e record the keymap builder, so they stay Lua's. 0.3f, the chord engine's
timing, is recorded when the app first owns a tap or a hold, step 5.3, since shadowing hears
presses and times nothing.

## How the app hears a key

**A listen only event tap at the HID level.** It is the earliest place a key is seen as a keyboard
event, after hidutil's remap and after kanata, and before Hammerspoon's own tap and its hotkeys,
so it sees a key Hammerspoon then swallows or claims. A listen only tap changes nothing and can
delay nothing, since it is handed a copy. It needs the Input Monitoring grant, Olm.app's first, and
without it the app logs once that it cannot hear keys and shadows nothing.

**The two kinds of leader as this machine sends them.** With the `kanata` piece on, Hyper arrives
as shift, ctrl, alt and cmd and META as shift, ctrl and alt, real modifiers on every key. Without
kanata, or with kanata stopped, Caps Lock arrives as F18 and Right Option as F16 through
`lib/keyremap.lua`'s remap, and a held function key is remembered from its down to its up. Every
leader in use is handed over with both, so the app reads whichever arrives, as the composite does.

## Shadow, step 5.1

The app resolves every press against the bound rows as the Lua leader would and logs what it would
run. Hammerspoon tells the app every global row it ran, the notification `keyFired` with the action
and the chord, and the app pairs the two within 300 ms. A press the app resolved that Hammerspoon
did not run, and a run the app did not resolve, are each one line in `~/.olm/log/shadow-keys.jsonl`.
The gate is that log empty through a day of ordinary use. A press while one of the app's lists is
open is left out, since a list's own keys answer first there and the app's lists are the app's
already, and a press while a Lua list is open is logged as such rather than as a difference.

Only presses are shadowed. A key held to repeat and the depth a driven repeat hands its handler are
timing, measured at 5.3.

## Owning a key, step 5.3

Ownership moves one leader at a time, META first, then Hyper, then the plain combos. The keymap
names the owner of every row, and the binder skips a row the app owns, so a chord is never bound
twice. A row whose action is still Hammerspoon's is run over the bridge, `run` with the action id.

**A modifier chord is claimed with Carbon's `RegisterEventHotKey`.** It is the interface
`hs.hotkey` itself stands on, needs no grant, and a hotkey on real modifiers is delivered while
another app holds secure input, which a tap is not. So on a kanata machine Hyper would work in a
password field for the first time. That is believed rather than measured, and 5.3 measures it with
Milos over a browser's password field before anything depends on it.

**A held function key needs an active tap,** since F18 is no modifier and only a tap can swallow
the key pressed under it. That is Input Monitoring again, and the same blindness in a password
field Hammerspoon has today, `decisions/olm-leader-keys.md`.

## Cheat sheets, step 5.2

Drawn by the app from the same rows `lib/hints.lua`'s `sheetRows` reads, shared beside the keymap,
in the swift library's own panel drawing, while Hammerspoon still binds every key and still decides
when a sheet shows. The goldens of each sheet are compared with what the app draws.

## As built

**5.1, the keys in shadow, built 2026-11-20.**

- **Hammerspoon's half** is `lib/keyshare.lua`, pure and pinned by `test/keyshare.lua`. The root
  writes its share as `keymap.json` and hands the binder a copy of the bound rows whose runs send
  `keyFired`, so the keymap's own rows, which the launcher and the sheets read, tell the app
  nothing. `docs/PROTOCOL-BRIDGE.md` The keys has the shape.
- **The app's half** is `app/Sources/OlmKeys`. `Keymap` reads the share, `Resolver` is the port of
  `_resolve`'s global pass and the three triggers, `KeyTap` the listen only tap on a thread of its
  own that keeps trying every ten seconds until Input Monitoring is given, and `KeyShadow` the
  pairing on a queue of its own. The app asks for Input Monitoring once, with macOS's own prompt, at
  launch.
- **Pairing.** A press and a run of the same row within a second are one, in either order, and a
  row that runs once its leader is released waits ten. A repeating row's runs while its key is down,
  and for a quarter second after it comes up, are its press, since a system repeat calls the
  handler exactly as a press does and Hammerspoon cannot tell them apart. Presses while one of the
  app's lists is up, and for 300 ms after, are left out on both sides. The one gate the app answers
  itself is `multipleDisplays`, and any other is taken as open and said once, as the Lua leader takes
  an unknown one.
- **The check** is `test/olmkeys.sh`, in `suite.sh dry`, 30 cases, the triggers, both tier rules,
  the gates, the share's parsing and the pairing with each kind of line it logs.
- **What the trial reads.** `~/.olm/log/shadow-keys.jsonl` for the differences and
  `~/.olm/log/shadow-keys-count.json` for how many presses were heard and paired since the app
  started, so an empty log is read beside the presses it covered.

**5.2, the cheat sheets drawn by the app, built 2026-11-20.**

- **What moved is the window, not the layout.** `lib/cheatsheet.lua` still lays each sheet out and
  `lib/panel.lua` still places it, centred on the screen the overlay policy picks, and reduces it to
  hs.canvas elements. A panel may now carry its own drawing backend, and the cheat sheet's is the
  bridge's, `obj:sheetBackend()`, a router over the backend Hammerspoon drew with before and one that
  sends the frame, the surface's corner and the content elements to the app as the notification
  `sheet`, and `sheet` with `hide` when the leader is released. The app draws them in
  `app/Sources/OlmCore/SheetHost.swift` on the swift chooser's own panel window, `PanePanel` with a
  panel's config, the window Hammerspoon's native backend already used, read by the same
  `PaneElements` reader a hosted list's preview pane is, step 3.3d. So the app's sheet is the Lua
  sheet element for element, which is what comparing with the goldens would have checked.
- **The switch** is `sheetsInApp` in `config/plugins.lua`. While the socket is down, or the switch is
  off, Hammerspoon draws the sheet as before.
- **Checked** by `test/bridge.lua`, a show and a hide sent, and the configured backend drawing with
  the session gone or the switch off, and `test/panelbackends.lua`, a panel's own backend handed the
  configured factory. An element the app cannot draw is logged once by name, in Hammerspoon when it
  cannot cross and in the app when it cannot be read.

## Rejected

- **Porting `lib/keymap.lua` to Swift now.** 2026-11-20. It reads Lua config, and the app needs only
  its answer. Porting it is stage 8's question, once nothing else reads the Lua files.
- **Hammerspoon forwarding every key event to the app over the bridge.** 2026-11-20. It would shadow
  the resolver and never the hearing, which is the part that can fail, and it costs a message per
  key on the one thread that must stay free.
- **IOHIDManager for hearing.** 2026-11-20. It reads a device's values before hidutil's remap and
  beside kanata's seized device, so the app would have to redo both.
- **Porting the sheet's grid to Swift at 5.2.** 2026-11-20. The layout reads the kit's tokens and the
  keymap's sections, both Lua's until stage 8, and the elements it answers already cross for the
  preview pane, so the app draws the very sheet with no second layout to keep in step. A port is
  stage 8's, with the keymap's.
- **Claiming a modifier chord with an active event tap.** 2026-11-20. Carbon's hotkey needs no grant
  and is believed to work under secure input, where a tap is blind.

## Steps

1. **5.1 Shadow.** Hammerspoon writes `keymap.json` and sends `keyFired`. `app/Sources/OlmKeys`
   reads the keymap, hears through the tap, resolves, pairs and logs. Trial: Milos grants Input
   Monitoring, uses the Mac for a day, and the log stays empty.
2. **5.2 Cheat sheets in the app.**
3. **5.3 Ownership,** META, then Hyper, with 0.3f recorded first and the secure input measurement.
4. **5.4 The key daemon,** optional.

## Open questions

1. Whether a listen only tap at the HID level sees a key Hammerspoon's session tap swallows and one
   its hotkeys claim, as believed. 5.1's trial answers it, an empty log with keys pressed being yes.
2. Whether Carbon hotkeys on real modifiers fire under secure input on macOS 27. 5.3 measures it.
