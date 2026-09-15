# Shell autocomplete, and what it costs the herdr agents panel

Status. Iris is disabled as of 2026-09-16 and the shell runs zsh-autosuggestions, fzf-tab and
carapace, all inside zsh, so herdr sees every session. Iris stays built and stowed so it can
be re-enabled with one line if herdr ever learns to see through a pty proxy.

## Now

Herdr names an agent pane by listing the foreground process group of the pane's own terminal.
A PTY proxy holds that terminal and runs the shell on a second one in its own session, so
nothing the shell runs is ever in the group herdr lists, and a Claude session behind the
proxy never reaches the agents panel. Iris, ghost-complete and inshellisense are all that
shape. Anything sourced from `.zshrc` runs inside zsh and never causes it. Reporting the pane
from a Claude Code hook does not fix it, since a reported state becomes the pane's authority
and freezes it, which `herdr-agent-detection.md` records.

So the choice is between an autocomplete that draws its own menu and a panel that works,
and the panel won. The stack is zsh-autosuggestions for grey ghost text from history, fzf-tab
for an fzf picker on Tab, and carapace underneath as the dictionary, roughly a thousand
commands with flag and value descriptions, including git, aws, gcloud, az, docker, kubectl,
gh, npm and nvim, and live values such as branch names, container names and cloud profiles.
The first two were already in the zsh package. Carapace is one Brewfile line, one map line,
one declaration and two lines in `.zshrc.custom`.

Versions at the time of the decision, 2026-09-16.

| tool | version |
|---|---|
| macOS | 27.0 |
| zsh | 5.9 |
| herdr | 0.9.0, Homebrew formula, source at github.com/herdrdev/herdr tag v0.9.0 |
| iris | fork build 0.7.0+mdj.b8b7ac8, upstream base v0.6.4 nightly, commit b8b7ac8 of 2026-09-15 |
| Claude Code | 2.1.273 |
| carapace | 1.7.3 |
| fzf | 0.74.4 |
| atuin | 18.22.0 |
| zsh-autosuggestions | 85919cd, 2025-06-24 |
| fzf-tab | fc6f0dc, 2025-07-11 |
| fast-syntax-highlighting | 3d574cc, 2025-07-16 |

The two guides below are the whole of what a future change needs.

### Guide one, the in shell stack, which is what runs now

1. The iris hook line is absent from the `.zshrc` template in `src/setup-zshrc.sh`. The iris
   package stays stowed, `src/build-iris.sh` still builds it and `src/check-iris-upstream.sh`
   still watches upstream, so re-enabling is putting `eval "$(iris init zsh)"` back above the
   Powerlevel10k instant prompt and rerunning the script.
2. carapace is `brew "carapace"` in the Brewfile, `carapace | brew | carapace` in
   `DEPENDENCIES.map`, and a line in `dotfiles/zsh/DEPENDENCIES` naming `.zshrc.custom`.
3. `.zshrc.custom` sources it after `oh-my-zsh.sh`, since carapace registers completion
   functions and needs compinit to have run, which oh-my-zsh does while loading. fzf-tab is
   an oh-my-zsh plugin and is already loaded by then. The order between carapace and fzf-tab
   does not matter, one supplies candidates and the other draws them.
4. Test in a new pane. `git ch` then Tab lists checkout and cherry-pick with descriptions in
   the fzf picker. `aws s3 ` then Tab lists subcommands with descriptions rather than files.
   Start claude in the pane and `herdr agent list` shows it, tracking working, blocked and
   done by itself.
5. If a picker on Tab is not enough and the list should open as you type, swap fzf-tab for
   zsh-autocomplete. It must be sourced first in `.zshrc` and every other compinit call
   removed, so it is a template change rather than a plugin list change. Carapace and
   autosuggestions stay. Never run fzf-tab and zsh-autocomplete together, both own Tab.

### Guide two, keep a proxy and teach herdr to see through it

The change is one function. In herdr's `src/platform/macos.rs`, `foreground_job` lists one
process group with `proc_listpids(PROC_PGRP_ONLY, ...)`. Add a descendant walk. When the
front group contains no known agent, list all pids once, index them by parent pid, which
`process_bsdinfo` already fetches as `pbi_ppid` and never reads, walk the children of the
front group's members, and for any child whose own terminal reports a different foreground
group, list that group too and fold it into the job. `identify_agent_in_job` in
`src/detect/mod.rs` then matches claude with no further change. The screen manifest, the
state engine and the notifications take an identity in and never ask how it was found, and
the proxy relays the child's screen verbatim, so nothing downstream changes. Mirror the walk
in `src/platform/linux.rs`. Add a test beside `foreground_job_detects_agent_behind_shell_wrapper`
that starts the agent behind `script -q /dev/null`.

1. Fork `github.com/herdrdev/herdr`, branch from the tag Homebrew installs, one commit with
   the walk and its test.
2. Open the upstream pull request first. The reproduction for a maintainer on any Mac is
   `script -q /dev/null zsh -f`, then `claude`, then `herdr agent list` shows nothing.
3. Until it merges, build locally the way iris is built. A `src/build-herdr.sh` pinned to the
   fork commit, installing into `~/.local/bin` so it wins over the Homebrew copy, and a
   `src/check-herdr-upstream.sh` in the shape of the iris one. Move `herdr` in
   `DEPENDENCIES.map` from brew to the built origin.
4. Restart the herdr server so the new binary runs, put the iris line back per guide one, and
   check a session behind iris with `herdr agent list` and `herdr agent explain`.
5. Record it here and in `herdr-agent-detection.md`.

Performance is negligible, herdr rechecks a pane every two to five seconds and the walk is
one process listing. The cost is the fork. Herdr released three times in the five weeks before
this was written, and a pinned build stops taking those until rebased, so this is sensible
only while the pull request is open. If upstream declines, either the fork becomes permanent
or the proxy goes and guide one applies.

## Rejected

- **A Claude Code hook that reports the pane to herdr.** 2026-09-16 00:43. It names the pane
  and owns its state, so every session froze at idle. Recorded in full in
  `herdr-agent-detection.md`.
- **inshellisense.** 2026-09-16 01:20. A PTY proxy with the same blindness as iris, and it
  excludes the aws, gcloud and az specs by design, which are the commands the dictionary is
  most wanted for.
- **ghost-complete.** 2026-09-16 01:20. The closest thing to iris, native, macOS, zsh auto
  trigger, but a PTY proxy by its own description, so it blinds the panel exactly as iris
  does. Set aside rather than refused, it is the candidate if the panel ever loses.
- **zsh-autocomplete in place of fzf-tab.** 2026-09-16 01:30. The one in shell tool that
  opens the list as you type, so the closest feel to iris. Not taken first because it owns
  compinit, repaints under the prompt on every keystroke, and pushes out an fzf-tab that is
  already wired and painted. Listed in guide one as the next step if Tab is not enough.
- **Autosuggestions and carapace with zsh's own menu, no fzf-tab.** 2026-09-16 01:32. Sound
  and the leanest of all, turned down only because fzf-tab was already there and costs
  nothing to keep. Fuzzy narrowing in the picker is the one thing it would lose.

## Log

### 2026-09-16 01:40

Milos chose to disable iris and run the in shell trio, and asked for both guides kept here
with versions and the date, since herdr may fix identification or the pull request may be
opened later. File created with the two guides and the version table. The change that follows
removes the iris line from the `.zshrc` template, adds carapace to the Brewfile, the map and
the zsh declarations, and sources it in `.zshrc.custom`.
