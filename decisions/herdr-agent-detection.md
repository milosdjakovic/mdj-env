# Herdr agent detection behind a terminal wrapper

Status. Settled on vanilla, 2026-09-16. Nothing announces a session to herdr, no integration
is installed, and the panel is blind behind iris by design. Which autocomplete to run, and
so whether the panel stays blind, is the open decision, and it is not this file's.

## Now

Herdr names an agent pane by reading the pane's foreground process. Any wrapper that holds the
pane's terminal and runs the shell behind it on a pty of its own hides whatever is really
running, and a pane that fails that first check never has a title rule or a screen rule
evaluated against it. Iris is the wrapper that happens to be here.

`dotfiles/claude/.claude/hooks/herdr-agent-pane.sh` runs `herdr pane report-agent` on
`SessionStart` and `herdr pane release-agent` on `SessionEnd` with the source id
`custom:mdj-env`. That names the pane, and it also makes the hook the pane's state authority.
Herdr keeps one authority slot per pane, and a reported state from any source that is not one
of herdr's own full lifecycle integrations is effective until released or until the process
exits. Screen detection keeps running and `herdr agent explain` keeps showing its answer, but
the sidebar reads the authority, so the pane shows the one state the hook reported, idle, for
the life of the session. The same happens on a pane herdr identifies by itself, so the hook is
not a no op without iris either. It is gone, the hook file, its declaration, the reconciler
check that watched it, and the settings merge now prunes it from any machine that still
carries it. Nothing in this repository announces a session to herdr, so a session behind iris
is not listed, and a pane herdr sees by itself works fully. The measured detail and the
source lines are in the 2026-09-16 log entries.
`src/setup-claude-settings.sh` wires it, `src/check-dependencies.sh` warns when it is unwired
or when any herdr integration is installed, and the reasoning is in the root CLAUDE.md under
Claude Code.

One limit stands. `herdr agent prompt` and `herdr agent send-keys` refuse on a wrapped pane
even after it is named, because they check the real foreground process. Pane level `send-text`
and `send-keys` work, so the agents panel and scripting are unaffected and only herdr's own
agent automation is not.

A pane that has ever carried a session under `herdr:claude` stays unnameable for the life of
the herdr server. Resuming the session in that pane with `claude --resume` does not help,
because the block is on the pane and not on the session. The only recovery is to close that
pane and open a new one, and `check-dependencies.sh` names such a pane so nobody has to work
that out from an empty panel.

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
  Reopened 2026-09-16 00:55. The reason was that it blocked our hook, and the hook is gone.
  It is no longer forbidden and the reconciler no longer warns. Not tried since.
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
Corrected 2026-09-16 00:43, see below.

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
Corrected 2026-09-16 00:43, see below.

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

### 2026-09-15 00:23

Milos closed this session and ran `claude --resume 5e1b0941-75f6-4cbe-ba3b-82ead2894d06` in
the same pane, wA:pR, and it was still not listed. Checked. Same pane, the `herdr:claude`
session record from the 21:40 probe is still on it, the hook is wired and fired on resume, and
a manual `start` changes nothing either. This is the poisoned pane behaving as recorded, not a
regression. The block is on the pane rather than the session, so resuming inside it cannot
help, and closing the pane and opening a new one is the only recovery. That was in the record
and was not in what Milos had been told to expect, so the Now section now says it plainly and
check eight in the reconciler names any pane in this state. On this machine it names wA:pR.

### 2026-09-15 00:24

Confirmed in ordinary use. Milos opened a new herdr tab and started a fresh session there,
behind iris as every pane here is, and it appeared in the agents panel with nothing done by
hand. That is the first confirmation from normal use rather than from a throwaway pane driven
by the assistant, and it is the one that counts. The poisoned pane wA:pR stays the single
exception, and the reconciler names it.

### 2026-09-16 00:43

Milos reports that agents appear in the panel and never change state, no working, no blocked,
no done notification. Measured on this session's pane, wA:pY. Title `◐ ...`, `herdr agent
explain` says working by `osc_title_working`, `herdr agent get` says idle. Reproduced on a
throwaway pane. Named idle from a custom source, then held a working title for forty seconds,
status stayed idle while explain said working. Reported unknown, status became unknown while
explain still said working. So the 21:30 belief was wrong. `explain` shows what detection
would say, not what the pane shows, and a `report-agent` from any source takes the state.

The 23:15 belief was wrong too. On a pane with no iris and a process named claude holding a
working title, herdr showed working by itself. One `report-agent --state idle` from
`custom:mdj-env`, the exact call the hook makes, and the status was idle while the title still
said working. A release afterwards left it unknown. So the hook damages native detection as
well, and removing iris does not make the hook harmless.

Read herdr 0.9.0's source to see why. `src/terminal/state.rs` keeps one `hook_authority` per
terminal, `recompute_effective_state` takes the authority's state whenever
`hook_authority_is_effective`, and that is true for every source that is not in the six
entry allowlist in `src/detect/mod.rs` `full_lifecycle_hook_authority`. Screen results land
in `fallback_state` and are used only with no effective authority. A visible blocker can
override a hook, but only when the process probe also identified the agent, which behind iris
it never does. Herdr's own claude hook never calls `report_agent` at all, only
`report_agent_session`, because upstream moved claude to screen detection in 0.6.7 after
hook driven state proved stale. The docs say so in the integrations table.

Identification itself is `proc_listpids(PROC_PGRP_ONLY, tcgetpgrp(tty))` in
`src/platform/macos.rs` `foreground_job`, one process group on one tty, no parent walk, and
`HERDR_AGENT` is read from the environment of members of that same group. Nothing in herdr
can reach a process on a pty a child opened. `process_bsdinfo` already fetches `pbi_ppid` and
nothing reads it. So the fix that costs nothing downstream is a descendant walk in
`foreground_job`, folding a child pty's foreground group into the job, after which
`identify_agent_in_job` and the whole state engine work unchanged. Nothing in this repository
can do that. Recorded as the answer, and the hook as something to remove rather than extend.

### 2026-09-16 00:55

Milos asked for the hook out. Removed `hooks/herdr-agent-pane.sh`, its line in
`dotfiles/claude/DEPENDENCIES`, and check eight in the reconciler, which watched a mechanism
that no longer exists. `setup-claude-settings.sh` now prunes the hook from every event in
`settings.json` rather than appending it, ran it on this machine, everything but the hooks
table is byte identical. The stow link in `~/.claude/hooks` was dangling after the restow and
was removed by hand with the empty directory. The root CLAUDE.md section is rewritten to say
why no hook can fix this and where the fix is.

- **A patched herdr built here, pinned the way iris is.** 2026-09-16 01:05. Offered as the
  one fix that costs nothing downstream, a descendant walk in `foreground_job`. Milos declined
  it for now, unsure of the route, and said the gymnastics were for iris's sake and iris
  itself needs reevaluating. Listed in the log rather than under Rejected because it was not
  turned down on its merits, only not taken. The upstream issue with the `script`
  reproduction is still the cheapest thing to do and is still unfiled.

### 2026-09-16 01:15

Milos chose vanilla. Herdr and Claude Code as shipped, with the panel blind behind iris
rather than patched around it. Checked what was still not vanilla. No integration installed,
no hook in `settings.json`, but five panes still carried the old hook's naming with its frozen
idle, this one among them. Released each from `custom:mdj-env`, the panel emptied, and the
pane the integration poisoned on the 14th had already been closed. So the live state matches
the repository at 7e7020a and nothing is left to undo.

The autocomplete question is being decided separately. inshellisense is out because it
excludes the aws, gcloud and az specs by design. ghost-complete is a PTY proxy like iris and
blinds the panel the same way, so it is only a candidate if the panel loses. carapace behind
the fzf-tab already loaded, or zsh-autocomplete, are the in shell shapes that keep the panel
whole. Whatever is chosen, nothing here needs changing, since the proxies only affect the
panel and the in shell tools affect nothing herdr sees.
