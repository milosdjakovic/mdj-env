# The action bar

Opened 2026-10-23 on branch `olm/action-bar`. Milos asked for the footer Raycast and Tinycast
draw under a list, one row always visible, a key list behind a button on the left, and on the
right what Return does, what Command and Return does, and where the rest of the actions live.
It replaces the docked shortcut hint pane, which appeared under a list after an 800 ms pause.

## What a person sees

Every list in the default chooser carries one footer row at the bottom of its own canvas.

```
├────────────────────────────────────────────────────────────────┤
│ (?)              Choose Files ↩ │ Uninstall ⌘↩ │ Actions ✦ O   │
└────────────────────────────────────────────────────────────────┘
```

The right side reads, from left to right, the primary label with the Return glyph, the secondary
label with its chord when the list declares a secondary, and Actions with the action panel's
chord. Every label follows the level being shown, so a pushed level names its own primary.

The (?) on the left toggles a key panel that rises above the footer inside the same canvas,
covering the bottom rows while the list stays where it is. It lists every other key the open
list answers, moving, closing, Back, Command and a digit, and the list's own extra keys, drawn as
the cheat sheets draw a key, a badge beside a caption. A click on (?) toggles it, so does the
shared `showKeys` list verb, and any key that acts, Escape included, or a second click closes it.
It never scrolls, since a list answers about a dozen keys.

The action panel lists Back, then the primary, then the secondary, then the list's extra verbs,
each with its chord and its live label.

The legacy chooser draws no footer. It is deprecated and stays as it is.

## The contract a plugin gets

All of it is declared in the `surface` block a plugin already writes, and none of it names a key.

`primary.description` is the Return label, already today. A list that states none reads Open.

`secondary`, optional, `{ action = "...", description = "..." }`, the same shape as `primary`,
validated the same way, with `needs`, `chord` and `repeats` gates allowed and nothing else. Its
action is answered by the plugin's surface adapter like any `extra` action. It is a shared verb,
`shared = "secondary"`, so the action panel and the hint model treat it like primary.

A presentation, the table a plugin answers for a list or a pushed level, may declare `labels`,
a member resolving to a function from the highlighted item to a table with `primary` and
`secondary` strings, either one absent meaning the declared description. It is asked live, so
"Uninstall 4" can count what is checked. Lookup order for a label is the presentation's
`labels`, then the existing `liveLabels`, then the binding's `description`, then Open for the
primary and the humanized action name otherwise. `liveLabels` stays, its one user is the
clipboard, and it is not migrated in this change.

## Keys

Olm's own `all` layer, `keymap.listDefaults`, gains two entries. `secondary` sits on Command and
Return as a field key, leader false, so the default chooser's field answers it through
`nav.fieldKeys` before its own Return handling, which the previous commit made possible. And
`showKeys` sits on `/` on the list role, Hyper and slash inside a list, shadowing file search's
global key only while a list is open, which list keys may do. Both move and free in the `lists`
section of `config/keymap.lua` like every shared verb. `listDefaults` holds only key names today,
so a field key default needs a shape that carries modifiers and leader false, decided in the
build and stated in the `listDefaults` comment.

Command and Return with no secondary declared keeps choosing the row, as it did before.

## Shape of the code

The model and the paint stay apart, the same split the hint pane had between `lib/hints.lua`
and `lib/panel.lua`.

`lib/hints.lua` builds the footer model as pure data, `footerModel(contextName, plan, deps)`
answering `{ right = { {label, chord}, ... }, keys = { {badges, label}, ... }, state = string }`,
from the same bindings, gates and label lookup `rowsFor` uses, so the bar, the key panel and the
action panel cannot disagree. `footerFor` folds into it or is replaced by it.

The default provider takes one injected collaborator, `footer`, a function answering that model
for the list now showing, asked on every redraw and polled while showing the way `CanvasPanel`
polls `state()`, so a gated key or a live label changes without anyone telling the provider. The
provider knows no keymap and no plugin. It draws the model through the UI kit, the five type
roles and the eight colour roles, the badge chip `shortcutsContent` already builds, and it owns
the (?) toggle state, the hit test and the key panel rect. With no `footer` injected it draws
none, so the provider stays usable alone.

Geometry gains a footer rect at the bottom of the canvas. `trimmedRowCount` subtracts its
height, the list clip stops above it, the companion pane keeps matching the canvas height, and
`_rowIndexAtPoint` excludes it. A press on the footer is claimed and never hides the list, a
press on (?) toggles the key panel.

The root wires `footer` once for the stage, resolving the showing context through
`stageModule:current()` as the stage panel does today, and asks the stage for the current
presentation's `labels`.

## What goes away

The docked shortcut pane in full, `shortcutsContent` and `shortcutPanelFor` in `lib/hints.lua`,
the `shortcutsPanel` policy in `root/compose.lua` and its commented seam in `config/settings.lua`
and `init.lua`, the panel triple `lib/services.lua` and `lib/wire.lua` earn per plugin and the
stage manifest's three optional values, and the stage's `_panelOnPositioned`, `_panelOnActivity`
and `_panelOnClose`. The stage still fans `onPositioned` out to the presentation's own hook, so
the clipboard, Local Servers, file search, speed test and settings panes keep docking. Nothing
stays behind drawing a second bar.

Tests and goldens move with it. `test/cases/surfaces.lua` and `test/cases/compose-shortcutdelay.lua`
lose the pane cases and gain footer model cases. `test/keymap-person.lua` reads the footer model
where it read `footerFor`. The inventory golden's `panelrows` and `hypercontexts` lines are
regenerated, and every changed line is explained by the primary and secondary joining the panel.

Docs move in the same change, the hint pane paragraphs in the hammerspoon `AGENTS.md`, the spoon
`AGENTS.md`, the per plugin `AGENTS.md` files that name the pane, `PLUGIN-AUTHORING.md`,
`PLUGIN-CONTRACT.md` and `DESIGN-UI-KIT.md`. Historical plans, briefs, reviews and audits are
left as written. `decisions/olm-chooser-keys.md` takes the decision and the rejections below.

## Rejected

A dropdown anchored to (?), since it is a new kind of component with its own scroll and key
handling, for a list of about a dozen keys. Turning the list itself into the key list the way
Actions does, since the person loses sight of the list they were in. A footer as a separate
docked `CanvasPanel`, since a press outside the chooser's canvas hides the chooser, so (?) would
need a second hit test across two surfaces, and one canvas draws both for free. Keeping the
pause before the footer shows, since what Return and Command and Return do is the thing worth
seeing before pressing either.

## Gates

`./src/check-dependencies.sh` and the dry gate clean, every offline suite under `test/` green,
the goldens regenerated with each changed line explained, one adversarial review, a live load
with a clean console, and Milos pressing Return, Command and Return, (?) and the action panel.
