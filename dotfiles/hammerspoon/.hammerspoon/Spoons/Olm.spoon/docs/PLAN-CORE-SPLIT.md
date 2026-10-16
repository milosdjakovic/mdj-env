# Plan, core and plugins apart

Written 2026-10-16. The goal is the one Milos stated. A plugin is a self contained, portable
directory whose manifest names everything it needs and everything it offers. Olm finds it,
reads the manifest, loads it, puts its rows in the launcher, its keys on its leader and in that
leader's cheat sheet, and lets a person switch it off. Core is everything plugins consume, and
core may be wired by name. Core never names a plugin.

The facts below were checked against the tree on 2026-10-16, by reading and by a plan probe run
inside the live Hammerspoon. Recheck any citation before acting on it, since the spoon moves.

## The layers

| Layer | What it holds | May name |
|---|---|---|
| Core libs, `lib/` | chooser, CanvasPanel, cheat sheet renderer, UI kit, icons, the leader engines, paste, storage, registry | nothing outside core |
| Core hosts, `host/` | launcher, stage, queryscope, actionpanel, the cheat sheets | core only |
| Plugins, `plugins/` | every feature | core contracts only, through its manifest |
| Person's config, `init.lua` and `config/` | data and overrides | plugins, by identity, as data |

The root may name anything in the first two layers and nothing in the third. A dry gate check
enforces it, so the separation cannot erode quietly.

## What stands in the way today

1. **The launcher depends on plugins.** `host/launcher/manifest.lua` declares seven siblings on
   four plugins. windowActions on windowmanager, appFocus and appToggleURL on apptoggler,
   runCapture on capture, and settingsPaneRows, openSettingsPane and focusSettingsSearch on
   systemsettings. In the other direction menuSearch takes coveredApp and refreshLauncher, and
   textCase takes coveredApp, as siblings on the launcher.
2. **Leader plumbing lives in `plugins/`.** The root reads keyremap's catalog
   (`root/compose.lua:673`), windowmanager's bindings (`:711`), and finds windowleader by name
   (`:1187`), with windowcheatsheet reached through windowleader's manifest. Hyper's engine is
   already core in `lib/hyperkey.lua`, its window twin is not.
3. **`config/keys.lua` is mostly dead.** Four entries are read, appToggles, clipboardShortcut,
   appLeader and windowLeader. The rest, every per plugin key, alias and hyperContexts block, is
   read by nothing at runtime, only by `test/inventory.lua` and `test/world.lua`. Rebinding a
   plugin's key actually works through the `spoon.Olm:start` table keyed by identity, merged over
   the manifest in `lib/resolve.lua`, while the docs and the olm-plugin skill still say
   `config/keys.lua`.
4. **Two activation switches, one of them dead.** `toolActivation` in `config/settings.lua` is
   read by nothing. The registry roster `Olm.registryActivation` is unset, so all is active, and
   it only hides a plugin while the plan level `false` drops it.
5. **Disable is incomplete.** A plugin set to `false` still has its `init.lua` run by the loader
   before the plan exists, its tools probed, and its predicates and live labels harvested. Its
   optional users log `names 'x', which is not a plugin here`, which reads as a defect.
6. **A cheat sheet lists a dead key.** The Hyper sheet lists o for Actions, which only works
   inside an open list, where the sheet never shows.

## Phases

Each phase lands on its own branch with the dry gate, the dependency check, one live load under
the devlock, and a comparison of the wiring report against main. A phase that changes nothing a
person sees still gets the live load.

### Phase 1, dead config and stale docs

Delete the dead entries of `config/keys.lua` and `toolActivation`, and move the two tests off
them. Create `config/plugins.lua` per decision one, move the per plugin `data`, the `globals`
entry and any overrides into it, and have Olm read overrides, data and globals from
`cfg.plugins`. Correct the docs and the skill to say where a person changes a plugin. No
behaviour changes, so the wiring report must match main exactly.

### Phase 2, leader plumbing into core

Move keyremap, windowleader and windowcheatsheet out of `plugins/` beside hyperkey and the
Hyper cheat sheet. Make the window leader work like Hyper, so any plugin may declare
`leader = "window"` with bindings and the root collects them by walking the plan, the way the
Hyper cheat sheet already collects `leader = "app"`. windowmanager stays a plugin and declares
its bindings in its own manifest, which it already does, and the root stops reading them by
name. Thirds, sixths and other layouts become later additions to windowmanager with no core
change.

**Done, 2026-10-16.** The three pieces are core and the root names none of them as plugins.
Keyremap is `lib/keyremap.lua`, its catalog is `policy.leaderCatalog` in `root/compose.lua`
and overridable through `cfg.policy`, and hidutil is declared by `root/manifest.lua` with the
unit still called keyremap. The root applies the remap itself just before the leaders are
configured, through the dependency door like scutil. The window leader is `lib/windowleader.lua`,
published in `obj.lib` and in the root's `libs`, configured once with the window role's keycode,
and a plugin binds through `bind(key, fn, mods, opts)` with no keycode, `opts` carrying `when` and `repeats`, and the lib owns the predicate gate like Hyper. The window cheat sheet
is `host/windowcheatsheet` and reads the root word `windowBindings`, which is every binding on
the window leader found by `hints.leaderBindings` walking the plan, stamped once, and also handed
to the launcher in place of windowmanager's own record, though the launcher's window rows still
come only from windowmanager's actions until phase 3. Windowmanager keeps `leader = "window"`,
renames `windowManagement` to `bindings`, and declares `needs.lib.windowLeader` with the wiring
step `bindToLeader(self.windowLeader, self.bindings)`. The remap is applied just before the
engines start, so a failed load leaves the native keys. The root words
`activeNames`, `mapping` and `windowManagement` are gone and `windowBindings` is new. The
launcher's sibling on windowmanager for the action map is untouched, and phase 3 removes it.

### Phase 3, the launcher stops naming plugins

Every one of the seven siblings becomes a generic contribution point a plugin declares.

1. Action rows carry their own run. capture already provides actionRows, windowmanager joins
   the same set, and the launcher runs what a row carries instead of calling capture.
2. App focus becomes a core service. The launcher already scans apps, apptoggler uses the same
   service rather than owning it.
3. Catalog rows. systemsettings contributes its pane rows and its search row to the launcher's
   own list, each with its select, through a set the launcher asks for.
4. coveredApp and refreshLauncher become root published words, so menuSearch and textCase stop
   naming the launcher.

When this lands the launcher manifest has no siblings, and switching off capture or
systemsettings produces no problem line.

**Done, 2026-10-16, built, live load owed.** A plugin contributes rows to the launcher's own
catalog by declaring `provides.launcherRows`, plain row descriptors, and `provides.launcherRun`,
handed a chosen row's item. The launcher asks the set for both, and the root resolves each
member through the registrar's own door, stamps the plugin's identity on every row's item as
`owner`, and hands the launcher `rowSuppliers` and `runners` keyed by owner. Query source rows
carry their owner the same way. The dispatcher runs an owned row through its owner's runner on
the same short delay, then falls back to its own kinds, `app`, `special`, `calc` and `scope`.
A row names its chord as `group` and `chord = { leader, key, mods }`, spelled by the launcher
with the leader names the root passes for every role, so every subtitle reads as before. Capture
and the window manager build their rows from their own effective bindings, System Settings
answers its panes, keyed by url, and its search row, which kept kind `special` and name
`searchSettings`. Each contributor declares its place as `defaults.launcherOrder`, a row may
state its own `order`, and a row states its own identity with `key` and `remember = false`, so
the launcher reads no kind word to place or remember a row it did not build. The supplier and
runner assembly is `lib/contributions.lua`, which the root calls and the unit case drives. Window Size runs its typed size row itself
through a second sibling on the window manager. Focus or cycle and toggle by url moved into
`lib/appfocus.lua`, published in `obj.lib` and the root's libs, with `open` declared by
`root/manifest.lua`, and the app toggler and the launcher's app rows both call it. `coveredApp`
and `refreshLauncher` are root words over the launcher. The `kin` table, `captureRows`,
`windowActions`, `windowLeaderName` and `settingsPanes` are gone, and the launcher manifest has no
siblings. A comparison against the previous commit found all 63 catalog rows equal in title,
subtitle, icon key, kind, identifying field, gate, keywords, order and recency key, the only difference being
that the window rows and the search row read their icon against the plugin that built them,
which declares the same emoji and SF Symbol. The gate this phase opens in report mode, phase
six, is not written yet.

### Phase 4, cheat sheets complete and honest

Every key a plugin declares on a leader appears in that leader's sheet, and nothing appears that
is not bound there. Fix the Actions listing. Check that a command declared on a leader reaches
the sheet, since the trace suggests a leader command is dropped. App toggles stay person data.

### Phase 5, the switch

1. One saved set of disabled plugins in `hs.settings`, merged with `false` entries from the
   person's config before anything loads. The loader, the dependency door and the predicate
   harvest skip a disabled plugin, so its code never runs.
2. A disabled plugin is reported as off, its dependents as off because of it, and its optional
   users stay silent.
3. A plugins page in the OLM settings plugin lists only `plugins/`, shows each plugin's about
   block and needs in the right pane, says what else goes down before confirming, saves and
   reloads. Reworked after the first live try, a choice is staged and the staged set applies
   with one reload when the stage closes or Apply now is chosen, see below.
4. The registry roster is deleted, so there is one switch.

**Packet one done, 2026-10-16, built, live load owed.** Items 1, 2 and 4, and the root words
item 3 will read. `lib/pluginswitch.lua` merges the `false` entries in `config/plugins.lua`
with the identities saved under `Olm.disabledPlugins`, refusing out loud anything that is not
a plugin under `plugins/`, and the root hands the set to the loader and to the resolver
before anything loads. `lib/plugins.lua` answers `offBecause`, every plugin requiring a
switched off one mapped to the sorted list of every switched off plugin it depends on, which the loader skips too, and the resolver reports
both as choices, `plan.disabled` and `plan.offBecause`, while a sibling or a set question
naming a switched off plugin is no longer reported as a defect. Everything in the root after
step C reads the manifests without the switched off ones, so the door, the icons, the fan out
and the delivery check never reach one. `spoon.Olm:report()` leads with `switched off, x` and
`off because x is switched off, y` and still says no problems when those are the only
differences. The settings plugin declares `pluginCatalog`, `pluginCascade` and `setPluginDisabled` as
optional root words, and `registrar.forWire` activates every tool that registered.
`test/cases/pluginswitch.lua` covers it.

**Packet two done, 2026-10-16, built, live load owed.** The Plugins page in `plugins/settings`,
rows with a green or red circle, a docked pane with the about block, needs and cascade, and one
reload per switch, covered by `test/cases/settings-plugins.lua`. The action panel's Actions key
no longer declares a leader or key in its manifest, since the real chord comes from
`lib/surface.lua` inside every list. The review then added that the page cannot switch itself
off, that a stale saved identity is warned about and dropped on the next switch, that a plugin a
host requires is locked by the core and a host is never marked off, and that the unused word
`disabledPlugins` is gone.

**Apply reworked after the first live try, 2026-10-16, built, live load owed.** A press saved
and reloaded at once, which tore the list down under Milos after every row. A choice on the
Plugins page is now only staged, in memory in the root, and the page stays open with the
highlight held, each row saying off after apply or on after apply, a dependent saying it goes
with the plugin it needs, and the pane's cascade measured against everything staged. Choosing a
row back drops its staged entry. The staged set is saved with one reload when the stage goes
away by any route, through a new `onClosed` observer list on `host/stage`, which a pop back to
the top level never fires, and after such a dismissal nothing reopens and one routine line names
what changed. An Apply now row after Back, shown only while something is staged, applies the
same way and reopens the page on the plugin last chosen, through a one shot note under
`Olm.resume` that `lib/resume.lua` writes and takes once and `stage.presentAt` acts on, walking
the plugin's own path of items through each level's `select`. The words are now
`stagePluginSwitch` and `applyPluginSwitches` in place of `setPluginDisabled`, and the stage
holds a "stay" highlight on an item's `key` so the Apply row appearing above does not move it.
`test/cases/stage-resume.lua` covers the stage half.

### Phase 6, the gate

A dry gate check that no file outside `plugins/` names a plugin identity in code or manifest
data, the person's config excepted. It runs from the start of phase 3 in report mode and fails
the gate from the end of phase 3.

## Decisions

Milos left all three to whichever shape best serves decoupling, 2026-10-16.

1. **Overrides live in one entry per plugin.** A new `config/plugins.lua` is the person side
   mirror of the manifests, one entry per plugin identity, holding that plugin's overrides of its
   own defaults, its person supplied `data`, the spoon global it is mirrored onto, or `false`.
   `init.lua` hands it to Olm as `cfg.plugins`. Today the overrides sit at the top of the `start`
   table beside `data`, `policy` and `globals`, so a plugin named after one of those would
   collide, and one plugin's person facts are spread over three keys. `config/keys.lua` keeps only
   what belongs to no plugin, the leaders and the app toggles. A plugin's defaults stay in its
   manifest, the person's changes stay in one file, and Olm is the only thing that merges them.
2. **Dependents go down and are shown.** The page computes the effect from the load plan and the
   saved state stays a plain set of the person's own choices. A dependent's own switch is never
   touched, so it comes back by itself. No confirm step, since nothing is lost.
3. **One reload per toggle.** Whether a plugin runs is decided once, by the plan, at load. Live
   toggling would need every plugin to know how to stop and unbind itself, which is coupling the
   contract avoids on purpose, nothing in Olm ever unbinds a key.

Phase 1 carries the first decision. The app toggles also feed the Hyper cheat sheet through
`shared`, a host reading one plugin's data, which phase 4 replaces with apptoggler contributing
its keys to the sheet like any other plugin.

The order is deliberate. Phases 1 and 2 are small and make the root honest. Phase 3 is the
largest and needs one adversarial review. Phase 5 depends on 2 and 3, since without them the
list would carry exceptions for core pieces that only look like plugins.
