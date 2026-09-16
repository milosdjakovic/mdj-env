# Iris, the shell autocomplete, from its two fixes to its removal

Status. Removed 2026-09-16, about 16:55. The shell runs zsh-autosuggestions, fzf-tab and
carapace, all inside zsh, and herdr is the Homebrew formula again, 0.9.0, unpatched. This file
is the whole record of iris here, the two fixes it needed and how each works, the herdr
limitation that ended it and how that works, what upstream herdr has said and where, the fork
that was built and given up, and how to recheck any of it later. It is written to stand on its
own. The fork repositories may be deleted at any time and nothing here relies on them.

## Now

The autocomplete is the in shell trio. zsh-autosuggestions draws grey ghost text from atuin's
history, fzf-tab opens an fzf picker on Tab, carapace underneath is the dictionary, roughly a
thousand commands with flag and value descriptions. Tab on an empty line lists files, the up
arrow is atuin's search seeded with what is typed, and ctrl+r is atuin's full search. Iris
folded history and commands into one inline menu filtered by the line itself, and that feel is
the one thing this stack does not give. It was tried and rejected on feel once, at 12:10 on
2026-09-16, and is accepted now as the price of a working agents panel.

herdr is the Homebrew formula, 0.9.0, released 2026-09-07. Every session runs inside zsh with
nothing holding the pane's terminal, so the agents panel names each one by itself and tracks
working, blocked and done from the screen, which is herdr's own design since 0.6.7.

### How to ask later whether herdr has fixed the limitation

The reproduction needs no iris and works on any Mac with herdr and Claude Code.

1. Open a fresh herdr pane and run `script -q /dev/null zsh`. `script` opens a new terminal and
   starts the shell in a new session on it, which is exactly the shape every pty proxy makes.
2. Start `claude` in that shell and give it something to do.
3. Look at the agents panel and run `herdr agent list` in another pane. At 0.9.0 the panel is
   empty and the list does not name the pane. `herdr pane process-info --current` from inside
   the proxied shell shows only `script` in the foreground processes.

If the pane appears and its state follows the session, herdr has learned to look past the
pane's foreground group and a pty proxy could come back. Then read these, newest activity
first, to see how it happened and whether it is on by default.

- https://github.com/herdrdev/herdr/issues/803, the open umbrella issue every wrapper report
  is consolidated into, opened 2026-06-25.
- https://github.com/herdrdev/herdr/pull/3176, the descendant walk, closed unread 2026-08-24.
- https://github.com/herdrdev/herdr/issues/3179, the issue behind that pull request, closed
  2026-08-24 as needing design rather than a fix.
- https://github.com/herdrdev/herdr/discussions/2237 and
  https://github.com/herdrdev/herdr/discussions/2136, the discussions describing this exact
  shape, unanswered when this was written.
- The `docs/agents.mdx` file in the herdr repository, which at 0.9.0 says in so many words
  that agent detection does not inspect a tmux started inside a pane.

Versions at removal, 2026-09-16.

| tool | version |
|---|---|
| macOS | 27.0 |
| zsh | 5.9 |
| herdr | 0.9.0, Homebrew formula, tag v0.9.0 of 2026-09-07 at github.com/herdrdev/herdr |
| iris upstream | v0.7.0 at github.com/versenilvis/IRIS, base commit ac1cfe7 |
| iris as built | 0.7.0+mdj.b8b7ac8, the fork main at github.com/milosdjakovic/IRIS, 2026-09-15 |
| Claude Code | 2.1.273 |
| carapace | 1.7.3 |
| fzf | 0.74.4 |
| atuin | 18.22.0 |
| zsh-autosuggestions | 85919cd |
| fzf-tab | fc6f0dc |

## The journey

Three chapters, each at the version it happened at.

### Chapter one, the theme could not follow the terminal

Iris v0.6.4 had one flat set of theme colours and no idea what the terminal behind it was
painting. Ghostty here follows the system appearance and both halves are painted from one
palette, so almost every iris value could be an ANSI slot, `"4"` for the accent and `"8"` for
the comment grey, and follow the terminal for free. That works because lipgloss turns `"4"`
into a basic ANSI colour, SGR 34, which lands on the terminal's slot. An early note claimed the
opposite, on the strength of a detector that matched only `38;2` and `38;5` sequences and never
the `30` to `37` range, so it reported zero colours while the menu was drawing in slots the
whole time. A detector that can only see one encoding reports the absence of every other one.

The one thing a slot cannot do is the selection bar. A bar has to be a tint of the page under
it, and no slot is dark on the dark palette and light on the light one. Every single file
alternative was measured. A fixed hex bar forces a fixed `match` colour, since `match` is
drawn on the page on every other row and inside the bar on this one, and a fixed `match` only
clears a bar that is very dark or nearly white. Letting both inherit means the bar must be dark
enough for the dark half's match colour and light enough for the light half's at once, which
lands at contrast 2.05 on slot 8, 1.08 on slot 4 and 1.27 on slot 7. There is no single bar,
which is why the feature had to exist. So `text` and the three idle tag backgrounds were made
deliberately unparseable, because lipgloss renders an unparseable foreground unstyled, which
inherits the terminal, and does not draw an unparseable background at all, which is what leaves
a tag as a word on the page instead of a chip stamped on it.

The fix, six commits on the fork branch `feat/appearance-aware-theme` between 2026-09-14 and
2026-09-15, is described under Recreating the fixes. It cost four measurement mistakes and one
regression in every layer above iris, all in the log.

### Chapter two, an alias came back as its expansion

Upstream issue 158 at github.com/versenilvis/IRIS. Iris expands a shell alias so the target's
spec can answer, which it has to do, and then never puts the typed word back. With `cd`
aliased to zoxide every row read `z /path` and with `ls` aliased to eza every row read
`eza Brewfile`. Ghost text died from the same cause, since it only draws when the top result
has the literal buffer as a prefix and `z ` never has `cd ` as one. One bug, two symptoms, and
no configuration option touches it. `expand-alias` governs something else entirely, whether
iris rewrites the literal prompt text on space.

The fix is one commit on the fork branch `fix/alias-display-preserves-typed-command`,
2026-09-14, twenty five lines in one function, described under Recreating the fixes.

### Chapter three, herdr could not see through it

This is the one that ended iris, and it is not iris's fault. It is a limitation of herdr 0.9.0
that applies to every program of iris's shape.

How herdr identifies an agent. `foreground_job` in `src/platform/macos.rs` asks the pane's
terminal for its foreground process group with `tcgetpgrp`, lists that one group with
`proc_listpids(PROC_PGRP_ONLY, ...)`, and `identify_agent_in_job` in `src/detect/mod.rs`
matches known agent names in it, preferring the group leader. It never walks parents or
children, though `process_bsdinfo` already fetches each process's parent pid and nothing reads
it. `src/platform/linux.rs` does the same through `/proc`, with one opt in,
`HERDR_PROCESS_DETECTION=child-groups`, that only runs when the terminal cannot answer at all,
as under gVisor, so it never fires when the answer is simply the wrong group. `HERDR_AGENT` in
the environment is read from members of that same group and nowhere else. Once a pane is named,
the screen manifest and the title rules decide its state and herdr's own claude integration
sends only a session id, never a state, because hook driven state went stale and was dropped in
0.6.7.

Why a pty proxy defeats that. Iris, ghost-complete, inshellisense, Fig's figterm, a tmux
started inside a pane, `script`, any program that reads every keystroke before the shell does,
has to own the pane's terminal. A controlling terminal belongs to one session, so the shell it
runs has to be started in a new session on a second terminal, with `Setsid` and `Setctty` in
iris's `root/wrapper.go` at line 247. Nothing in that new session can ever be the outer
terminal's foreground group, the kernel refuses it. So the group herdr lists is the proxy
itself, iris and iris, and claude is a descendant it never looks at. A tmux inside a pane is
worse still, since the tmux server is a child of launchd and the agent is not a descendant of
the pane process at all. No setting in either program changes any of this. `HERDR_AGENT` set
globally makes every shell pane an idle agent row, a per pane marker means opening a pane a
special way, and a Claude Code hook that reports the pane makes the hook the pane's state
authority, so the pane sits at whatever state the hook reported for the life of the session.
That hook ran here from 2026-09-14 to 2026-09-16 and froze every session at idle, including
sessions herdr could see by itself.

What upstream herdr has said. The project does not accept unsolicited pull requests. Its
`CONTRIBUTING.md` says so in its first heading, only accounts in `.github/APPROVED_CONTRIBUTORS`
may open one, the list is curated and explicitly not an application program, and a workflow
closes everyone else's on arrival. It also instructs any agent reading it to refuse to open an
implementation pull request from an account not on the list. The exact fix, a descendant walk,
was written by another user and opened as pull request 3176 on 2026-08-24, three hundred and
twenty two lines across six files with unit tests, and the gate closed it nine seconds later
without anyone reading it. Their issue 3179 was closed the same day by a maintainer bot saying
that walking descendant groups would change detection behaviour and can select background or
helper processes, so it needs product design rather than a bug fix, and pointing at the Ideas
discussions. Issue 803 is the open umbrella since 2026-06-25 that every wrapper report is
consolidated into, iris named twice among them, with community diagnosis through August and no
maintainer plan. The discussions board it points at had thirteen hundred threads when this was
written, the ten newest all from the previous thirty hours and none with a maintainer reply.
Discussion 2237 from 2026-08-03 describes a front end owning the pane terminal and running the
shell on an inner one, this problem word for word, zero comments. Discussions 2136, 699, 2473,
3180, 2607 and 3347 are the same problem behind sandboxes, containers, editor terminals and
WSL, none answered.

What was tried here and given up. On 2026-09-16 herdr was forked, that pull request's commit
was cherry picked onto the v0.9.0 tag with its author's name intact, a test was added that puts
the agent behind `script` and asserts both that the pane's own group carries no agent and that
the walk finds it, the binary was built and unit tested on this machine, and a general
mechanism for carrying forks was written around it and iris. It was undone the same afternoon,
before the running server ever used the binary, so the fix is not confirmed live. The reason is
the price. herdr released six times in ten weeks, a pin stops taking those the moment it is
set, and rebasing weekly for a project that will not take the fix is not a cost worth paying
for an autocomplete. Iris went instead, and with it the whole habit of building, pinning and
watching upstream. That habit is what this repository will not resort to again, and the root
guide says so.

## Recreating the fixes

Each of these is enough to rebuild the fix from the description if the fork branches are gone.
File names are upstream's at the versions named above.

### The iris alias fix, one commit above v0.7.0

Where. `spec/lookup.go`, inside `Lookup(input string) []Suggestion`, with a test in
`spec/lookup_test.go`.

What. `Lookup` already resolves the first word through the shell's aliases so the target's spec
can answer, and builds each suggestion's text from the expanded command. After the suggestions
are built, and before they are returned, walk them and replace the leading expanded target with
the alias word the user actually typed, keeping whatever followed it. Do the same for the
ghost text source, since ghost text is drawn only when the top suggestion has the literal
buffer as a prefix. Nothing about spec resolution changes, only what is shown and inserted.

Test. Register an alias `cd` for `z` and `nv` for `nvim` in the lookup's alias source, look up
`cd ho` and `nv al`, and assert every suggestion starts with `cd ` and `nv ` respectively and
none with `z ` or `nvim `. Upstream fails both at v0.7.0, so the test doubles as the check for
whether upstream has fixed it.

### The iris appearance theme, six commits above v0.7.0

Where. `internal/config/theme.go` and a test, `root/root.go`, `root/wrapper.go`,
`root/theme_cmd.go`, and a new `root/themenotify.go` with its test.

The theme file. `LoadTheme` accepts optional `[dark]` and `[light]` tables over the flat keys.
A key in the table for the active half overrides the flat key, and the flat keys stay the
default for a theme that carries no tables. Only four keys ever needed a half here, the
selected row's `sel_bg`, `text_sel`, `desc_sel` and `sel_text`, painted from the palette's
highlight, foreground, subtext and background roles. Everything else is a slot. The `theme`
subcommand's template documents the tables. Tests cover a theme with tables, without, and with
one half only.

Detecting the half. The watchdog process is the one moment iris holds the terminal with nothing
else reading it, so it asks there, once, with OSC 11, through the terminal it already holds and
through a call that distinguishes a failed query from an answer. Two mistakes to avoid. Pairing
the query with `os.Stdout` makes lipgloss refuse when stdout is not a terminal, and the helper
that answers dark for any error hides that refusal as a dark terminal. And the answer travels
to the drawing process in `IRIS_TERM_BACKGROUND`, which reaches the shell too, so an iris
started from that shell inherits it. Rewrite it on every start, and let a hand set value
survive only when the terminal declines to answer.

Following a switch. The wrapper turns on DEC private mode 2031 so the terminal reports an
appearance change as `CSI ? 997 ; 1 n` for dark or `; 2 n` for light. The report arrives on
the input stream with the keystrokes, so the wrapper removes it before the shell or the key
handling sees it, whole sequences only, because holding back a partial escape would delay the
arrow keys, which begin the same way. On a report it reloads the half and redraws the open box
directly, bypassing the render path that declines while the user is navigating, because the
terminal repaints every slot coloured part on its own and the hex selection bar is the one
thing left behind otherwise.

Relaying to the program behind iris. Removing the report is right for the shell and wrong for
every program behind iris that asked for the same report, because the terminal sends one copy.
herdr behind iris never heard a switch, and everything inside herdr asks herdr, so Neovim,
Claude Code and the iris in every pane stayed on the old half while the outer iris alone
followed. So the wrapper also scans the child's output for the child's own `2031` switch, the
same shape as its alternate screen scan, with a carry across split reads, relays each report
verbatim while the child has asked, turns the terminal's copy of the mode straight back on when
a child withdraws it, and clears the child's request at every new prompt so a program killed
before withdrawing cannot leave the line editor receiving reports. Relaying whenever a command
is running is not enough, since a program that reads no input leaves the bytes in the terminal
buffer for the shell to read at the next prompt. Tests cover the strip, the last report
winning, the scan across a split read, and the carry length.

Never test any of this by launching a second iris from a shell that is behind iris without
scrubbing its six `IRIS_` variables. The new one takes the launch for a reload of the real one.

### The herdr descendant walk, not confirmed live

Where. `src/platform/macos.rs`, `src/platform/linux.rs`, `src/platform/fallback.rs`,
`src/platform/windows.rs`, `src/detect/mod.rs` and `src/pane.rs`. Pull request 3176 at
github.com/herdrdev/herdr is the reference and is still readable though closed.

The approach. A new `descendant_agent_job(shell_pid)` per platform. List every process once,
index by parent pid, which macOS already has in `pbi_ppid` and Linux in field one of
`/proc/<pid>/stat`, then walk breadth first from the pane's shell pid, wrapping each visited
process in a one process job and returning the first one `identify_agent_in_job` recognises,
with a scan limit of about a hundred and twenty eight so a deep tree cannot cost the poll.
Windows already walks the tree and returns nothing here. In `src/pane.rs`, the probe that
already calls `foreground_job` and identifies the agent in it falls back to the walk only when
that identification yields nothing, so every pane that worked before is untouched, which is the
objection upstream raised. A pane running no agent finds nothing, so a helper process is never
promoted.

The test that was missing upstream. The only wrapper test at 0.9.0 spawns its agent as a
background job of the same non interactive shell, which never leaves the pane's process group
and so passed before the walk existed. The one to add puts the agent behind `script`, on macOS
`script -q /dev/null bash -c 'exec -a claude sleep 999'` and on Linux `script -q -c "..."
/dev/null`, waits half a second, and asserts that `foreground_job` finds no agent and the walk
finds claude, killing the descendant's group before the pane's since the agent lives in a
session of its own. A second test spawns `sleep` as an ordinary child and asserts the walk
finds nothing. Both passed on macOS on 2026-09-16 in a build of the branch. The whole binary
suite passed except two plugin tests that share a global config directory and fail in parallel
whichever pair races, which pass serially and touch nothing the branch touches.

Building it needs Rust through rustup and Zig 0.15 for a vendored terminal parser, whose build
fetches dependencies on a cold cache and fails with a hostname error in a sandbox with no
network. The binary went into `~/.local/bin`, ahead of the Homebrew prefix on the PATH, and
herdr's `[update] version_check = false` was set so it would not offer to replace itself.

## Rejected

- **A fixed hex selection bar with a fixed `match`.** 2026-09-14, before 8f21edf. Only clears a
  bar that is very dark or nearly white, since `match` is drawn on the page on every other row
  and inside the bar on this one.
- **An inherited bar with inherited `match`.** 2026-09-14, before 8f21edf. Then the bar must be
  dark enough for the dark half's match colour and light enough for the light half's at once,
  which lands at 2.05 on slot 8, 1.08 on slot 4 and 1.27 on slot 7. Measured, every single file
  alternative. There is no single bar, which is why the feature exists.
- **Treating `IRIS_TERM_BACKGROUND` as an override.** 2026-09-14, before 8f21edf. It reaches the
  shell too, so an iris started from that shell inherits it, and a decision about an earlier
  terminal outlived it and beat the one in front of you. Rewritten on every start now, a hand
  set value surviving only when the terminal declines to answer.
- **Configuring around the alias bug with `expand-alias`.** 2026-09-14, before 8f21edf. That
  option governs something else entirely, whether iris rewrites the literal prompt text on
  space. No configuration option touches the display bug.
- **Carrying the alias fix as a loose diff over the release binary.** 2026-09-14, before
  8f21edf. A fork with one commit per patch on its own branch is what lets each patch be
  offered back and measured against upstream independently.
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
  without scrubbing its environment.
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
  briefly, then withdrawn by Milos for the same reason as above.
- **`herdr integration install claude`.** 2026-09-14 about 21:40. Installs a SessionStart hook
  that sends only `pane.report_agent_session`. Session identity does not name a pane, and once
  a pane carries a session under `herdr:claude` no other source may ever name it. Neither
  `release-agent` nor `clear-agent-authority` undoes it. Installing it on this session's pane is
  why that pane never recovered. It also gives the one thing our source cannot, conversation
  resume after a herdr server restart. Reopened 2026-09-16 00:55 once the hook it blocked was
  gone. Not tried since, and with no proxy in front of the shell there is no reason to.
- **Fixing it inside iris.** 2026-09-14 about 23:05. Read `root/wrapper.go`. The shell is
  started with `Setsid` and `Setctty` at line 247, so it lives in its own session, and the outer
  terminal goes raw at line 274 so iris can read every key. A terminal can only have a
  foreground group from its own session, and iris has to stay foreground to read, so handing
  the group to the child is refused by the kernel and dropping `Setsid` costs the child its job
  control. What iris could do is lie, rewrite its own argv to claude or fork a decoy process by
  that name, and both would make every process tool on the machine wrong.
- **Hand written JSON onto the socket with `nc`.** 2026-09-14 about 21:55, superseded 22:45. The
  first shipped version, built on the belief that `herdr pane release-agent` could not parse its
  own arguments. It could. See the correction in the log.
- **Re announcing on every prompt so the report survives a herdr server restart.** 2026-09-15
  about 00:00. Probably harmless, but probably is not enough to justify a hook on every prompt
  for a scenario nobody has hit. Moot since the hook is gone.
- **Configuration options that do not exist.** 2026-09-14 about 23:20 and 23:35. Two suggestions
  arrived from elsewhere, a herdr re index command and an iris `ignore_processes` list. Herdr
  has no command matching index, rescan or refresh. Iris's config is TOML and its complete key
  list contains nothing resembling ignore, bypass or yield. Both came with real URLs whose
  content said something else. Verify a cited mechanism against the binary before trying it.
- **A Claude Code hook that reports the pane to herdr.** Shipped 2026-09-15 00:08 as c82178d,
  removed 2026-09-16 00:55. It names the pane and owns its state, so every session froze at
  idle, including sessions herdr could see by itself. The measurements are in the 2026-09-16
  00:43 entry.
- **inshellisense.** 2026-09-16 01:20. A PTY proxy with the same blindness as iris, and it
  excludes the aws, gcloud and az specs by design, which are the commands the dictionary is
  most wanted for.
- **ghost-complete.** 2026-09-16 01:20. The closest thing to iris, native, macOS, zsh auto
  trigger, but a PTY proxy by its own description, so it blinds the panel exactly as iris does.
- **zsh-autocomplete in place of fzf-tab.** 2026-09-16 01:30. The one in shell tool that opens
  the list as you type, so the closest feel to iris. Not taken because it owns compinit,
  repaints under the prompt on every keystroke, and pushes out an fzf-tab that is already wired
  and painted. Still the untried next step if Tab is ever not enough.
- **Autosuggestions and carapace with zsh's own menu, no fzf-tab.** 2026-09-16 01:32. Sound
  and the leanest of all, turned down only because fzf-tab was already there and costs
  nothing to keep.
- **A forked herdr carrying the descendant walk, pinned and built here.** Declined 2026-09-16
  01:05, built 14:50, given up about 16:55. The fix that costs nothing downstream and the only
  way to have both iris and the panel, and the price is a weekly rebase for as long as upstream
  declines, which for a project that refuses outside pull requests is forever. Iris went
  instead. The approach is written above so it can be rebuilt if upstream ever opens a door.
- **Scripts that watch upstream and prove whether a patch is still needed.** 2026-09-16 about
  16:10. Written for iris on 2026-09-14 and generalised to both forks on 2026-09-16, then
  removed with the forks. Sound machinery for a habit this repository has decided not to keep.
  A defect is written down with a reproduction and rechecked by hand when someone asks.
- **Iris itself.** 2026-09-16 about 16:55. Two of its defects were fixable and were fixed. The
  third is not its defect and is not fixable from its side, and the agents panel was worth
  more than its menu. It comes back only if herdr learns to look past the pane's foreground
  group, which the reproduction above is the test for.

## Log

The entries below were written in four files, `iris-appearance-theme.md`,
`iris-alias-display.md`, `herdr-agent-detection.md` and `shell-autocomplete.md`, and moved
here verbatim on 2026-09-16 when the four were merged. A reference to one of those files inside
an entry now means this file. Where two files had an entry at the same minute both paragraphs
sit under one heading.

### 2026-09-14, before 14:02

While building. An earlier version of the theme notes claimed palette slots did not work, on the
strength of a detector that matched only `38;2` and `38;5` sequences and never the `30` to `37`
range, so it reported zero colours while the menu was drawing in palette colours the whole
time. A detector that can only see one encoding reports the absence of every other one. That
mistake cost several rounds. Slots work because lipgloss turns `"4"` into `ansi.BasicColor(4)`
at `color.go:66-85`.

While building. The OSC 11 query paired the input tty with `os.Stdout`, and lipgloss refuses
unless both are terminals, which the watchdog's stdout is not always. Invisible, because
`HasDarkBackground` answers true for any error, so a query that never worked read as a terminal
that said dark. Asking through the tty iris already holds, via `BackgroundColor` so a failure
stays distinguishable from an answer, fixed it.

### 2026-09-14 14:02

8f21edf. Iris arrives from the fork with this branch merged.

8f21edf. Iris arrives, built from the fork rather than installed, because the released binary
has this defect and the appearance one and neither can be configured around. The build pins one
commit into `~/.local/bin`, so two machines build the same binary.

### 2026-09-14 14:12

c705467. Switching appearance with the menu open updated everything except the selection bar,
and closing and reopening the menu put it right. The terminal repaints its own palette, so
every slot coloured part followed the switch without iris doing anything, which made the switch
look like it worked. The bar is hex, so it stayed in the old appearance until something drew
the box again and nothing did. The half was reloading correctly the whole time and only the
repaint was missing. The pin moves to a fork that redraws the box on a switch, directly, since
the usual render path declines while the user is navigating, the moment a stale bar shows most.

### 2026-09-14 14:35

4361b76. `src/check-iris-upstream.sh` added, because a fork stops asking whether upstream has
moved. It reads the changelog rather than the log, tests each patch against vanilla upstream,
and rebases each in a throwaway worktree so a conflict is known before anyone commits to it.
It reports and changes nothing. Which branch to watch was settled once, `main`, since `dev`
reads like where new work lands and is not.

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

### 2026-09-15 09:31

Pushed, so the entry above is now stale in two ways and keeps its text under the contract. The
commit is no longer 48ed0c4, because integrating twelve commits from the other machine rebased
the seven local ones and 48ed0c4 became 88e2bc0. And it is no longer unpushed, since Milos asked
for it to go up once the integration was verified. The fork was already on GitHub throughout,
which was never optional, because the build script clones the fork from there rather than from
anything on this machine. So a second machine now gets both halves, the pin and the binary it
names.

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

### 2026-09-16 01:40

Milos chose to disable iris and run the in shell trio, and asked for both guides kept here
with versions and the date, since herdr may fix identification or the pull request may be
opened later. File created with the two guides and the version table. The change that follows
removes the iris line from the `.zshrc` template, adds carapace to the Brewfile, the map and
the zsh declarations, and sources it in `.zshrc.custom`.

### 2026-09-16 11:05

First real use, two screenshots from Milos. Typing `git` into the picker for git's own
subcommands kept sixty eight of a hundred and fifty nine rows, because fzf-tab matches the
query against the candidate and its description by default and carapace's descriptions all
say Git. Fixed with `--nth=2` in fzf-tab's `fzf-flags`, which lands after its own `--nth=2,3`
and fzf keeps the last. The picker also opened with four lines of group headers, since
carapace names a dozen groups for git alone, and every group in its own colour, blue,
magenta, yellow and cyan down one list, with a coloured bullet in front of each row. Headers
and bullets are off through `show-group none` and an empty `prefix`. The colours are
carapace's own, emitted as `list-colors` for every group and every flag arity, so they are
cleared at the source through the file `carapace --style` writes, stowed as a new `carapace`
package. Corrected 2026-09-16 11:35, see below, the colours were fzf-tab's and the style file
changed nothing visible. On macOS that file is under `Library/Application Support`, not
`~/.config`, because carapace asks Go for the user config directory, which was measured after
a first copy under `.config` changed nothing. Every key is `default`, so the row takes the
terminal foreground and only the description keeps carapace's faint attribute.

History matching, the other half of what iris gave, was already there and is worth naming.
The up arrow is atuin's search seeded with what is typed, since atuin binds it during init and
nothing here rebinds it, and the ghost text comes from atuin first, because atuin's init sets
the autosuggestions strategy to `atuin history`. An inline atuin, `style = "compact"` with
`inline_height` set in its config, would put that list under the prompt the way iris did, and
atuin's config is not managed here yet.

### 2026-09-16 11:35

Two more screenshots from Milos. The descriptions were ragged, the order looked odd, and Tab
on an empty line listed files where iris had listed history. The first two have one cause.
Carapace calls `_describe` once per group, ten times for git, and zsh's `compdescribe` pads
each call to its own longest name, capped by `max-matches-width` and never widened across
calls, read in `Src/Zle/computil.c`. The 11:05 change removed the `format` style for
descriptions, and that style is the only thing that makes `_description` pass `-X`, which is
the only thing fzf-tab reads a group from. So ten blocks, each aligned to itself, merged into
one alphabetical list and the padding showed. Restoring the groups was measured against and
turned down, carapace orders its tags by name, so main commands would sit eighth behind
external and low-level ones, and without the colour legend nothing would say where one block
ends.

The fix is a tab in front of the separator, `list-separator` set to a tab and `--`, and
`--tabstop=24` on fzf. fzf expands a tab to the next multiple of the stop counted from the
start of the row, in `util.StringsWidth`, so every row lands on column twenty four whatever
its group padded to. Every git subcommand is under that, and a longer name moves only its own
description to the next stop. It is two documented options and the whole of what is needed.
The lasting fix belongs in carapace, one `_describe` call for all groups, and is not filed.

Correction to 11:05. The colours in the first screenshot were fzf-tab's group colours, not
carapace's. fzf-tab writes each group's colour in front of its rows with no reset and stacks
the group names at the top as a legend for those colours, which is where the four coloured
header lines and the coloured bullets came from. fzf-tab applies `list-colors` to files only,
so carapace's per group `list-colors` never reached the picker and the styles file stowed at
11:05 changed nothing anyone saw. The colours went at 11:05 because the format style went and
the groups with it. The carapace stow package is removed, carapace's own styles stay at their
defaults, and `show-group` and `prefix` are gone too since with no groups they had nothing to
act on. What keeps the picker plain is the absence of a format style, and `.zshrc.custom` now
says so.

A scripted zsh under zpty never accepted a keystroke in this session, with Powerlevel10k's
gitstatus unable to start under the tool sandbox, so this change is verified by reading the
three sources rather than by a captured picker, and the next Tab in a new pane is the test.

History is not a Tab thing here. Tab on an empty line is completion and lists files, which is
what zsh has always done. The up arrow is atuin seeded with what is typed, ctrl+r is atuin's
full search, and the grey ghost text is atuin's best match. Iris folded history into the same
menu as commands and that is the one thing this stack does not reproduce.

### 2026-09-16 12:10

Iris is back. After the tab stop fix Milos tried the stack in a herdr pane and rejected it
outright. `cd home-` and Tab inserted the one match with no menu, the picker has a search
row of its own under the prompt instead of filtering on the command line, it opens large
outside tmux where there is no popup, and typing `herdr` and Tab listed the command and six
environment variables with none of the history that iris would have shown first. He had been
satisfied with iris and said so. None of that is a setting. fzf-tab is a Tab picker with its
own query line and no history, and no amount of tuning makes it the inline menu iris draws.

Offered three ways, iris back, zsh-autocomplete as the closest in shell feel with the list
under the prompt filtered by the line itself and ctrl+r flipping it to history, or a smaller
fzf-tab that would not have answered the complaint. Milos chose iris back. The template line
is restored with a note on why it was out, `~/.zshrc` regenerated, and fzf-tab with carapace
stays underneath since Tab reaches the shell whenever the iris menu is closed and the aligned
picker is better than zsh's own listing there. The herdr agents panel is blind behind iris
again, by choice this time, and guide two is the way to get it back.

zsh-autocomplete is not tried and not rejected. It is the next thing to try if the panel is
ever wanted more than the iris feel, and it is a template change since it owns compinit.

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

Guide two is no longer hypothetical. herdr is built from a fork carrying the descendant walk,
so a session behind iris reaches the agents panel and iris keeps its menu. What changes on the
shell side is nothing. The trio stays exactly where it was, under iris, answering Tab whenever
the iris menu is closed. Both iris patches were reproved against unmodified upstream on the
way, and both are still needed.

### 2026-09-16 about 16:55

Milos undid it all, and this file is the result. Homebrew herdr is back, iris is removed, the
fork mechanism, its two engines and its skill are gone, and the four decision files are merged
into this one with every entry above kept verbatim. His reasoning, in his words as near as
matters. The herdr fix is not confirmed live and will not be, since the fork was only a bypass
that costs a rebase every week for a project that refuses outside pull requests, and iris was
the only reason to want it. What he wants instead is one document from which the two iris
fixes and the herdr approach can be rebuilt, with the versions and dates and the upstream links,
so that when herdr is updated he can ask whether they fixed it and get an answer from the
reproduction rather than from a script. The rules for checking upstream are plucked out
completely, and the general layer of the repository names no tool.

What was done on the machine. The iris package unstowed, `~/.local/bin/iris` and
`~/.local/bin/herdr` removed with the build caches and stamps, so `herdr` resolves to the
Homebrew binary again, which is what the running server always was. The zig formula the build
needed uninstalled, and Homebrew's autoremove took the LLVM it depended on with it. The zshrc
template no longer execs anything and was regenerated, so a new shell is plain zsh with the
trio. The herdr config no longer turns the update check off.

What was done in the repository. `forks/`, `src/check-forks.sh`, `src/build-forks.sh`, the
`carried-forks` skill and `dotfiles/iris` deleted. herdr back to a formula in the Brewfile, the
map and its module manifest. The go, rustup, zig and gh lines removed from the map and the
Brewfile, since nothing declares them now, which leaves the formulae installed on this machine
and only unlisted. The reconciler no longer reads a forks directory. The root guide's fork
section is replaced by one that says this repository builds nothing from a fork and why, and
points here. The iris section is gone from the root guide, the herdr module guide carries a
short note on the limitation pointing here, and the theme guide no longer lists iris among the
painted tools.

What to expect in herdr. Nothing on the server side changes, it was never running the fork.
Panes opened before this keep their iris until the shell restarts, so a new pane is the test.
A session started in a new pane appears in the agents panel by itself and its state follows
the screen, because nothing holds the pane's terminal any more.
