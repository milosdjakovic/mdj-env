# Plan, one keymap and leaders as data

Written 2026-10-19, revised the same day at 17:32 with Milos's answers. The goal is the one he
stated. A plugin says what it can do and which keys it would like, and Olm decides how it is
reached. A person writes every key choice in one file Olm owns, names any held modifiers they
want as a leader of their own, and puts any plugin's action on any chord with no plugin edited.
Every shortcut is then visible to the same collision check, the same cheat sheets, the same
launcher chord labels and the same hint bar.

The facts below were checked against the tree on 2026-10-19 by reading. Recheck any citation
before acting on it, since the spoon moves. `decisions/olm-keymap.md` is the decision record for
this plan and is written in the same change as each phase.

## What is true today

**Two leaders, named in the root.** `root/compose.lua` resolves `appKeycode` and `windowKeycode`
by role at 777 to 780, configures `hyperKeyAtom` at 1579 and `windowLeaderAtom` at 1597, starts
exactly those two at 2143, and binds a host key only when its code equals `appKeycode` at 2046,
so a host on the window leader is skipped in silence. `leaderRoles` is `{ app = "HYPER", window =
"META" }` merged with `cfg.leaders` at 228.

**Two adapters that are near copies.** `lib/hyperkey.lua` and `lib/windowleader.lua` share the
same mods resolver and both register into `lib/chordkey.lua`, but differ in policy.

| Behaviour | hyperkey | windowleader |
|---|---|---|
| Tap | `onTap`, Caps Lock toggle | none |
| Repeat | system | driven, with hold depth |
| Over an open list | stays live, contexts take over | quiet through `suppressWhen` |
| Contexts, `priority`, modal | yes, 133 to 233 | no |
| Binding whose `when` is false | skipped, so it can pass through | swallowed as a noop |
| Unknown predicate name | passes silently | warns once |
| Real modifier trigger | `TRIGGERS.chord`, 340 to 486 | no |
| `isActive`, `owns` | yes | no, the engine has `isActive(keyCode)` |
| Hold sheet | callbacks from the root | its own closures over `opts.windowCheatSheet` |

**Two cheat sheet hosts.** `host/hypercheatsheet` and `host/windowcheatsheet` draw through the same
`lib/cheatsheet.lua` renderer but build their rows separately, four columns with icons against two
columns keyed by stamped keycode.

**Five binding paths.**

1. A registry tool's open key, `defaults.key` on `defaults.leader`, bound by the root through
   `registrar.bind` at `lib/registrar.lua` 884, Hyper only. A tool on another leader is refused at
   908. Nine tools use it.
2. A registry command with `shortcut = "global"`, bound through `hs.hotkey.bind` at compose 1853.
   The clipboard's Ctrl and Option with C and V are the two.
3. A plugin binding its own `defaults.bindings` through a wiring step, capture through
   `bindHotkeys` onto Hyper and windowmanager through `bindToLeader` onto the window leader.
4. A plugin binding from person data, apptoggler's toggles from `config/keys.lua`, onto Hyper, or
   through `hs.hotkey.bind` when a toggle states `modifiers`, which is how Option and backtick
   summons the terminal.
5. Root owned keys, the launcher host on Hyper and space, lock and sleep at compose 2061, and every
   surface context binding through `nav.bindOne` onto Hyper.

Plus dead code, `bindHotkeys` in `plugins/clipboard/init.lua` 266 to 292, which no wiring calls.

**Collisions are barely checked.** `lib/defaults.lua` 189 compares only `leader .. "+" .. key` of
top level `defaults.key`, ignores `mods` and case, and never sees `bindings`, toggles, commands,
surface keys or plain combos. Both `bind` functions append without a warning.

**Spelling knows one leader.** `hints.chordFor` gets `leaderName = leaderDisplayNames.app` at
compose 1643, so the docked hint bar can only spell an app leader chord.

**No key inventory exists.** Nothing records the full set of bound chords, so a phase that moves
binding code has no baseline to compare against.

**A person sets a key in seven places.**

| What | Where it is changed today |
|---|---|
| Which physical key each leader is | `config/keys.lua`, `appLeader` and `windowLeader` |
| App toggles | `config/keys.lua`, `appToggles`, keys and behaviour in one list |
| A tool's open key | `config/plugins.lua`, `key`, `mods`, `leader` |
| A plugin's bindings | `config/plugins.lua`, `bindings` |
| Keys inside an open list | `config/plugins.lua`, `surface`, over shared j, k, i, x and o that `lib/surface.lua` hardcodes at 39 and 231 |
| Global commands | the registrar's `meta` override table, `registrar.commandKey` at 935 |
| Olm's own keys | the launcher host's `defaults.key`, and `specialRows` for lock and sleep in its manifest |

The clipboard's `data.shortcut` in `config/plugins.lua` is not one of these. Olm posts that combo
to another clipboard manager rather than listening for it, so it is plugin data and stays.

## The shape

There is one way to set a key. Every chord a person chooses is written in `config/keymap.lua`, in
one grammar, a leader or modifiers joined by `+` and the key last, on the left, and an action on
the right. Nothing else a person edits holds a key.

**An action is a Command, and its descriptor is the whole declaration.** A plugin answers its
actions through `provides.actions`, a list of descriptors, and Olm derives every key, cheat sheet
row, launcher row and chord label from that one list. A plugin learns nothing about any of those
surfaces, which is the decoupling this plan exists for. The test is that a new plugin declares
actions and suggests keys, and is reachable, listed and labelled with nothing else to learn.

```lua
-- a descriptor, every field but run optional
leftHalf = {
  run         = function(depth) end,  -- depth is how deep into a held repeat, 0 on the press
  description = "Left Half",          -- the label on every surface
  subtitle    = nil,                  -- the launcher row's second line
  icon        = "windows",            -- a key into the manifest's icons, or a content spec
  keywords    = nil,                  -- further search words, never shown
  repeats     = true,                 -- the action is a step worth repeating while held
  when        = nil,                  -- a predicate name, live state gating key and rows together
  group       = nil,                  -- a word or a function answering one, the cheat sheet section
  kind        = nil,                  -- the launcher catalog kind a scope narrows by
  app         = nil,                  -- a bundle id this action stands for, see below
  listed      = true,                 -- false keeps an internal action off the launcher
},
```

An action is addressed as the plugin's identity, a dot, and the action name, `vpn.open` or
`windowmanager.leftHalf`. A registry tool's open is the implicit action `open`. `provides.actions`
is the only way to declare anything runnable, so the registry's `commands` block retires, the
clipboard's `appendCopy` and `pasteNext` becoming ordinary descriptors, and with it the
registrar's `meta` key override. Hosts answer descriptors the same way, `launcher.open`,
`launcher.lock`, `launcher.sleep` and `actionpanel.open`, so lock and sleep leave the launcher's
`specialRows` and Olm's own keys are no different from a plugin's. A plugin never calls a bind
function again.

From the descriptors Olm builds four things, and each replaces a channel a plugin used to speak.

| Olm derives | From | Retires |
|---|---|---|
| The key | the plugin's default, then `config/keymap.lua` | every bind call, `provides.bindings` |
| The cheat sheet row | `description`, `icon`, `group`, `when` | `provides.cheatSheetSections` |
| The launcher row | `description`, `subtitle`, `icon`, `keywords`, `kind`, `listed` | `provides.launcherRows` and `launcherRun` for anything that is an action |
| The chord label | the keymap | `provides.launcherAppDetails` |

An action carrying `app` merges into the launcher's own row for that app rather than listing twice,
so the app row shows the chord, which is all `launcherAppDetails` ever did. A `group` answered by a
function is asked on every show, which is how the toggler's running and not running split becomes
two groups rather than a section of its own. Every listed action is a launcher row with no plugin
code, so the mandate that every shortcut also has a launcher row holds by construction.

**Actions may be built from data.** A descriptor list is answered once per load, either fixed in
code or built from the plugin's own data, and the second is an ordinary case rather than a toggler
trick. apptoggler answers one action per app in `config/apps.lua`, `apptoggler.Safari`, with no
data needed for an app that only focuses or cycles. An app that needs more, show and hide or
placement, gets a named variant in apptoggler's own data, and each variant is an action too,
`apptoggler.GhosttyPlaced`. The keys leave the toggle list and the behaviour stays with the plugin
that runs it. Workspaces with one action per saved layout, display profiles with one per profile,
and System Settings with one per pane are the same shape. The last one means Hyper and comma can
name `systemsettings.General` directly, so apptoggler's url field goes. Keys bind at load, so an
action added while Hammerspoon runs, a layout saved a minute ago, is bindable after the next
reload, while its launcher row may appear at once through the launcher's existing refresh.

What stays outside descriptors, on purpose. List keys act on whichever list is open, so they stay
the surface's own verbs in the `lists` layer below. Launcher rows that are not actions, the alias
directory and the catalog scopes, keep `launcherRows`.

```lua
-- config/plugins.lua, apptoggler's data, no keys
apptoggler = { data = { apps = apps, variants = {
  GhosttyPlaced  = { app = "Ghostty", hides = true, description = "Terminal placed",
                     placement = { width = 2400, height = 1350, padding = { x = 40, y = 20 } } },
} } },
```

apptoggler supplies no sheet section and no launcher details any more. Its descriptors carry
`app` and a `group`, and Olm draws the rest, so the plugin never learns a chord, the keymap or a
person's file.

**A plugin suggests keys in one place, and a default names a role, never a leader.**
`defaults.bindings` is the only way a plugin suggests a key, a row naming an action, a role, a key
and optional modifiers. The shorthand `defaults.key`, `defaults.mods` and `defaults.leader` for a
tool's open key retire, each becoming a `bindings` row for `open`. The role word is `app` or
`window`, so a shipped plugin never learns a person's leader names, and Olm maps `app` to `hyper`
and `window` to `meta`.

```lua
-- a manifest's suggested keys, the only form
defaults = {
  bindings = {
    { action = "open", leader = "app", key = "P" },
  },
},
```

**The person's keys and aliases live in one file Olm owns.** How a plugin is reached, by a chord
or by a typed word, is a host concern, the way an editor owns its user keybindings file and an
extension only contributes commands and suggested keys. `config/keymap.lua` reaches Olm as
`cfg.keymap` through `spoon.Olm:start`, beside `cfg.plugins`, and no plugin ever reads it.

```lua
-- config/keymap.lua
return {
  leaders = {
    nav = { "shift", "ctrl" },
  },
  keys = {
    ["meta+E"]     = "vpn.open",
    ["nav+T"]      = "tmuxSessions.open",
    ["ctrl+alt+C"] = "clipboard.appendCopy",
    ["hyper+S"]    = "apptoggler.Safari",
    ["alt+`"]      = "apptoggler.GhosttyPlaced",
    ["hyper+3"]    = false,
  },
  lists = {
    all       = { ["hyper+j"] = "selectNext", ["hyper+x"] = "close" },
    clipboard = { ["hyper+d"] = "delete" },
  },
  aliases = {
    vpn = { "v", "vpn", "tunnel" },
  },
}
```

A chord is written the way the cheat sheet reads it, a leader or modifiers joined by `+` and the
key last, with the key compared without case. The right side is an action, or `false` to free the
chord. An action named in `keys` takes exactly the chords listed for it there and loses its
default, and everything unlisted keeps the plugin's default. An optional `roles` table,
`{ window = "super" }`, moves every default on a role at once, which replaces `appLeader` and
`windowLeader` in `config/keys.lua`.

**Aliases sit beside the keys.** `aliases` maps a plugin's identity to the words that scope the
launcher to it. A plugin named there takes exactly those words in place of its manifest's
`defaults.aliases`, and every other plugin keeps its default, the same rule `keys` follows. The
existing alias collision check in the registrar keeps answering a clash, now reading the merged
words, and the alias directory, the row hints and `aliasLabel` read the same answer they read
today.

**Each concern has one way.**

| Concern | The one way |
|---|---|
| What a plugin can run | `provides.actions` descriptors |
| Which keys a plugin suggests | `defaults.bindings` |
| Which words a plugin suggests | `defaults.aliases` |
| A plugin's lists and their verbs | its `surface` block |
| A person's keys, list keys and aliases | `config/keymap.lua` |
| A plugin's data and its switch | `config/plugins.lua` |
| Which physical key is remapped | Olm's leader catalog |

**Keys inside a list are a layer of their own.** `lists` holds the chords live only while a list is
open, keyed by the list's context name, with `all` for the keys every list shares, which replaces
the constants in `lib/surface.lua`. The right side is the surface's own action name, routed as it
is today, since a list key acts on whichever list is showing. Defaults stay in each manifest's
`surface` block and the person writes only changes. A list chord may shadow a global chord while
its list is open, as Hyper and j does today, opening emoji outside a list and moving down inside
one, so collisions are checked within the global layer and within each list layer with `all`, never
across them. A listing with `chord = false`, Backspace leaving a hosted list, stays a manifest fact
and is not a person setting.

**Two kinds of leader, and the trigger is a Strategy.** One file each, and a third kind is a file
plus a line.

- **Held.** `hyper`, `meta` and `super` are built in, one per row of the leader catalog, because
  each is a physical key remapped to a function key that belongs to no app. A held leader is
  remapped only while some chord uses it, the rule the catalog already follows, so writing
  `super+V` is what claims Right Command. Its policy ships in core defaults, Caps Lock's tap toggle
  and contexts on `hyper`, driven repeat and quiet over open lists on `meta`, and a cheat sheet on
  hold for every held leader.
- **Modifier.** A name the person gives a set of real modifiers in `leaders`. It is bound through
  `hs.hotkey`, carved out of `TRIGGERS.chord` in hyperkey. It has no cheat sheet, since holding
  Shift and Ctrl is ordinary typing, and no tap, since those keys already do their own thing. Its
  chords are taken from every app, so it suits combos the person knows their apps leave free. A
  chord with modifiers and no leader at all, `ctrl+alt+C`, is the same thing unnamed.

A name in `leaders` that matches a built in, or a modifier word, is refused out loud.

**A key switched off for the moment is swallowed on every leader.** A binding whose `when` is false
does nothing and is not passed to the app in front. The key stays reserved for its situation, so a
person never reuses it and nothing is lost by swallowing.

**The keymap is the one table.** `lib/keymap.lua` collects every binding from every source above,
applies `cfg.keymap`, resolves roles to leaders, normalises key case and modifier order, and
refuses out loud any two rows on the same leader, key, modifiers and context. Every consumer reads
that list and nothing else, the binder, every cheat sheet, the launcher's chord labels, the hint
bar and the action panel. It names no plugin and no leader. The root builds it once and hands it
out by reference, the same rule as the stamped window bindings today.

**One leader adapter, one sheet host.** `lib/leader.lua` is the union of hyperkey and windowleader,
configured once per leader in use with its trigger and policy. `host/leadersheet` draws whichever
held leader is down, its layout, columns, icons and badge width coming from that leader's policy.

What stays as it is. ChordKey stays the one event tap for every held leader. The leader catalog and
`lib/keyremap.lua` stay the only place a physical key is remapped, since that describes the
hardware rather than a shortcut. List keys stay on `hyper`. `config/plugins.lua` keeps a plugin's
own data and its switch, and holds no keys.

What goes. `config/keys.lua` is deleted. apptoggler's literal Hyper fallback goes, since Olm binds
every key and a plugin has nothing left to fall back to. `provides.cheatSheetSections`,
`provides.launcherAppDetails` and `provides.bindings` leave the contract, and `launcherRows` and
`launcherRun` remain only for rows that are not actions. The registry's `commands` block, the
launcher's lock and sleep `specialRows`, and `defaults.key`, `defaults.mods` and `defaults.leader`
retire too. The registrar refuses a manifest that still declares a retired field, naming the field
and what replaced it. `config/plugins.lua` refuses `key`, `mods`, `leader`, `bindings`, `surface`
and `aliases` with a problem line naming `config/keymap.lua`.

## Phases

Each phase lands on its own branch in `../.worktrees/` with the dry gate, the dependency check,
the plain Lua tests, a live load under the devlock taken only after Milos says start, a clean
console, and the key inventory compared against main. A phase that touches a plugin goes through
the `olm-plugin` skill and updates it in the same change. Each phase writes its entry in
`decisions/olm-keymap.md` as it lands.

### Phase 0, a baseline

Add a probe that dumps every chord bound in the live config, one line each with leader, key,
modifiers, context and owner, into `test/keys.golden`, read through a log file rather than over
the port. Every later phase must reproduce this file exactly unless the phase says what changes.
Add plain Lua cases for the two adapters' resolvers as they stand, the gated key difference
included, so the merge in phase 3 has a fixed target.

### Phase 1, the keymap as a read model

Build `lib/keymap.lua` and feed it from all five paths, without changing who binds. Its first
output is problems. Collisions now include `mods`, case, `bindings`, toggles, commands, surface
keys and plain combos. Retire the narrow check in `lib/defaults.lua` once the keymap covers it.
The golden is unchanged, and any collision the wider check finds on this machine is reported to
Milos rather than fixed in passing.

### Phase 2, descriptors, and the core binds every action

Introduce the descriptor contract in `lib/registrar.lua`, validated like every other manifest field,
a malformed descriptor refused with one line naming the plugin, the action and the field. The
binder walks the keymap and binds each row's `run` through the engine its leader resolves to, still
the two existing adapters plus `hs.hotkey` for modifier chords.

- capture and windowmanager answer descriptors and lose their bind wiring steps, and windowmanager
  its `needs.lib.windowLeader`. windowsize reads windowmanager's actions as a sibling, so it moves
  to the descriptor shape in the same change.
- Launcher rows for actions are built by Olm from descriptors, and capture's and windowmanager's
  own `launcherRows` and `launcherRun` go. The launcher's window scope narrows by `kind` as before.
- apptoggler exports `provides.bindings`, rows built from its toggle list as it stands, and a
  toggle stating `modifiers` becomes a modifier chord row. This is a bridge that phase 6 removes.
- The clipboard's two commands become descriptors with modifier chord rows, the registry's
  `commands` block retires, and the clipboard's dead `bindHotkeys` is deleted.
- Every manifest's `defaults.key`, `defaults.mods` and `defaults.leader` becomes a `bindings` row
  for `open`, nine tools and the launcher host, a mechanical move the golden proves.
- The registrar stops binding and the refusal at 908 goes, since a tool's `open` is an ordinary
  row. That reopens a rejection in `decisions/olm-core-split.md`, which the record says.
- The dry gate refuses `hs.hotkey.bind`, `hs.hotkey.new` and any leader `bind` call under
  `plugins/` and `host/`.

The golden is unchanged, and the launcher's rows are compared against main, same rows, same order,
same subtitles. The one visible gain is that Option and backtick and the clipboard combos now reach
the collision check and the hint bar spelling.

### Phase 3, one leader adapter

Merge hyperkey and windowleader into `lib/leader.lua` with the policy fields above, and the two
triggers into `lib/leader/triggers/held.lua` and `modifier.lua`. The root loops over the leaders in
use instead of naming two, so `appKeycode`, `windowKeycode`, the host key check at 2046 and the
two element lists at 2019 and 2143 go. The shipped defaults reproduce today exactly. A gated key is
swallowed on every leader, which changes Hyper and is the one difference the golden is allowed to
show, and an unknown predicate name warns once on every leader. `hints.chordFor` takes the leader
of each row, so the hint bar can spell any leader.

### Phase 4, one sheet host

Replace both cheat sheet hosts with `host/leadersheet`, its rows built from the keymap filtered by
the held leader and the descriptor behind each chord, sectioned by `group`, with a descriptor's
`when` hiding its row exactly while its key is gated. Layout per leader reproduces today, four
columns with icons for `hyper` and two for `meta`. The toggler's app section is the first group
answered by a function, until phase 6 still supplied as a section, after it as descriptors. Parity is checked by holding each leader under
the devlock with Milos watching, since a drawn sheet is what a test cannot see.

### Phase 5, the person's keymap

Read `config/keymap.lua` with its `leaders`, `keys`, `roles` and `aliases`, and migrate
`appLeader` and `windowLeader` out of `config/keys.lua` into `roles`, written only when they
differ from the default. Hosts answer their descriptors, lock and sleep leaving `specialRows`, and
the registrar's `meta` key override is retired, with any entry on this machine moved into `keys`.
Any alias override on this machine moves from `config/plugins.lua` into `aliases`. An action that does not exist, a chord that does not
parse, or a leader name that clashes is a problem line naming the entry. Prove Milos's case with a
test fixture holding `meta+E` and `meta+Y` on two plugins and a `nav` modifier leader, and leave the
live keys alone until he writes his own. The golden is unchanged.

### Phase 6, actions built from data

apptoggler answers a descriptor per app in `config/apps.lua` and per variant in its data, each
carrying `app` and a running `group`, and drops `provides.bindings`, `bindHotkeys`, its Hyper
fallback, its url field, `cheatSheetSections` and `launcherAppDetails`. The launcher merges an
action carrying `app` into that app's row. The person's toggle list is split, each key into `keys`
and each special behaviour into a variant, Hyper and comma moving to `systemsettings.General`, and
`config/keys.lua` is deleted. The same phase gives systemsettings a descriptor per pane in place of
its `launcherRows`, and reads workspaces and displayprofiles for whether their layouts and profiles
are worth answering as descriptors now, a question settled per plugin through the `olm-plugin`
skill rather than assumed. The golden is unchanged apart from owner names on toggle rows. Two
entries naming the same app, Hyper and backtick plain and Option and backtick placed, are the case
to check by hand, and the Hyper sheet's open and not running split is checked by eye.

### Phase 7, list keys in the keymap

Read `lists`, `all` first and each context over it, and move the shared j, k, i, x and o out of
`lib/surface.lua` into Olm's default `all` layer. Collisions are checked per layer. Any `surface`
override on this machine moves into `lists`. `config/plugins.lua` then refuses every key field with
a problem line naming `config/keymap.lua`, and the dry gate refuses a key literal in `lib/surface.lua`.
The golden is unchanged. Update `docs/PLUGIN-CONTRACT.md`, `docs/PLUGIN-AUTHORING.md`, the hammerspoon
`AGENTS.md` leader section and the `olm-plugin` skill, which from here carry the one way table
above, one place a person sets a key or an alias and one way a plugin declares each thing.

## Not in this plan

List keys on a leader other than `hyper`. A keys page in the OLM settings, which the keymap makes
cheap later as a read only list.
Moving the generic mechanism still inside `root/compose.lua`, `chordLabel`, `aliasLabel`,
`rowIntercept` and `anyListShowing`, into `lib/`, which is worth its own plan.
