# Shell autocomplete, and what it costs the herdr agents panel

Status. Iris runs again as of 2026-09-16 12:10, after half a day on fzf-tab with carapace,
and the herdr agents panel stays blind to sessions behind it. The in shell stack stays
underneath as what Tab does when the iris menu is closed. The way to get the panel back is
the herdr change in guide two, still unfiled.

## Now

Herdr names an agent pane by listing the foreground process group of the pane's own terminal.
A PTY proxy holds that terminal and runs the shell on a second one in its own session, so
nothing the shell runs is ever in the group herdr lists, and a Claude session behind the
proxy never reaches the agents panel. Iris, ghost-complete and inshellisense are all that
shape. Anything sourced from `.zshrc` runs inside zsh and never causes it. Reporting the pane
from a Claude Code hook does not fix it, since a reported state becomes the pane's authority
and freezes it, which `herdr-agent-detection.md` records.

So the choice is between an autocomplete that draws its own menu and a panel that works,
and the panel won. Corrected 2026-09-16 12:10, see below, the menu won after half a day. The
stack under it is zsh-autosuggestions for grey ghost text from history, fzf-tab
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

### Guide one, the in shell stack, which ran for half a day and now sits under iris

1. Disabling iris is removing `eval "$(iris init zsh)"` from the `.zshrc` template in
   `src/setup-zshrc.sh` and rerunning the script. The iris package stays stowed,
   `src/build-iris.sh` still builds it and `src/check-iris-upstream.sh` still watches
   upstream, so putting it back is the same one line above the Powerlevel10k instant prompt.
   Since 12:10 on 2026-09-16 the line is in.
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
changed nothing visible. On macOS that file is under `Library/Application Support`, not `~/.config`, because
carapace asks Go for the user config directory, which was measured after a first copy under
`.config` changed nothing. Every key is `default`, so the row takes the terminal foreground
and only the description keeps carapace's faint attribute.

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
