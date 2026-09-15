# One palette, every tool painted from it

Status. `theme/` is the source of colour, Ghostty and Neovim are generated from it, herdr,
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
edits a file it does not own outright.

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
