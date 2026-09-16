# Iris

Running. It was disabled for half a day on 2026-09-16 so the herdr agents panel could see
sessions, and came back the same day. `decisions/shell-autocomplete.md` has both routes.

The long form, why iris is built from a fork, its two patches, the keys it claims before the
shell sees them, and the appearance detection, is the Iris section of the repository
`CLAUDE.md`. This file carries only what a change here needs to know.

## The theme, and how to reload it

`theme.toml` is two things in one file. Everything drawn on the page is an ANSI slot written
by hand, `"4"` for the primary accent and `"8"` for the comment grey, because a slot follows
whatever the terminal is painting and Ghostty is painted from the same palette. The `[dark]`
and `[light]` tables at the bottom are generated and must not be edited by hand. They hold
the four keys of the selected row, which a slot cannot carry because a bar has to be a tint
of the page and no slot is dark on one half and light on the other. `theme-map` at this
package root says which key takes which role and why, `theme-emit` beside it rewrites the
span from the `[dark]` header to the end of the file and copies everything above it through.
Run `src/check-theme.sh` after changing a colour or a role, review the regenerated tables,
and commit them. `theme/CLAUDE.md` has the whole contract.

iris reads `theme.toml` once, when it starts, and there is no reload command. A new shell is
the test, so open a new pane after regenerating and look at the selected row there. A pane
that was already open keeps the old tables until its shell is replaced.

The two tables need the fork. Stock iris has one flat set of keys and no idea what the
terminal is painting, and `src/build-iris.sh` is where that patch is pinned.
