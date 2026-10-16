# Olm core and plugins apart

Status. In progress. Phases 1 to 3 of `Spoons/Olm.spoon/docs/PLAN-CORE-SPLIT.md` have
landed. Phase 5, the switch and the settings Plugins page, is built and reviewed on its branch,
its apply reworked after Milos's first live try to stage choices and apply them when the stage
closes, and owes its live load. Phase 4, cheat sheets that list exactly what their leader binds, is built on
its branch stacked on phase 5 and owes its live load.

## Now

A plugin is a self contained directory whose manifest names what it needs and what it offers,
and core is everything plugins consume, which the composition root may name. Core never names
a plugin. `config/plugins.lua` holds one entry per plugin identity, the person's overrides of
that plugin's own defaults, its person supplied `data`, its spoon `global`, or `false`, and
`config/keys.lua` holds only the two leaders and the app toggles. KeyRemap is `lib/keyremap.lua`,
the window leader is `lib/windowleader.lua` beside `lib/hyperkey.lua`, and the window cheat
sheet is a host. A plugin binds on the window leader the way it binds on Hyper, by declaring
`defaults.leader = "window"` with `defaults.bindings` and asking for `needs.lib.windowLeader`,
and the root collects every window binding by walking the plan rather than reading any plugin.
A plugin puts rows in the launcher's own catalog by declaring `provides.launcherRows` and
`provides.launcherRun`, the root stamps its identity on each row's item as `owner`, and the
launcher runs an owned row through that owner's runner, so the launcher declares no siblings.
Where a row sits is the contributor's own `defaults.launcherOrder`, and what it is remembered by
is its own kind joined to its item's `key` or name.
Bringing an app forward is `lib/appfocus.lua`, and `coveredApp` and `refreshLauncher` are words
the root publishes over the launcher.
A leader's cheat sheet lists what the root collected from the manifests, a plugin's own key, its
`bindings`, its keyed special rows and its registry leader commands, plus the sections a plugin
supplies by declaring `provides.cheatSheetSections`, placed by `defaults.cheatSheetOrder` and
routed by `defaults.leader`. The app toggler supplies the app sections, so the Hyper sheet reads
no person data and names no plugin.
There is one plugin switch. A plugin under `plugins/` is off when `config/plugins.lua` says
`false` or the settings page saved its identity under `Olm.disabledPlugins`, its code never
runs, a plugin requiring it is reported off because of every switched off plugin it depends on,
and a change takes one reload. A plugin a host requires is locked by the core and cannot be
switched, and the settings page cannot switch itself off. The page does not save a choice, it
stages it in memory in the root, and the whole staged set is saved with one reload when the
stage goes away by any route, which `host/stage` reports through its `onClosed` observers, or
when the page's Apply now row is chosen. A dismissal reopens nothing and one routine line after
the reload names what changed. Apply now leaves a one shot note under `Olm.resume` describing
the place the plugin was in, and the next load reopens it through `stage.presentAt`.

## Rejected

- **Making `config/keys.lua` the override file.** 2026-10-16. It is where the docs already
  pointed, which made it the obvious choice, but per plugin overrides sat at the top level of
  the `spoon.Olm:start` table beside `data`, `policy` and `globals`, so a plugin named after one
  of those would collide, and one plugin's person facts were spread across three keys. One entry
  per plugin in its own file removed both.
- **Toggling a plugin on and off live.** 2026-10-16. It would need every plugin to know how to
  stop and unbind itself, and nothing in Olm ever unbinds a key. A plugin runs or not by the
  plan, decided once at load, so a switch costs one reload.
- **A confirm step before switching off a plugin others need.** 2026-10-16. Nothing is lost,
  since a dependent's own switch is never touched and it returns when its dependency does, and
  the page shows the effect before the choice.
- **Applying the remap early in the load.** 2026-10-16 12:10 to 12:19, aee029d. Moving KeyRemap
  into core first placed the remap before the leaders were wired, so a load failing partway left
  Caps Lock and Right Option remapped with nothing listening. It applies immediately before the
  chord engine starts, so a failed load leaves the native keys.
- **Listing contributed launcher rows in plan order alone.** 2026-10-16. It is the obvious
  generic order and it would have moved lock, sleep and the alias directory past every window
  action and the System Settings panes up among the commands, which a person scrolling an
  untouched list would see. Grouping by kind with a `directory` mark keeps the old order and
  names nothing.
  Corrected 2026-10-16 13:32, see below.
- **Placing contributed launcher rows by the order their kind words sort.** 2026-10-16 13:32. It
  reproduced the old order only because capture, special and window happen to sort that way,
  so the place of a row depended on how a kind is spelled, and it needed a `directory` mark to
  keep the panes last. Each contributor declares `defaults.launcherOrder` instead, a row may
  state its own `order`, and the launcher sorts by the number.
- **Keeping the registry roster as a second switch.** 2026-10-16. `Olm.registryActivation`
  could hide a registered tool while the plan still loaded and wired it, so two switches could
  disagree about whether a plugin is on, and nothing had ever written it. Deleted, the plan's
  disabled set is the only switch.
- **Letting a page or a config line switch off a host.** 2026-10-16. A host is core that
  plugins stand on, so one choice could take down every plugin above it. Refused out loud.
- **Saving and reloading on every choice on the Plugins page.** 2026-10-16 14:58. It was the
  first shape built and it took the list down under the person after each press, so flipping
  two plugins meant reopening the page between them. A choice is staged and the set applies
  once, when the stage closes or Apply now is chosen.
- **Persisting each staged choice as it is made.** 2026-10-16 14:58. It would survive a crash,
  but any other reload, a config file saved while the page is open, would then apply a half
  made set nobody announced. A staged set is a draft, it lives in memory until apply, and a
  draft lost to a reload costs a few presses.
- **Keeping the toggle split in the Hyper sheet and handing it the toggles as root data.**
  2026-10-16 16:40. It would have removed the person data read from the manifest and kept the
  code where it was, but the sheet would still know the shape of one plugin's data, app, key,
  modifiers and the running split, and the plugin would still bind from a list the sheet did not
  see. The plugin supplies its own sections instead.
- **Rendering every contributed badge through the glyph helper.** 2026-10-16 16:40. It is the
  uniform choice, and it would have turned every toggle's letter into its upper case glyph, a
  visible change on a sheet that was meant to look the same. A row may state its own badge.
- **Asking the window sheet the same set.** 2026-10-16 16:40. It reads no person data, and a set
  question nothing answers is reported as a problem on every load. It asks the day a plugin on
  the window leader supplies sections.
- **A contributed row keeping the launcher as its icon owner.** 2026-10-16. It would have kept
  the owner field identical, but only by a plugin naming the launcher, the coupling phase 3
  removes. The plugin declares the same icon instead.

## Log

- 2026-10-16 11:52, e48d0fa. Found that of roughly thirty entries in `config/keys.lua` only four
  were read at runtime, the per plugin keys, aliases and every `hyperContexts` block having been
  dead since manifests took them over, while the docs and the olm-plugin skill still told a person
  to rebind there. `toolActivation` in `config/settings.lua` was dead too. Both removed, and
  `config/plugins.lua` added. The builder's own check caught that an entry holding only `data`
  became an empty override, which the defaults merge reads as an empty list that wipes every
  shipped default, and such an entry is now no override at all.
- 2026-10-16 11:58, 10e5065. The key inventory golden had been a copy of the dead `hyperContexts`
  table, eleven contexts, while the live plan builds nineteen. Regenerated live.
- 2026-10-16 12:19, 2cf867e. Phase 2 landed. An adversarial review found three minor points, the
  early remap above, `when` gated only inside WindowManager while the docs presented it as a
  leader feature, now owned by `lib/windowleader.lua` as Hyper owns it, and a single window key
  row the walk emitted that nothing bound. Milos tested the window cheat sheet, two window keys,
  a Hyper app key and the Caps Lock tap live on the branch.
- 2026-10-16 12:53. Phase 3 designed. A launcher row cannot carry a function, since `hs.chooser`
  drops it, so a plugin contributes plain rows and a runner, and the launcher routes a chosen
  row by its owner. The launcher's recency memory is keyed by kind and name, so contributed rows
  keep the kind words they carry today and the persisted order survives.
- 2026-10-16 13:16. Phase 3 built on its branch. The seven launcher siblings became the two
  contribution members, a core lib for app focus, and two root words. Three things the design
  did not settle came out of the code. An untouched list's order had to stay as it was, and plan
  order alone would have moved lock, sleep and the alias directory past the window rows and the
  panes ahead of them, so commands are grouped by kind in the order the kind words sort with the
  launcher's own rows last in their group, and a pane row is marked `directory` to stay last.
  That rule names nothing and reproduces the old order exactly. The window rows and the settings
  search row read their icon against the plugin that built them, since a plugin must not name
  the launcher to borrow its icon, so both plugins declare the same emoji and SF Symbol the
  launcher did and the picture is unchanged. A field named `apps` was already the person's
  bundle id registry, so the lib is `appfocus` rather than `apps`. A one off comparison against
  the previous commit found all 63 catalog rows otherwise equal, and
  `test/cases/launcher-contributions.lua` keeps the expected rows and one dispatch per kind.
  Corrected 2026-10-16 13:32, see below.
- 2026-10-16 13:32. The phase 3 review found no blocker and eight things to rework, done on the
  same branch. The 13:16 entry was wrong that the order rule named nothing. Sorting groups by
  kind word read the spelling of `capture`, `special` and `window`, and it matched the old order
  by coincidence. Placement is a declared number now, `defaults.launcherOrder` per contributor,
  overridable in `config/plugins.lua`, with a row's own `order` for the System Settings search
  row, shipped as capture 10, the search row 20, the launcher's own rows 30, the window actions 40
  and the panes 50, and the `directory` mark is gone since the panes sit last by number. Row
  identity moved to the row too. An item may state `key`, which System Settings sets to each
  pane's url, and `remember = false`, which Window Size sets on its typed size, so the launcher
  keys every row it did not build as kind joined to key or name and keeps rules only for its
  own kinds. Every persisted key is unchanged, checked row by row against the previous commit.
  The root now always writes the owner over what a row carries, an owned row skips the alias
  hint and the root's intercept and never falls through to `special` or `scope`, two
  contributors answering one kind and key are named with both owners, and the assembly moved
  into `lib/contributions.lua`, which the unit case drives. `coveredApp` and `refreshLauncher`
  are published only when the launcher is in the plan, so menu search's required policy can
  fail out loud. The review also noted that the set edges move the window manager and window
  size later in configure order, after workspaces, display profiles and text case. Accepted
  as is, since none of the plugins whose order shifted reads another at configure, every
  contributed member is called when the launcher first builds its rows, and the plan still
  wires every contributor before the launcher.
- 2026-10-16 14:03. Phase 5 packet one built on its branch, the switch without its page. The
  disabled set is the union of the `false` entries in `config/plugins.lua` and a list of
  identities saved in `hs.settings` under `Olm.disabledPlugins`, merged in the root before
  anything loads by `lib/pluginswitch.lua`, a pure module the unit case drives. Only a plugin
  under `plugins/` is switchable. A host written `false` or saved is refused with one console
  line, never honoured, since core must not be switchable, and nothing today writes `false` for
  a host. A config `false` locks the plugin, since a page cannot undo a line in the person's
  file. A plugin that requires a switched off one goes off with it, answered before loading by
  `pluginsLib.offBecause` and recorded by the resolver under `plan.offBecause` naming the
  switched off plugin, never under `blocked`, so the report reads it as a choice. The loader
  skips both kinds, so a dependent's code does not run either, a step past what the plan asked,
  taken because the answer is pure and known before loading. The resolver still receives every
  manifest, since it has to know a switched off plugin exists to stay silent about an optional
  sibling naming it, and every other reader in the root gets the set without them. The
  registry roster `Olm.registryActivation` is deleted from `registrar.forWire`, which activates
  every tool that registered. Nothing had ever written that key, so no machine loses a choice.
- 2026-10-16 13:56, 452be9c. The Actions key of the action panel declared a leader and a key in
  its manifest, which put o Actions on the Hyper cheat sheet although nothing binds o on that
  leader. The real chord comes from `lib/surface.lua` inside every list, so the manifest now
  declares neither.
- 2026-10-16 14:12. Phase 5 packet two built on its branch, the Plugins page in the settings
  plugin. It lists every plugin under `plugins/` with a green or red circle, shows the
  highlighted one's about block, needs and cascade in a docked pane, and a press saves the switch
  and schedules one reload. The page reads three root words, `pluginCatalog`, `pluginCascade` and
  `setPluginDisabled`, and its row on the top level appears only when they arrive. A press on a
  locked row answers stay and changes nothing.
  Corrected 2026-10-16 14:58, see below.
- 2026-10-16 14:26. Review fixes to phase 5. The page could switch itself off and lose the only
  way back, so it now treats its own row as not toggleable, the plugin reading its identity from
  its own directory name. A stale saved identity was logged as an error on every load and never
  removed, so `set` now writes back only identities that are still switchable and the root logs
  a refused saved entry as a warning saying it is dropped on the next switch, keeping the error
  for a refused `false` in config, which is a person's own mistake. `offBecause` picked the
  first required sibling `pairs` returned, so it now maps each off plugin to the sorted list of
  every switched off plugin it depends on, and every report line, the explanation, the catalog
  and the page subtext read the list. A host is never marked off, and a plugin that a host
  requires is reported by `pluginsLib.requiredByCore`, refused by the merge and the setter, and
  shown as needed by the core, which changes nothing live today since no host requires a plugin.
  The pane no longer hides itself when the empty state is missing, the unused root word
  `disabledPlugins` is gone, and a stale comment about registry deactivation was rewritten.
  Still open. Five plugins now copy the same canvas lifecycle for a docked companion pane, so a
  shared companion pane kit piece in the lib is a candidate once a sixth appears or one of them
  changes. And no test runs `root/compose.lua`, so a regression that read `allManifests` where
  it should read the switched off set would stay green until phase 6's gate or a live load.
- 2026-10-16 14:58. Apply per toggle corrected after Milos's first live try. In his words, "when
  i enable or disable plugins i do not want to close it immediately, but somehow when i dismiss
  olm apply then, and somehow reopen where it was if possible". The 14:12 entry's press that
  saves and schedules a reload is gone. A press stages the choice in the root,
  `stagePluginSwitch`, and writes nothing, the page answering stay with the circle and the
  subtitle showing the state after apply, a dependent naming the plugin it goes with, and the
  pane's cascade measured against everything else staged. A choice that returns a plugin to what
  this load has drops its staged entry. The staged set is held in memory rather than persisted,
  see Rejected. It is saved with one reload when the stage goes away. The stage had no close
  notice the root could hear, so `host/stage` gained an `onClosed` observer list, told once per
  close after every presentation's own `onClose` and never on a pop, which is exactly the line
  between leaving the Plugins page for the top level and being done. A dismissal reopens nothing
  and says one line through the shared `notify` after the reload. An Apply now row after Back,
  only while something is staged, calls `applyPluginSwitches` with a place the plugin describes
  about itself, its registered name, the item that leads to the page and the plugin last chosen,
  and the root leaves it in a one shot note under `Olm.resume` that `lib/resume.lua` validates,
  writes and takes once, cleared before it is acted on. The stage reopens it with `presentAt`,
  walking the items through each level's own `select` so Back still works, and highlights by
  item fields. Since the Apply row appearing above a row moved a held highlight one row off, the
  stage now holds a "stay" on an item's `key` when the item states one. The confirm step stays
  rejected, Apply now is optional and dismissing applies just the same. The settings row for
  where the launcher appears changed its icon at the same time, to `macwindow.and.cursorarrow`,
  an outline window with a pointer naming both modes, confirmed in the CoreGlyphs name list.
- 2026-10-16 16:40. Phase 4 built on its branch, stacked on phase 5. The Hyper sheet read the
  person's appToggles and app registry through `cfg.shared`, while the app toggler bound from its
  own merged list, so a core host knew one plugin's data and shape and the two could disagree. A
  plugin now supplies sheet sections through `provides.cheatSheetSections`, routed by its
  `defaults.leader` and placed by `defaults.cheatSheetOrder`, assembled by
  `contributions.sheetSections` beside the launcher's `assemble` and resolved through the same
  member door. The app toggler builds its rows in `bindHotkeys` from the entries it bound into the
  modal and answers running then dormant on every show. The sheet's own block takes fifty from the
  sheet's own manifest. The second question, whether a leader command reaches its sheet, had a
  real answer. `hints.sections` found a registry command's key through the plan, which has no
  directory for a command, so a command bound on a leader was dropped from the sheet while the
  registrar bound it through the root's own lookup. Nothing shipped was lost, since the only
  keyed commands, the clipboard's append copy and paste next, are global. The lookup moved into
  `registrar.commandKey`, used by both. `test/cases/leader-sheets.lua` builds the plan over the
  real manifests, drives the real binding code into recorders, restating only the two rules that
  live inline in `root/compose.lua`, the host key loop and the lock and sleep rows, and found no
  key bound and not shown and none shown and not bound on either leader. A mutation giving the
  alias directory a key the root never binds failed it, as it should. Still open. A registry
  tool declaring `leader = "window"` with a leader shortcut would be bound on Hyper by
  `registrar.bind` and listed on neither sheet, since bind always uses the app engine. No such
  tool exists. And the launcher still reads the person's toggles and app registry itself for
  its app rows' chord subtitles, the same shape of leak this phase removed from the sheet.
