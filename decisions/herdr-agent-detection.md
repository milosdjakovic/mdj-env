# Herdr agent detection behind a terminal wrapper

Status. Fixed in herdr, 2026-09-16, by a fork this repository builds and pins. Nothing
announces a session to herdr, no integration is installed, and the panel sees through the
shell autocomplete because herdr now walks descendants when the pane's own foreground group
holds no agent. The fork is declared at `forks/herdr` and is a cost paid weekly until upstream
takes the walk, which it has given no sign of doing.

## Now

Herdr names an agent pane by listing one process group, the foreground group of the pane's own
terminal, and matching known names in it. It never walks parents or children, though
`process_bsdinfo` already fetches each process's parent pid and nothing reads it. A pty proxy
holds the pane's terminal and runs the shell on a second terminal in a session of its own, so
the agent is a descendant of the pane process and can never be in the group herdr lists. Iris
is the proxy that happens to be here, and the same is true of every other one.

That is a kernel fact rather than a choice either program made. A controlling terminal belongs
to one session, a proxy has to keep the outer one to read keys, so the shell needs a new
session on a new terminal and no process in it can ever be the outer terminal's foreground
group. Nothing in the proxy can change it and no configuration option in either program
touches it.

So the fix is a descendant walk in herdr, and since 2026-09-16 this machine runs it. When the
pane's own foreground group yields no agent, herdr indexes every process by parent pid, walks
the children of the pane process breadth first, and identifies the first agent it finds, with
a scan limit so a deep tree cannot cost the poll. A pane whose foreground group already holds
an agent never reaches the walk, so every pane that worked before behaves exactly as it did,
which was the objection upstream raised when it closed the idea. A pane running no agent at
all finds nothing, so an ordinary helper process is never promoted into an agent, and there is
a test for each of those three cases.

The branch is `feat/detect-agents-in-descendant-process-groups` on `milosdjakovic/herdr`, two
commits above the v0.9.0 tag. The first is another user's work, cherry picked with their
authorship intact under Apache 2.0, from a pull request upstream closed unread. The second is
the test it lacked, because the only wrapper test upstream had spawns its agent as a
background job of the same shell, which never leaves the pane's process group and so passed
before the walk existed and proves nothing about it. The new one puts the agent behind
`script`, which is a new session on a new terminal, the shape a proxy makes.

`forks/herdr` declares it and `forks/CLAUDE.md` carries the rule for when it can go. The
update check is off in the stowed herdr config, because an update never installs on its own
but does offer a command that would replace the patched binary with an unpatched release.

Nothing in this repository announces a session to herdr and nothing should. A state reported
by any source becomes the pane's authority until released, so a hook that reports idle at
session start leaves the pane idle for the life of the session, with no working, no blocked
and no done notification. It does that to a pane herdr identifies by itself too, so it was
never a harmless no op. The hook is gone and `setup-claude-settings.sh` prunes it from any
machine that still carries one.

Two limits stand, both unchanged by the walk. `herdr agent prompt` and `herdr agent send-keys`
refuse on a wrapped pane, because they check the real foreground process rather than the
identified agent. Pane level `send-text` and `send-keys` work, so the panel and scripting are
unaffected and only herdr's own agent automation is not. And a pane that has ever carried a
session under `herdr:claude` stays unnameable for the life of the herdr server, because the
block is on the pane rather than the session, so the only recovery is a new pane.

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

### 2026-09-16 14:50

The fork exists and the walk is in it. Milos asked for it as a feature branch offerable
upstream rather than a patch, with the whole upstream picture written down, and for a rule
that makes both forks answerable when he asks about them.

What upstream is, measured rather than assumed. herdr does not take outside pull requests.
`CONTRIBUTING.md` says so outright, only accounts listed in `.github/APPROVED_CONTRIBUTORS`
may open one, the list is curated and explicitly not an application program, and a workflow
closes everyone else's automatically. It also instructs any agent reading it to refuse to open
an implementation pull request from an account not on those lists, which is why none was
opened and why none should be.

The walk had already been written by another user.
[PR 3176](https://github.com/herdrdev/herdr/pull/3176), "fix: detect agents in descendant
process groups", 322 lines across six files with unit tests, closed by the gate bot nine
seconds after it opened and never read. Their issue
[3179](https://github.com/herdrdev/herdr/issues/3179) was closed by a maintainer bot with
"Walking arbitrary descendant groups would change detection behavior and can select background
or helper processes, so this needs product design rather than a bug fix", pointing at the
Ideas discussions. [Issue 803](https://github.com/herdrdev/herdr/issues/803) is the open
umbrella every wrapper report is consolidated into, community diagnosis through August, no
maintainer plan attached. Same shape, different wrapper, in issues
[2360](https://github.com/herdrdev/herdr/issues/2360),
[2481](https://github.com/herdrdev/herdr/issues/2481),
[1998](https://github.com/herdrdev/herdr/issues/1998),
[2999](https://github.com/herdrdev/herdr/issues/2999) and
[2617](https://github.com/herdrdev/herdr/issues/2617), all closed.

The discussions board is where the maintainers point and it is not a door. Thirteen hundred
discussions, eleven hundred of them ideas, and the ten newest, all from the last thirty hours
when this was written, carry no maintainer reply at all. Ours is already there several times
and unanswered since August.
[2237](https://github.com/herdrdev/herdr/discussions/2237) describes a front end that owns the
pane terminal and runs the shell on an inner one, word for word this problem, zero comments.
[2136](https://github.com/herdrdev/herdr/discussions/2136) asks for configurable wrapper
support, [699](https://github.com/herdrdev/herdr/discussions/699) and
[2473](https://github.com/herdrdev/herdr/discussions/2473) for containers,
[3180](https://github.com/herdrdev/herdr/discussions/3180) and
[2607](https://github.com/herdrdev/herdr/discussions/2607) for editor terminals,
[3347](https://github.com/herdrdev/herdr/discussions/3347) for WSL. None answered. herdr's own
`docs/agents.mdx` states the limit plainly for the tmux case, so it is acknowledged rather
than unknown.

So a pull request was not opened and posting an eighth discussion was not worth doing. The
fork is the answer, and the watched links in `forks/herdr/FORK` are what will say if that ever
changes.

What was built. The branch from the v0.9.0 tag, the other user's commit cherry picked clean,
then a commit adding two tests and a formatting fix the current toolchain wants. Both new
tests pass on macOS. The whole binary test suite passes except two plugin tests that share a
global config directory and fail in parallel whichever pair happens to race, which was proved
pre existing by running that module serially, where all fifty three pass, and by the branch
touching no plugin file. The build needs Zig 0.15 for a vendored terminal parser, which is a
keg only formula now declared and mapped, and cargo through rustup, which has no shim on this
machine so it is asked for by name.

The general mechanism. `forks/` with one directory per fork, each holding a declaration and
two executables the engines find by name, `build` and `prove`. `src/build-forks.sh` builds
each fork at its pin and installs it, keeping a stamp of the pin and a checksum so a binary
something else replaced is rebuilt rather than trusted, which matters because herdr offers its
own updates and Homebrew owns a copy of the same name. `src/check-forks.sh` reports releases
since the pin, whether each patch is still needed, whether it still rebases, and which watched
links have moved. Iris moved onto the same mechanism and `src/build-iris.sh` and
`src/check-iris-upstream.sh` are gone, their logic now living in `forks/iris/build` and
`forks/iris/prove`. Verified by rebuilding iris through the engine to the same version string
it reported before, and by running its prove against unmodified upstream, where both patches
correctly answer still needed and the alias one quotes the real upstream failure.

Two defects found in the reporter while testing it, both fixed. It counted upstream's preview
tags as releases, which would have reported movement on nearly every run until nobody read it.
And it mapped a pull request URL to the issues endpoint, which answers 404, which it then
printed as though 404 were a state.

Left undone on purpose. The running herdr server is still the Homebrew binary, since handing
live panes to a new server is Milos's to run rather than mine. The Homebrew formula is still
installed and now unlisted in the Brewfile, harmless because `~/.local/bin` comes first on the
PATH.
