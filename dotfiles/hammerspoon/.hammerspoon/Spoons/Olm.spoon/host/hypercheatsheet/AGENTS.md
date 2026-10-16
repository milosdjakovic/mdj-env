# HyperCheatSheet.spoon

The decision trail for this host. Cross cutting material stays in the hammerspoon
`AGENTS.md`, which links here.

## What it is, and what it deliberately is not

A content builder for the overlay that appears while the Hyper leader is held. It lays out and
hands to the renderer an ordered list of sections, and it decides nothing about what is in
them. It names no plugin and reads no plugin's data. The promise it keeps is that every key
bound on the app leader is on the sheet and nothing is on it that is not bound there, and that
promise is kept by where the sections come from rather than by anything this host checks.

## Where the sections come from

Two sources, both assembled by the composition root and handed over as one list in
`opts.sections`.

The sheet's own block is every chord the root found bound on the app leader,
`lib/hints.lua`'s `sections`. It walks the registry's leader shortcuts, the registry commands
on the leader through the registrar's own key lookup, and every plugin on the app leader in
plan order for its own key, its `bindings` and its keyed special rows. It carries no live state,
so it is built once at configure.

The rest comes from plugins that declare `provides.cheatSheetSections` and state
`defaults.leader = "app"`, found by the set this host declares, `needs.set.cheatSheetSections`.
Each arrives as a function the host calls on every show, so a section may read live state. The
app toggler is the one today, answering its toggles split into the apps running now and the ones
that are not. lib/contributions.lua resolves each member, wraps it so one that raises costs only
its own sections, and orders everything by `defaults.cheatSheetOrder`, the toggles at ten and
this host's own block at fifty.

Until phase four of the core split this host read the person's appToggles list and the app
registry itself, resolved every icon and did the running split here. That was a core host
knowing one plugin's data and its shape, and it read the person's raw list while the plugin
bound from its merged one, so the two could disagree. The split is app knowledge and moved into
the plugin with the list, and the sheet now lists exactly the entries the plugin bound into the
Hyper modal.

## Layout

A section with `icons = true` renders in the panel's icon grid, four columns wide enough for a
long app name with a 32 point icon. Any other section overrides the panel to the same four
columns with no icon gutter, so long labels such as Screenshot to clipboard are not cut. A row
that states its own `badge` keeps it, any other row and every binding is spelled by the shared
glyph helper, so Hyper+Shift+4 reads ⇧4. Empty sections are dropped by the renderer, so a group
with nothing in it, no running app for instance, simply does not appear.

## What the manifest declares, and why each policy is what it is

The shared `cheatSheet` renderer is required. This host draws nothing of its own, so without
the renderer there is nothing for the row model to become.

`sections` is optional. Without it the overlay opens empty rather than failing, which is the
honest degradation for a list the root assembles.

The set question answers nothing on an install with no app toggler, and with the toggler
switched off the sheet simply has no app section. Every other bound key is still listed.

## The test that guards it

`test/cases/leader-sheets.lua` builds a plan over the real manifests, runs the code that binds
with recorders standing in for the leader engines, shows this host and the window sheet into
recorders, and fails on any key bound and not shown or shown and not bound.
