# Olm keymap, and leaders as data

Status. Phases 0 to 5 landed and live, 0 to 2b on 2026-10-19 and 3 to 5 on 2026-10-20, so a
person sets any key in `config/keymap.lua`. Phase 6 landed and live on 2026-10-20, so app
toggles and System Settings panes are actions built from data and `config/keys.lua` is gone.
Phase 7 landed and live on 2026-10-20, so the plan is complete. The keys
live while a list is open are the `lists` section of `config/keymap.lua` and `config/plugins.lua`
holds no key. The plan is
`dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLAN-KEYMAP.md`.

## Now

A person's keys and aliases are written in `config/keymap.lua`, read by the root alone as
`cfg.keymap`, a chord to `identity.action` or false, a set of modifiers named as a leader, a role
moved to another held leader, and replacement aliases. An action named there takes exactly its
listed chords, a person's chord on a default's slot drops that default with a routine line, and a
held leader is remapped exactly while some bound row uses it. Olm builds a candidate leader per
catalog row and per named leader and keeps the ones the keymap's rows use, Hyper on the app role
and META on the window role here, each an instance of the one adapter `lib/leader.lua` with a held trigger and a
policy from `policy.leaderPolicy`, plus a plain leader on an empty set of modifiers for a combo
with no leader, and the composition root loops over them naming none. A key gated off is swallowed
on every leader and an unknown predicate name warns once on every leader. Over an open list every Hyper key that is not a live list key is swallowed too, through `sealedOverLists`, and outside lists an unbound key still passes through. One cheat sheet host,
`host/leadersheet`, draws whichever held leader is down, its layout a table beside `sheet = true`
in that leader's policy, and a descriptor's `group` files a row under a section. With phase 2a every global key is a row of the keymap,
`lib/keymap.lua`, carrying the function it calls, and `lib/binder.lua` binds the keymap's bound
list on the engine each row's leader names, or as a plain combo, in the order the five old paths
used. A plugin answers what it can run as a list of descriptors through `provides.actions` and
binds nothing, and since phase 2b Olm also builds a launcher row from every listed descriptor,
with the chord the keymap binds, so capture, the window manager and the clipboard build no row.
`defaults.bindings` is the one place a plugin suggests a key, a tool's open key being the row
whose action is `open`, a row naming its own role or `leader = false` for a plain combination,
and `defaults.leader` the role a row naming none inherits. `registry.commands`, `defaults.key`
and `defaults.mods` are retired and refused by name. Every leader's sheet reads the keymap. Since
phase 6 the app toggler answers one action per app in `config/apps.lua` and one per named variant
in its data, built in configure, each naming its app and a group function answering a RUNNING
table or a faded DORMANT table, and every toggle key is a line of `config/keymap.lua`, so
`config/keys.lua` is gone. Hyper and comma is `systemsettings.General`, one action per pane that
toggles System Settings onto it, while the pane rows the launcher lists stay rows, since a row
must navigate and never hide the app. The sheet files rows in blocks by each owner's
`defaults.cheatSheetOrder`, draws a row naming an app with that app's icon and name and leaves an
uninstalled one off, and the launcher merges an action naming an app into that app's own row
with its chord. `provides.bindings`, `provides.cheatSheetSections` and
`provides.launcherAppDetails` are retired and refused by name. A list's own keys are bound through
the root's contexts, built by `lib/surface.lua` on Olm's own `all` layer, `keymap.listDefaults`,
and laid over by the person's `lists` section through `keymap.applyLists` before the hint bar, the
action panel, the keymap and the contexts read them. `config/plugins.lua` refuses `key`, `mods`,
`leader`, `bindings`, `surface` and `aliases` with a problem line naming `config/keymap.lua`. The collision
check covers every row, modifiers, case, bindings, toggles, commands, list keys and plain combos.
The plan replaces the rest of this with one keymap the core builds from
actions plugins export and bindings they propose, overridden by the person in one file Olm owns,
`config/keymap.lua`, where a chord string maps to a `plugin.action` name and a person may name a
set of modifiers as a leader of their own. The three held leaders are built in from the catalog
and carry a cheat sheet, a modifier leader carries none, and a key switched off for the moment is
swallowed on every leader. The plan ends with one place a person sets a key, which phase 7 made
true. A plugin's action is a descriptor, run plus description, icon,
group, kind, app and the rest, answered fixed or built from its data, and Olm derives the key, the
cheat sheet row, the launcher row and the chord label from it, which retired
`cheatSheetSections`, `launcherAppDetails`, `provides.bindings`, and `launcherRows` for anything
that is an action. Each concern then has one way. Actions are declared only as
descriptors, keys are suggested only in `defaults.bindings`, and a person's keys, list keys and
aliases live only in `config/keymap.lua`.

## Rejected

- **Keeping global keys live over an open list.** 2026-10-20. Leaving an unbound Hyper key to
  pass through while a list is open would let a global toggle fire underneath the list, acting on
  whatever sits behind it. Milos chose to swallow instead, see the log.
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

- **A table of action descriptors keyed by name.** 2026-10-19 20:53. It was the shape phase 2a
  shipped, and it says nothing about order, while every surface that lists actions needs one, the
  launcher's rows first. Ordering by the plugin's bindings reproduced the window rows and not the
  clipboard's, whose keyless manage history sat between its two keyed commands, and ordering by
  name did the reverse. A list where each descriptor names itself is the plugin saying its order
  once, so `provides.actions` answers a list and a keyed table is refused whole.
- **Retiring `defaults.leader` with `defaults.key`.** 2026-10-19 20:53. The plan listed all three
  as shorthand for the open key. `defaults.leader` turned out to be read by every bindings row of
  a plugin, not only the open key, so retiring it would move the role onto every row, sixteen
  times for the window manager, to say one thing. It stays as the default a row naming no role
  inherits, a default for a field rather than a second way to declare a key, and the plan text
  was corrected.
- **Keeping a predicate on both the window manager's bindings and its descriptors.** 2026-10-19
  20:53. The window sheet read the raw bindings for `when` while the launcher rows needed it on
  the descriptor, so either the gate was written twice or the sheet moved. The sheet now reads the
  keymap's rows on its leader, a step phase 4 had planned, and the gate and the repeat live once,
  on the action.

- **Unifying the two tier rules in the merged resolver.** 2026-10-19 21:53. One rule for every
  leader was the obvious shape for one adapter. But Hyper picks the best priority and lets a gated
  binding drop out of its tier, while the window leader takes the first exact match, swallows a
  gated one there and lets the last catch all win, and `test/leaders.lua` pins both. Either rule on
  the other leader changes which binding answers some press, so the rule follows the `contexts`
  policy and priority stays a property of a leader that hosts lists.
- **Keeping `policy.hyperTrigger`, Hyper as a modifier chord with a hold reveal.** 2026-10-19
  21:53. It was the chord shape inside the old hyperkey and still worked. The plan makes a named
  set of modifiers a leader of its own and rejects a sheet on one, so keeping it would have meant a
  modifier trigger with a reveal for one case nobody here uses. It is retired and named as a
  problem line when a config sets it.
- **Capture keeping a leader lib to wait on.** 2026-10-19 21:53. Generically it would ask the
  leader adapter whether it is held. But capture's wait is unconditional, every action of it posts
  a keystroke, and it waited on Hyper whichever leader its key sat on, so the fact belongs on the
  descriptor as `afterRelease` and the core waits on the leader that actually fired. The clipboard
  is the case where a lib stays, since its wait is the chosen provider's answer at the press.
- **A plain combo resolved against the hardware modifiers when its callback runs.** 2026-10-19
  21:53. That is what the chord shape did. `hs.hotkey` fires only on exactly the combination it
  claimed, so the claimed set is the truth, and reading the hardware a moment later could turn a
  press made with a finger lifted early into nothing, where the binder's own `hs.hotkey.bind`
  always ran.

- **Two sheet hosts sharing a row builder.** 2026-10-20 08:30. It would have been the smaller edit,
  since only the sources of the rows had been unified and the two hosts differed in layout, but
  the layout was the whole difference and it belongs to the leader. A new leader would still have
  needed a host written for it, and a rule such as gating a row on `when` had already lived in one
  host and been missed in the other. One host with the layout in policy needs no new file for a
  new leader.
- **The layout in the host, keyed by leader name.** 2026-10-20 08:30. It was the first shape
  considered, a table inside the host mapping hyper and meta to their columns. It names the
  leaders, which is the roster the sheet host exists to stop holding, and a new leader would have
  edited the host. The layout is policy, validated with the rest of the policy.
- **`sheet` staying the identity of the host and a second field for the layout.** 2026-10-20 08:30.
  With one host there is nothing to name, and a word that names a directory is the kind of quoted
  value the policy otherwise avoids. `sheet` is a boolean and `sheetLayout` a table.

- **Binding a person's chord beside the default it lands on.** 2026-10-20 09:19. It is what the
  collision check's one exemption allowed, both rows bound and the binding order deciding which
  answers. A default the person wrote over can never be wanted on that chord, and two rows on one
  slot read as one on the sheet and two to the engine, so the default is dropped and said once as
  a routine line.
- **Keeping the leaders in use as the ones a role names.** 2026-10-20 09:19. It was the rule since
  the catalog moved into the root, and it was cheap because the roles are known before anything
  loads. But it remapped Right Option for a role whose every row the person moved, and it could
  never claim Right Command for one chord written on super. The bound rows decide, so the root
  builds every catalog leader as a candidate and keeps the used ones after the keymap.
- **The slot of a named modifier leader's chord by its leader name.** 2026-10-20 09:19. That is the
  slot shape every held leader has. A named leader is claimed as the whole combination through
  `hs.hotkey`, so `nav+T` and `ctrl+shift+T` are one physical chord, and naming them apart would
  let both claim it with nothing reported.
- **An entry naming a plugin switched off as a problem.** 2026-10-20 09:19. Switching a plugin off
  takes its keys with it, which is what the person asked for, so a keymap entry for it binds
  nothing and says so in a routine line, and only an identity naming no plugin at all is a
  problem.

- **The System Settings pane rows as the pane actions' launcher rows.** 2026-10-20 10:20. It was
  the plan's shape, panes as descriptors in place of `launcherRows`. But Hyper and comma hid
  System Settings when it was already in front and had to keep doing so, while a pane picked from
  the launcher must navigate, and the launcher hands focus back to the app it covered before it
  runs a row, so a row running the toggle would hide System Settings whenever a person used the
  launcher from inside it. A descriptor has one run, and the row's memory key was the pane's url,
  which a descriptor row cannot state. So each pane is an action for keys and the rows stay rows.
- **A running group of System Settings' own, so Hyper and comma stayed in the app section.**
  2026-10-20 10:20. It would have kept the gear icon among the apps exactly as before. It meant a
  second plugin answering the same RUNNING and DORMANT words and its own running check, a
  vocabulary repeated across plugins with only equal strings joining the sections. The pane action
  is a command, so its row sits among the Hyper sheet's actions as General settings.
- **Olm splitting app rows into running and not running by itself.** 2026-10-20 10:20. Olm knows
  `app` and could ask which apps run, which would have needed no group from the plugin. The plan
  gives the split to the descriptor's group, which keeps what a section means the plugin's choice,
  and Olm owns only how an app row is drawn, its icon, its name, an uninstalled app left off and
  the order by key.

- **Olm's `all` layer in `policy` beside the leader catalog.** 2026-10-20 12:10. It is where the
  core's other defaults live, which made it the first place considered. But `cfg.policy` merges
  over it, so a person could move a list key there as well as in `config/keymap.lua`, a second
  place to set a key. It is `keymap.listDefaults`, read by nothing a person writes.
- **An `all` layer keyed only by action names.** 2026-10-20 12:10. It is how the plan wrote it,
  and every list's primary and close happen to share one name today. But each list names its own
  primary action and may name its own close, so moving the primary in every list would have named
  an action some list does not answer. A shared verb is named by what it does and every other
  action by its name.
- **Laying the person's lists inside `lib/surface.lua` or the resolver.** 2026-10-20 12:10. Both
  already touch the bindings, and the resolver once merged a person's `surface` fragment there.
  The builder would then learn the person's keys, and the resolver hold a second copy of the
  keymap's three rules. The root lays the section with `keymap.applyLists` beside the keys
  section's rules, and the builder takes only Olm's own layer.
- **Binding both of two entries on one slot of a list and reporting the pair.** 2026-10-20 12:10.
  It is the keys section's rule. In a list an `all` clash would be reported once for every list it
  reaches, and binding both leaves the engine's order to pick. Both are refused with one problem.
- **The person's `all` moving every list's shared verb, a key a manifest states included.**
  2026-10-20 12:23. It was the first build, so `all` with `close` on C moved the launcher's close off
  space. The launcher's space close doubles as its open toggle, and a manifest states its own key
  for a shared verb exactly when that list needs it to differ, so `all` would undo the one
  decision the list made. Milos decided that `all` moves and frees only keys Olm's own layer gave,
  and a list's own key moves when the person names that list.

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
- 2026-10-19 20:53. Phase 2b built, awaiting review and a live load. Two baselines were taken
  first from the live main config, read only, `test/launcher.golden`, the launcher's own catalog
  in resting order with each row's remembered key, title, subtitle, icon and its owner, gate,
  keywords and order number, 85 lines, and `test/sheets.golden`, both sheets' content model, 54
  lines, the Hyper sheet's app sections written as headers and one sorted membership so whether an
  app is running does not move a line. `test/views.sh` diffs both live or offline and
  `test/goldens.sh` runs all three goldens offline in one command. The offline sheets run answered
  installed apps from `test/sheets-apps.lua`, a fixture the live probe wrote, corrected at 21:10,
  and the offline runs
  answer a tool at a fixed system path present the way they already answered a PATH tool, without
  which the Dock row went missing. The first launcher golden also carried each row's routing owner,
  and the branch showed exactly one difference there, the clipboard's three rows now owned by the
  clipboard and run by its descriptors rather than by the registry, which is the intended move, so
  the column was taken out as routing rather than anything a person sees and the golden retaken
  from live main, identical in every other field. The build. `provides.actions` answers a list,
  `lib/contributions.lua` builds one row per listed descriptor with the keymap's chord and one
  runner per owner, and the launcher puts a registered tool's own action rows right after its row.
  Capture and the window manager lost `launcherRows` and `launcherRun`, the window manager's gates
  and repeats moved onto its descriptors, exact size and screen recording are unlisted since
  neither had a row, and Window Size finds exact size by name. The clipboard's three commands,
  manage history included, became descriptors of kind special, so `special:appendCopy` and its
  siblings are remembered exactly as before, with append copy and paste next as `leader = false`
  rows. `lib/registry.lua` lost commands whole and refuses a descriptor carrying them,
  `registrar.commandKey` and the command half of the `meta` override went, and
  `registrar.retiredFields` names `registry.commands`, `defaults.key` and `defaults.mods` on every
  load and in the dry gate. Every open key is a bindings row, the keymap tells a tool's open row
  from a host's, and each row now carries its role and its modifiers in the order a Mac spells
  them, which the launcher and both sheets read, since the keymap's sorted order would print
  Option before Control. A person's `key` and `mods` in `config/plugins.lua` land on the open row
  through `lib/defaults.lua` until phase 7, and this machine's file sets none. One defect was found
  on the way and fixed. `lib/plugins.lua` sorted the plan's entry order but walked each plugin's
  siblings and set queries with `pairs`, so the plan order, the registry and the launcher's
  catalog varied between loads, two runs in six of main's own tree listing the tools in another
  order. Sorting those edges made six runs in a row agree, and agree with the live golden. Proof.
  All three goldens reproduced byte for byte offline, `keys.sh --bound` matched and
  `--bound-order` against a copy of main showed the same order on every key, the dry gate reported
  no finding and no unknown with a clean rename proof, the plain Lua cases pass, and the three
  unit cases this phase touched, the registry, the leader sheets and the launcher contributions,
  pass under plain Lua. They also run inside the live Hammerspoon, which this build did not do.
- 2026-10-19 21:10. An adversarial review of the 2b commit found no blocker and seven fixes,
  applied on top. A person's `key = NONE` or `key = false` unbinds the open row again, as it left
  a tool with no key on main. A person's `bindings` override that states no open row keeps the
  plugin's default one unless the key was declined, every other row still replaced wholesale, and
  a registered leader tool left with no open row is one problem line, quiet where the person
  unbound it. Writing the case for that found a worse defect in the translation itself, an
  override holding only `key` left an empty table to merge, which the merge reads as a list and
  so replaced every default of the plugin with nothing, and it now merges nothing. The sheets
  golden committed this machine's app inventory, `test/sheets-apps.lua`, which made it a per
  machine file against the root rules on machines, so the fixture is gone and a supplied section
  is written as its headers alone, its rows checked by eye, retaken from live main at 36 lines and
  reproduced offline. A descriptor's launcher row now takes its key's gate, the binding's own
  `when` before the descriptor's, as the keymap and both sheets do. The `windowBindings` docs in
  the contract, the root and the window sheet manifest describe the step K handover. A descriptor
  claiming a kind the launcher keys specially, app, calc or scope, read from the launcher's own
  `reservedKinds`, is refused, and special is refused only on a registered tool's name. A role word
  no leader answers is a problem naming the plugin, the action and the word, and that row is left
  unbound rather than moved to the app leader. All three goldens match offline and live, the bound
  recording and the order against main match, and the dry suite, the dry gate and the dependency
  check are clean.
- 2026-10-19 21:18. Phase 2b landed after a live load of the branch under a manual hold. The
  console was clean, the wiring report said no problems, and keys, launcher rows and sheet
  headers all matched their goldens live. Milos ran a window action from its launcher row, saw the
  paste next row with its chord, pasted with Ctrl, Option and V, started an area capture on Hyper
  and 4 and opened the VPN list, and called all of them good. The branch was squashed to one
  commit before merging so the machine specific app fixture never reached history.
- 2026-10-19 21:53. Phase 3 built, awaiting review and a live load. `lib/leader.lua` replaces
  `lib/hyperkey.lua` and `lib/windowleader.lua`, which are deleted, with the trigger a Strategy in
  `lib/leader/triggers/held.lua`, one function key through ChordKey, and
  `lib/leader/triggers/modifier.lua`, combos claimed through `hs.hotkey` on a base set, named only
  in the root. The policy is `policy.leaderPolicy` beside `policy.leaderCatalog`, keyed by catalog
  name, every field a boolean or a number apart from the sheet host, HYPER `tapTogglesCapsLock`,
  `contexts` and the Hyper sheet, META and SUPER `drivenRepeat`, `quietOverLists` and the window
  sheet, checked once with a problem line for a typo. The root builds the leaders in one loop over
  the referenced catalog names and a plain leader on an empty base set, which the binder now hands
  every row with no leader instead of calling `hs.hotkey.bind` itself, and it names no leader
  anywhere. `appKeycode`, `windowKeycode`, both atoms, both two element lists, the role pair the
  binder's engines were keyed by and the Hyper reveal closures are gone. The leader that hosts
  list keys, the chooser field's yield, `leaderHeld` and the contexts stage are all the one leader
  whose policy turns contexts on, a missing or second one a problem line. `hints.chordFor` spells
  a binding's own leader through `leaderNames`, and the hint bar's default word is the context
  leader's. The predicate table installs into every leader. Capture's wait for Hyper became the
  descriptor field `afterRelease`, honoured by the leader that fired the key and by a launcher row
  for every held leader, so capture lost `needs.lib.hyperKey`. The clipboard's `hyperKey` became
  `leader`, a view answering whether any held leader is down. Every reader moved, the key probe and
  the inventory to the new `_composed.leaders`, the bound recording to a tap on the adapter's own
  `bind` that still labels an older spoon's two adapters, and the unit cases. Exactly two
  behaviours changed as agreed, a key whose matching bindings are all gated off is swallowed on
  every leader, and an unknown predicate name warns once on every leader. On this machine the keys
  that flip outside a list from leaking to swallowed are Hyper and H, Q and Y, the file search
  list's own keys, and inside any open list every Hyper key another list binds and this one does
  not. A key dropped by the modal rule still passes through. The plan was wrong that the gated key
  change would show in the keys golden, since that golden records bindings and not resolution, and
  the host key check it listed had already gone in 2b. Proof, offline unless said. All three
  goldens byte identical, `keys.sh --bound` matching and `--bound-order` against a copy of main the
  same order on every key, the old probe against live main identical to the golden, the new probe
  identical to it both against live main through its fallback and against the stubbed new root
  through `_composed.leaders`, `test/leaders.lua` 116 checks with every old case held but the
  named flips, the dry gate at 0 findings and 0 unknown with a clean rename proof and its binding
  rule still refusing a bind under `plugins/` and `host/`, and the dependency check clean.
- 2026-10-19 22:05. An adversarial review of the phase 3 commit found no blocker and six fixes, applied on top.
  The swallow rule was described as narrower than it is. Inside an open list the modal rule drops
  every base binding, and a key some other list binds is then swallowed through that list's gated
  binding, so with the launcher open Hyper and A, D, F, L, M, R, S, X, H, Q and Y are swallowed while
  B, C and E still pass through. The behaviour stays, it is the agreed rule, and `lib/leader.lua`,
  the hammerspoon `AGENTS.md`, `Spoons/Olm.spoon/AGENTS.md` and `PLUGIN-CONTRACT.md` now state both
  halves. The modifier trigger claims each combo under its own pcall, so one raise costs that combo
  alone with one line naming its key and modifiers, the per row isolation the binder gave before.
  It installs the repeat callback when any binding on a combo repeats rather than only the first,
  resolving at each repeat, and reclaims a combo when a repeating binding arrives after start. It
  passes a declared fn through to `hs.hotkey`, as main did. A launcher row that waits for release
  now waits until no held leader is down, through `afterAllReleased` in the adapter, where it waited
  on the first held leader alone. Two changes the phase 3 entry did not list are recorded here. META
  now receives the merged predicate table every leader gets, every surface gate plus the root's own,
  where it had the root's own alone, which changes nothing a binding on it names today. And the
  overlay hide every action calls now takes down any leader's revealed sheet, the window sheet
  included, where it hid the Hyper sheet alone, which matters only if an action runs while a window
  sheet is up. The goldens, the bound recording and its order against main, the plain Lua cases at
  130 checks, the dry suite, the dry gate and the dependency check all pass.
- 2026-10-20 08:11. Phase 3 landed after a live load of the branch under a manual hold. The console was
  clean, the wiring report said no problems, and all three goldens matched live. Milos checked
  Caps Lock's tap, both cheat sheets on hold, a held window move on META, a list key inside the
  launcher, a toggle, a capture after release, a plain combo paste and the placed terminal, all
  good. He noticed a held move does not speed up the longer it is held, which is the recorded
  design, a press moves movePixels and every repeat movePixelsHeld at the machine's steady rate,
  nothing ramps. The test instruction that said it would speed up was wrong, not the code.
- 2026-10-20 08:30. Phase 4 built, awaiting review and a live load. `host/leadersheet` replaces
  `host/hypercheatsheet` and `host/windowcheatsheet`, both deleted. The adapter hands it the
  leader's own keycode on a hold and it draws that leader's record, built by the root in step K.
  A record is the leader's keycode, its layout and an ordered entries list, which is the leader's
  own block, `LeaderSheet.ownSections` over `hints.sheetRows`, placed among the sections plugins
  supply by `lib/contributions.lua` as before. Policy changed shape. `sheet` is a boolean and
  `sheetLayout` is a table of `title`, `columns`, `colWidth`, `iconSize`, `gap`, `groupGap` and
  `badgeWidth`, checked by `leader.checkPolicy` and defaulted by `leader.sheetLayout`, to two columns
  of 250 under SHORTCUTS. HYPER ships four columns of 215 with a 32 point icon, a gap of 10 and a group
  gap of 20 under ACTIONS, META and SUPER ship two columns of 250 with a badge of 44 and a gap of 12
  under WINDOW MANAGEMENT. `windowSectionTitle`, the root value `leaders`, `windowBindings`,
  `leaders.stampBindings`, `hints.sections` and `hints.leaderRows` are retired, the manifest needs
  became `sheets`, required, and `predicates`, optional. Five things the plan did not say. The two
  sheets ordered rows differently, so `hints.sheetRows` is the one rule, the Hyper order, and only a
  tool's open key moved onto the window leader would show a difference. The Hyper sheet had ignored
  `when`, so now it gates like the window sheet, which no Hyper row on this machine exercises. A row
  with no description now wears its action in words on every leader. The keymap row gained
  `group`, from the descriptor, a function being asked with nothing at every show. The line
  `sheetSections` said for a supplier on another role would have named the toggler unreached while
  the window sheet asked, so it moved to `unreachedSheetSections`, said once. The old sheets probe
  was run against live main and matched `sheets.golden` at 36 lines, then the new projection run
  offline over the new host matched the same golden byte for byte, with the two line families the old
  hosts wrote kept on purpose. All three goldens, the bound recording and its order against an
  archive of main, the plain Lua cases at 81 checks in `test/leadersheet.lua` and the unit case
  over the real manifests, the dry suite, the dry gate at 0 findings and 0 unknown, the rename
  proof at 0 differences and the dependency check pass. What none of them can see is the drawing,
  so holding each leader under the test lock with the sheet beside the old one is owed.
- 2026-10-20 08:39. Review fixes of phase 4 applied on top of 57e4fbd4, which found no blocker. `sheet = false`
  in a person's policy no longer reports the shipped layout merged beside it, and only a layout
  stated with no sheet is a problem. `hints.sheetRows` lists provided rows, `provides.bindings`,
  unless their plugin supplies sections for the leader's role, so a provided row reaches a sheet
  without the toggler being listed twice. The sheet's default sizes are read from the renderer,
  which exports `DEFAULTS`, instead of copied. The unknown predicate warning is said once per name.
  A leader answering two roles asks for the suppliers of both, and neither is reported unreached.
  Two behaviours of the phase 4 entry are stated here since it did not. Duplicate chords on one
  sheet collapse to the first, now on every leader, though the keymap already refuses two rows on a
  chord. And a supplied section no longer accepts `bindings`, only `rows`, a shape no supplier used
  and the contract never documented. Plain Lua cases cover each fix, 93 checks in
  `test/leadersheet.lua`.
- 2026-10-20 08:45. Phase 4 landed after a live load of the branch under a manual hold. The console was
  clean, the wiring report said no problems, and all three goldens matched live. Milos held Caps
  Lock and Right Option and judged both sheets the same as before, the Hyper sheet's four columns
  with its action rows and app sections, and the window sheet's two columns of wide badges. The
  squashed commit was first built on main's moved tip and would have reverted another session's
  handoff skill, which a diff caught before the merge, and it was rebuilt on its merge base.
- 2026-10-20 09:19. Phase 5 built, awaiting review and a live load. `config/keymap.lua` is new,
  every section present and empty with a header in the house style, and init.lua hands it to Olm
  as `cfg.keymap`, no plugin reading it. `lib/keymap.lua` gained `readConfig`, which reads the four
  sections and names every entry it cannot read, `parseChord`, the grammar, a leader or modifiers
  joined by a plus with the key last, a trailing pair of plus signs being the plus key, a leader
  chord with no modifiers a catch all like every default, and `leadersInUse`. `build` lays the keys
  over the defaults. An action named there takes exactly its chords and loses every row it had,
  its new rows copying the gate, label, repeat and function of the first row it had, or built from
  the descriptor, the tool, the host or the provided row its id names. A person's row on a default's
  slot drops the default with one routine `Olm keymap` line, every row of the person's included,
  which replaced the collision check's exemption, and false frees a slot. Two of the person's own
  on one slot are a collision named by entry, and an entry for a plugin switched off is a note.
  A named leader's slot is its whole combination. `roles` replaced `appLeader` and `windowLeader`,
  both removed from `config/keys.lua` since they equalled the defaults, and is merged by hand, since
  `lib/defaults.lua`'s merge read the empty section as a list and left no role at all, which the
  first offline run caught. `cfg.leaders` is retired and named. `aliases` merges over the person's
  overrides before the plan resolves, the keymap winning, and this machine's `config/plugins.lua`
  had no alias override to move. The root builds a candidate leader per catalog row and per named
  leader, keeps the ones `leadersInUse` answers after the keymap is built, and the leader list, the
  binder's engines, the sheets, the remap and the leader hosting lists follow it, the last chosen
  from the catalog by policy since list keys always use it. A keymap that fails to build falls
  back to the leaders the roles name. Lock and sleep are the launcher's own descriptors through
  `provides.actions` with bindings rows, kind special so their rows keep `special:lock` and
  `special:sleep`, the launcher pushes its declared rows ahead of its suppliers so the alias
  directory still leads them, the keymap's special rows source, the root's lock and sleep calls
  and the launcher's own special fallbacks for them went, and a key left on a special row is named
  retired. A launcher row and a tool's chord name a leader no role answers by its own name, Nav T.
  Proof, offline. All three goldens byte identical, `keys.sh --bound` matching and `--bound-order`
  against an archive of the merge base the same order on every key. `test/keymap-fixture.lua`,
  the person's case with the window role on super, `hyper+3` freed and a vpn alias override,
  has three goldens, the bound keys with vpn on Meta E and off Hyper P, the clipboard on Meta Y
  and off Hyper X, Tmux Manager on Nav T, nothing on Hyper 3, every window binding on SUPER and a
  remap line of HYPER, META and SUPER, the launcher rows reading Meta E, Meta Y, Nav T, Super for
  every window row, OCR with no chord and the vpn row with its three words, and the sheets with the
  window rows on Super's sheet and the two moved tools on Meta's. The task asked that remap to
  leave META out, which cannot hold while Meta E and Meta Y are bound, so
  `test/keymap-fixture-roles.lua`, the roles alone, carries the proof that META is freed, its remap
  line HYPER and SUPER. `test/keymap-person.lua` holds 108 plain Lua checks of the grammar, every
  problem, displacement, false, leaders, roles, aliases and activation, and `test/keymap.lua` was
  updated for the exemption's end and the special rows' end. The dry suite, the dry gate at 0
  findings and 0 unknown, the rename proof at 0 differences and the dependency check pass. One gap
  is known and left for phase 6, a moved app toggle binds its new chord while the toggler's own
  sheet sections and launcher app details, built from its data, still read the old one.
- 2026-10-20 09:35. An adversarial review of e1b442bb found no blocker and eight fixes, applied on
  top. fn on a chord opening with a held leader is refused, since the leader compares only shift,
  ctrl, alt and cmd and bound `hyper+fn+4` as a chord stating no modifier that beat Hyper 4. The
  trailing `++` rule was wrong, the live keycode table has no `+`, so it went, a chord ending in
  `pad+` is the keypad plus and the main row plus is written `shift+=`, and the test stub now
  carries the live codes of `=` and `pad+`. An id over several rows running different functions,
  `apptoggler.Ghostty` today, is a problem naming the rows and both stay bound, where it had moved
  both and kept the first in silence. A keymap entry ranks above every other source of the
  person's, so it displaces a toggle on its slot with the routine line, where the toggle won the
  tie. The key inventory gained a last line, the held leaders the remap was applied with, recorded
  as `_composed.remap`, written by the bound recording, the offline projection and the live probe,
  and `keys.golden` was retaken offline and changed by exactly that line, `remap HYPER+META`, which
  the live probe against main agreed with. The fallback for a keymap that fails to build keeps the
  list leader in use beside the roles' leaders, `keymap.fallbackLeaders`. A named leader no chord
  uses is a routine note. The config header, both AGENTS files, the contract and the skill now say
  where keys live today, that a moved toggle's sheet section and app row lag until phase 6, that
  false frees global chords only until phase 7, and that a displaced default loses that one row.
  `test/keymap-person.lua` is at 129 checks.
- 2026-10-20 09:41. Phase 5 landed after a live load in two steps under a manual hold. With the shipped empty
  config/keymap.lua the console was clean, the wiring report said no problems, all three goldens
  matched live, remap line included, and Milos confirmed the launcher, the VPN key and a window
  action unchanged. Then his own example, `["meta+E"] = "vpn.open"`, was written into the
  branch's file and the branch reloaded. The live key diff showed exactly VPN leaving Hyper and P
  for META and E, and Milos confirmed META and E opened the VPN list, Hyper and P did nothing, VPN
  appeared on the window sheet, and the launcher row read META E. The entry was removed before
  merging, so main ships the file empty.
- 2026-10-20 09:46. Milos agreed phases 6 and 7 and asked that they be noted rather than started. Phase 6 turns
  app toggles and settings panes into actions built from data and deletes `config/keys.lua`,
  phase 7 moves list keys into the keymap and makes `config/plugins.lua` refuse key fields. Until
  then three transitional facts stand, recorded in the config header and the hammerspoon
  AGENTS.md. A moved toggle shows its old chord on the Hyper sheet's app section and the launcher
  app row, an entry naming `apptoggler.Ghostty` is refused because two toggles share that id, and
  false frees global chords only.
- 2026-10-20 10:20. Phase 6 built on `olm/keymap-phase6`, awaiting review and a live load. The app
  toggler answers one action per app in `config/apps.lua`, `apptoggler.Safari`, focusing or
  cycling it, and one per named variant in its data in `config/plugins.lua`,
  `apptoggler.GhosttyPlaced` with hides, a description and the placement, each built in configure,
  naming its app and a group function answering a RUNNING table or a DORMANT table with
  `faded = true`, read from one enumeration of running apps shared for a quarter of a second. It
  dropped `provides.bindings`, `bindHotkeys`, its leader check, the url field and its own sheet
  sections and app details, and suggests one key, Finder on Hyper and F. Every toggle key is a line
  of `config/keymap.lua`, and `config/keys.lua` is deleted. Hyper and comma is
  `systemsettings.General`, one action per pane named by the pane with everything not a letter or a
  digit taken out, running the toggle by url Hyper and comma always ran, each naming System
  Settings as its app. The descriptor field `group` takes a table with a title and faded too. The
  leader sheet host files the keymap's rows in blocks by each owner's `defaults.cheatSheetOrder`,
  a block holding a group function asked at every show, a faded section after every section in
  full colour, a row naming an app drawn with that app's icon and name resolved once at build and
  left off when the app is not installed, and a section of app rows an icon grid ordered by key.
  The launcher lists no row for an action naming an app and shows its chord on the app's own row,
  through `contributions.appChords`, a plain combination winning the row with its description, and
  an app row always focuses or cycles. `provides.bindings`, `provides.cheatSheetSections` and
  `provides.launcherAppDetails` are refused by name, the keymap's provided rows source, the
  registrar's `providedBindings`, `contributions.sheetSections`, `contributions.appDetails` and the
  leader sheet's set are gone, and so is the refusal of one id over rows running different
  functions, which nothing can produce now that every row of an action runs its descriptor.
  Workspaces and display profiles were read through the olm-plugin skill and left as they are.
  A layout is a snapshot a person takes while Hammerspoon runs, reached by its scope and applied
  only when its displays are attached, so an action per layout would bind only after a reload,
  list every layout twice in the launcher unless hidden, and nobody has asked for a key on one. A
  display profile is applied by the engine on every screen change and the picker deliberately
  does not apply, so an action per profile would offer a switch that can never take effect.
  Proof, offline. `keys.golden` changed in one line, the owner of Hyper and comma from apptoggler
  to systemsettings, and `keys.sh --bound` matched it, with the binding order on every engine and
  key the same as main's when each runs its own config. `launcher.golden` is byte identical.
  `sheets.golden` gained one line, General settings on comma among the Hyper sheet's actions,
  and keeps the RUNNING and DORMANT headers, which the offline run now produces as the live one
  does by answering Finder as running. The two fixture key goldens lost every toggle but Finder's
  and Hyper and comma, and the fixture sheet golden its DORMANT header, since a fixture replaces
  the whole person keymap the toggles now live in. `test/keymap-person.lua` pins
  `apptoggler.Ghostty` and `apptoggler.GhosttyPlaced` as two ids, each moving alone, and
  `test/leadersheet.lua` proves offline that a moved toggle shows its new chord in the sheet's
  running section and on the app's launcher row. The rename proof renames the identity in every
  keymap entry and alias list now that the person's keymap names plugins, the dry gate is at 0
  findings and 0 unknown, the dependency check passes, and the unit cases
  `test/cases/leader-sheets.lua`, which had stopped at the launcher's host module since phase 5 and
  runs to the end again, and `test/cases/launcher-contributions.lua`, whose 35 failures under
  plain Lua are the same as main's, pass their phase 6 checks.
- 2026-10-20 10:30. An adversarial review of acf3ef97 found no blocker and seven fixes, applied
  on top. Every pane action hid System Settings whenever it was in front, which was right for
  General alone, so a key on Wi-Fi would have hidden the app showing General. A pane action now
  hides only when System Settings is in front and the pane the plugin last opened, by a key or a
  launcher row, is its own, decided in `SystemSettings:paneToggle`, and `appfocus.toggleURL`
  became `appfocus.openURL`, which only opens. Hyper and comma pressed twice still opens General
  and hides it, and `test/systemsettings.lua`, run by the dry suite, pins both. A click inside
  System Settings to another pane is not seen, so a key pressed after it may hide rather than go.
  The root's `open` reason named an app toggle and an app row, and says a pane action's key now,
  regenerated through the collector. An app row's chord on a leader spells its modifiers through
  the shared chord speller, so Hyper, Shift and S no longer reads Hyper S. A sheet row for an app
  macOS names nothing for wears its catalog name again rather than its bundle id. The key probe's
  fallback to `config/keys.lua` is gone, the pane descriptors lost an icon nothing read, and the
  launcher record no longer says an app row carries no chord with the toggler off, since
  `systemsettings.General` names System Settings. Two side effects were accepted. Finder's shipped
  key, Hyper and F, now survives a person keymap that never names Finder, since it is the
  toggler's own default rather than a line of the person's toggle list. And with the toggler
  switched off every keymap entry naming it prints a routine note that it binds nothing, the rule
  phase 5 set for an entry naming a plugin switched off.

- 2026-10-20 11:30. The System Settings panes carry no launcher alias at all, neither `s` nor
  `system`, in the plugin manifest and in the launcher's catalog scope for settings panes. Typing
  "system settings" in the launcher claimed the `system ` alias and searched the panes for
  "settings", which matches none, so the System Settings app could not be found by its own name.
  Milos decided that System Settings carries no alias, so typing system settings finds the app by
  name, and the pane rows stay findable by name in the main launcher, such as appearance or wifi.
  The registrar already treats a scope with no aliases as valid, so the field is simply omitted and
  the scope line stays. `test/inventory.golden` follows with an empty alias list, and its emoji line
  was brought in line with the emoji manifest, `e+em+emoji`, which it had gone stale against.
- 2026-10-20 11:50. Phase 6 landed on main after its live load. Milos pressed Hyper and
  backtick, Option and backtick and Hyper and comma, checked the Hyper sheet's running and not
  running split and the Ghostty and System Settings launcher rows, and found system settings by
  name. The live inventory corrected the 11:30 entry. A scope with no alias is not counted in the
  live registry, so `test/inventory.golden` drops the settings panes scope line and counts 17
  scopes rather than keeping it with an empty alias list.
- 2026-10-20 12:10. Phase 7 built on `olm/keymap-phase7` from main at 24a647db, pending its live
  load. `config/keymap.lua` gains a `lists` section, `all` and one table per list keyed by its
  context name, a chord on `hyper` to a surface action or `false`, read by `keymap.readConfig` and
  laid over the built lists by `keymap.applyLists` in the root before anything reads them. The
  shared j, k, i, x and o left `lib/surface.lua` for `keymap.listDefaults`, Olm's own `all` layer,
  handed to the resolver as `listKeys`, and each shared binding names its verb in `shared`, which
  is how `close` reaches a list whose close sits on another key. The dry gate refuses a key
  literal in `lib/surface.lua`. `config/plugins.lua` refuses `key`, `mods`, `leader`, `bindings`,
  `surface` and `aliases`, and held none of them on this machine, so nothing moved and
  `config/keymap.lua` ships no list entry. The open key translation of phase 2b, `key = NONE` or
  `false` unbinding an open row, the resolver's `surface` fragment merge and the keymap's tier for
  a binding written in `config/plugins.lua` are gone with them. `hints.actionKinds` reads `shared`
  so a freed primary key cannot turn an extra into navigation. `keys.golden`, `launcher.golden`,
  `sheets.golden` and the two earlier fixture goldens are byte identical, the binding order per
  engine matches main, and `test/keymap-fixture-lists.lua` with its golden shows `all` moving
  selectNext to N, the clipboard moving Delete onto E, a chord the global layer gives menu search,
  and selectPrev onto A over Append, file search freeing Y and the launcher's close moving to C by
  the verb's name. `test/keymap-person.lua` pins the same in plain Lua, with the hint bar and the
  action panel reading the moved chord.
- 2026-10-20 12:23. An adversarial review of 3f7dde02 found seven fixes, applied on top. A
  `config/plugins.lua` entry left with nothing once its key fields were refused came back as an
  empty table, which the merge reads as an empty list replacing every default, so a leftover
  `vpn = { key = "Q" }` would have left the VPN with no open row, leader, aliases or
  description, and it is now left out, with fields inside `data` never read. A list's own table
  overrode an `all` entry only when both spelled the action alike, so `primary` in `all` and
  `insertSelected` in a list left both chords bound, and the override now goes by the bindings an
  entry resolves to. An entry naming an action a missing need left out is a routine note through
  the block's `unmet`. `all` moves only keys Olm's own layer gave, see Rejected. The dry gate's key
  literal check sets quoted strings aside first, so a log message is not a field and an index such
  as `keys[1]` is not a literal, and its blind spots are written beside it. The root keys the list
  names it knows by identity, the way the resolver keys the lists, and the query scope notes no
  longer say aliases join from `config/plugins.lua`. Every golden is byte identical to main.
- 2026-10-20 21:28. Milos found the swallow split over an open list inconsistent. With the launcher
  open Hyper and A was swallowed through the clipboard's gated list binding while Hyper and B
  leaked to the app in front, since nothing binds B once the modal rule drops the base bindings.
  He chose to swallow. Hyper's policy gains `sealedOverLists`, which makes `_onKey` answer the
  bound no op when a list is open and nothing resolves, so every Hyper key that is not a live list
  key is swallowed over a list, and outside lists an unbound key still passes through. META and
  SUPER already swallowed every key over an open list through `quietOverLists`, so they did not
  change. `test/leaders.lua` pins both halves and the policy check refusing a non boolean.
- 2026-10-20 13:05. Phase 7 landed on main after its live load, which completes the plan. Milos
  pressed the list keys in the launcher, the clipboard, file search and emoji, checked the hint
  bar against them, and confirmed that every Hyper key that is not a live list key does nothing
  while a list is open, while Hyper and B still toggles Books with no list open.
- 2026-10-21 14:30. The Olm unit cases were made green again, thirty six failing checks of 1957, all
  stale tests and no code defect. `launcher-contributions` still expected lock and sleep as special
  rows the launcher's manifest declared, and the case never loaded the launcher as a module, so once
  phase 5 made them its own actions no row for them was built and every later row sat two places
  early, which is why the first pane read Network and the last window row read Bluetooth. The case
  now loads the launcher module with recorders for its two runs, expects the owner `launcher` the
  rows are stamped with, and checks that a chosen lock row reaches that descriptor. The
  `windowmanager-holdstep` case indexed `actions()` by name, which was true until the descriptors
  became a list in the order of the launcher's rows, so it indexes the list once by name. Phase 6
  and phase 7 caused none of them. `chooserprovider` fails six checks under a plain interpreter
  only, since it needs `hs`, and passes in the live run, so it was left alone.
