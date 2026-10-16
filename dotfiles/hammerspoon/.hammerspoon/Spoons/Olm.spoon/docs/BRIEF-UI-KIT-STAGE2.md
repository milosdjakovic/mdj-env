# UI kit stage two, the shared surfaces draw through the kit

Read docs/DESIGN-UI-KIT.md, then lib/ui/ as built in stage one, then this. Work only in the
worktree this file is in.

## The rule of this stage

Nothing a person can see changes. Every surface below must draw the same pixels it drew
before, same fonts, sizes, colours, spacing and placement. Where today's value and a token
disagree, change the token or add a variant so the token equals today's value, and say so in
your report. The look changes in stage three, never here.

## Move these onto the kit

1. lib/panel.lua `emptyStateElements` draws through `ui.text` in the dim variant, centred.
   Keep its signature, since four plugins call it as `opts.emptyState`. The docked pane in lib/dockedpane.lua replaced that grant on 2026-10-16.
2. lib/hints.lua, the docked shortcut bar, the message toast, the colour toast and the list
   toast. The bar is a `flow` of rows of badges and labels. The hint badge today uses the ui
   font at 11, not mono, so the hint badge geometry in style.lua must say ui 11. The colour
   swatch and the dismiss chip may stay bespoke inside hints.lua if no primitive fits, but
   they read their colours, radii and sizes from tokens.
3. lib/cheatsheet.lua, the grid of sections with key badges, optional icons and labels, the
   section titles and the dormant fade, through `grid`, `badge`, `icon`, `text` and `group`.
4. The canvas provider. field/render.lua and list/render.lua stay bespoke renderers, as the
   design says, but read every font, size, colour, alpha and spacing from the tokens the
   provider hands them rather than from their own literals or from chooserTheme. The three
   disagreeing layout tables, geometry.lua, list/render.lua and native.lua, become one source
   for the canvas side, with native keeping its own because the OS draws it. geometry.lua's
   values are the ones the canvas provider uses today, so those win.
5. Every light and dark pick in these files goes through `ui.tokens()`, so
   `hs.host.interfaceStyle` is asked only inside lib/ui/style.lua among the files you touch.

Do not touch any plugin under plugins/. Do not remove lib/chooser/textwidth.lua if something
outside your scope still uses it, list its remaining callers instead.

## Proof of parity

For each surface write a small probe under Spoons/Olm.spoon/test/ that builds the surface's
elements for a fixed model through both the old code at the commit before this stage and the
new code, and compares fonts, sizes, colours and frames element by element, reporting every
difference. You cannot load the old code live, so load the old file contents from
`git show HEAD:<path>` into a temporary file in the scratch area and dofile both. Run these
through the `hs` CLI against the running instance with dofile, never reloading. Report the
differences found and fixed, and any that remain with the reason.

## Acceptance

- Every parity probe reports no difference, or each remaining one is listed with a reason.
- `./test/units.sh` keeps every existing assertion with only the known actionpanel failure.
- `luac -p` clean on every file touched, `src/check-dependencies.sh` and `src/check-theme.sh`
  report nothing new.
- Do not reload Hammerspoon, take the devlock, drive the screen or commit.

## Writing style, a hard requirement

Comments in plain sentences with only periods and commas. No dashes of any kind, no colons
or semicolons in prose. Match the comment density of the surrounding code.
