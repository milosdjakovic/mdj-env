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
   reloads.
4. The registry roster is deleted, so there is one switch.

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
