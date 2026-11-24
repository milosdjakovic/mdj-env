# The Leaders page

Status. Designed on 2026-11-24, asked by Milos, not built. Waiting on his answers to the open
questions at the end. Part of 6.2 in `docs/PLAN-STANDALONE.md`, the recorder's leaders, and it
settles open question 4 there, leaders in a password field.

## What a person gets

A Leaders section in Olm Settings, one card per leader, Hyper, META and SUPER, in that order. Each
card has five rows.

1. **Key.** Which physical key is the leader: Caps Lock, Left or Right Shift, Control, Option or
   Command, F13 to F20, or None. Left and right are separate choices.
2. **Sends.** How the key reaches Olm, one of three, each with its caveat written under it on the
   page. These are the kanata and Karabiner ideas the page borrows.
   - **Real modifiers.** The key becomes a held set of real modifiers below every app: Hyper
     ⇧⌃⌥⌘, META ⇧⌃⌥, SUPER ⌃⌥⌘. This is kanata's `multi` and Karabiner's "to" of modifiers. Needs
     the kanata piece on this Mac.
   - **A function key.** The key is remapped to F13 to F20 through `hidutil`, needs no driver and no
     password, and Olm's event tap hears it as a leader. A pedal or a macro pad sends F13 to F20
     itself, so that key choice skips the remap.
   - **Both.** Real modifiers while kanata runs, the function key when it doesn't. This is how Hyper
     and META ship today.
3. **Alone.** What a quick tap does: its own key (Caps Lock toggles, Right Command is Command) or
   nothing. This is Karabiner's `to_if_alone` and kanata's tap action. With real modifiers there is
   a fourth row, **Decides on**, which is the next key press (kanata's `tap-hold-press`, fast) or the
   key's release (`tap-hold-release`, safer for someone who rolls keys while typing), and the hold
   time, 200 ms as shipped.
4. **Holds.** Which roles it holds: app keys, window keys, list keys. This is the `roles` section of
   `config/keymap.lua` as three menus, so moving window management to SUPER is one choice.
5. **Cheat sheet.** A switch for showing the sheet on a hold, and a Show button that opens it now, on
   any leader. The sheet lists every key bound on that leader, its count shown on the card.

A leader nothing uses says "Unused, Right Command stays a normal key" and claims nothing, as SUPER
does today.

## What each choice costs, the words on the page

- **Function key: deaf in password fields.** macOS hides every key from every event tap while an
  app holds secure input, a password field in Safari, or any Chrome window with one, which keeps it
  on whichever app is in front. Olm says which app holds it when a leader is pressed then. This was
  measured on 2026-10-27, `decisions/olm-leader-keys.md`, and no function key avoids it.
- **Function key: other apps can't record it.** macOS's own shortcut fields reject a held F18. An
  app with its own event tap, Raycast or BetterTouchTool, can.
- **Real modifiers: works in password fields.** It happens below secure input, so a leader and a
  letter still reach Olm. The cost is the driver, two root daemons and the password once, which is
  the kanata piece.
- **Real modifiers: can clash with an app.** An app's menu shortcut on ⇧⌃⌥⌘ or ⌃⌥⌘ and a letter is
  answered by Olm first while Olm binds that letter. macOS keeps a few before any app sees them,
  Hyper and slash among them.
- **Left modifiers.** Left Shift as a leader means capitals come from Right Shift, and the same goes
  for each left key. The page says so under the choice.
- **Any remapped key** loses its own meaning in every app, apart from what Alone gives it back.

## How it works underneath

- **Saving.** The page writes a `leaders` setting in `~/.olm/state/settings.json`, laid over
  `SHIPPED_LEADERS` the way the `leaders` section of `config/keymap.lua` is today. A leader that
  section sets is locked on the page with "Set in config/keymap.lua", the rule every setting keeps.
- **A function key, live.** `lib/keyremap.lua` already writes one `hidutil` table for every held
  leader. Its allow list, `USAGE`, gains the left modifiers, and a change applies at once with no
  reload, which is rule 11.
- **Real modifiers, live.** The kanata config gets its leader lines from what the page saved, the
  `defsrc` keys and the `tap-hold` aliases, and nothing else in it moves. For kanata to pick up a
  change with no password, the daemon would be started once with its TCP port on localhost, and Olm
  sends a reload there. Whether kanata 1.12 takes a reload that way is checked before this is built.
  Without it, each change would restart the root daemon and ask for the password.
- **Which side heard it.** The function key route tells left from right through the `hidutil` usage
  of each key. The modifier route does through kanata, which reads the physical key. Olm never has
  to tell left from right in a shortcut, which macOS can't do.
- **Defaults.** Hyper on Caps Lock, META on Right Option, SUPER on Right Command, which is
  `SHIPPED_LEADERS` today. META's default keys are the window keys it has now. Hyper's default app
  keys are only the apps macOS ships, which `machines/default/hammerspoon-apps.lua` already holds.

## The order to build it in

1. The page, reading and saving the setting, and the function key route live through `hidutil`, the
   left modifiers added to the allow list.
2. The cheat sheet's switch and its Show button on every leader.
3. The roles menus.
4. Real modifiers through kanata, once the reload check passes.

The function key leaders stay heard by Hammerspoon's tap until the app has a tap of its own, since a
Carbon claim can't hold a function key down as a leader.

## Open questions for Milos

1. Left modifiers as leaders were refused on 2026-10-22, since a left key taxes typing. You asked
   for left and right, so the page offers both with the caveat. Is that what you want, or right side
   only?
2. SUPER's set of real modifiers. ⌃⌥⌘ is proposed, of the three sets of three META leaves free, ⇧⌃⌘
   and ⇧⌥⌘ being the others. Which one?
3. Real modifiers changed with no password needs kanata listening on a localhost port, which any
   program on this Mac could then send a reload to. Is that acceptable, or should each change ask for
   the password?
