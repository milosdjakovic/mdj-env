# Iris appearance aware theme

Status. Working on the fork branch `feat/appearance-aware-theme`, built into the pinned binary.
Four measurement mistakes on the way, each recorded.

## Now

`theme.toml` takes optional `[dark]` and `[light]` tables over its flat keys, and iris asks the
terminal which it is in. Almost every value is an ANSI palette slot rather than a hex colour, so
Ghostty stays the one owner of the palette and a theme change repaints the menu with no edit
here. The `[dark]` and `[light]` tables exist for the selection bar and almost nothing else,
because a bar has to be a tint of the page under it and no slot is dark on one palette and
light on the other.

The appearance is asked once by OSC 11 in the watchdog, and after that the terminal reports
changes itself through DEC private mode 2031. The report arrives on the input stream and is
stripped before the shell sees it, whole sequences only, since holding back a partial escape
would delay the arrow keys. A switch reloads the half and redraws the box directly, bypassing
the render path that declines during navigation.

Full reasoning is in the root CLAUDE.md under Iris, The theme.

## Rejected

- **A fixed hex selection bar with a fixed `match`.** 2026-09-14, before b74c212. Only clears a
  bar that is very dark or nearly white, since `match` is drawn on the page on every other row
  and inside the bar on this one.
- **An inherited bar with inherited `match`.** 2026-09-14, before b74c212. Then the bar must be
  dark enough for the dark half's `#ffca85` and light enough for the light half's `#6b4400` at
  once, which lands at 2.05 on slot 8, 1.08 on slot 4 and 1.27 on slot 7. Measured, every single
  file alternative. There is no single bar, which is why the feature exists.
- **Treating `IRIS_TERM_BACKGROUND` as an override.** 2026-09-14, before b74c212. It reaches the
  shell too, so an iris started from that shell inherits it, and a decision about an earlier
  terminal outlived it and beat the one in front of you. Rewritten on every start now, a hand
  set value surviving only when the terminal declines to answer.

## Log

### 2026-09-14, before 14:02

While building. An earlier version of the theme notes claimed palette slots did not work, on the
strength of a detector that matched only `38;2` and `38;5` sequences and never the `30` to `37`
range, so it reported zero colours while the menu was drawing in palette colours the whole
time. A detector that can only see one encoding reports the absence of every other one. That
mistake cost several rounds. Slots work because lipgloss turns `"4"` into `ansi.BasicColor(4)`
at `color.go:66-85`.

### 2026-09-14, before 14:02

While building. The OSC 11 query paired the input tty with `os.Stdout`, and lipgloss refuses
unless both are terminals, which the watchdog's stdout is not always. Invisible, because
`HasDarkBackground` answers true for any error, so a query that never worked read as a terminal
that said dark. Asking through the tty iris already holds, via `BackgroundColor` so a failure
stays distinguishable from an answer, fixed it.

### 2026-09-14 14:02

b74c212. Iris arrives from the fork with this branch merged.

### 2026-09-14 14:12

50a17d5. Switching appearance with the menu open updated everything except the selection bar,
and closing and reopening the menu put it right. The terminal repaints its own palette, so
every slot coloured part followed the switch without iris doing anything, which made the switch
look like it worked. The bar is hex, so it stayed in the old appearance until something drew
the box again and nothing did. The half was reloading correctly the whole time and only the
repaint was missing. The pin moves to a fork that redraws the box on a switch, directly, since
the usual render path declines while the user is navigating, the moment a stale bar shows most.
