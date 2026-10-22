# Plan, every leader is configurable

Written 2026-10-22, revised the same day with Milos's answers. The goal is the one he stated. A
leader is whatever the person says it is, and no leader name is reserved. Hyper may be Caps Lock
made to act as a modifier, or the four real modifiers Shift, Control, Option and Command, which is
what Karabiner or a person's own fingers produce, and everything bound on Hyper keeps working
either way. Changing which it is takes one line in `config/keymap.lua`, and everything about one
leader, the key and how it behaves, is written in that one entry.

```lua
leaders = {
  hyper = { mods = { "shift", "ctrl", "alt", "cmd" } },     -- real modifiers, from Karabiner or by hand
  meta  = { key = "rightOption", drivenRepeat = true },     -- a key Olm makes act as a modifier
  pedal = { key = "f13", sheet = true },                    -- a foot pedal or macro pad sending F13
  nav   = { mods = { "shift", "ctrl" } },                   -- a new leader of real modifiers
}
```

The facts below were checked against the tree on 2026-10-22 by reading. Recheck any citation
before acting on it, since the spoon moves. `decisions/olm-leader-keys.md` is the decision record
for this plan and is written in the same change as each phase. Three entries in the Rejected list
of `decisions/olm-keymap.md` are reopened by it, named under the shape below with why each no
longer holds.

## What is true today

**Two kinds of leader, kept apart by name.** The held leaders HYPER, META and SUPER come from
`policy.leaderCatalog` in `root/compose.lua` at 199, one row per leader giving a physical source
and the function key it is remapped to. A leader the person names in the `leaders` section of
`config/keymap.lua` can only be a set of real modifiers, read by `readConfig` in `lib/keymap.lua`
from 373. That reader refuses a name the catalog already holds at 380, so `hyper` cannot be
redefined, and refuses anything that is not a list of modifiers.

**Two triggers already behind one contract.** `lib/leader/triggers/held.lua` registers a key into
the ChordKey engine, and `lib/leader/triggers/modifier.lua` claims each binding through
`hs.hotkey`. Both answer start, bound, isActive and owns, and `lib/leader.lua` calls only that.
The root builds held leaders from the catalog at 925 and modifier leaders from the keymap at 962,
two loops that know which kind each is by where it came from.

**Policy is keyed by catalog name.** `policy.leaderPolicy` at 224 is keyed HYPER, META and SUPER.
`tapTogglesCapsLock` is a policy field, read in `lib/leader.lua` at 307, so whether a tap toggles
Caps Lock is stated per leader rather than following from the key.

**Roles move only between held leaders.** The roles reader in `lib/keymap.lua` at 407 refuses a
value that is not a held leader at 415, so app, window and list cannot land on a modifier leader.

**A modifier leader is second class in three more ways.** It has no sheet, since the 2026-10-19
rejection of a sheet on a modifier leader. It does not seal over an open list, since
`sealsOverLists` is set only by the held trigger, so its global chords stay live under a list. And
a list chord on it is a field key answered by the chooser's own field rather than a claimed hotkey,
which is right for a list and stays.

**The remap follows the catalog.** `lib/keyremap.lua` turns the active catalog rows into one hidutil
mapping. Its `USAGE` table knows six names, three sources and three function keys.

## The shape

**One leaders table, two kinds of entry.** An entry with `mods` is a modifier leader, and an entry
with `key` is a held leader, a key Olm makes act as a modifier. This is Strategy, and the root is
the one place that reads the field and names the concrete trigger, so nothing past the root learns
which kind a leader is.

**An entry names its kind with a field.** `mods`, a list of shift, ctrl, alt and cmd, makes a
modifier leader. `key`, one key name, makes a held leader. An entry carrying both, or neither, is a
problem line and the leader keeps its shipped default. The kind is stated rather than guessed from
the shape of the table, which is Milos's rule of structural values over loose words. A bare list,
the form the leaders section takes today, is read as `mods` for one release and said in a routine
console line, then refused.

**Behaviour is written in the same entry.** Every field `policy.leaderPolicy` carries today,
`ranked`, `drivenRepeat`, `sheet` and `sheetLayout`, may sit beside `mods` or `key`, so one entry
describes one leader whole. Milos chose this over a separate policy section on 2026-10-22, since a
leader split across two places is read in two places. `policy.leaderPolicy` and
`policy.leaderCatalog` retire, each named in a problem line pointing at the leaders section.

**Olm ships its three leaders as defaults in that same shape.**

```lua
hyper = { key = "capsLock", ranked = true, sheet = true,
          sheetLayout = { columns = 4, colWidth = 215, iconSize = 32, gap = 10, groupGap = 20 } },
meta  = { key = "rightOption", drivenRepeat = true, sheet = true,
          sheetLayout = { columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 } },
super = { key = "rightCommand", drivenRepeat = true, sheet = true,
          sheetLayout = { columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 } },
```

**A person's entry is laid over the shipped one with the same name in two halves.** The trigger
fields, `mods`, `key` and `remapTo`, replace together, so Hyper written with `mods` drops the
shipped `key`. The behaviour fields merge one by one, so Hyper redefined as four modifiers keeps
its ranking, its sheet and its layout unless the entry says otherwise. A new name starts with every
behaviour field off. No name is reserved. A name is still refused when it is a modifier word or a
role word, since a chord could not tell the two apart.

**A held key names its source, and only keys on an allow list may be one.** The list is Caps Lock,
Right Command, Right Option, Right Control and F13 to F20. The left modifiers stay off it because
ordinary shortcuts need them. Letters, digits, punctuation, Space, Return, Escape, Tab, the arrows
and F1 to F12, which carry brightness and media, are refused with one problem line naming the
allowed keys, and the leader keeps its shipped default. F13 to F20 are what makes extra hardware
work. A full size keyboard has them, and a programmable keyboard, a macro pad or a foot pedal can be
told in its own firmware to send one, so any physical key can become a leader without Olm ever
allowing a letter. The list is the `USAGE` table `lib/keyremap.lua` already keeps, so admitting
another key later is one row. Milos chose an allow list over a block list on 2026-10-22, since a
block list has to guess every key that is dangerous and an allow list only has to know which are
safe.

**Olm decides how the key reaches the engine.** F13 to F20 already send a clean press and release
and are used as they are. Caps Lock and the right modifiers do not, so Olm remaps them with hidutil
to a spare function key. Each has a preferred target that keeps today's keys stable, Caps Lock to
F18, Right Option to F16 and Right Command to F17, because another app may already bind F18 and a
letter through passthrough. Right Control takes the first free key from F13 to F20 not used
directly by another leader. `remapTo` pins the target when a person needs one,
`{ key = "capsLock", remapTo = "f19" }`, chosen over `as`, `via` and `sends` on 2026-10-22 as the
one a reader understands without the docs. Two leaders on one physical key, or two remapped to one
function key, are refused together.

**A tap does what the key does alone.** A quick press with nothing else toggles Caps Lock when the
key is Caps Lock and does nothing for any other key on the list. It follows from the key rather than
from a behaviour field, so `tapTogglesCapsLock` retires with a problem line.

**Behaviour does not care about the kind.** `drivenRepeat` works on both, since `hs.hotkey` already
takes a repeat callback, and `ranked` is a property of the resolver every leader shares.

**Roles and list keys land on any leader.** The roles reader accepts any name the leaders table
holds. The list role on a modifier leader places every default list key there, where each is a
field key as today.

**A modifier leader hosting list keys seals over an open list.** Milos chose on 2026-10-20 that no
global key fires underneath an open list, and a modifier Hyper must keep that. A modifier trigger
answers `sealsOverLists` when its leader hosts any list key, and the root disables that leader's
global hotkeys while a list is open and enables them as it closes, through the same
`anyListShowing` gate the held leaders use. A modifier leader hosting no list key, such as a plain
combination, still fires over a list as it does anywhere.

**A modifier leader may reveal a sheet.** When its entry states a sheet, a watcher on modifier
changes reveals it once exactly that set has been held for the hold delay with no other key, and
conceals it on any key or any change of the set. Every modifier change carries the true state, so
this cannot stick the way a remembered held key could. A set of two typing modifiers simply does
not state a sheet, which is the case the 2026-10-19 rejection was about.

**Reopened rejections from `decisions/olm-keymap.md`.**

- **A cheat sheet on a modifier leader.** It was rejected because holding Shift and Control is
  ordinary typing. That stays true, so the sheet is opt in per leader. Four modifiers arriving
  together from one key is not typing, which is the case that did not exist then.
- **Hyper as a modifier chord with a hold reveal.** Retired as a case nobody here used. Karabiner,
  or a person who presses the four, makes it a real case.
- **A leaders section that only names new modifier sets.** It becomes the one place every leader
  is defined, with the shipped three as defaults in it. The rejection was of a section that must
  declare every leader, and that stays rejected, since an empty section still means the shipped
  three.

## Phases

Each phase lands with its tests, its goldens and its decisions entry, and is loaded live with a
clean console before the next starts. A phase that changes no behaviour proves it by the keymap
goldens staying identical.

### Phase 0, a baseline

Record `test/keys.golden`, every keymap fixture golden and the sheet goldens as they stand, and add
`test/keymap-fixture-modhyper.lua`, a keymap that sets nothing yet, to hold the shape the later
phases fill in.

### Phase 1, one leaders table

Move the shipped three, behaviour included, into `leaders` in the shape above, read by one reader
in `lib/keymap.lua` that tells the two kinds apart by the `mods` or `key` field, lays a person's
entry over the shipped one in its two halves, and drops the refusal of a shipped name. A bare list
is read as `mods` with its routine line. The root builds every leader in one loop, naming the
trigger from the field. `policy.leaderCatalog` and `policy.leaderPolicy` retire with problem lines.
The remap is computed from the held leaders in use, with today's preferred targets. With an empty
person's section every golden is identical, and `config/keymap.lua`'s header documents the new
entry.

### Phase 2, any key on the allow list as a held leader

Grow `lib/keyremap.lua`'s `USAGE` to the allow list, Right Control and F13 to F20 joining what it
has. Use F13 to F20 directly, remap the rest to their preferred target or the first free one, honour
`remapTo`, and refuse a key off the list, two leaders on one physical key and two leaders on one
function key, each with a problem line. The tap toggles Caps Lock only when the key is Caps Lock,
and `tapTogglesCapsLock` retires with a problem line. `test/chordkey.lua` gains the tap cases, and a
fixture with a pedal on F13 and Caps Lock pinned with `remapTo` holds the remap in its golden.

### Phase 3, a modifier leader is a leader like any other

Roles and the list role accept any leader. The modifier trigger seals over an open list when its
leader hosts list keys. The fixture defines Hyper as the four modifiers, and its golden shows every
app toggle, list key and launcher label on that set, with Caps Lock left unremapped.
`test/leaders.lua` pins the sealing.

### Phase 4, a sheet on a modifier leader

The modifier trigger gains the reveal described above when its entry states a sheet, sharing the
hold delay and the one sheet host. `test/leadersheet.lua` pins that the set must match exactly and
that any key or change conceals it.

## Answered by Milos, 2026-10-22

1. **Behaviour is written inside the leader's own entry**, beside `mods` or `key`, rather than in a
   separate policy section.
2. **`remapTo` pins the function key**, chosen over `as`, `via` and `sends`.
3. **A held key comes from an allow list**, Caps Lock, the three right modifiers and F13 to F20,
   and anything else is refused with a problem line. A letter is refused, and extra hardware is
   reached by having it send F13 to F20.

## Not in this plan

- **One leader on two triggers at once**, such as Hyper from the four modifiers and from a second
  physical key. It is a Composite over the same trigger contract and can follow once a second
  physical key is actually wanted.
- **Which tool supplies Hyper on which machine.** Karabiner on one Mac and Olm's own remap on
  another is a difference between machines, so it is a piece in `MACHINES` with a probe in
  `capture`, never a second keymap.
- **Installing Karabiner.** If it is chosen, it is declared in `DEPENDENCIES.map` and the Brewfile
  like any tool, and its own configuration lives in a module of its own.
- **Real modifier leaders that work in a password field.** That is Karabiner's driver, outside
  anything Olm does.
