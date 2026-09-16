# Ghostty

The terminal, and the one tool every other slot painter follows. The long form of how it came
to Aura on both halves is `decisions/ghostty-aura-theme.md`, and the palette it is painted from
is `theme/CLAUDE.md`. This file carries only what a change here needs to know.

## The theme, and how to reload it

Both files under `.config/ghostty/themes` are generated. `mdj-dark` and `mdj-light` are
written by `theme-emit` at this package root from `theme-map`, which names Ghostty's keys and
points each at a role, and `src/check-theme.sh` runs it. They are named for the half they fill
rather than for a palette, so the `theme` line in `config` never changes, and a light slot
holding a dark palette when `theme/active.toml` is held is not a file lying about its name.
Never edit them by hand. Change a colour in `theme/palettes`, a role in `theme-map`, run the
checker, and commit what it regenerated.

Ghostty reloads with `Cmd+Shift+,` and nothing outside Ghostty can send that reliably, so
after regenerating, press it. Once Ghostty repaints, every program drawing in palette slots
follows on its own, fzf, tmux, the Claude statusline and herdr, because none of
them carries a colour, only a slot number. That is why a wrong colour in one of those is
usually Ghostty not yet reloaded, and the record of that mistake is in the theme decisions.

`ghostty +validate-config` checks the config and exits nonzero on a key it does not know, and
it is worth running after a config edit, since a wrong name otherwise fails quietly at load.

## Slots 16 to 19 are declared here for other tools

Ghostty paints all 256 slots, and `theme-map` declares four beyond the sixteen, since no slot
among the sixteen is the same neutral on both halves. Slot 16 is the bar under a current row,
per half, `surface` on light and `dim` on dark. Slot 17 is the secondary grey, `overlay`. Slot
18 is the quiet rule, `dim`. Slot 19 is the page, `background`, for text painted onto a signal
colour. fzf, tmux and the Claude statusline read them and have no map of their own, so before
using one of those numbers anywhere, or claiming a fifth, read the comment above them in
`theme-map`, since every other slot is claimed by a role that differs by half.

## The neutral slots swap by half

ANSI black is the page on the dark half and the ink on the light one, and white the other way
round, which is what the `[dark]` and `[light]` sections in `theme-map` say. A script that
writes `black` or `white` expecting one of them is right on one half only. That is the defect
the tmux bar had, and the answer there was `default` or a declared slot.

## Repo only files

`theme-map`, `theme-emit` and `DEPENDENCIES` are listed in `.stow-local-ignore` and never reach
the home directory. The checker refuses one that is not listed. `config` is stowed to
`~/.config/ghostty/config` and the themes directory beside it.
