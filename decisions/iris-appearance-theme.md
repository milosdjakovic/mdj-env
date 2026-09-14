# Iris appearance aware theme

Status. Working on the fork branch `feat/appearance-aware-theme`, built into the pinned binary.
Four measurement mistakes on the way, each recorded, and one regression it caused in every
layer above it, fixed 2026-09-15 by relaying the report to a child that asked for it.

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

The report is also relayed to the program behind iris when that program has asked for it,
read off its output as the same `2031` switch iris sends, with the request cleared at every new
prompt. Iris keeps the terminal's copy of the mode on regardless and answers a child's
withdrawal by turning it back on. Without the relay, herdr behind iris never heard a switch, and
everything inside herdr asks herdr, so Neovim, Claude Code and the iris in every pane were stuck
with it while the outer iris alone followed.

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
- **Swallowing the appearance report outright.** 2026-09-14 c3be08d, found wrong 2026-09-15
  01:20. Right for the shell, which would print it, and wrong for every program behind iris that
  asked for the same report, since the terminal sends one copy. Replaced by relaying to a child
  that has asked.
- **Relaying the report whenever a command is running.** 2026-09-15 about 01:45, not built. A
  program that reads no input, `sleep` say, leaves the bytes in the tty buffer for the shell to
  read at the next prompt, which is the original defect back again. The child's own `2031`
  request is the only reliable signal that it will consume the report.
- **Probing iris by launching a second iris from inside an iris session.** 2026-09-15 01:27. The
  probe inherited this pane's six `IRIS_` variables, the new iris took the launch for a reload
  and reloaded the real iris under the pane, and Ghostty's mouse reporting was still on, so the
  pane filled with SGR mouse events as text. Never launch iris from a shell that is behind iris
  without scrubbing its environment. The screenshot of the stuck stack and a herdr started with
  no iris anywhere were the decisive evidence instead, and cost nothing.

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

### 2026-09-15 about 01:05

Milos reports automatic switching regressed in herdr, Neovim, Claude Code and the iris menu bar,
a day after all of them were proven. Read every decisions file first, then traced the live
process chain, Ghostty, iris, zsh, herdr, then per pane iris, zsh, nvim or claude. Read
`root/wrapper.go` on the fork. The strip of `CSI ? 997 ; n` runs before the executing check and
forwards nothing, so herdr behind the outer iris never hears a switch. The herdr binary's
strings confirm it depends on that report, `[?2031h`, `[?997;1n`, a per pane
`color_scheme_reporting` flag, a `HostPaletteColors` cache and OSC 11 answers to panes from it.
Neovim polls OSC 11 and is answered from that stale cache. Claude Code is on `theme = "auto"`,
sends OSC 11 once and listens for the report, both through herdr. The inner iris does the same.
One eaten report, five symptoms. Startup still detects correctly because herdr's own OSC 11
query at launch passes through iris while a command is executing, which is why it looked like
it worked and then drifted.

### 2026-09-15 01:27

The pty probe misfired and reloaded the real iris under this pane, see Rejected. Stopped
probing. Milos's screenshot at 01:28 showed the predicted shape, a dark herdr sidebar over a
light pane.

### 2026-09-15 about 01:35

Milos ran the distinguishing tests. `herdr server reload-config` applied and changed nothing,
expected, since it reapplies config to the appearance herdr last heard. `herdr --session probe`
opened light and stayed light through a switch to dark, with pane backgrounds going dark, since
those are Ghostty's palette slots repainting through herdr, while the tab bar, the new tab
modal, the iris bar and Neovim stayed light, every one of them drawn from a remembered half.
Then a fresh Ghostty instance with `IRIS_RESCUE=1` and herdr directly on the terminal followed
every switch. The first attempt at that was refused as nested herdr, because `open` carried the
launching pane's `HERDR_` variables into the new instance, and unsetting them fixed it. Iris
alone switches, herdr alone switches, iris above herdr does not. Cause confirmed.

### 2026-09-15 01:51

144c2de on the fork's `feat/appearance-aware-theme`, merged as b8b7ac8, pin moved and built.
The wrapper scans the child's output for its own `2031` switch with a carry across reads, the
same shape as the alternate screen scan, relays each report verbatim while the child has asked,
re-asserts the mode after a child withdraws it, and clears the request at every new prompt.
`stripThemeNotifications` hands back the removed sequences rather than a verdict. Unit tests
cover the strip, the last report winning, the scan across a split read, and the carry length.
Live confirmation from Milos is owed, a new Ghostty window so the outer iris is the new binary,
herdr inside it, switch each way.

### 2026-09-15 01:56

Confirmed by Milos in ordinary use. A new Ghostty window, so the outer iris is the new binary,
herdr inside it, appearance switched each way. Everything followed. The status line, the herdr
theme and the Neovim theme were never wrong, each of them was answered by a herdr that could not
hear, and the fix touched nothing but the layer that was eating the report.

### 2026-09-15 01:57

Committed locally as 48ed0c4 and deliberately not pushed, on Milos's instruction. The fork
branches are on GitHub already, since the build script pulls from there, so another machine
running setup gets the new binary only once this repository's pin lands upstream too. Two things
to remember until then. A window or pane opened before the rebuild keeps the old iris until its
shell restarts, so a stuck surface in an old pane is not a regression, and only new windows and
new panes prove anything. And the pin move and the fork are two pushes, not one, so pushing the
fork alone leaves a second machine building the old commit.
