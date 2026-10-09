# Herdr command palette

Status. `prefix+space` opens `tools/palette.sh`, a palette written here, after four published ones were compared and none installed.

## Now

The palette is a popup in the `mdj-tools` plugin. It lists every agent, space, tab, pane and
session, every herdr action with the key that does the same thing, every custom command in
`config.toml` and every action another plugin offers, in that order, and enter does the
chosen thing. The rows are read from one `herdr api snapshot`, so they cannot disagree with
each other.

The actions are data. `tools/palette-actions` holds one line per action, its herdr name, a
group, a mode and the herdr command it runs, and the engine names no action. The modes are run,
ask for one line of text, confirm, step to the next or previous one, and key, for the actions
herdr only does from inside its own window, where enter says which key to press. A key row is
left out while its key is unbound.

Opening it takes about 55 ms warm, measured with fzf stubbed out.

## Rejected

**fabiogaliano/herdr-command-palette, 2026-10-08.** The closest fit and the one recommended
before building was chosen. It lists live agents, spaces, tabs and sessions beside the actions,
in fzf. Turned down because it paints rows from herdr's theme rather than the fzfrc slots every
other picker here uses, it is a single 44 KB Python file from one author, and it passes a
`--json` flag to `herdr plugin action list` that herdr 0.9.3 rejects with exit 2, so other
plugins' actions never appear. Checked on this machine.

**ramarivera/herdr-palette, 2026-10-08.** The best interface on paper, a Rust TUI with a tree
and a flat list and ranked fuzzy matching. Turned down because a GitHub install points the pane
at a relative binary path and fails to open, reported in its issues 4, 15 and 16, with the fix
pull requests unmerged and no commit on main since 2026-07-09.

**cesarferreira/herdr-palette, 2026-10-08.** Actions only, no agent, tab or space rows, and its
matching is plain substring with no ranking. It also carries no license.

**haisi/herdr-plugin-command-palette, 2026-10-08.** Keybindings only, three commits in one day.

**Borrowing tuios's palette, 2026-10-08.** It is compiled into tuios's own Go program, so
there is nothing to borrow but the design. What was taken is the group as a quiet column that
also narrows when typed, the key shown on every row, rows left out when they cannot apply, and
an order that never shuffles between keystrokes.

**The group column naming what an action acts on, 2026-10-08.** Rename tab sat in a tab
column and Close space in a space column, which read as the row being that tab or that space.
Every row that does something is grouped as a command now, and only the rows that are a thing
keep agent, space, tab or session.

**One group for every pane, agent or not, 2026-10-09.** Two named panes in one tab read
`agent` and `pane`, which looked inconsistent. Turned down because the group is what tells a
row with a state and a place in the want order from one without, and listing every pane as a
pane would lose the ordering that answers which agent needs you. The layout was made the same
instead.

**A pane's name in place of the agent's topic, 2026-10-09.** Built that way first and undone
the same day, since it dropped the conversation topic from the row and from search.

**Group headings in the list, 2026-10-08.** tuios shows headings while nothing is typed and
drops them once a query ranks the list. fzf cannot hide a row by query, and a heading left in
a ranked list splits it into runs. The quiet first column carries the group instead.

**Opening another popup from inside the palette, 2026-10-08.** herdr shows one popup at a
time. A custom command or a plugin action may open one, so both start detached and wait 0.3
seconds for the palette to close. Verified with a command that writes a file, not yet with one
that opens a popup. Corrected 2026-10-08, see below.

## Log

**2026-10-08 10:52.** Built after comparing the four published palettes and tuios. Every
dispatch was run against a headless named session, `palettetest`, never the live one,
renaming with spaces in the name, new tab, close tab after a confirm, next and previous with
wrap at both ends, split, zoom, focus by row, a failing worktree open that reported herdr's own
error message as a notification, the key hint for help, and both session cases. The text
prompt was driven through a pty, enter returns the text with status 0 and escape returns 130.
The binding on `prefix+space` it replaced pointed at `alonz.command-palette`, a plugin that
was never installed, so the key had been dead. The agent state glyphs moved into
`tools/status.sh`, shared with `tools/agents.sh`.

**2026-10-08 15:43.** The fuzzy search did not open when picked from the palette, on the first
live try. A probe plugin linked into a headless named session showed why. A second popup open
while one is showing fails with `ui_busy`, which the delay was for, but the detached child never
ran its first line, because closing a popup ends its whole process group and `nohup` only
survives a hangup. `launch` now switches on job control around the one background start, so the
child gets a process group of its own, and the same probe then opened the fuzzy search after
0.3 seconds. The same change grouped every runnable row as a command, on request, and dropped
the group column from `palette-actions`, which nothing read any more.

**2026-10-08 17:37.** `tools/agents.sh` and its key were removed, so `tools/status.sh` had one
reader left and was folded back into `palette.sh`.

**2026-10-08 17:42.** Two of the gaps listed after the first commit closed on request. Panes
without an agent are rows now, titled by the command they run or by their path when the title
is a shell prompt, with a path cut from the left so its last folder shows. herdr 0.9.3 has no
focus by pane id, only `pane focus --direction` from a given pane, so a pane row focuses the
tab and then steps once from whichever pane `pane neighbor` reports the target beside. Open
worktree lists the worktrees from `herdr worktree list` through a `{worktree}` placeholder
instead of asking for a branch. Both were run against a headless named session, a three pane
tab reached at each pane, and a scratch repository whose second worktree opened as its own
space.


**2026-10-08 20:46.** Rows were two columns wider than the list, so fzf drew two dots over
the group of a pane row it scrolled sideways to show a match and over the space of a tab row it cut at the
end, and a search for shell read as the same two results twice. The width now leaves eight
columns rather than four, and `--no-hscroll` keeps the left edge in place.

**2026-10-09 10:03.** Agents ordered blocked, done, working, idle, with the state as searchable text beside
the title, the last five picks first with the current place skipped, a here marker on the row
the palette was opened over, a single pane tab listed once as the tab with its pane's path,
and rename prompts that start from the current name through a `{label}` placeholder. The
title now leaves room for its detail, since a long agent title had pushed the state word out
of sight and out of reach of the search. Run against a headless named session with reported
agent states, and the recent file removed afterwards so no test ids were left in it.

**2026-10-09 11:12.** Panes are searched by the name you give them, and renaming one starts from that name.
The earlier entries treated a pane as having no name because the snapshot keys of every pane
on this machine had no `label`. herdr adds the field only once a pane is renamed, which a
rename in a headless named session showed in the snapshot, `pane get` and `pane list` alike.

**2026-10-09 12:20.** Rows that stand for a pane share one layout, the name, then what it is doing, then the
state word in its own column, then where it is. A named agent shows its name and keeps its
topic beside it rather than losing it. A location too long for its column is cut from the left
so the tab and here survive.

