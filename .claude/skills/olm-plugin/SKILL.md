---
name: olm-plugin
description: Build, change, or review a plugin in the Olm Hammerspoon spoon under dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon. Use for any new picker or chooser tool, launcher row, Hyper context, stage presentation, manifest change, or any question about how an Olm plugin should be shaped or behave. Carries the decision rules for choosing a surface, nesting levels, plugin anatomy, dependency declarations, and the gates before commit.
---

# Olm plugin work

This skill holds the judgment layer, which shape to pick, how a plugin behaves, and what it
never does. The field level truth lives in the tree next to the code and this skill routes to
it rather than repeating it. Where this skill and the code disagree, the code is reality, the
disagreement is a finding to report, and the fix lands in this skill in the same change that
moved the behavior. This skill names files and rules. It never cites line numbers, counts, or
measurements, because those drift silently. Paths below that start at `Spoons/Olm.spoon`
are rooted at `dotfiles/hammerspoon/.hammerspoon` in this repository.

## Read order

Do not start from memory of how these plugins look. The contract has moved several times and a
plugin written from a stale mental model registers, reports success, and shows nothing.

1. Read `Spoons/Olm.spoon/docs/PLUGIN-AUTHORING.md` in full. It is short and it is the recipe,
   the required fields, what each optional field costs, the stage words, every refusal the
   wiring layer prints, and the build order to follow step by step.
2. Read `Spoons/Olm.spoon/docs/PLUGIN-CONTRACT.md` only for depth on a field the recipe sent
   you to, never front to back instead of the recipe.
3. When changing an existing plugin, read that plugin's own `manifest.lua`, its `README.md`,
   and its `CLAUDE.md` where it has one, and treat its stated design record as binding.
4. Before relying on any behavior a doc describes, open the file it cites and confirm the code
   still says that. The settled examples named below are worth reading beside the docs, since
   an example that loads today proves more than prose.

## Choosing the shape of the interaction

Work down this ladder and stop at the first rung that fits. Each rung is cheaper, more
consistent, and more discoverable than the one below it.

1. No list at all. A plugin whose whole job is an action or a watcher declares commands or
   wiring and shows nothing. KeyRemap and WindowManager are the settled examples. The recipe
   is written for list tools, so for this shape read the contract's `wiring` and `registry`
   sections directly. Do not invent a list so the plugin has a face.
2. A typed word. When the thing beneath a row can be reached by typing, prefer a scope, the
   alias and a space in the launcher, declared through `provides` or `registry.scope`. A
   scope needs no Back row because deleting the text is the way back. A row is only worth
   adding where there is no text to delete. Choosing a scoped tool's launcher row holds its
   scope rows in the list already open rather than opening the tool standalone, and that
   comes from the tool declaring a presentation, never from `registry.hosted`, which is a
   diagnostics flag a listing reads and nothing the stage or the launcher's own row
   intercept ever consults.
3. A child level. When choosing a row means showing another list, the row's `select` answers
   a presentation table and the stage pushes it in place. BrowserTabs and DisplayProfiles are
   the settled examples.
4. A page in place. When a row changes the list it is standing on and the person stays put,
   that is `intercept`, not a child. The clipboard's prune page is the settled example.
5. A new tool with its own chord. Only when nothing existing leads there, or the interaction
   genuinely needs its own key and context. This is the last resort, not the default.

## Choosing the surface

A searchable list the person picks from is a stage presentation, always. A plugin never builds
a window, never touches the chooser widget, and never holds chooser state, it declares a
presentation and reads the stage words off `opts`.

A glanceable overlay nothing is typed into, a preview, a toast, a status card, is CanvasPanel
content, never a window of the plugin's own. A companion preview pane beside the rows is
declared on the surface, `pane = true`, and routine feedback goes out through an injected
callback the root draws on the shared panel. A docked pane is never hidden while its
presentation is showing, a highlight with nothing to describe paints the shared empty state
instead, the injected `emptyState` routine that arrives beside `surface`, so a reserved rect
never sits there with nothing drawn in it. The pane genuinely vanishes only when the stage
tells it `onPositioned(nil, nil)` and on close. A
grid of key badges under a held leader is the shared cheatsheet lib. Verbs come free, the
action panel reads them from the registry declaration, so never build a second list to make
verbs discoverable.

`hs.alert` is reserved for a hard failure that stopped the action entirely, a missing window, a
dead binary. Routine feedback while a feature works never goes through an alert.

## How levels behave

These rules are what make every plugin feel like the same instrument.

A menu level's first row is Back, spelled Back, carrying the back glyph the existing menus
use. A typed scope has no Back row. Backspace on an empty field pops, the presentation's own
`back` answers first, and the stage pops only when it declines. A row that must leave its
level itself, a delete landing you above the thing you acted on, calls `stagePop` from inside
its own `intercept`, since a child can only ever push.

The highlight belongs to the person. A plugin never moves it, never caches the selected row,
and reads it only through the stage words. An async answer lands on its own level via the
token discipline in the authoring guide, or not at all. A redraw that resets to the top is
sanctioned only when a reorder left no row worth preserving. A row that mutates the list it
is standing on answers "stay" from intercept, never plain true, so the highlight never
leaves the row the person chose, and a page of options a person flips never pops or closes
on selection, leaving is always the person's own key. Plain true from intercept is for a
wholesale swap of the list and nothing else.

The placeholder names the list, never a key, and no user visible text anywhere names a
physical key, since bindings live in `config/keys.lua` and the hint surfaces already say them.
A child inherits everything it does not declare, so declare only what genuinely differs.

## Anatomy

Two shapes are legitimate. A plugin with no moving parts is `manifest.lua`, `init.lua`, and
`README.md`. A plugin built around swappable behavior splits into an engine that owns state
and no policy, a contract its providers satisfy with a validate step, one self contained file
per provider, and a chooser or store file when those earn their keep, with `init.lua` as the
plugin's own composition root, loading siblings by `loadfile` and naming the concrete pieces.
Capture is the settled example of that file shape, and Clipboard shows the same idea grown
larger, its engine a manager subpackage rather than one file. Never `require` a sibling, the spoon directory
is not on the module path, and never add the engine and contract ceremony to a plugin with one
behavior.

The manifest is pure data, loads with nothing required, and never touches `hs`. The directory
is one lowercase word. The identity is the directory unless it needs a different spelling,
camelCase being the common case and a genuinely different word the rare one, in which case
declare `name` and spell `surface.context` identically.

Every plugin carries a `README.md` in the house shape, a paragraph on what it does, a line on
how it opens and where it appears, a line on the in list keys. A plugin earns a `CLAUDE.md`
only when it holds decisions or measured findings a future reader would otherwise rediscover
the hard way, and that file records why, never what.

## What a plugin never does

A plugin receives its whole world through `configure(opts)` and through the stage words it
declared. It never references `spoon.Olm`, never loads a lib file by path, never builds an
`hs.chooser`, an `hs.hotkey`, or an eventtap for a leader key, and never resolves where a tool
is installed. External binaries and bundles are declared in `needs.tools` and arrive through
the scoped `deps` adapter, and anything undeclared answers nothing by design.

Never write an install command anywhere, not in code, not in a comment, not in help text a
person reads. The repository root holds the answer key for where every tool comes from.

## What declaring earns

Every plugin receives `after` and `log` without asking. Declaring a `surface` earns the shared
chooser factory, the theme, and the placeholder. The docked panel callbacks are a separate per
plugin grant shaped by the plugin's own stated declaration, and the contract holds the detail.
Declaring
`needs.tools` earns `deps`. Declaring `needs.lib` earns the named lib instance, and the set in
real use is small, paste for insertion, recency for lift to front ordering, storage for cache
and data paths, plus the leader engines and the cheatsheet renderer for the plugins that own
those surfaces. Declaring `needs.data` with `source = "root"` earns a stage word or a root
value, and the vocabulary is deliberately shared, so grep the other manifests and reuse an
existing word before minting a new one, since a vocabulary of one word per plugin is a
vocabulary nobody can pay. Siblings exist and are rare, prefer not needing one.

Configuration splits three ways. The plugin proposes its own `defaults`, a leader role, a key,
aliases, a glyph, and a person overrides them outside the plugin, rebinding a physical key only
in `config/keys.lua`, so no other file ever names one. Person supplied policy arrives as `needs.data` with `source = "user"`,
always optional, always with a `breaks` sentence and a working fallback.

A field on that configuration surface prefers a structural value over a loose quoted word, a
number, a boolean, a table, or a function rather than a string a plugin then matches against a
set of meanings only its own source code knows. A bare string is unchecked vocabulary, and
`config/keys.lua` requires nothing, so no plugin vocabulary can ever reach it and catch a typo
on the way in. AppToggler's own `hides` and `placement` fields are the settled example, a
boolean and a table or a function rather than a word like `"showAndHide"` naming a behaviour
from a set nothing validates. Where an enumeration genuinely cannot be avoided, validate it
loudly at bind time rather than letting an unrecognised word fail silently by matching nothing.

## Dependencies end to end

Declare the tool in `needs.tools` and nowhere else, the authoring guide holds the field detail
and the policy guidance. The plugin's half ends there. The other half lives at the repository
root, add the line to `DEPENDENCIES.map`, add the matching `Brewfile` entry for a package
manager origin, and run `./src/check-dependencies.sh` from the repository root until it
finishes with no error and no new warning naming the plugin.

## The gates

In order, before anything merges.

1. `./src/check-dependencies.sh` clean, from the repository root.
2. The dry gate, `Spoons/Olm.spoon/test/drygate.sh` under `dotfiles/hammerspoon/.hammerspoon`,
   lock free and instant. Run it and read
   the line naming your tool. It is the only thing that checks `registry.open`, scope members,
   and command functions, so skipping it is how a typo becomes a key that does nothing.
3. One live load. This is the gate no static check replaces, and the discipline around the
   devlock, the console read, and the scheduled reload lives in the hammerspoon `CLAUDE.md`.
   Never drive the screen or the keyboard for a test until Milos says start.
4. One real key press. Structure has never proven that a key fires.

## Style and commits

Comments and docs explain why, not what. Plain sentences, only periods and commas, no dashes
or hyphens in prose. Commits go on a branch in the `olm(scope)` style of the recent history,
and nothing merges or pushes unless asked.

## Keeping this skill true

When a rule here stops matching the tree, fix the rule in the same change. When Milos states a
new preference during plugin work, when the right panel is the right choice, how a new surface
should behave, fold it into this skill so the next cold session already knows. The skill stays
rules and routing, the tree stays the reference, and neither repeats the other.
