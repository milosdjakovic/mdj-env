# Herdr agent detection behind a terminal wrapper

Status. Solved by a Claude Code hook that announces its own pane, committed as c82178d, with
an upstream issue to file and one limit recorded.

## Now

Herdr names an agent pane by reading the pane's foreground process. Any wrapper that holds the
pane's terminal and runs the shell behind it on a pty of its own hides whatever is really
running, and a pane that fails that first check never has a title rule or a screen rule
evaluated against it. Iris is the wrapper that happens to be here.

`dotfiles/claude/.claude/hooks/herdr-agent-pane.sh` runs `herdr pane report-agent` on
`SessionStart` and `herdr pane release-agent` on `SessionEnd`, both documented as how a custom
hook reports an agent, with the source id `custom:mdj-env`. Once the pane is named, herdr's own
claude manifest decides the state. The hook reads nothing of iris and is a measured no op on a
pane where herdr can see the agent by itself, so replacing or removing iris changes nothing.
`src/setup-claude-settings.sh` wires it, `src/check-dependencies.sh` warns when it is unwired
or when any herdr integration is installed, and the reasoning is in the root CLAUDE.md under
Claude Code.

One limit stands. `herdr agent prompt` and `herdr agent send-keys` refuse on a wrapped pane
even after it is named, because they check the real foreground process. Pane level `send-text`
and `send-keys` work, so the agents panel and scripting are unaffected and only herdr's own
agent automation is not.

## Rejected

- **Global `HERDR_AGENT=claude` before `exec iris`.** 2026-09-14 about 21:50. Herdr's documented
  hint for wrappers, and it works, but it is read from the foreground process environment,
  fixed when iris is exec'd, so it would make every shell pane an idle agent row. Herdr's own
  documentation warns against exporting it globally.
- **Per pane marker, keep iris.** 2026-09-14 about 21:52. A pane opened with `--env` carries the
  hint and others do not. Precise, and a workaround, since it means remembering to open a pane
  a special way, which is the exact friction being fixed. Turned down by Milos as a patch.
- **Per pane marker, skip iris in that pane.** 2026-09-14 about 21:52. Same marker, zshrc skips
  `exec iris`, claude becomes the real foreground process and herdr detects it natively with
  nothing undocumented. Bulletproof and costs iris exactly where most time is spent. Chosen
  briefly, then withdrawn by Milos for the same reason as above. It remains the only option
  with no reliance on unwritten behaviour, and is listed so that fact is not lost.
- **`herdr integration install claude`.** 2026-09-14 about 21:40. Installs a SessionStart hook
  that sends only `pane.report_agent_session`. Session identity does not name a pane, and once
  a pane carries a session under `herdr:claude` no other source may ever name it. Neither
  `release-agent` nor `clear-agent-authority` undoes it. Installing it on this session's pane is
  why that pane never recovered. It also gives the one thing our source cannot, conversation
  resume after a herdr server restart, so on this machine it is detection or resume, never
  both. Never install it. The reconciler warns if it is.
- **Fixing it inside iris.** 2026-09-14 about 23:05. Read `root/wrapper.go`. The shell is
  started with `Setsid` and `Setctty` at line 247, so it lives in its own session, and the outer
  terminal goes raw at line 274 so iris can read every key. A terminal can only have a
  foreground group from its own session, and iris has to stay foreground to read, so handing
  the group to the child is refused by the kernel and dropping `Setsid` costs the child its job
  control. What iris could do is lie, rewrite its own argv to claude or fork a decoy process by
  that name, and both would make every process tool on the machine wrong.
- **Hand written JSON onto the socket with `nc`.** 2026-09-14 about 21:55, superseded 22:45. The
  first shipped version, built on the belief that `herdr pane release-agent` could not parse its
  own arguments. It could. See the correction in the log. Not wrong so much as unnecessary, and
  the CLI is the supported interface.
- **Re announcing on every prompt so the report survives a herdr server restart.** 2026-09-15
  about 00:00. Probably harmless, since the manifest is the authority once the pane is named,
  but probably is not enough to justify a hook on every prompt for a scenario nobody has hit.
  Deferred, with the cheap fix noted here in case it ever bites.
- **Configuration options that do not exist.** 2026-09-14 about 23:20 and 23:35. Two suggestions
  arrived from elsewhere, a herdr re index command and an iris `ignore_processes` list. Herdr
  has no command matching index, rescan or refresh. Iris's config is TOML and its complete key
  list contains nothing resembling ignore, bypass or yield. Both came with real URLs whose
  content said something else. Verify a cited mechanism against the binary before trying it.

## Log

### 2026-09-14 about 21:15

Milos reports this Claude session missing from herdr's agents tab, as was the session before
it. A previous session had diagnosed the cause correctly, the pane's foreground processes read
iris and iris and herdr never sees claude, and offered two ways out, launching claude outside
iris or asking herdr for an iris detection manifest. Both are wrong. A manifest classifies
state on a pane already named, and the second was never needed.

### 2026-09-14 about 21:30

`herdr pane report-agent` from a made up source names the pane, and `herdr agent explain`
immediately shows `rule: osc_title_working` driving the state from the title. That is the whole
finding. Only identification was missing and everything downstream already worked.

### 2026-09-14 about 21:40

Installed herdr's claude integration on the guess that it was the durable form of the above.
Read the installed hook. It sends `pane.report_agent_session` only. Simulated its exact call
against this pane, the server answered ok, the pane stayed unknown. Then re reporting from the
made up source no longer named the pane either. Measured on fresh panes over the next half
hour. A custom source names a pane, `herdr:claude` does not, and a pane that has ever carried a
`herdr:claude` session refuses every other source thereafter. Uninstalled it. This pane is
permanently stuck for the life of the herdr session.

### 2026-09-14 about 21:50

Read herdr's agents documentation. `HERDR_AGENT=<agent>` on the wrapper command is the
documented answer for wrappers. Proved it works behind iris with a throwaway split carrying
`--env HERDR_AGENT=claude`, herdr named the pane as claude with iris and iris as its foreground.
Proved the downside in the same test, a shell pane so marked shows as an idle agent. Asked
Milos where the hint should live. He chose skipping iris in marked panes, then withdrew it,
wanting no marker and no patch.

### 2026-09-14 about 21:55

Settled the mechanism on a throwaway pane. A report with state `idle` or `working` names the
pane, `unknown` does not. Release from the owning source clears it, release from another source
does nothing, and the cycle repeats cleanly. Wrote the hook to speak the socket directly with
`nc`, because `herdr pane release-agent --source X --agent Y PANE` answered `unknown option`.
Declared herdr's CLI unable to do the release half and documented that in CLAUDE.md.
Corrected 2026-09-14 22:45, see below.

### 2026-09-14 22:01

Stowed. Settings merged. `src/setup-claude-settings.sh` rewritten to stop exiting early when a
`statusLine` key exists, since that guard made it a script that could configure a machine once.
Verified end to end at about 22:05 with a real headless session pointed at a throwaway pane, the
hook fired on start and end, `~` expanded in the command, the pane went idle and back to
unknown.

### 2026-09-14 22:45

Correction. Herdr's CLI was never broken. The CLI reference puts the pane id first as a
positional argument, `herdr pane release-agent <pane_id> --source ...`, and in that order both
commands work. The `unknown option` came from passing the pane last. A second piece of evidence,
an exit code of 1 after a release, belonged to the `herdr agent explain` at the end of the same
compound command, which correctly reported the pane as not found because the release had
worked. Rewrote the hook onto the two CLI commands with the documented `custom:` source prefix,
swapped the declared dependency from `nc` to `herdr`, rewrote the CLAUDE.md paragraph to say
what actually happened, re verified with a live session. Also found `pane.clear_agent_authority`
in the schema and tried it on this pane. It does not clear a `herdr:claude` session record.

### 2026-09-14 about 23:15

Milos asks for a fix that does not depend on iris, since he may replace it. Tested the
replacement case. Iris's shell hook honours `IRIS_RESCUE`, so a pane built with
`--env IRIS_RESCUE=1` is bare zsh. Herdr named claude there by itself. Fired the hook into that
pane. Nothing changed, the pane stayed named, the manifest kept deciding the state and the
release at the end did not evict the still running session. The fix was already general.
Rewrote the CLAUDE.md prose to state the rule before the instance. Added a section to
`check-dependencies.sh` warning when any herdr integration is installed or the hook is unwired
from either event, proved both by breaking and repairing them. The first version of the jq
test warned when the hook was present, fixed before it landed.

### 2026-09-14 about 23:55

Tried to drive a promoted, wrapped pane through `herdr agent prompt` to reach a working state
for a further test. It refused, `agent is no longer the pane foreground process`.
`herdr agent send-keys` refused with `not an active named agent`. `herdr pane send-text`,
`herdr pane send-keys`, `herdr agent read` and `herdr agent list` all work. Herdr's agent level
writes check the real foreground process independently of naming. Recorded as a limit rather
than solved, and as the strongest point for the upstream issue since it is an internal
inconsistency rather than a request.

### 2026-09-15 00:08

Committed as c82178d. Nothing in iris changed. Milos asked whether this was a patch, whether it
depended on iris, and whose fault the whole thing was. The answers are in the commit message
and in CLAUDE.md, and the last one is that iris does nothing wrong, herdr has a design gap and
one real defect, Claude Code is clean, and two of the evening's detours were the assistant's.

### 2026-09-15 about 00:30

The problem is not iris specific in the other direction either. Behind stock macOS
`script -q /dev/null zsh -f`, herdr's foreground list reads only `script`, and a Claude session
started with the hook neutralised stays unknown while its title shows the `✳` glyph, the same
failure with no iris anywhere. The hook names that pane the same way it names an iris one. So
`script` is the reproduction for the upstream issues, since a maintainer can run it on any Mac.
Named by hand and driven with `herdr agent prompt`, the pane refuses exactly as behind iris.
Two bug drafts and one discussion draft written, not filed, pending Milos. This file, the
`decisions/` directory and its README, the CLAUDE.md section and the reconciler check nine
were all created in this same sitting, and this entry is the first one written under the
contract rather than reconstructed for it.
Corrected 2026-09-15 00:17, see below.

### 2026-09-15 00:17

Correction. The entry above was written at about 00:12, not 00:30. The estimate came from a
sense of how much had happened rather than from a clock, and the two commits either side of it,
c82178d at 00:08 and c90ff87 at 00:15, bound it. An estimated time is anchored to the nearest
commit or file timestamp before it is written, and the README now says so. This is the first
correction made under the contract, on the first entry written under it.
