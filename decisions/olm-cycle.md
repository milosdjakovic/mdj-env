# Olm cycle, a list stepped by one repeated key

Status. On main since 2026-10-26, and the Globe key rule for the person's own keymap merged on
2026-10-28, when Milos closed the trial under the test lock with the live questions in the Now
section still unanswered. Input Sources is the first and only list that declares it.

## Now

A plugin with a presentation may suggest a `defaults.bindings` row whose action is `cycle`. The
keymap binds it the way it binds an `open` row, to a function the root answers, and the press
runs `Stage:cycle` rather than `Stage:present`. The first press shows the presentation bare, the
default chooser's list alone with no field and no action bar and no peek row, with the highlight
on row two, since a cycled list is ordered by recent use and row one is where the person already
is. Each further press of the same key steps the highlight down one row, wrapping. 0.8 seconds
after the last press the list completes on the highlighted row through the presentation's own
`select`, the same completion Return gives. An arrow or the pointer stops that and the list waits.
Escape closes without completing. Any other key completes the list and is posted again 50
milliseconds later into the app underneath, built afresh after the completion so it carries the
characters of a keyboard layout the completion switched to.

The same presentation opened through `open`, the launcher row or the alias is the full list,
searched as before, so how a list is shown follows the door and is never a plugin field. The bare
posture is `setPosture` on the default provider, applied by the stage through the same hide and
reshow a row count change takes. The Globe key, code 179, which macOS posts for a tap of fn, is
named `globe` by `lib/keycodes.lua`, the key table every reader of a key name now uses, and is the
one standalone key, which a row may bind with neither a leader nor a modifier. A row with no
leader that states no modifiers means none, never a catch all, and the person's keymap may name
`globe` alone, so `config/keymap.lua` can move a binding onto the Globe key or free it. The plain leader
claims it as an `hs.hotkey` by code. With the plugin switched off nothing binds it and macOS
answers a tap of fn with its own Globe key setting.

## Rejected

- **The plugin driving the cycle itself.** 2026-10-26. The first build, on 2026-10-25, had the
  Input Sources plugin install an event tap for the Globe key, a second tap started after the
  chooser's field so it heard typed keys first, its own close timer, a typed key reposted by hand,
  and a highlight it tracked against a counter of its own. It worked, and Milos asked whether it
  respected the structure. It did not. The shared field carried a special case for one plugin's
  key, a new root word `stageSelectNext` let a plugin move the highlight, the tap order it relied
  on was nowhere documented, and the recent order was a private list lost on every reload. Each
  part is now the core's once, and the plugin declares rows, a choice and one bindings row.
- **Letting the Globe key pass through the chooser's field by name.** 2026-10-26. It made a tap
  of fn reach the plugin's tap while any list was open, and it put one plugin's key into the
  shared field. A bare list now answers its own cycle key, and a full list swallows the Globe key
  like any key it does not read, so a tap of fn over the launcher does nothing.
- **A plugin field choosing bare or full.** 2026-10-26. Proposed as a posture a presentation
  declares. The same list is wanted both ways, full from the launcher and bare from its cycle key,
  so the posture belongs to the door, and a plugin declaring it would have to pick one.
- **A plugin SDK the plugin calls to cycle.** 2026-10-26. Asked about by Milos. A plugin calling
  the stage would point a dependency from a plugin into the core's behaviour, and the keymap
  already turns a declared row into a bound key for `open`, so `cycle` is a second action of that
  same kind, read from data, with no call in either direction.

## Log

### 2026-10-25 22:00

Estimated from the session, no commit. The Input Sources plugin was built with a tap of fn opening
its list and repeated taps stepping it, through its own event tap on code 179. A second tap of fn
did nothing at first, because the default chooser's field claims every key down and its tap,
started after the plugin's, heard the press first. The field was taught to let code 179 pass. The
close delay was tried at 1.2, 0.6, 0.35 and 0.5 seconds and settled at 0.8, the shorter ones
closing before a second tap landed.

### 2026-10-26 16:25

The cycle moved into the core, the reasons under Rejected. An `hs.hotkey` on code 179 with no
modifiers was bound from the running config and fired on each of two taps of fn, so the Globe key
binds through the plain leader with no tap of its own. The field's pass through for code 179 and
`stageSelectNext` were removed. The keymap unit case covers the key table, a cycle row on the
Globe key with no leader, a typing key bound bare still refused, and a cycle row on an identity
with no presentation refused by name. Whether a typed key lands in the new layout every time, and
whether 50 milliseconds is enough for the app underneath to take focus back, is owed from the live
trial.

### 2026-10-26 17:47

The standalone rule had reached only one of the keymap's two readers. The plugin row reader let
a row bind the Globe key bare, but the row it built stated no modifiers and the keymap read that
as a catch all, while the binder bound it with an empty list, the only shape `hs.hotkey` has. So
the keymap and the binder described one key two ways, which the offline goldens showed as a
`hotkey globe` line with no owner, and the keys page would have called it a chord with any
modifiers. The person's reader, `parseChord`, had no standalone rule at all, so `config/keymap.lua`
could neither move a binding onto the Globe key nor free it, which a plugin's manifest could do.
Both were fixed in `lib/keymap.lua`. A global row with no leader that states no modifiers means
none, and `readConfig` takes `standalone` from the root, `lib/keycodes.lua`'s answer, and hands it
to `parseChord`. The plugin's manifest did not change. Rejected on the way, correcting only the
test projection, which would have left the keymap wrong for every other reader, and writing an
empty modifier list into the manifest, which would have made a plugin know a quirk of the core.
`test/keymap-person.lua` pins both rules, and the goldens were refreshed for the Input Sources rows
and the category moves of the same day, which had not been written into them.

### 2026-10-28 10:29

The branch carrying the entry above was rebased onto main to merge. Its first half had already
landed there by another route, a85fb348, which clears the catch all for a global row with no
leader in the same place, so the rebase kept main's version and dropped this branch's. Its second
half, `parseChord` and `readConfig` taking `standalone` so `config/keymap.lua` may bind or free
the Globe key, was not on main and merged as written. Its goldens commit had become empty, since
main had already refreshed the same goldens. Milos ended the manual hold the trial was running
under and asked for the work merged, without a verdict on the feel, so whether a key typed during
a cycle lands in the new layout every time and whether 50 milliseconds is enough stay owed.
