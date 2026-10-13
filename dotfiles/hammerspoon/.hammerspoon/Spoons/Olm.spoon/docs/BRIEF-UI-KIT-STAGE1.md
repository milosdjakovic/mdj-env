# UI kit stage one, the four units, wired and offered, drawing nothing yet

Read docs/DESIGN-UI-KIT.md first, it is the design and this brief does not repeat it. Then
read docs/PLUGIN-CONTRACT.md on `needs.lib`, lib/services.lua and lib/wire.lua for how a
lib capability is delivered, root/compose.lua around the CanvasPanel and chooser configure
calls, lib/panel.lua, lib/chooser/textwidth.lua and lib/glyphicon.lua. Work only in the
worktree this file is in.

## Build

`lib/ui/style.lua`, `lib/ui/measure.lua`, `lib/ui/kit.lua`, `lib/ui/layout.lua`, and a
small `lib/ui/init.lua` that is the one table a plugin receives, the primitives, `layout`,
`tokens()` answering the current half, and `measure`.

`style.lua` and `kit.lua` must load in plain Lua with no `hs`. `measure.lua` and
`layout.lua` may use `hs.styledtext` and `hs.drawing`, since the unit cases run inside
Hammerspoon through test/units.sh.

`icon` with a glyph draws to an `hs.image` through the same approach as lib/glyphicon.lua,
cached by glyph and size. Do not change lib/glyphicon.lua or any plugin copy in this stage.

## The style spec values, which must equal today's

The spec built in compose from policy must answer these so stage two changes nothing a person
can see. Where settings supplies a value, read it from policy rather than copying it.

- colors. foreground is chooserTheme titleColor, subtext is subColor, dim is subtext at the
  dim alpha, background and border are settings.surface bg and border, surface is the same
  as background for now, badge is white 1 at alpha 0.12 on dark and white 0 at 0.06 on light,
  selection is foreground at alpha 0.20, highlight is foreground at alpha 0.14, overlay, path
  and note are chooserTheme preview meta, path and note, accent is preview fg.
- fonts. ui is ".AppleSystemUIFont", mono is "Menlo".
- text. title ui 16, body ui 14, sub ui 12, label mono 11, heading ui 16 in subtext, mono
  mono 12, big mono 20. Line height is one rule, ceil(size times 1.35), unless a variant
  states its own.
- space. xs 2, s 6, m 10, l 14, xl 20.
- radius. surface from settings.surface cornerRadius, badge from cheatSheet badgeRadius, chip 6.
- alpha. dim 0.4 as a multiplier, fade 0.55.
- icon. row 28, list 28, sheet 32.

Where these disagree with a literal somewhere in the tree, the tree is wrong and stage two
fixes it. Record any value you had to choose in a comment in style.lua saying why.

## Wire

compose builds the spec and configures style once, beside `canvasPanel.configure`. The kit is
delivered through `needs.lib` under the name `ui`, the same way `glyphicon` and `cheatsheet`
are, so a plugin writes `needs = { lib = { ui = { from = "ui" } } }`. Add it to
docs/PLUGIN-CONTRACT.md where the other lib capabilities are listed, and add a short
"Drawing with the kit" section to docs/PLUGIN-AUTHORING.md with one small worked example of a
pane drawing a heading, a row of label and value, and a dim note through `ui.layout`.

## Tests

New unit cases under dotfiles/hammerspoon/.hammerspoon/test/cases/, at least these.
style resolves the right half for a stubbed appearance and falls back to dark when light is
absent. Every primitive builds a node of the right kind and refuses an unknown variant with a
message naming it. layout of a stack of texts answers elements in order with the summed
height, a flow wraps at the rect width, a group multiplies child alpha, scrollY offsets every
element and the clip is opened and closed exactly once, an id reaches trackMouseUp, and the
content height is returned.

## Acceptance

- `./test/units.sh` keeps every existing assertion with only the known actionpanel failure,
  plus your new cases passing.
- `luac -p` clean on every file touched, `src/check-dependencies.sh` and
  `src/check-theme.sh` from the worktree root report nothing new.
- Do not reload Hammerspoon, take the devlock, drive the screen or commit.

## Writing style, a hard requirement

Comments in plain sentences with only periods and commas. No dashes of any kind, no colons
or semicolons in prose. Match the comment density of the surrounding code.
