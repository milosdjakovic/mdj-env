# Olm leader keys

Status. Caps Lock stays F18 through hidutil, and a held leader is released whenever secure input
is on or the tap was disabled, because typing after a lost key-up used to keep it held forever.
Every leader is configurable since `docs/PLAN-LEADERS.md` completed on 2026-10-22, so Hyper may
also be the four real modifiers with its keys, list keys and sheet intact.

## Now

A held leader is a function key remapped by hidutil, F18 for Caps Lock and F16 for Right
Option, read by one event tap in `lib/chordkey.lua`. A function key is not a modifier, so macOS
cannot be asked whether it is down and the engine remembers the hold instead. Two checks keep that
memory honest. A thirty second staleness window releases a hold that has gone silent, and since
2026-10-22 a check that runs only while a leader is held releases every hold within a quarter of a
second once `hs.eventtap.isSecureInputEnabled()` answers true or the tap is no longer enabled,
starting the tap again in the second case. Each recovery writes one ChordKey console line naming
its cause. Hyper does nothing in a password field, since secure input hides every tap, and no
code at this layer changes that. Since phase 3 of `docs/PLAN-LEADERS.md` a person may instead
write Hyper as the four real modifiers, the form Karabiner produces, and it keeps its roles, its
list keys and its behaviour, with Caps Lock then left unremapped.

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

### 2026-10-22 14:43

Phase 1 of `docs/PLAN-LEADERS.md` landed. `policy.leaderCatalog` and `policy.leaderPolicy` are
one shipped leaders table, a person's entry is laid over it in two halves and no name is reserved,
and the function key each source is remapped to lives in `lib/keyremap.lua`. Three choices were
made while building. An entry carrying neither `mods` nor `key` on a shipped name keeps the
shipped kind and merges its behaviour, since otherwise a behaviour only override would be
impossible. A held leader's identity inside the root stays its name upper cased. A behaviour field
on a new modifier leader is ignored with a problem line until phase 3. A renamed parameter in
`KeyRemap:apply` left the loop reading a name never set, so a live load would have remapped
nothing, and every offline gate stubs that call. It was caught in review, and `test/keyremap.lua`
now pins the command. The live load on the worktree was clean, hidutil held Caps Lock to F18 and
Right Option to F16, and Milos confirmed the launcher, the sheet and the Caps Lock tap.

### 2026-10-22 15:09

Phase 2 landed. A held leader's `key` comes from an allow list, Caps Lock, the three right
modifiers and F13 to F20, which is `USAGE` in `lib/keyremap.lua`, and anything else is a problem
line. F13 to F20 are heard as they are. The others are remapped to `remapTo`, then their preferred
key, then the first free one, by a pure `allocate` in the same file, with a note when a preference
is taken. `remapTo` must sit beside `key`, since the two replace together. In a conflict the
person's entry is dropped and the leader keeps its shipped trigger, and a pin wins over another
leader's preference. A lone tap toggles Caps Lock only when the key is Caps Lock, decided in the
held trigger, and `tapTogglesCapsLock` is retired with a problem line. Every existing golden is
unchanged, `keymap-fixture-heldkeys` is new, and `test/keyremap.lua` tests the allocation and
the real command. The live load was clean, hidutil held only Caps Lock to F18 and Right Option to
F16, and Milos confirmed the launcher, the sheet and the tap.

### 2026-10-22 15:40

Phase 3 landed. A shipped name may change kind, so `hyper = { mods = { "shift", "ctrl", "alt",
"cmd" } }` is a modifier Hyper that keeps its shipped behaviour and leaves the remap. Every leader
is now known inside the root by its name upper cased whatever its kind, which is what kept every
existing golden identical, and roles and the list role land on any leader. Behaviour fields reach a
modifier leader, and under `drivenRepeat` its hotkey hands a repeating handler its depth. A sheet on
one is a routine note until phase 4. Before building the seal, a probe in the live config posted one
synthetic chord with a key down tap and an `hs.hotkey` both on it. The tap saw the chord first, and
when it swallowed the chord the hotkey never fired. So no open and close signal was needed. A
modifier leader hosting a list key says `sealsOverLists`, which covers the legacy chooser where its
hotkey still fires, and over the default chooser the root's field watcher claims any other chord
under it, so Hyper and a digit or an arrow no longer picks or moves a row. Milos accepted one limit
of a four modifier Hyper. A binding that adds a modifier Hyper already holds is the same press as
the plain one, which on this keymap is Hyper Shift 4 and the Hyper Command j and k preview scroll in
the clipboard and file search, so the existing warning names each and a person moves them in
`config/keymap.lua`. `keymap-fixture-modhyper` and its goldens are new, the live load was clean,
hidutil held only Caps Lock to F18 and Right Option to F16, and Milos confirmed the launcher, the
sheet and the tap.

### 2026-10-22 16:10

The four modifier Hyper was loaded live from the worktree, with the Hyper line set in its
`config/keymap.lua` only and reverted afterwards. The console held the five overlap problems
accepted at 15:40 and nothing else, and hidutil held Right Option to F16 alone. Holding Shift,
Control, Option and Command by hand, Milos confirmed the launcher on Space, an app toggle, j and k
moving the launcher's highlight, an app letter, a digit and an arrow doing nothing over the open
launcher, and Caps Lock toggling as a plain key.

### 2026-10-22 16:59

Phase 4 landed, the last phase of `docs/PLAN-LEADERS.md`. A modifier leader whose entry states a
sheet runs one event tap over flags changes and key downs that only observes, answering false to
every event. Exactly its set of shift, ctrl, alt and cmd held for the hold delay with no key shows
the sheet, fn and caps lock counting neither way, and any key or any change of the set hides it.
While the sheet is up a poll asks the live modifiers four times a second and hides it once they no
longer match, since a tap can miss a release under secure input and real modifiers can always be
asked. Review found that the poll left the tap's memory of the last set stale, so a press arriving
as one event naming the same set would never arm again, and the poll now forgets it, pinned by a
test that fails without the line. The leader sheet host finds a sheet by keycode for a held leader
and by name for a modifier one. The live load was clean apart from the five overlaps accepted at
15:40, and holding the four modifiers by hand Milos confirmed the sheet appearing, hiding on a
released modifier and on an app letter, staying away for Shift and Control or Command and Option
and over the open launcher, and no flash on a quick shortcut. The plan is complete. A macOS tap
disabled by a timeout is not re enabled here, since this tap only observes and returns at once.

### 2026-10-22 23:44

Phase 0 of `docs/PLAN-MACHINES.md`, measuring kanata 1.12.0 against Olm's hidutil remap with the
stowed main config live. Kanata's debug log and a Hammerspoon tap logging key codes and flags
were read side by side while Milos pressed each key by hand. Kanata reads the physical keyboard
before hidutil, since it saw `KEY_CAPSLOCK` and `KEY_RIGHTALT` while hidutil mapped them to F18
and F16. What kanata sent back was not remapped either. A Caps Lock tap reached macOS as Caps
Lock itself and toggled it directly, with no F18 and no part for Olm, and a hold reached it as
the four modifiers alone. Right Option held arrived as shift, ctrl and alt with no F16. No press
produced both forms, so one press cannot fire a leader twice. Phase 1 can keep the remap on every
machine, and the Composite needs no guard against a double fire.

The first attempt measured nothing. The Karabiner driver daemon had stopped since the trial, so
kanata waited ten seconds for the virtual keyboard, then released the keyboard and ran without
remapping, and Caps Lock arrived as F18 through Olm the whole time. That is the fallback the
Composite is chosen for, observed rather than argued, and it is why phase 3 runs the daemon under
launchd. Hammerspoon was loaded before kanata started in the run that counted. Whether a reload
while kanata runs lays the remap over the virtual keyboard was not checked. If it does, a tap
arrives as F18 and Olm's held engine toggles Caps Lock itself, which is still one toggle, and the
phase 1 live check confirms it.
