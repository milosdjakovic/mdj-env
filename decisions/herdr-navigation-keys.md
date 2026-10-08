# Herdr navigation keys, agents and back and forth

Status. The flat agent picker on `prefix+a` is gone, the palette's agent rows replaced it, `prefix+t` is `last_pane`, `prefix+alt+1..9` is `focus_agent`.

## Now

The flat list of agents is the first section of the palette on `prefix+space`, each row its
state, its terminal title and its space and tab, and enter focuses it.
`decisions/herdr-palette.md` has the palette. `prefix+a` is unbound. The built in `goto` stays
on `prefix+g` for the whole tree.

`last_pane` is on `prefix+t`, t for last, and it crosses tabs and spaces, so it is also the
last tab and the last space. herdr 0.9.0 has no separate last tab or last workspace action.
`focus_agent` is on `prefix+alt+1..9`.

## Rejected

**Built in `goto` for jumping to agents, 2026-09-27.** It nests spaces, tabs and panes, and the pane
level is one nobody picks an agent by. Its footer offers `filter a/b/w/i/d`, which reads as a
state filter, but it filters inside the tree rather than flattening it.

**`prefix+l` for last pane, 2026-09-27.** Taken by the built in `focus_pane_right`.

**`prefix+tab` for last pane, 2026-09-27.** herdr's own suggestion, and taken by `cycle_pane_next`.

**`prefix+D` for last pane, 2026-09-27.** That is `prefix+shift+d`, the built in `close_workspace`,
so a slip closes a space.

## Log

**2026-09-27 17:28.** `prefix+alt+1..9` did nothing, and the reason was that `focus_agent` is unset by
default in 0.9.0, not a terminal or key encoding problem. Bound it, bound `last_pane` to
`prefix+a`, and replaced `goto` on `prefix+g` with the flat agent picker. Reload reported
applied with no diagnostics, so none of the three keys collides with a built in.

**2026-09-27 17:57.** Rearranged on request the same day. `goto` is back on `prefix+g`, since the tree is
still wanted beside the flat list, the agent picker moved to `prefix+a`, and `last_pane` moved
to `prefix+t`. Reload reported applied with no diagnostics.

**2026-10-08 17:37.** `prefix+a` and `tools/agents.sh` removed on request. The palette on
`prefix+space` lists the same agents first, from the same snapshot, so the picker had become a
second copy of its first section. The glyph file it shared with the palette went with it,
folded back into the palette, its only reader.

