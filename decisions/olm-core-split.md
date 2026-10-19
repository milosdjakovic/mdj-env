# Olm core and plugins apart

Status. In progress. Phases 1 to 3 of `Spoons/Olm.spoon/docs/PLAN-CORE-SPLIT.md` have
landed. Phase 5, the switch and the settings Plugins page, is built and reviewed on its branch,
its apply reworked after Milos's first live try to stage choices and apply them when the stage
closes, and owes its live load. Phase 4, cheat sheets that list exactly what their leader binds, is built on
its branch stacked on phase 5 and owes its live load, with its two open items closed on a branch
of their own. Phase 6, the dry gate's layer rule, fails the gate now.

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
no person data and names no plugin. The launcher's app rows learn each bound app's chord and url
the same way, from `provides.launcherAppDetails`, so the launcher reads neither the toggles nor
the app registry. A registry tool's open key binds on the app leader only, and a tool stating
`leader = "window"` with a leader shortcut is refused at wiring with a problem line. The dry gate
fails on any file outside `plugins/` that names a plugin, as a string, a path, a field, a table
key or a string folded from literals, with the icon engine's own `emoji` source set and icon spec
field accepted line by line, and it runs the composition root a second time with every plugin
renamed and fails on any difference in what core decided.
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
A docked companion pane is core too. `lib/dockedpane.lua` owns the canvas, the dock, the shared
surface and empty state, the scroll and the teardown, `pane = true` on a surface earns
`opts.dockedPane`, a function answering one, and a plugin hands it only what to draw.

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
- **Handing the launcher the toggles as root data instead of reading them as person data.**
  2026-10-16 16:52. It would have moved the read from the manifest to the root and kept the code,
  but the launcher would still know the toggle list's shape, app, key, modifiers and url, and
  still resolve app names through a registry it does not own. The plugin that bound the keys
  supplies what each app row shows instead.
- **Binding a registry tool declared on the window leader on the window leader.** 2026-10-16
  16:52. It is the generous answer, but the window leader binds a declared `bindings` list and
  nothing else, a rule `hints.leaderBindings` and the root's host key loop already keep, and
  routing a tool's open key onto it would need the registrar to know two engines and the window
  sheet and the key inventory taught a second source, all for a case no plugin has. Refused out
  loud at wiring instead.
  Reopened 2026-10-19 16:44, see `olm-keymap.md`.
- **Renaming the icon engine's `emoji` source set to clear the layer rule.** 2026-10-16 16:52.
  The word is core's own vocabulary, written in `config/icons.toml` as the set and the fallback,
  and it shares a spelling with the emoji picker plugin by coincidence. Renaming it would change a
  person's config to satisfy a scanner, so the three lines are accepted with a reason.
- **A contributed row keeping the launcher as its icon owner.** 2026-10-16. It would have kept
  the owner field identical, but only by a plugin naming the launcher, the coupling phase 3
  removes. The plugin declares the same icon instead.
- **Delivering the docked pane through the UI kit, `needs.lib.ui`.** 2026-10-16 17:47. The kit
  was the obvious home, since the pane lays out kit nodes, but every plugin that asks for the kit
  could then make a pane without declaring one, so `pane = true` would stop being the gate, and
  the kit is node vocabulary that loads with no hs while the pane owns a window. It is granted by
  the pane declaration instead, the way the surface and the empty state already were.
- **Making the docked pane a mode of CanvasPanel.** 2026-10-16 17:47. CanvasPanel places and
  sizes itself from an anchor and its content and owns reveal timing, while a docked pane lands
  on a rect the chooser reported and must not move off it, or a click on it dismisses the list.
  One object with two placement models would be harder to read than two small ones sharing the
  surface and the empty state routines.
- **Keeping the raw `surface` and `emptyState` grants beside the pane.** 2026-10-16 17:47. Once
  the pane holds them nothing in a plugin reads them, and a plugin handed the raw routines is one
  step from copying the lifecycle again, so `pane = true` now earns `dockedPane` alone.

- **Reporting a lower case field only when its receiver is a table known to be keyed by plugin
  identity.** 2026-10-16 23:23. It was the precise rule first proposed, `modules`, `plan.effective`,
  `plan.identity`, `cfg.plugins` and the rest read off compose and the libs, but that list is a
  roster of receiver names, the moment a table is copied into a local with another name the field
  on it is invisible, and the list has to be kept in step with core by hand. Measured on the tree,
  every lower case field and key equal to an identity is 35 hits, 21 of them on the bare `hs`
  global, so reporting all of them but the one receiver that is structurally never a plugin left
  14, few enough to settle one by one.
- **Accepting every remaining collision instead of renaming the two settings options.** 2026-10-16
  23:23. Accepting `deps.settings` and the theme store's `opts.settings` would have kept the code
  as it was, but both lines sit in `root/compose.lua` and `lib/hints.lua`, which change weekly, and
  neither name was precise, one held the policy and the other a store over hs.settings. They were
  renamed `deps.policy` and `opts.store`. This is not the rejected `emoji` rename above, no person
  config changes and the old words described nothing core owns.
- **Running the rename proof as a unit case instead of inside drygate.sh.** 2026-10-16 23:23. The
  unit runner needs a live Hammerspoon, while the proof runs in plain lua in under a second, so
  putting it there would have taken the one test of the composition root away from every agent
  that cannot start Hammerspoon.
- **Comparing the two runs line for line in order.** 2026-10-16 23:23. The first comparison did,
  and its only differences on a clean tree were the dependency summary listing owners in the order
  their names sort, which a renamed set sorts differently. Lines are compared as counted sets of
  their sorted words instead, a list ordered by name is generic, and a leak changes which words
  or lines exist.
- **Scrambling with a prefix or a suffix on each name.** 2026-10-16 23:23. A marker such as
  `zqx` would have made turning names back trivial, but it changes every name's length, and a
  report that pads by name length would then differ for no reason. A case keeping letter shift
  keeps the length, keeps a directory and an identity that differ by case related the same way,
  and the shift is chosen so no scrambled name is already a word in the original snapshot.

- **Calling every closure the root hands out under the stub.** 2026-10-16 23:39. It would reach
  key handlers and chooser callbacks the proof cannot see, but those closures share state and
  would be called in the order a walk of identity keyed tables meets them, which a renamed key
  changes, so two clean runs could disagree for no reason. It was reasoned out rather than built.
  Only content strategies are called, each one alone, since each answers what it shows from its
  own inputs.
- **Comparing the order of lists between the two runs.** 2026-10-16 23:39. Measured with array
  positions in the snapshot, a clean tree gave 1072 differences, a list core builds by walking a
  table keyed by identity comes out in hash order and a renamed key changes it, so no difference
  could be told apart from a leak.
- **Giving check two the modules the composition root configured.** 2026-10-17 09:25. The rename
  proof already runs the person's `init.lua` and the root under a stub, so its modules carry real
  opts, a real Chrome bundle id among them. But that run is a separate process inside a sandbox
  with its own `hs`, so check two would have to move into it or run the root a third time in the
  gate's own process, a plugin the person switched off would never be composed and so never
  checked, and whether a manifest's members resolve would depend on one person's config, which a
  contract check must not.
- **Answering nil from the particular hs getters whose real answer is often absent.** 2026-10-17
  09:25. It would have cleared capture and the launcher, but it is a list of hs calls kept in
  step with whatever plugins happen to call, the shape the stub exists to avoid, and the getters
  in question, a default handler and the running bundle id, answer a string on a real machine,
  so nil would have been a different lie rather than the truth.
- **Raising the stub's instruction budget for processes.** 2026-10-17 09:25. Measured with a
  sampling hook at five times the budget, every sample sat in the stub's own `__index` under one
  `ipairs` in `plugins/processes/icons.lua`, so no budget would ever have been enough.
- **Exposing the shown rows as a new picker contract method.** 2026-10-17 10:17. It would let
  the stage read the ranked list straight off the provider, but it adds a twenty sixth required
  method to both providers, the contract, its document and every fake in the tests, for a list
  the stage can already rebuild exactly, since both providers rank through `lib/chooser/rank.lua`
  with the instance's own matcher. The facade exposes that module instead.
- **Holding the highlight by key inside each provider's own refresh.** 2026-10-17 10:17. The
  provider knows the shown rows, but it treats an item as opaque, `key` is a stage word rather
  than a picker one, and the hold would be written twice, once per provider. It lives once in
  `host/stage`.
- **Leading the BrowserTabs Settings row on every two letter prefix of a settings word.**
  2026-10-17 10:17. It shipped in 91cf8be and opened settings on Enter for di, meant for
  Discord, and en, since a prefix is often the start of a tab's name and the first row takes
  Enter. Only a whole word leads.

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
- 2026-10-16 16:52. Phase 4's two open items closed and phase 6 switched to failing, on
  `olm/core-split-finish`. The app toggler declares `provides.launcherAppDetails`, a table keyed by
  bundle id built in `bindHotkeys` from the entries it bound, chord by leader role or literal
  combo, description and url, keeping the rule that a combo wins the chord over a modal entry for
  one app and a url from either stays. `contributions.appDetails` merges every supplier of the
  launcher's new `launcherAppDetails` set into one function, the root hands it over as
  `appDetails`, and the launcher asks it whenever it builds its app rows and spells a leader chord
  with the leader's name, so every subtitle reads as before. The launcher's `toggles` and `apps`
  declarations are gone, since its app catalog is a disk scan and needs neither. With the person's
  config the set of apps carrying a chord is unchanged. On a machine with no person toggle list
  the shipped Finder toggle now shows on its row as it is bound, which the old read of raw person
  data missed. `registrar.bind` takes `leaderRole` and raises for a tool whose effective leader
  names another role, which the wiring stage reports as a problem line, see Rejected for why it is
  not bound on the window leader. `test/cases/leader-sheets.lua` moves keep awake onto the window
  leader and finds it refused by name, bound nowhere and shown nowhere, and
  `test/cases/launcher-contributions.lua` checks the app row subtitles and urls. For the gate, the
  launcher's System Settings scope icon key `settings` collided with the settings plugin's identity
  and is `settingsPanes` now, the four `emoji` hits are accepted, see Rejected, the stale
  verification note in `test/drygate-accepted.txt` quotes the line compose writes today, and
  `LEAK_FAILS` is true, so the gate reads 0 findings and 0 warnings. Still open, the scan's named
  blind spot, a lower case identity written as a bare field such as `opts.audio`, which no form
  matches, so a review has to look for it by hand.
- 2026-10-16 17:05. Review fixes to the finish branch. The Hyper sheet now validates every section
  and row before building and drops a bad one with one log line, so a malformed supplier answer
  costs itself and never blanks the sheet. The app toggler builds its sheet rows and launcher
  details one bound entry at a time with each lookup guarded, and refuses at configure a
  `leader` other than app, since its keys always bind on the app leader and another word would
  list them on the wrong sheet. A supplier that reaches no sheet, no `defaults.leader` or a
  leader the asking sheet does not reveal, is logged by `lib/contributions.lua`, and the window
  sheet still does not ask the set. The layer gate counts hits per line and the count is part of
  the finding text, so an accepted line accepts exactly that many and `lib/icons/config.lua` line
  15 carries two. Two more blind spots of that scan are written in phase 6 of the plan, a name
  built by concatenation and a lower case table key in a constructor. The host key rule now
  lives in `hints.hostKeyBinding`, which `root/compose.lua` and `test/cases/leader-sheets.lua`
  both call, so the case restates nothing and the earlier restatement, which wrongly asked for
  no registry block and skipped the show check, is gone. The case compares chords as counted
  lists and runs once more with the real `config/plugins.lua`, `config/keys.lua` and
  `config/apps.lua`.
- 2026-10-16 17:32. The app catalog and the app toggles left `cfg.shared` and now reach the app toggler through its own `apptoggler` entry in `config/plugins.lua`, as `data = { apps = require("config.apps"), toggles = require("config.keys").appToggles }`. A grep over every manifest found no other plugin or host declaring a user sourced need named apps or toggles, so the flat channel carried values for one plugin only. The lists stay in `config/apps.lua` and `config/keys.lua`, referenced rather than copied, since keys.lua is where a person rebinds a physical key. `shared` in init.lua is now empty. The leader sheets case no longer builds the toggler data by hand, it reads it from the real plugins entry.
- 2026-10-16 17:47. The docked companion pane moved into core, closing the 14:26 entry's open item.
  Five plugins each carried the same canvas lifecycle, the settings Plugins page, speedtest,
  processes, file search's side panel and the clipboard preview, and `lib/dockedpane.lua` now
  owns it once, the canvas, the dock on the companion rect, the surface underneath, the empty
  state, the scroll and its clamp, the thumb, the hide guard and the destroy. It is Template
  Method on closures, the paint is the fixed skeleton and what is drawn is a describer answering
  one kit node or a painter answering elements and an overflow, for a pane of several regions.
  `root/compose.lua` builds the factory with the kit and CanvasPanel's two routines, and
  `lib/wire.lua` grants it as `opts.dockedPane` for `pane = true`, replacing the `surface` and
  `emptyState` grants. Settings lost its `pane.lua` and speedtest kept a `pane.lua` that only
  chooses the view, and neither reads the kit any more, so both dropped `needs.lib.ui`. Kept in
  the plugins on purpose, the processes cache of the static half and the file search header,
  body split and thumbnail generation, since each is what that pane draws rather than how a pane
  lives. Four behaviours moved slightly and none should be visible. A pane given no empty state
  now leaves the bare surface up in all five, where three used to hide, a case the grant never
  produces. The clipboard preview is destroyed on close rather than hidden, so a reopen waits for
  the first dock instead of painting at the last open's frame. A scroll is clamped as it arrives
  rather than only at paint. A redock rebuilds the processes and file search caches only when
  the box changed size. Speedtest negates the scroll it is handed before passing it on, because
  it has always moved against the other two scrolling panes, and keeping that is the live check's
  question rather than this change's. `test/cases/dockedpane.lua` drives the piece over a stub
  canvas and timer and runs in plain lua, and the dry gate hands a pane declaring plugin an
  autostub `dockedPane` in place of the old `surface`.
- 2026-10-16 17:54. Speedtest's scroll direction was corrected to match the other panes, so it passes the points the chooser hands it straight through and no longer negates them. The 17:47 entry's open question about keeping the old inversion is closed.
- 2026-10-16 23:23. The layer gate's blind spots closed, on `olm/gate-blind-spots`. The scan in
  `test/drygate-leaks.lua` now tokenizes operators and reports four more forms, a lower case
  identity as a field or method on anything but the bare `hs` global, as a table constructor key,
  a string folded from literals joined with `..` or from `string.format` and `("..."):format` with
  literal arguments, and a literal ending in `plugins/` joined to something computed. Measured on
  the tree before choosing, lower case fields 24 hits, 21 on `hs`, constructor keys 11, bare names
  3, folded strings and run time plugin paths 0. Bare names are not reported, see phase 6 of the
  plan. The two `settings` collisions were renamed, see Rejected, and the nine `emoji` icon spec
  keys in the host manifests and `lib/icons/rows.lua` are accepted. A leak finding now names its
  line by the line's text rather than its number, so the 12 accepted leak lines survive edits
  elsewhere in their files. `test/drygate-rename.lua` with `test/drygate-composerun.lua` is the
  second layer, run by `drygate.sh` on every call. It runs the person's `init.lua`, and so
  `root/compose.lua`, under a stub with a sandbox that refuses every write and every read of
  runtime data, once over the spoon and once over a copy where every plugin directory, manifest
  name, surface context, sibling need and person config key is spelled by a fixed case keeping
  letter shift, and compares the two snapshots, log lines, the wiring report, the record of the
  run, the shared atoms, every hs call and every file loaded, after turning the names back. A
  difference, or a scrambled name that never reached core, is a finding that cannot be accepted.
  Two stub rules made the root run to the end, a stand in indexed by a number answers nil so
  `ipairs` over one ends, and a stand in can be added, compared and joined. On the real tree it
  reads 0 differences over 4439 distinct lines. Thirteen planted leaks in a scratch copy, a field,
  a field through the plan binding a key, a constructor key, a literal concatenation, a plugins
  path by concatenation, a plugins path finished at run time, `string.format`, `:format`, a
  reversed literal, a `table.concat`, a concatenation inside `lib/registrar.lua`, a literal in
  launcher code that runs only on show, and `hs` reached through another table, each failed the
  gate, the reversed literal and the `table.concat` through the proof alone, the run time path,
  the launcher literal and the indirect `hs` through the scan alone, the rest through both. The
  hs global's own `settings` and a bare local named like a plugin read clean.
  `test/cases/leakscan.lua` keeps the scan's forms under the unit runner. The gate went from about 1.2 to 1.9
  seconds. Still open, host code that runs only when a list shows is seen by the scan alone, a
  bare name sharing a plugin's word is never reported, and a core that orders plugins by one
  particular name passes the proof, since order is not compared.
- 2026-10-16 23:39. Review fixes to the rename proof, after 5975fec. A review planted a leak in
  `lib/hints.lua` that kept a decision inside the panel the root builds, a delay dropped for one
  context, and it passed with 0 differences, since the snapshot saw only the record, the atoms'
  own fields and hs calls. `test/drygate-composerun.lua` now wraps every function of every
  `Olm.lib` atom and every host module, and the methods of every object one of them returns,
  through its metatable, and records each call with its arguments, a table written as its sorted
  plain contents four levels down, a table inside an atom written as atom since its state is a
  cache filled in call order. Every content strategy handed to one, a table with a draw, is asked
  its state and preferred size and drawn at 400 by 300 after the root finishes, which compares the
  hint bar's footer per context, and text measures a fixed width per character so the kit can lay
  one out. hs.settings, hs.json, hs.execute and hs.fs record their calls and still answer nothing,
  hs call arguments are written the same deep way, so a modifier list differs where it used to
  read table, the sandbox also refuses io.output and io.input with an argument, io.lines outside
  the two trees, os.tmpname and package.loadlib, and the snapshot walk has no depth limit. The
  comparison splits words at braces too, keeping key=value as one word. A unit check in
  `test/cases/surfaces.lua` proves `deps.policy.shortcutsPanel.delayMs` reaches the panel, and
  `test/cases/compose-shortcutdelay.lua` runs the root through the same stubbed run and requires
  every hint bar panel to carry one delay above zero, which a half reverted rename in either
  `root/compose.lua` or `lib/hints.lua` fails, checked in a scratch copy each way. The planted
  cases were rerun with five more, the delay dropped in the panel constructor, the policy dropped
  for one identity, an hs.settings write keyed by a computed name, different hotkey modifiers for
  one plugin and an empty footer for one context, all built with a reversed literal the scan
  cannot see, and all five fail through the proof. The earlier fifteen give the same results as
  before. The gate reads 0 findings, 23 accepted and 0 differences over 5159 lines, in about 2.4
  seconds, 1.9 before this change and 1.2 on main. The coverage wording in the three gate files
  and the plan now says what the proof records rather than every route, and phase 6 of the plan
  lists what stays open, code that runs only once a person acts, state nothing reads back, order,
  and nesting inside one argument.
- 2026-10-17 09:25. The dry gate's four unknowns cleared, measured one by one. processes was
  never a heavy load. A sampling hook at five times the budget put every sample in the stub's own
  `__index` under `ipairs(hs.styledtext.fontNames())` in `plugins/processes/icons.lua`, endless
  because the stub answered every numeric index with another stub. capture and the launcher were
  correct code joining a real string answer, a default url handler and `hs.processInfo.bundleID`,
  that the stub answered with a table. browsertabs, and the launcher once it got past its load,
  were handed an empty table for an optional `needs.data` field, a Chrome bundle id the chromium
  factory refused as not a string and a stage asked for a method it lacks, a state no real load
  reaches. Two general changes, no plugin or host code touched. `test/drygate-hsstub.lua` now
  gives the answer shape `test/drygate-composerun.lua` already gave, nil at a numeric index and a
  plain value when joined, compared or used in arithmetic, so the gate's two stubs agree, and
  `test/drygate.lua` leaves an optional data field absent, the state the manifest's own breaks
  sentence describes, while a required one keeps its empty table. Before and after were compared
  in a scratch copy with every configured module's function members dumped, the 27 modules that
  configured before have identical members after, five more configure now, the four plus the
  stage host, and the gate's output is identical apart from the four unknown lines. One planted
  member typo in each of the four manifests, a registry open, a launcher runner, a wiring step and
  a dotted open, each became a finding. The gate reads 0 findings, 23 accepted, 0 warnings, 0
  unknown and 0 differences over 5159 lines, in about 2 seconds against 3.1 before, the time the
  budget used to burn. Noticed and left for a change of its own, browsertabs hands an empty
  string Chrome bundle id to the factory, which raises and takes Safari down with it, against its
  manifest's own breaks sentence.
  Corrected 2026-10-17 09:31, see below.
- 2026-10-17 09:31. Review of the entry above found two claims too broad. It said an empty table
  for an optional data field is a state no real load reaches. Several optional fields are tables,
  capture's providers, apptoggler's apps and toggles, windowmanager's margins and settings and
  processes' policy, so that holds only for a field that is a string or a host object, as the
  Chrome bundle id and the stage are. What is true for every optional field is that
  `lib/wire.lua` delivers it absent when nobody supplied it, which is the reason the gate leaves
  it absent. The entry also named no cost. The gate now checks the degraded configure path for an
  optional root word that is present on every live load, so a member assigned only when such a
  value is present would read as a false finding, loud rather than a silent pass. And the stub's
  new shape stops surfacing a genuine type bug where an hs object is joined into a string, which
  a live load raises on and the old stub reported as unknown, while a numeric index answering
  nil makes correct code like `hs.screen.allScreens()[1]:frame()` read as unknown, a false
  unknown rather than a false pass. Both comments now say this, in `test/drygate.lua` and
  `test/drygate-hsstub.lua`. No behaviour changed.

- 2026-10-17 09:36. The browsertabs defect noted on 2026-10-17, an empty Chrome bundle id raising
  out of configure and costing Safari and Arc their load, is fixed. `providerNamed` now reads nil
  and an empty string as the same absent case and keeps its friendly message, and calls the provider
  factory under `pcall`, so a factory that refuses a present but wrong value, a number for instance,
  becomes the skip reason `configure` already logs while the other browsers still load.
  `chromium.lua` keeps its own validation unchanged. A unit case,
  `test/cases/browsertabs-chromeid.lua`, configures safari and chrome with nil, an empty string, a
  number and a valid id, and proves configure never raises, Safari is always built and Chrome is
  built only for the valid string.
- 2026-10-17 10:15. The BrowserTabs per browser level was dropped at Milos's request. Selecting a
  browser on the settings level now switches it in place and answers stay, and the permission
  actions it held moved to one extra row directly under a switched on browser, only when the
  permission asks something, each naming the browser. The settings list also filters now, with
  Back and every row stating a filterText, and a settings word typed in the tab list puts the
  Settings row first instead of last.
- 2026-10-17 10:17. A review of the 10:15 change found the highlight could leave the browser the
  person was on. A permission read lands through an async redraw, which kept the row number, so
  on a first open with Chrome highlighted, Safari's read inserting Ask Safari for permission above
  it put the highlight on that row and Enter asked Safari. A stay held by key, but under a typed
  query `selectWhere` refused and fell back to the number, which in a ranked list is a different
  item. `host/stage` now holds the highlight on the same item across every repaint that keeps the
  person on the same level, a stay, a refresh and an async redraw, in one routine. The item under
  the highlight is read before the rebuild and found again by its `key` in the list as shown,
  ranked through the facade's own `rank` with the instance's matcher, the same module and inputs
  the provider uses, so the index is the one on screen. An item with no key, or a key that is
  gone, keeps the row number as before. processes, menusearch and speedtest rows already state
  keys, so their async redraws now follow the item rather than the number. A unit case,
  `test/cases/stage-holdkey.lua`, runs the real stage over the real default provider kept off
  screen and fails five checks against the old stage. Two things moved in BrowserTabs with it. A
  permission row now filters on its browser's name alone, so it no longer shows on a state word
  such as a or o without its browser, nor ranks above it for sf or co. And the belief the plugin's
  AGENTS.md held, that drilling in is for acting on one browser, was reversed at Milos's request
  at 10:15, its sections now describe the flat list. The Settings row leads the tab list only when
  the trimmed query, ignoring case, is a whole settings word, and on a prefix of one it trails the
  tabs as it did before 91cf8be, since di for Discord or en then Enter opened settings.
  Corrected 2026-10-17 10:27, see below.
- 2026-10-17 10:27. Review of the 10:17 entry found its list of lists that now follow the item rather than
  the row number incomplete. It named processes, menusearch and speedtest. The launcher changes
  too, since System Settings pane rows carry their url as a key and menu scope rows carry keys, so
  an async `Launcher:refresh` now follows those items while app rows, which state no key, keep the
  row number. The Plugins page, through its Apply row and its plugin rows, and BrowserTabs settings
  follow the item as well. Kept on purpose, holding what the person sees is the principle. The
  same review found the lookup called a plugin's rows and the ranking a second time with no pcall,
  so a raising rows function escaped `Stage:refresh` and could stop a background tick such as live
  process sampling. Both now run under pcall, a failure is logged and the row number stands, and
  `test/cases/stage-holdkey.lua` proves it with rows that raise on the lookup's call.
