# Herdr agents sidebar

Status. An agent row reads space and tab, then pane and agent, each name shown only once it was
set, and a Claude agent goes by its session name, reported by the status line.

## Now

`ui.sidebar.agents.rows` is two lines. The first is `state_icon, machine, workspace, tab`, and
the tab entry hides any label that reads as a number, since an unnamed tab keeps the number herdr
proposed as its label. The second is `pane, agent`, and herdr reports a pane label only once the
pane is named. Claude Code hands its status line command `session_name`, the `/rename` name or,
without one, the title it generated, and `statusline-command.sh` reports it to `HERDR_PANE_ID`
as the display agent with `herdr pane report-metadata --source claude-statusline`, clearing it
when there is none, so the `agent` token falls back to claude. Metadata is display only. It left
`agent_status` following the session when probed, unlike the hook `iris.md` records.

## Rejected

- **`terminal_title_stripped` as the session name.** 2026-10-27 13:40. Free, since Claude writes
  its AI generated title into the terminal title and herdr reads it, but that is the topic Claude
  picks, not the name `/rename` sets, which is what was asked for.
- **Reading the `custom-title` entry from the transcript.** 2026-10-27 13:55. `/rename` appends
  it to the session file, but the status line JSON already carries `session_name`, so reading the
  transcript would be a second source of the same value and a file walk on every refresh.
- **A `$session` token on a Claude only layout.** 2026-10-27 14:02 to about 14:10. Built first, under
  `rows_by_agent.claude`. A row cannot fall back from one token to another, so an unnamed
  session lost its second line instead of saying claude. `--display-agent` replaces the name the
  `agent` token shows and falls back by itself, which needs no override at all.
- **A different separator between row values.** 2026-10-27 14:15. herdr 0.9.5 joins adjacent
  values with ` · ` and has no setting for it in the sidebar. The only separator key is
  `ui.tab_bar_right_separator`, which is the tab bar's, and token styles leave separators alone.
  Recheck the config reference after an upgrade.
- **Hiding the tab when it repeats the space name.** 2026-10-27 13:45. Not expressible. A row
  rule compares a token with a literal, never with another token.

## Log

### 2026-10-27 14:02

Found `session_name` in the status line payload by reading the Claude Code 2.1.311 bundle, set
only when the session has a name. Probed `report-metadata` on a live Claude pane, the token
appeared under `tokens`, `agent_status` stayed `working`, and the call took 0.12 seconds, so the
status line runs it detached. Ran the script with and without a name and saw the token set and
cleared. `herdr config check` and `reload-config` reported no diagnostics for the numeric tab
rule. The rule's effect on screen was not yet seen when this was written.

### 2026-10-27 about 14:10

Replaced the `$session` token with `--display-agent`, after Milos asked for claude to show when a
session has no name. Probed on a live pane, `display_agent` set and cleared while `agent` stayed
claude and `agent_status` stayed `working`. Found that `session_name` is not only the `/rename`
name, the rb agent reported "Cloning gau3 web repos", which its transcript holds as an
`ai-title` with no `custom-title`. Kept, since a generated title beats the word claude. The
`custom-title` entry in the transcript is the route if only names set by hand should show.

### 2026-10-27 14:15

Rows moved to space and tab on the first line, pane and agent on the second, at Milos's asking.
Config check and reload reported no diagnostics.
