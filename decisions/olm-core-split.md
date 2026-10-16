# Olm core and plugins apart

Status. In progress. Phases 1 and 2 of `Spoons/Olm.spoon/docs/PLAN-CORE-SPLIT.md` have
landed, the person's plugin changes live in one file and the leader plumbing is core. Phase 3,
the launcher naming no plugin, is built on its branch and owes its live load.

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
