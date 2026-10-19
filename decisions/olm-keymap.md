# Olm keymap, and leaders as data

Status. Phases 0 and 1 landed 2026-10-19, phase 2a, the core binds every key, built the same
evening and awaiting review and a live load. The plan is
`dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLAN-KEYMAP.md`.

## Now

Olm has exactly two leaders, Hyper on the app role and META on the window role, each with its own
adapter in `lib/hyperkey.lua` and `lib/windowleader.lua` and its own cheat sheet host, and the
composition root names both. With phase 2a every global key is a row of the keymap,
`lib/keymap.lua`, carrying the function it calls, and `lib/binder.lua` binds the keymap's bound
list on the engine each row's leader names, or as a plain combo, in the order the five old paths
used. A plugin answers what it can run as descriptors through `provides.actions` and binds
nothing, and the app toggler's keys arrive as complete rows through `provides.bindings`, a bridge
phase 6 removes. A list's own keys are still bound through the root's contexts. The collision
check covers every row, modifiers, case, bindings, toggles, commands, list keys and plain combos.
The plan replaces the rest of this with one keymap the core builds from
actions plugins export and bindings they propose, overridden by the person in one file Olm owns,
`config/keymap.lua`, where a chord string maps to a `plugin.action` name and a person may name a
set of modifiers as a leader of their own. The three held leaders are built in from the catalog
and carry a cheat sheet, a modifier leader carries none, and a key switched off for the moment is
swallowed on every leader. The plan ends with one place a person sets a key. App toggles become
actions derived from `config/apps.lua` with behaviour as named variants in apptoggler's data, list
keys get a `lists` layer, Olm's own keys and global commands become actions, `config/keys.lua` is
deleted, and `config/plugins.lua` refuses every key field. A plugin's action is a descriptor, run plus description, icon,
group, kind, app and the rest, answered fixed or built from its data, and Olm derives the key, the
cheat sheet row, the launcher row and the chord label from it, which retires
`cheatSheetSections`, `launcherAppDetails`, `provides.bindings`, and `launcherRows` for anything
that is an action. Each concern then has one way. Actions are declared only as
descriptors, keys are suggested only in `defaults.bindings`, and a person's keys, list keys and
aliases live only in `config/keymap.lua`.

## Rejected

- **A plugin naming a leader rather than a role.** 2026-10-19 16:44. It would let a binding say
  `option` directly, but a shipped plugin would then know the person's own leader names. A binding
  names a role and a leader answers roles, so a plugin travels and the person decides where.
- **Leaving plain combos bound by the plugin through `hs.hotkey`.** 2026-10-19 16:44. It is what
  apptoggler and the clipboard do today, and it is why Option and backtick and the clipboard
  combos reach no collision check and no hint spelling. A combo with no leader key is a chord
  leader with no modifiers of its own, the `global` leader, so it joins the one table.
- **Merging the two adapters before the keymap exists.** 2026-10-19 16:44. The merge is the larger
  risk and has no baseline to compare against until every binding is in one table and a key
  inventory records it, so the keymap and the inventory come first.
- **A person's key choices per plugin in `config/plugins.lua`.** 2026-10-19 17:32. It was the
  first recommendation, matching where a plugin's overrides already live, but a shortcut is the
  host's concern rather than the plugin's, and spreading keys across plugin entries hides the
  whole set from the person reading it. One file Olm owns holds every key, and `config/plugins.lua`
  keeps data and switches only.
- **Passing a key switched off for the moment through to the app in front.** 2026-10-19 17:32.
  Hyper does this today. A key reserved for a situation is never reused for something else, so
  passing it on buys nothing, and one rule for every leader is simpler.
- **A cheat sheet on a modifier leader.** 2026-10-19 17:32. Holding Shift and Ctrl, or left
  Option, is ordinary typing, so a sheet there would flash in use. A held leader is a remapped key
  that types nothing, which is why the sheet belongs to held leaders only.
- **A leaders section that must declare every leader, and a separate global leader.** 2026-10-19
  17:32. Both were in the first draft. The three held leaders come from the catalog and are active
  only while a chord uses them, and a combo with no leader is written as its modifiers, so the
  section exists only to name a new set of modifiers.

- **Leaving app toggle keys in apptoggler's data.** 2026-10-19 17:44. It was the deferred choice in
  the first revision and it left a second place a person sets a key. The keys move into the keymap
  and only the behaviour stays with the plugin.
- **Leaving list keys out of the keymap as navigation inside one list.** 2026-10-19 17:44. It kept
  the file short, but list keys were then the one key still changed somewhere else, under
  `surface` in `config/plugins.lua`, with the shared ones hardcoded and not changeable at all. A
  separate `lists` layer keeps them apart from global chords while keeping one file.

- **An action exported as a bare function, with presentation through side channels.**
  2026-10-19 17:50. It was the shape of the first three revisions, matching what windowmanager
  exports today, but it left each surface its own provides field, a launcher row list, a cheat
  sheet section and app row details, so a plugin still had to learn every surface and the toggler
  stayed special. A descriptor carries what every surface needs and Olm draws them all.
- **A `chordsFor` lib so a plugin could label its own keys.** 2026-10-19 17:50. Proposed at 17:44
  for the toggler's sheet section. It handed a plugin knowledge of its keys, which is the coupling
  the plan removes, and descriptors make it unnecessary.

- **Keeping `registry.commands`, `specialRows` and the `defaults.key` shorthand beside
  descriptors and bindings.** 2026-10-19 17:57. Each still works and moving them is churn, but each
  is a second way to declare something runnable or to suggest a key, which is the drift a one way
  rule exists to stop.
- **Leaving alias overrides in `config/plugins.lua`.** 2026-10-19 17:57. Aliases were never keys,
  so the earlier revisions left them, but they answer the same question, how a plugin is reached,
  and splitting that question across two files was the problem this plan set out to remove.

- **Keeping the old binding paths callable as a fallback for a keymap that fails to build.**
  2026-10-19 19:39. It was the lean in the brief for phase 2a, so a defect in the read model
  could not leave a machine with no keys. The evidence ran the other way. No plugin binds a key
  any more and the dry gate refuses a bind call under `plugins/` and `host/`, so the only paths
  left to fall back on were the root's own, the registry shortcuts, the host keys and the special
  rows, which would bind some keys and silently drop every plugin binding and toggle. A partial
  fallback with nothing saying which half is missing is worse than one loud line. The build is
  pure, has never raised, and runs under pcall, so a raise is reported in the wiring report as
  leaving every global key unbound, and the lists' own keys, the leaders' taps and the remap are
  left as they are.

## Log

- 2026-10-19 16:44. Milos asked how Olm should split core from plugins for shortcuts, with the
  example of Option and E for one plugin and Option and Y for another. Two reads of the tree found
  the five binding paths, the two near copy adapters, the narrow collision check, the hint bar
  spelling only the app leader, and no key inventory. The plan was written from those findings. It
  reopens the 2026-10-16 16:52 rejection in `olm-core-split.md` of binding a registry tool on the
  window leader, because that rejection rested on no plugin having the case and the case now
  exists, a person placing any action on any leader. Three questions are open, whether a gated key
  on Hyper is swallowed or passed through, whether a chord leader shows a sheet, and whether
  placements live per plugin in `config/plugins.lua` or in one keymap file.
- 2026-10-19 17:32. Milos answered the three questions. A key switched off for the moment is
  swallowed on every leader, since a key reserved for a situation is never reused. A cheat sheet
  is safe on Right Option because it is remapped and types nothing, which narrowed the no sheet
  rule to modifier leaders. And a person's keys live in one file Olm owns, `config/keymap.lua`,
  a chord string to a `plugin.action` name, with a `leaders` section only for naming a set of
  modifiers, after the per plugin placement in `config/plugins.lua` was turned down. The plan was
  revised to this shape.
- 2026-10-19 17:44. Milos asked for one way of managing keys. A read found seven places a person
  sets a key today, the leader roles and the app toggles in `config/keys.lua`, a tool's key, a
  plugin's bindings and list keys in `config/plugins.lua`, the registrar's command override, and
  the launcher host's own keys, with the shared list keys hardcoded in `lib/surface.lua`. The
  clipboard's `data.shortcut` was found to be an outgoing combo rather than a binding and stays
  plugin data. The plan gained phases 6 and 7, app toggles as actions and list keys in the
  keymap, and ends with `config/keymap.lua` as the only place a key is set.
- 2026-10-19 17:50. Milos asked whether the plan unifies every plugin rather than only where keys
  are set, and said plugins should be as decoupled as possible. The review found that an action as
  a bare function still left four presentation channels, two of them used only by the toggler, and
  that layouts, profiles and settings panes have the same built from data shape the toggler has.
  The plan now makes the action descriptor the whole declaration and Olm derives every surface
  from it, phase 2 introducing descriptors, phase 4 building sheet rows from them and phase 6
  covering every plugin whose actions are built from data.
- 2026-10-19 17:57. Milos asked whether the plan now gives one way for everything. A check against
  that goal found three places with two, alias overrides still in `config/plugins.lua`, the
  registry's `commands` block and the launcher's lock and sleep rows declaring runnable things
  beside descriptors, and the `defaults.key` shorthand beside `defaults.bindings`. All three were
  folded in, aliases into `config/keymap.lua`, commands and special rows into descriptors, and the
  shorthand into `bindings` rows for `open`, and the plan now carries a table of each concern and
  its one way.
- 2026-10-19 18:11. Phase 0 landed. `test/keys-probe.lua` reads every chord the live config has
  bound, through the two leader engines and `hs.hotkey.getHotkeys`, and `test/keys.sh` diffs it
  against `test/keys.golden`, 159 lines on main, 140 on Hyper, 16 on META and 3 plain combos, with
  every owner resolved from declarations and none guessed. Two runs are byte identical.
  `test/leaders.lua` pins both adapters' resolvers as they stand, 44 checks, the gated key
  difference included. The read found three dormant binding paths the plan's list did not name,
  capture's and the clipboard's `hs.hotkey.bind` for a binding stating `modifiers`, apptoggler's
  literal Hyper fallback, and Hyper's chord trigger, none of which binds anything on this machine,
  and all of which phase 2 removes. It also found that the window leader folds key case at bind,
  so META and C is center with no shift tier, which the merge in phase 3 must keep.
- 2026-10-19 19:05. Phase 1 built, awaiting review and a live load. `lib/keymap.lua` is a pure
  read model, one row per chord with layer, leader, key, mods, owner, action, source, when,
  priority, description and origin, built in the root right after the registry registers and
  kept on the record as `keymap`. It reads the plan, the registry's shortcuts, the manifests'
  commands, the data each plugin was handed and the roles, and names no plugin and no leader.
  Toggles are found by the shape of the data, a list under `toggles`. Collisions are layer,
  leader, key and mods, reported through the wiring report's own problem channel, with the one
  exemption the old check kept. The key slot half of `defaults.collisions` is retired and its
  alias half stays. The offline projection of the keymap into the golden's format matched
  `keys.golden` byte for byte, 159 lines and no collision on this config. The stub cannot know
  the real keycode table, so it matched with a table dumped from the live session and also
  without one, and it cannot tell which tools are installed, so the offline run reports every
  one present, without which tmux sessions is left out of the plan and 6 lines go missing. The
  live `--keymap` projection is still owed, it needs the worktree made live under the test lock.
- 2026-10-19 19:12. Phase 1 landed after a live load of the branch under the test lock. The
  console was clean, the wiring report said no problems, the live root built 159 keymap rows, and
  both `keys.sh --keymap` and `keys.sh` matched `keys.golden`. A review before the load put the
  build under pcall, since a read model that binds nothing must never stop the keys after it.
- 2026-10-19 19:39. Phase 2a built, awaiting review and a live load. `lib/binder.lua` is the one
  place a global key is bound. It walks the keymap's new `bound` list, the global rows in the
  order the old paths bound them, plugin bindings and provided rows in plan order, then the
  registry's shortcuts in registration order, then host keys, then special rows, and binds each
  on the engine its leader names, or through `hs.hotkey.bind` for a row with no leader, passing
  `when`, `priority` and `repeats` in the options. Each keymap row now carries `run`, the
  registry fn for a tool or a command, the descriptor's run for a binding, the provided row's fn,
  the host's show and the launcher's lock and sleep calls, all handed to the keymap by the root,
  so the module still names no plugin and binds nothing. The order lives on a second list rather
  than as a number on each row, since the number is a place in the plan's own order and showed as
  80 differences in the rename proof. `lib/registrar.lua` lost `bind` and gained
  `validateActions` and `providedBindings`, refusing a malformed descriptor or row with one
  problem line, and `lib/wire.lua`'s register stage no longer binds. Capture and windowmanager
  answer descriptors and lost `bindHotkeys` and `bindToLeader`, windowmanager its
  `needs.lib.windowLeader`, capture its `hs.hotkey.bind` fallback, windowsize calls `run`, and
  apptoggler builds its rows in configure and lost its wiring step, its `hyperKey` need and its
  literal Hyper fallback. The keymap's toggles source reads the bridge instead of a data shape.
  The clipboard's dead `bindHotkeys` is deleted, and the dry gate refuses `hs.hotkey.bind`,
  `hs.hotkey.new` and any bind call under `plugins/` and `host/`. This reopens the 2026-10-16
  16:52 rejection in `olm-core-split.md` in code, a registry tool on the window leader is no
  longer refused and binds there. Its window sheet does not list it yet, since that sheet reads
  only bindings, and phase 4 closes that. Proof, all offline. `keys.sh --offline` matches the
  golden, and the new `keys.sh --bound`, which records every bind call under the stub, matches
  it byte for byte too, 159 lines, as main's own recording did. `keys.sh --bound-order` against
  a copy of main shows every engine receives its bindings in the same order on every key. The
  wiring report under the stub says no problems.
- 2026-10-19 19:51. A review of the 2a commit found no blocker and seven fixes, applied on top. A global row's
  predicate now reaches an engine as `gate` rather than `when`, since on Hyper every `when`
  was recorded as a context, so a gated global row such as a window binding moved to the app
  leader would have made Hyper modal and silenced every base key while it held. HyperKey treats a
  gate as eligibility alone, the window leader reads it as its `when`, and list keys keep
  `when`. Each keymap source now reads under its own pcall, so one raise costs that source's
  keys with one problem line and the root's pcall is the last defence. A failed actions member
  marks every binding of its plugin refused, so it reports once. A host with a key and nothing to
  show is a quiet row again, unbound in silence as on main. Two roles naming one catalog leader
  are a problem line rather than one engine silently replacing the other. The binding scan now
  sees `hs.hotkey.modal` and skips block comments. `olm-core-split.md` Now no longer says a
  window tool is refused. The golden, the bound recording and the order against main still match.
- 2026-10-19 19:54. Phase 2a landed after a live load of the branch under a manual hold. The
  console was clean, the wiring report said no problems, the live keys matched `keys.golden`, and
  Milos pressed one key from each binding path, the launcher on Hyper and space, a toggle, a
  window action on META, the placed terminal on Option and backtick, a tool's open key and Caps
  Lock's tap, and called all of them good. Phase 2b, launcher rows from descriptors, the
  retirement of `registry.commands` and the `defaults.key` shorthand as `bindings` rows, is next.
