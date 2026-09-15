# One palette, every tool painted from it

Status. `theme/` is the source of colour, Ghostty, Neovim and herdr are generated from it,
iris, fzf, tmux and the Claude statusline still carry their own copies and are next.

## Now

`theme/palettes/aura.toml` holds Aura's nine published colours per half and a `[roles]` table
that says which colour answers each role in `theme/VOCABULARY`. A tool's package root carries a
`theme-map`, its own keys pointing at roles, and a `theme-emit` that knows its file syntax and
nothing else. `src/check-theme.sh` resolves the palette, resolves each map, runs each emitter,
and reports any generated file that came out different from what is on disk, regenerated and
named, the same way a stale `DEPENDENCIES` is. The generated files are committed, so a fresh
machine generates nothing.

`theme/active.toml` names a palette per half and a `mode` of system, dark or light. On a held
mode both halves are written from one palette's one half, so every tool keeps asking which half
it is on and both answers agree. No tool reads the word. Full contract in `theme/CLAUDE.md`.

The palette has one purple. The selection tint is `{ color = "purple", alpha = 0.14 }`, which
is purple composited at fourteen percent over the page and lands four units of green from
Aura's own published `accent38`. Alpha, mix, darken and lighten are one line of arithmetic.

Sixteen roles. herdr added `highlight`, the bar under a list's cursor, `subtext`, the ink
stepped back, and `fill`, the accent as a block under a label in the page colour. Each is a
rule over a named colour, so a different palette answers them by the same arithmetic.
herdr's emitter owns one span of a hand written config and copies the rest through, which is
the shape for any tool with no include.

## Rejected

**A Hammerspoon plugin watching the appearance and writing an fzf file, 2026-09-15.** Built,
gated, loaded, and reverted the same hour, before this design existed. Wrong layer, and it
should never have been offered. Recorded in `fzf-appearance-colour.md` and in the standing
rule in the repository `CLAUDE.md`.

**Slot numbers or tool names inside the palette, 2026-09-15.** The first draft of the palette
had `slot4` and `herdr_accent` as keys. Both make the palette know its consumers. A slot is
Ghostty's idea and belongs in Ghostty's map, and a tool's exception belongs in that tool's map
pointing at a role, so the palette never learns who paints with it.

**Roles as hue names in the vocabulary, 2026-09-15.** `purple` as a role forces every future
palette to own a purple. The vocabulary names ranks instead, `primary` through `senary`, which
are Aura's own words for its table, and the palette says which hue is which.

**Two or three purples in the palette, 2026-09-15.** Aura's table lists `accent20`, a dark
purple at 50% alpha, and `accent38`, the same thing composited onto the page. Carrying either
as a colour made the palette hold what is really a rule. Measured, `accent38` is `accent20`
composited to within a rounding step, and neither is `accent1` faded, the closest fade is 29%
and misses by seven. Nothing here blends a terminal cell, so the palette carries one purple and
the tint is a rule over it.

**Ghostty's own `selection-background` as the tint, 2026-09-15.** It is a different colour on
the light half, `#dfdaf2` carrying the page's lilac where herdr's near neutral grey was the one
actually wanted. The palette answers `selection` by rule instead, and herdr's map can point
elsewhere when it joins.

**Python for the reader, 2026-09-15.** `tomllib` would be a real parser. The system Python on
this Mac is 3.9.6 and has no `tomllib`, so it would mean a Homebrew Python as a dependency of
checking colours, which is the one check that has to run before Homebrew has. The reader is
awk over a documented subset and refuses a line outside it.

**Every value as a literal, no rules, 2026-09-15.** Offered as the smaller first build.
Turned down because the selection tint had to be derived from the one purple on day one, and
because herdr's light ramp is a hand computed derivation whose method lived only in prose.

**Generating herdr's tables in this pass, 2026-09-15.** herdr has no include, so its two
theme tables have to be rewritten inside a hand written config between `[theme.custom.dark]`
and `[keys]`. Deferred to the next pass rather than rushed, since it is the one emitter that
edits a file it does not own outright. Done in that next pass, 2026-09-15 17:15, see the log.

**One `selection` role for both a selected span and a list's cursor row, 2026-09-15 17:05.**
The vocabulary's sentence covered both, and the values did not. herdr, iris and fzf all want a
bar found at a glance, purple at 0.26 on dark and a neutral grey on light, where a span in
Ghostty or Neovim only has to be seen and sits at purple 0.14 and 0.20. Folding them either
way moved tools that were right. `highlight` is the second role, and it is neutral on the light
half by rule for the same reason herdr's light surfaces are, a tinted bar on the light page is
a lilac slab.

**`primary` as herdr's light accent, 2026-09-15 17:05.** `#7e54d1` reads 4.83 to 1 against the
light page, solved for a letter. herdr paints a label in the page colour on that fill, and a
block wants more room, which is why its hand picked `#5e36ee` read 6.08. `fill` is the role,
answered by `primary` on dark and `{ color = "purple", darken = 0.15 }` on light at 6.21. The
hand picked value was more saturated rather than darker, so no rule reproduces it and the
darken lands nearest.

**`foreground` or `overlay` for herdr's unselected row label, 2026-09-15 17:05.** The dark
value `#cdccce` is the ink at 0.85 over the page to the unit, and iris's secondary text reads
the same value, so it is a real step on the ladder between the ink and `overlay` rather than
either neighbour. `subtext` is the role, 0.85 on dark and 0.88 on light by the usual light ramp
reason, and the light value moves from a neutral `#5c5c5f` to `#5c5a6a`, a cast nothing sees.

## Log

**2026-09-15 15:20, estimated from the conversation, anchored to the 16:06 commit that preceded the build.** Asked for one place to change a colour and have every tool follow, on
any machine. Inventory found the same Aura numbers in seven places, four of them documented as
hand copies. Ghostty and herdr agreed value for value on the dark half and diverged on the
light accent on purpose, `#7e54d1` against `#5e36ee`, because herdr paints a label in
`panel_bg` on that fill. That divergence is what settled roles over flat values.

**2026-09-15 15:50, estimated the same way.** The design was corrected twice by Milos and both corrections are the
Rejected entries above. The palette must not know slots or tools, and it must hold one purple
with the rest derived. Alpha over the page and mixing are the same arithmetic, so the checker
has one blend function.

**2026-09-15 16:12, from the emitters' file timestamps.** Built. `theme/VOCABULARY` with thirteen required roles,
`theme/palettes/aura.toml`, `theme/active.toml` on system, `src/check-theme.sh`, and maps and
emitters for Ghostty and Neovim. Every one of the nine base colours came out bit identical to
the hand written files on both halves in both tools. The derived roles moved by a few units.
Neovim's dark selection moved from `#3d375e` to `#29223b`, which is the fix, since the old
value was Aura's alpha form with the alpha cut off, painted solid. Ghostty's dark slot 0 moved
from `#110f18` to the page `#15141b`, and light slot 15 from `#eeedf0` to `#e8e7ec`, both
neutrals nothing distinguishes by eye.

**2026-09-15 16:15.** `aura-light` and `aura-dark` under Ghostty's themes are deleted and the
config reads `light:mdj-light,dark:mdj-dark`, named for the half rather than the palette so the
line never changes. `setup.sh` runs `check-theme.sh` beside `check-dependencies.sh`. Restowed.
Ghostty was not frontmost so its reload keystroke was not sent, it needs `Cmd+Shift+,`.

**2026-09-15 16:50.** herdr's `CLAUDE.md` was found to carry four sections three times over,
`Do not walk the home directory`, `Current keys`, `A palette edit needs the server restarted`
and `The one colour the exported palette cannot hold`, and the middle copy of the last one
describes the FzfTheme plugin that was reverted. The first and third copies agree. To be folded
to one copy in the same change that adds herdr's reload step for a theme.

**2026-09-15 17:00.** herdr's emitter is built and tested in a clone before any colour was
decided, since it depends on none. It owns the span from the `[theme.custom.dark]` header up to
the `[keys]` header and copies every other byte through, refuses when either header is missing
or out of order, and writes its banner as the first lines inside the dark table because the top
of the file is hand written. That moved the checker's banner rule from the first three lines to
anywhere in the file, since a file written whole still opens with it and a file owned in part
carries it where a person editing that part would look. The tamper test also showed the checker
printing "every generated theme is current" after an emitter had failed, because only the stale
and unchecked counts gated that line, so a failed count now gates it too. Keys come out in
alphabetical order rather than herdr's grouped order, because the order is the map's business
and the resolved map arrives sorted.

**2026-09-15 17:05.** The colour decisions were brought with measurements rather than picked,
and Milos asked what they would cost if the base colours ever changed, then said proceed with
the recommended set. Nothing overrides an Aura colour. Every new role is a rule over a named
colour, and the one palette value retuned is the dark half's `dim`, a derived neutral nothing
painted with yet, moved from ink at 0.28 to 0.11 so it lands on herdr's dark border `#2d2d2d`,
which makes `surface_dim` take `dim` without moving. The light border moves from `#bdbdc3` to
`#c6c5cd`, 0.33 to 0.28, a hair lighter. `overlay1` on dark moves from `#97949f` to `overlay`,
one step lighter for the plus sign and a renamed unfocused tab, and the light half already had
the pair equal. `active_row_bg` takes `selection` on dark and `surface` on light, the light one
exact and the dark one from purple 0.17 to 0.14, since herdr lifts rows in purple on dark and in
neutral on light by its own recorded decision and the map's half sections exist for that.

**2026-09-15 17:08.** The checker's `darken` and `lighten` branch was unreachable. The alpha
branch was tested first on `color` being present, and a darken rule also names `color`, so
`{ color = "purple", darken = 0.15 }` would have been read as alpha with no amount. Found the
moment the first darken rule was written, which is the argument for a role being answered by
rule on day one rather than by a literal. The order is fixed and an alpha rule with no amount is
now an error rather than a blend by an empty string.

**2026-09-15 17:15.** herdr is painted from the palette. Sixteen roles, the three new ones
answered in `aura.toml` under `[roles]` and `[roles.light]`, and a `[roles.dark]` section for
`dim`. The regenerated tables moved exactly what the decisions above say and nothing else, dark
`subtext0` and light `selection_bg` and light `active_row_bg` came out identical to the hand
written values. Ghostty and Neovim were untouched by the new roles. The hand written `[theme]`
comment in herdr's config lost its derivation prose, which the palette now carries, and gained
a pointer at the generated tables. `check-dependencies.sh` passed, herdr restowed, the map and
the emitter stayed out of the home directory, `herdr server reload-config` applied with no
diagnostics. The theme is client local and waits on a detach and reattach. herdr's `CLAUDE.md`
folded to one copy of each section, lost the stale `aura-light` Ghostty theme names, and gained
the theme section with the reload step.

**2026-09-15 18:24.** Reattached and confirmed by eye, herdr looks right on the generated
tables.
