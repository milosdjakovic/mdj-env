# Olm leader keys

Status. Caps Lock stays F18 through hidutil, and a held leader is released whenever secure input
is on or the tap was disabled, because typing after a lost key-up used to keep it held forever.

## Now

A held leader is a function key remapped by hidutil, F18 for Caps Lock and F16 for Right
Option, read by one event tap in `lib/chordkey.lua`. A function key is not a modifier, so macOS
cannot be asked whether it is down and the engine remembers the hold instead. Two checks keep that
memory honest. A thirty second staleness window releases a hold that has gone silent, and since
2026-10-22 a check that runs only while a leader is held releases every hold within a quarter of a
second once `hs.eventtap.isSecureInputEnabled()` answers true or the tap is no longer enabled,
starting the tap again in the second case. Each recovery writes one ChordKey console line naming
its cause. Hyper does nothing in a password field, since secure input hides every tap, and no
code at this layer changes that.

## Rejected

- **F17 or F16 in place of F18.** 2026-10-22. None of them is a modifier, so each fails in a
  password field and needs a remembered hold exactly as F18 does.
- **Caps Lock as four real modifiers through hidutil.** 2026-09-06, measured. hidutil stores
  four rows sharing one source and then emits exactly one of them per press, a different one on
  different holds.
- **Caps Lock as four real modifiers through Karabiner Elements.** 2026-09-06, reaffirmed
  2026-10-22. Its driver sits below secure input and is the only route to a real Hyper on one key,
  but Milos chose not to take on the driver, and a modifier leader has no cheat sheet, no tap and
  no role today. Reopening it means lifting those three limits of the modifier trigger first.
  Reopened in part 2026-10-22 14:22. `docs/PLAN-LEADERS.md` lifts the three limits so a Hyper of
  four real modifiers works in Olm, while installing Karabiner stays outside the plan.
- **Adding Fn to a modifier Hyper.** 2026-10-22. `hs.hotkey` cannot claim fn, and macOS already
  answers fn with letters and arrows itself.
- **Stamping the four modifiers onto every key while F18 is held.** 2026-10-22, discussed and not
  built. It is still a tap, so a password field receives plain letters and a lost key-up still
  sticks, and macOS never sees the modifiers as held.
- **Moving to Hammerspoon2 for this.** 2026-10-22, read at its repository that day. It offers no
  way to make a key a modifier. It does offer fn and side specific modifiers on its tap hotkeys,
  and the secure input query this fix uses, and it is scripted in JavaScript, so moving would be
  a rewrite.
- **Asking the keyboard whether F18 is down through a compiled helper.** 2026-10-22, measured
  and turned down. `CGEventSource.keyState(.hidSystemState, key: 79)` sees the remapped key as
  F18 in an ordinary hold, but it saw nothing for a whole hold while secure input was on, and it
  also missed a hold made seconds after secure input turned off with the browser in front. A
  helper that can miss a held key could also release one a finger is still on, so it is not the
  ground truth it was meant to be. The log below has the runs.
- **Leader behaviour in a separate policy section.** 2026-10-22 14:22. It would keep the leaders
  section about physical keys only, but one leader would then be read in two places, so behaviour
  sits in the leader's own entry.
- **Telling the two kinds of leader apart by the shape of the entry.** 2026-10-22 14:22. A bare
  list for modifiers and a `key` field for a held key was the first draft, and it made Olm guess
  from a shape. `mods` and `key` state the kind.
- **`as`, `via` or `sends` for pinning the remapped function key.** 2026-10-22 14:22. `as` is vague
  about what it does, and `via` and `sends` read less directly than `remapTo`.
- **A letter, or any key, as a held leader, with only dangerous keys blocked.** 2026-10-22 14:22. A
  block list has to guess every key that is dangerous, and a letter as a leader taxes every word
  typed with it. An allow list of Caps Lock, the right modifiers and F13 to F20 only has to know
  what is safe, and extra hardware reaches it by sending F13 to F20 from its own firmware.

## Log

### 2026-09-06 12:51

8ecfa51f. A lost key-up left a leader held forever. The staleness watchdog was added, timed off
the machine's key repeat delay and refreshed by the leader's own autorepeat, and the release was
reordered so a consumer callback could no longer strand the engine. Secure input was measured the
same day as blanking every tap while a password field has focus.

### 2026-09-07 10:12

68988dfd. The watchdog released a leader held over a list the moment a chord key was pressed,
since macOS autorepeats only the newest key. The window became a flat thirty seconds and every
key reaching the tap during a hold began to refresh it. Corrected 2026-10-22, see below.

### 2026-10-22 13:10

The refresh on every key reopened the stuck Caps Lock. Once a key-up is lost, every key typed
afterwards reads as a chord and pushes the window out, so the leader stays held for as long as the
person keeps typing. A check now runs only while a leader is held and releases every hold when
secure input is on or the tap was disabled, without toggling Caps Lock, and `test/chordkey.lua`
pins it, failing ten of its twenty three checks against the engine before the change. The live
reload was clean. The cause of the reported sticking is not yet known, and the console line names
it the next time it happens.

### 2026-10-22 13:54

The key state helper was measured before being built, with a probe printing F18, Caps Lock and
`IsSecureEventInputEnabled()` ten times a second while Milos held Caps Lock. With the terminal in
front it reported F18 down at 1.3s and up at 5.9s, and Caps Lock never, so the remap is visible.
In a browser password field secure input was on from 1.8s to 19.8s and a two second hold inside
that span never showed, and a second hold made after clicking out of the field, while secure input
read off, never showed either. Which of a lingering blindness after secure input or the app in
front explains the second miss was not settled, since either way the helper cannot be trusted and
it was dropped. The probe source was a scratch file and is not kept.

### 2026-10-22 14:22

`docs/PLAN-LEADERS.md` is written and agreed. Every leader becomes configurable in one leaders
table with no reserved names, an entry naming its kind with `mods` or `key` and carrying its own
behaviour, the shipped Hyper, Meta and Super as defaults in that table, `remapTo` to pin a remapped
function key, and an allow list of Caps Lock, the three right modifiers and F13 to F20 for a held
key. A Hyper of four real modifiers then keeps its roles, list keys, sealing over lists and sheet.
Nothing is built yet, and the Now section changes as each phase lands.
