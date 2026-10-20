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
-- a descriptor, one entry of the list provides.actions answers, every field but name and run optional
{
  name        = "leftHalf",           -- the action's name, the list's order is the rows' order
  run         = function(depth) end,  -- depth is how deep into a held repeat, 0 on the press
  description = "Left Half",          -- the label on every surface
  subtitle    = nil,                  -- the launcher row's second line
  icon        = "windows",            -- a key into the manifest's icons, or a content spec
  keywords    = nil,                  -- further search words, never shown
  repeats     = true,                 -- the action is a step worth repeating while held
  when        = nil,                  -- a predicate name, live state gating key and rows together
  group       = nil,                  -- a word or a function answering one, the cheat sheet section
  kind        = nil,                  -- the launcher catalog kind a scope narrows by, else the identity
  app         = nil,                  -- a bundle id this action stands for, see below
  listed      = true,                 -- false keeps an internal action off the launcher
  afterRelease = nil,                 -- true runs only once the leader that fired it is released, phase 3
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
and optional modifiers. The shorthand `defaults.key` and `defaults.mods` for a tool's open key
retire, each becoming a `bindings` row for `open`. `defaults.leader` stays, as the role every row
of the plugin inherits when the row names none, which is a default for a field rather than a
second way to declare a key, corrected in phase 2b. A row may also say `leader = false` for a
plain combination with its modifiers. The role word is `app` or `window`, so a shipped plugin
never learns a person's leader names, and Olm maps `app` to `hyper` and `window` to `meta`.

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
launcher's lock and sleep `specialRows`, and `defaults.key` and `defaults.mods` retire too, while
`defaults.leader` stays as the default role. The registrar refuses a manifest that still declares a retired field, naming the field
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

Built in two halves, 2a binding every key from the keymap and 2b deriving launcher rows from
descriptors and retiring `registry.commands` and the `defaults.key` shorthand.

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
- Every manifest's `defaults.key` and `defaults.mods` becomes a `bindings` row for `open`, nine
  tools and the launcher host, a mechanical move the golden proves. `defaults.leader` stays as the
  role a row naming none inherits.
- Found in 2b. `provides.actions` answers a list, each descriptor naming itself, since the rows
  need an order a keyed table cannot give. A descriptor states `kind` to keep the memory key its
  rows had, capture, window and special, and a registered tool's action rows follow the tool's own
  row, which is where the clipboard's commands always sat. Two baselines beside the key golden,
  `test/launcher.golden` and `test/sheets.golden`, prove the move, and the window sheet's rows
  became the keymap's here rather than in phase 4, since the gates the descriptors now carry had
  to reach it.
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
use instead of naming two, so `appKeycode`, `windowKeycode` and the two element lists at 2019 and
2143 go. The shipped defaults reproduce today exactly. A gated key is swallowed on every leader,
which changes Hyper, and an unknown predicate name warns once on every leader. `hints.chordFor`
takes the leader of each row, so the hint bar can spell any leader.

- Found in 3. The keys golden records what is bound and never how a press resolves, so the gated
  key change does not show there at all, and all three goldens stayed byte identical. The change is
  pinned in `test/leaders.lua` instead, where the flipped cases say so in their names.
- Found in 3. The host key check this phase was to remove had already gone in 2b, when a host's
  open key became an ordinary bindings row.
- Found in 3. Hyper's own hold reveal already held back over an open list, through the root's
  closures, so going quiet over lists was never META's alone. Every held leader now holds its
  reveal back over a list, and `quietOverLists` decides only whether its keys go inert too.
- Found in 3. The policy is `policy.leaderPolicy` in the root, keyed by catalog name, and every
  field is a boolean or a number apart from the sheet host's identity, `tapTogglesCapsLock`,
  `drivenRepeat`, `contexts`, `quietOverLists`, `sheet` and `holdDelay`. Corrected in phase 4,
  there is one sheet host, so `sheet` is a boolean and the layout is a table beside it,
  `sheetLayout`. SUPER ships META's policy,
  since it is the documented other home of the window role.
- Found in 3. `policy.hyperTrigger`, which could make Hyper a modifier chord with a hold reveal, is
  retired and named as a problem when set, since a held leader is its catalog row and a named set
  of modifiers is a leader of its own from phase 5, with no sheet.
- Found in 3. The two tier rules stay as they were per leader, best priority with a gated binding
  dropping out of its tier where contexts are on, first exact match and last catch all elsewhere.
- Found in 3. Capture's wait for Hyper's release became the descriptor field `afterRelease`, which
  the leader that fired the key honours and a launcher row honours for every held leader, so
  capture asks for no lib. The clipboard keeps a lib, `leader`, a view answering whether any held
  leader is down, because whether it waits is its chosen provider's answer at the press.

### Phase 4, one sheet host

Replace both cheat sheet hosts with `host/leadersheet`, its rows built from the keymap filtered by
the held leader and the descriptor behind each chord, which both sheets already read since 2b, sectioned by `group`, with a descriptor's
`when` hiding its row exactly while its key is gated. Layout per leader reproduces today, four
columns with icons for `hyper` and two for `meta`. The toggler's app section is the first group
answered by a function, until phase 6 still supplied as a section, after it as descriptors. Parity is checked by holding each leader under
the devlock with Milos watching, since a drawn sheet is what a test cannot see.

- Found in 4. The layout lives in the leader policy and not in the host, so a new leader gets a
  sheet by policy alone. `sheet` becomes a boolean and `sheetLayout` a table beside it, `title`,
  `columns`, `colWidth`, `iconSize`, `gap`, `groupGap` and `badgeWidth`, validated by
  `leader.checkPolicy`, with defaults of two columns of 250 under the heading SHORTCUTS for a
  leader that states none. The window sheet's heading moved from the root's
  `windowSectionTitle` into META's layout.
- Found in 4. The two sheets did not order their rows the same way. The Hyper sheet drew tools
  first and then each plugin in plan order, where the keymap's bound list holds a plugin's own
  bindings first, so the plan's "rows from the keymap filtered by leader" was not one rule yet.
  `hints.sheetRows` is that one rule now, the Hyper order for every leader, and it replaced both
  `hints.sections` and `hints.leaderRows`. On this machine the window sheet's order is unchanged.
  With a tool's open key on the window leader that tool now leads the window sheet, which is the
  only case that moved.
- Found in 4. The Hyper sheet never read `when`, so a gated Hyper key still showed. One host
  gates every leader the way the window sheet did, and no Hyper row carries a `when` on this
  machine, so nothing visible changes today.
- Found in 4. A row with no description took its raw action name on the Hyper sheet and the action
  in words on the window sheet. Every leader takes the words now, which only shows for a row that
  states no description anywhere.
- Found in 4. The sheet is keyed by the leader's keycode, which the adapter already hands it, so
  the root's stamping of window bindings with a keycode, `leaders.stampBindings`, and the root
  value `leaders` that carried the heading are retired.
- Found in 4. With one host asked once per leader, the line `contributions.sheetSections` said for a
  supplier on another role named the toggler as unreached while asking for the window sheet. That
  report moved to `contributions.unreachedSheetSections`, said once.
- Found in 4. Duplicate chords on one sheet collapse to the first, the Hyper sheet's old rule, now
  for every leader, though the keymap refuses two rows on one chord so it only guards the sheet.
  `buildSupplied` no longer accepts `section.bindings`, the shape only the old own block used, which
  no supplier used and the contract never documented.
- Found in 4, after review. `sheet = false` in a person's policy drops the merged shipped layout in
  silence and only a layout stated with no sheet is a problem. Provided rows reach a sheet unless
  their plugin supplies sections for the role. The renderer exports its layout defaults and
  `leader.sheetLayout` reads them. An unknown predicate is warned once per name. A leader answering
  several roles asks for the suppliers of every one.
- Found in 4. The keymap row gained `group`, the descriptor's, since the sheet is the first reader
  of it. A `group` function is asked with nothing at every show, and a block holding one is a
  supplier instead of a built list. No shipped descriptor states a group yet, so only plain Lua
  cases exercise it.

### Phase 5, the person's keymap

Read `config/keymap.lua` with its `leaders`, `keys`, `roles` and `aliases`, and migrate
`appLeader` and `windowLeader` out of `config/keys.lua` into `roles`, written only when they
differ from the default. Hosts answer their descriptors, lock and sleep leaving `specialRows`. The
registrar's `meta` key override for commands already retired with commands in phase 2b, and this
machine had no entry. Any `key` or `mods` a person wrote for a plugin in `config/plugins.lua`, which
2b translates onto that plugin's open row, moves into `keys` here, this machine having none, and
the translation itself retires in phase 7 when that file refuses every key field.
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
