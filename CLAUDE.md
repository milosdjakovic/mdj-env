# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

macOS development environment bootstrap and dotfiles management using GNU Stow. All dotfiles are symlinked from `dotfiles/` to `$HOME` via stow.

**Per-module CLAUDE.md convention.** Before touching any module under `dotfiles/` (nvim, kitty, ghostty, hammerspoon, tmux, lf, …), first read that module's own `CLAUDE.md` if it has one — it holds the reload/apply steps, gotchas, and conventions specific to that tool, and the section below links to it. If the module has no `CLAUDE.md` yet, propose adding one (and offer to write it) so the knowledge you just used or discovered is captured for next time; if it has one, keep it current as you change things. Treat a missing or stale module `CLAUDE.md` as part of the work, not an afterthought.

## Commands

```bash
# Full setup (run once on new machine)
./setup.sh

# Run individual setup scripts
./src/install-xcode-clt.sh
./src/install-homebrew.sh
./src/install-homebrew-packages.sh
./src/install-ohmyzsh.sh
./src/install-ohmyzsh-plugins.sh
./src/install-tmux-plugins.sh
./src/setup-stow-dotfiles.sh
./src/setup-zshrc.sh
./src/bootstrap-nvim.sh
./src/setup-dev-defaults.sh
./src/setup-capslock-hyper.sh
./src/setup-ivpn-permissions.sh   # repairs bundle modes the ivpn cask leaves wrong; needs sudo only when repairing
./src/setup-claude-settings.sh
./src/setup-herdr-plugins.sh
./src/check-dependencies.sh

# Ask what upstream iris has done since the fork branched, and whether either patch is
# still needed. Reports only, it never moves the pin.
./src/check-iris-upstream.sh

# Set default editor for dev file types manually (setup-dev-defaults.sh defaults to Zed)
./src/set-dev-defaults.sh "Zed"
./src/set-dev-defaults.sh "Visual Studio Code"

# Manual stow operations (from dotfiles/ directory)
cd dotfiles
stow -t ~ <package>           # Symlink a package
stow -t ~ --adopt <package>   # Adopt existing files and symlink
stow -D -t ~ <package>        # Unlink a package
```

## Architecture

### Directory Structure

- `setup.sh` - Main orchestrator that runs all scripts in sequence
- `Brewfile` - Homebrew packages and casks
- `DEPENDENCIES.map` - where each tool a module declares comes from
- `src/` - Modular setup scripts (all idempotent, support Apple Silicon and Intel)
- `dotfiles/` - Stow-managed configurations, each subdirectory is a stow package
- `decisions/` - What was tried, rejected and corrected, one dated file per topic

### Decisions, and when to read them

`decisions/` holds the record that neither the commit log nor this file can. A commit says
what changed at the moment it changed. This file and the module ones say what is true now and
why. Neither says what was already tried here and turned down, because a rejected approach
never reaches a commit and a current truth file has no room for history. That is what
`decisions/` is for, one file per topic, each with the current stance, every rejected approach
with its date and reason, and a dated log that is only ever appended to. A wrong entry keeps
its text, gains a line saying when it was corrected, and a new entry says what is true instead.
The wrong belief and the date it was held are part of the record.

Two rules follow, and `decisions/README.md` carries the full contract.

Read before proposing. Any change in an area that has a file there starts by reading that
file, the Rejected section first. Proposing something already listed there without saying why
the rejection no longer holds is the failure the directory exists to prevent.

Write in the same change that moves behaviour. A decision, a rejection, a bug found, a belief
corrected, each is recorded as it happens, with the date and the time, since afterwards the
reasoning is gone. A topic with no file gets one the first time it produces a decision worth
keeping. `check-dependencies.sh` verifies the index and the shape of every file, so a file
that drifts from the contract is reported rather than discovered.

### Dependencies, and which layer knows what

**A module declares what it needs on the machine and installs nothing.** That is the
whole rule. A module names a tool and says what breaks without it, and it never tells
anyone to install anything. This layer is the only place that runs a package manager,
and it is the layer responsible for making every declared thing actually present and
actually configured.

A module MAY say where a tool comes from, and that is a recent change worth being
precise about, since the older rule said it must not. The thing that was never allowed
is naming an install command, because that duplicates an answer this layer already
holds and the two then drift apart. Saying that a tool is the `displayplacer` formula
is not that. It is a fact about the tool, and a plugin built to travel to another
machine has to carry it, since this repository's map will not be there. So an origin
may sit in a declaration, the map at the repository root stays the complete answer key
a person reads, and the reconciler refuses any disagreement between the two. That is
what makes writing it twice safe rather than a source of drift.

A module exposes its needs in one `DEPENDENCIES` manifest at its own package root,
name, kind, locator, policy, consumer, and reason, then origin and origin detail where
the declaration states one. That file is its entire contract upward. How the module
produces it is the module's own business. A module with no moving parts writes it by
hand. A module built around swappable units generates it instead, from declarations
that live with whatever actually knows each tool, so a plugin, a provider, or an
adapter stays self contained. Hammerspoon and tmux both do this, each with its own
`dependencies-collect`, which the reconciler finds by name rather than by knowing
either module. The test of whether a module needs one is simple. If replacing a
swappable part would mean editing a manifest that sits outside it, the manifest is a
leak and should be generated.

Where those inner declarations live is also the module's own business, and the two
modules answer differently. tmux keeps small data files beside each unit. Hammerspoon
keeps them inside each plugin's `manifest.lua`, under `needs.tools`, which is the same
file the running config reads, so one tool is described exactly once. That choice has a
consequence for the collector, since a shell cannot read Lua, so the Hammerspoon
collector finds the manifests and hands them to a real Lua interpreter rather than
guessing at their shape with a pattern. Reading Lua needs Lua, so the module declares
it like any other tool. It is optional, because only regenerating the contract stops
working without it and the running config does not care.

Every one of these is repo only, so each package's `.stow-local-ignore` keeps the
generated manifest, the collector, its reader, and the module level declaration out of
the home directory.

The program a module configures is a dependency like any other, so the tmux module
declares tmux and the hammerspoon module declares the Hammerspoon application. A
configuration cannot work without the thing it configures, and declaring it is what
lets this layer guarantee it.

`kind` is how presence is proven. `path` for a command on PATH, `system` for a fixed
absolute path, `app` for a macOS bundle id, `manual` for a marker path, and `package`
for something that ships files rather than a command, where presence is proven by
asking the package manager instead of by probing a path, because the prefix differs
between machines and no module may know it. `policy` is `required` when the module is
broken without it and `optional` when only part of it degrades.

A gate is the sixth thing a module may declare and the one nothing can install. It lives in
its own list, `needs.gates` beside `needs.tools` in a plugin manifest, or a line in a module's
own hand written declaration, and the split is about who reads it rather than about tidiness.
A tool is a request to the resolver inside the running config, which probes for it and hands
back a path. A gate is not, so the door never sees one, which is why the two are separate lists
instead of one list with a flag on it. Two kinds are gates. `manual` is a marker path, proving
that a program has been opened once and written a file something here depends on, which is how
the Obsidian vault registry is declared. `grant` is a macOS permission.

A permission cannot be probed from the layer above, and the reason is worth stating rather than
rediscovering. macOS reports a permission for the process that asks, so a check run from a
setup script answers about the terminal it runs in, and would report granted on a machine where
the application in question is refused. A check that lies is worse than no check. Reading the
TCC database is the only other route and it needs Full Disk Access, which is another grant of
exactly the kind being checked, so that trades one gate for another.

So the reconciler delegates, the same way it already delegates manifest regeneration. A module
that declares a grant ships a `grants-probe` at its own package root, which the reconciler finds
by name rather than by knowing the module. It takes the locator the declaration carries, prints
one word, and exits zero. Exit 2 means this machine cannot answer right now, a machine fact and
a warning. Any other nonzero means the locator is not one that module understands, a repository
defect and an error. The vocabulary is three words, `granted`, `notDetermined`, and `denied`,
which is the distinction BrowserTabs settled on first. The last one matters most, since macOS
remembers a refusal forever and never prompts a second time, so the only route back is the pane
in System Settings. Which pane is not the prober's business either. That comes from
`DEPENDENCIES.map`, where every other answer to where something comes from already lives.

The Hammerspoon module's prober answers by asking the running config, because only Hammerspoon
can be asked about Hammerspoon. It is bounded, since the reply can go missing, and a setup step
that blocks forever is worse than one that says it could not answer. Every grant outcome is a
warning and never an error, because a grant is a fact about one machine.

This layer's own setup scripts declare too, in `src/DEPENDENCIES`, because tools like
stow and duti would otherwise be the one category nothing checks.

`DEPENDENCIES.map` joins a tool name to where it comes from, a Homebrew formula, a
cask, a third party tap, the Xcode command line tools, the operating system itself, or
a manual step whose detail says exactly what to do. The Brewfile carries the actual
install lines. So when a module declares something new, the work happens here. Add the
line to `DEPENDENCIES.map`, add the matching Brewfile entry for a package manager
origin, and for a manual origin make sure the detail says both how to install it and how
to configure it, since an installed tool that is unconfigured is still a broken
dependency. Never answer a missing tool by writing an install command into a module,
which is the leak this split exists to prevent.

`src/check-dependencies.sh` reconciles all of it, and runs at the end of `setup.sh` or
alone at any time. It regenerates every generated manifest so a stale one cannot be
committed, then reports these as errors, since each is a repository defect and identical
on every machine. A declared tool with no mapping. A mapping nothing declares any more. A
mapped formula missing from the Brewfile. A declaration whose stated origin contradicts
the map or contradicts another declaration of the same tool. A module that hardcodes an
install prefix, or probes for a tool itself instead of naming it, or names an install
command at all. And a module that RUNS a tool nothing declares, which is the check that
matters most and was the last one written, because a line that runs a tool looks like
ordinary code and names no prefix and no installer. It found three tools this repository
had never heard of, so the layer meant to guarantee they were present had no idea they
were needed.

The install command check matches every file type under `dotfiles` and under `src`, not only
the scripted ones, because the two real leaks it was written for were both help text, a
chooser row offering to copy a `brew install` line and a generator script telling you to run
one. Help text is not exempt, since it duplicates an answer the map already holds and the two
then drift apart with nothing watching.

It covers `src` because for a long time it did not, and the layer that owns the answer turned
out to be the likeliest place to reach for an installer. `set-dev-defaults.sh` probed for
`duti` and then installed it, three lines away from a declaration in `src/DEPENDENCIES`, a
mapping in `DEPENDENCIES.map` and a line in the Brewfile, and the check written to catch
exactly that had a blind spot over the whole directory. A rule this layer enforces on every
module and exempts itself from is not a rule. Widening it needed a left edge on the verb as
well, since `install-homebrew.sh` ends by reporting "Homebrew installed successfully" and
`brew installed` sits inside `Homebrew`. The reconciler excludes only itself, by path, because
it is the one file that has to write the verbs out in full.

Three things are only warnings. A declared tool not installed here, since an optional one
may legitimately not be wanted on this machine. A Brewfile entry nothing declares, since
the Brewfile is also a personal package list and an unclaimed entry is a question rather
than a defect. And a declared tool reached at its own fixed absolute path rather than
through the module's resolver, which is a real discipline break worth naming, but a path
under `/usr/bin` is the same on every machine, so unlike a Homebrew prefix it costs
correctness nowhere. It costs the console line an absent tool would otherwise produce.
Every warning names what it found so the question is answerable.

The script is module agnostic by construction, reading manifests and knowing no module
by name, so a future config joins in by writing a manifest, with no change to the
script.

Deciding whether something is genuinely a dependency, which origin it has, and whether
it is required or optional is judgment rather than pattern matching, so it belongs to a
person or to Claude reading the code. The reconciler only makes the result impossible
to drift unnoticed.

### Stow Packages

**Stowed by default:** ghostty, tmux, nvim, zsh, hammerspoon, claude, lf, lazygit, herdr, iris

**Available but not stowed:** alacritty, kitty, wezterm

Each package mirrors the home directory structure (e.g., `dotfiles/nvim/.config/nvim/` → `~/.config/nvim/`)

### Putting this on another machine

`./setup.sh` is the whole answer and it is meant to be run on a machine that is already in
use, not only on a blank one. Three things make that true, and each of them replaced a
behaviour that quietly did not.

**This repository wins, and what it displaces is kept.** Stow refuses to write over a real
file, and it aborts every package in the same invocation when it hits one, so a single stale
`~/.tmux.conf` used to stop the run before Neovim, the status line or the herdr plugin were
ever reached. `setup-stow-dotfiles.sh` now reads stow's own dry run, moves every path stow
names into `~/.mdj-env-backup/<timestamp>/` keeping its position under the home directory, and
then stows. It loops because clearing one conflict can uncover another under a folded
directory, and it is bounded so a loop that cannot converge says so. All three of stow's
conflict messages are handled, a plain file in the way, a symlink stow does not own, and a
symlink belonging to another package. Nothing is deleted. `setup-zshrc.sh` displaces the same
way, since `~/.zshrc` is generated rather than stowed and there is no symlink to make.

Restowing also clears links to files this repository used to have and no longer does, which is
the other half of overriding an outdated machine. That was verified rather than assumed, both
folded and unfolded.

**Neovim is pinned, and the pin is now actually used.** `lazy-lock.json` names an exact commit
per plugin, and `bootstrap-nvim.sh` used to run `Lazy! sync`, which is install, clean and
*update*, where update moves every plugin to its newest revision and then rewrites the
lockfile. So the second machine got whatever was newest that day rather than what this
repository pins, and because `~/.config/nvim` is a symlink into the repo, the rewrite landed
on a tracked file. It now runs install, clean and `restore`, which is lazy.nvim's own
documented answer for a config used on more than one machine. Updating stays a deliberate act,
performed here, recorded by committing the lockfile.

The same script also reconciles rather than guessing. It compares every name and every commit
in the lockfile against what is on disk, before and after, and fails with the list when
something does not converge. The old check looked for one directory, LazyVim's, and called the
job done, so a first run that died partway through was never retried.

**The lockfile records this machine.** When the two machines disagree, the fix is to capture
the good one rather than roll it back, which is
`nvim --headless -c 'lua require("lazy.manage.lock").update()' -c qa` followed by committing
the result. That is lazy.nvim's own writer, so the format cannot drift.

**The developer toolchain is installed rather than described.** Neovim's treesitter compiles
every parser on first open, and the Hammerspoon module compiles two small Swift helpers, the
eyedropper's colour sampler and the browser permission probe. So a machine without a compiler
loses all of that quietly and late, long after setup has said it was done. `DEPENDENCIES.map`
named `xcode-select --install` as the detail for `cc` and `swiftc` for a long time and nothing
ever ran it, which made it the one dependency this repository described instead of installing.
It is a command rather than a checkbox, so `src/install-xcode-clt.sh` runs it, first in
`setup.sh` because everything later that compiles wants it and because Homebrew's own installer
otherwise stops to ask for it. The guard asks `xcode-select -p` rather than testing a path,
since `/usr/bin/cc` is a stub present on every Mac whether or not a toolchain exists, and the
two real layouts keep the compiler in different places, so the stub proves nothing and only the
active developer directory answers for both. The dialog is somebody's to click, so the step
waits, bounded, and only when a terminal is attached, and a machine that never finishes gets a
warning rather than a failed run.

The `hs` CLI used to be listed here as a manual step too, and it never was one. The Hammerspoon
cask declares the copy inside the app bundle as a binary artifact, so Homebrew symlinks it into
the prefix as it installs the app, which is where the one on this machine came from, to the
second. Calling `hs.ipc.cliInstall()` from the config would have made that worse rather than
better, since it defaults to `/usr/local`, which is root owned, and pointed at the Homebrew
prefix instead it finds a bin link it did not make and no man page beside it, calls that broken,
and declines to repair it while saying so on every load. The map calls it a cask now, like every
other command a cask ships.

What no script can do is the part macOS will not allow, and two of those are now declared
gates rather than prose. The Accessibility grant, which the whole Hammerspoon module stands on,
is declared at that module's root and answered by its `grants-probe`. Obsidian's vault registry
is declared by the Obsidian plugin as a marker path, so a fresh machine is told to open the
application once rather than finding out later that the picker lists nothing.

Three are still only prose. Per browser Automation grants belong to BrowserTabs, and wiring them
into the same mechanism needs a seam inside Olm so a plugin can answer for its own grant, since
the only thing that can read one is the plugin's own compiled helper and the module level prober
must not reach into a plugin's cache to find it. Docker's first launch is deliberately not
probed, because asking the daemon is the call that hangs while Docker Desktop is starting, which
is why the processes plugin already refuses to ask it. And a VPN login is not readable at all on
the Mullvad side, which reports unavailable rather than logged out, so there is nothing to check
short of trying to connect.

### Claude Code

Configuration in `dotfiles/claude/.claude/` (stow managed):
- `commands/` - Custom slash commands (e.g., `/commit`)
- `skills/` - Skills scoped to this package
- `statusline-command.sh` - Custom status line script
- `hooks/herdr-agent-pane.sh` - Tells herdr this pane is running a session

`settings.json` is not tracked in the repo because Claude Code modifies it
directly. Since it is not stowed, the keys that point at the stowed scripts cannot be
symlinked in, so `src/setup-claude-settings.sh` merges them into `~/.claude/settings.json`
with `jq` and runs from `setup.sh` after stow. It writes three things, the `statusLine`
command, the two hook entries below, and `theme = "auto"`, because Claude Code paints hex
colours per theme rather than palette slots and only `auto` makes it ask the terminal which
half it is on. A fresh install defaults to `dark`, which is why the second machine showed the
dark half's slash command blue on a light terminal. `decisions/claude-code-theme.md` has it.
`jq` is in the Brewfile because the statusline script and this merge both depend on it (macOS
ships `jq` since 15, but the Brewfile guarantees it).

That merge used to exit the moment it found a `statusLine` key already set, which made it a
script that could configure a machine exactly once and never again. Adding the hooks under
that guard would have reached every new machine and no existing one, so it now builds the
settings it wants, compares, and writes only on a difference. Foreign keys survive, and a
hook group of ours is dropped and re-appended rather than stacked, matched on the script
path, so Claude Code's own writes and anything added by hand are left alone. The same trap
still sits in `setup-zshrc.sh`, which is worth knowing before changing what it generates.

### Why a session needs a hook to be visible to herdr

The rule is about wrappers rather than about any one of them. Herdr decides what an agent pane
is by reading the pane's foreground process, so anything that holds the pane's terminal and
runs the shell behind it on a pty of its own hides whatever is really running, forever. A pane
that fails that first check never has a title rule or a screen rule evaluated against it, so
the whole detection stack below is unreachable rather than wrong. Everything else already
worked. The OSC title a session sets matches herdr's claude manifest exactly, and once the pane
is identified that manifest takes over and reports working, idle and blocked correctly. Only
identification was ever missing.

Iris is the wrapper that happens to be here, which is why the panes that predate it are listed
and no pane created since is, and it is deliberately not what the fix is built around. Nothing
below reads an iris variable, asks whether iris is running, or changes if iris is replaced by
something else or removed entirely. That was measured rather than hoped for. On a pane built
with `IRIS_RESCUE=1`, where the shell is bare zsh and herdr names the agent by itself, the hook
firing changes nothing. The pane stays named, the manifest keeps deciding the state, and the
release at the end does not evict a session that is still running. So the hook is the answer
whenever a wrapper hides the process and a harmless no op whenever nothing does.

The general principle is worth keeping separate from this instance. Do not ask herdr to see
through a wrapper, and do not ask the wrapper to step aside, because the first is not in your
gift and the second costs the wrapper its reason to exist. Have the program that already knows
say so. Anything else added here that hides a process from the pane it runs in wants the same
shape, one hook belonging to the thing being hidden, announcing itself at its own boundaries.

`hooks/herdr-agent-pane.sh` runs `herdr pane report-agent` on `SessionStart` and
`herdr pane release-agent` on `SessionEnd`. Those two commands are documented as the way a
custom hook reports an agent, and the source id carries the `custom:` prefix the socket API
documents for a reporter that is not one of herdr's own integrations, so this is the
supported interface rather than a way around one. The hook is a no op anywhere the herdr
environment variables are absent, it never fails, and it reports nothing about state beyond a
seed, because herdr's own manifest is better at that than a hook can be.

Three things about it were measured rather than assumed, and each one cost a wrong turn.

The `HERDR_AGENT` hint that herdr's documentation gives for wrapper processes does work here,
and it is still the wrong tool. It is read from the foreground process environment, which is
fixed when iris is exec'd from the zshrc, long before anyone knows whether that pane will run
an agent. Scoping it means marking panes by hand, and setting it globally means every plain
shell pane claims to be a claude pane and joins the agents panel as an idle row.

Herdr's own claude integration, `herdr integration install claude`, installs a hook of very
nearly this shape and does not fix any of it. All it reports is session identity, and session
identity does not identify a pane. It is worse than useless here. Once a pane carries a
session recorded under the source id `herdr:claude`, herdr treats that pane as owned by its
own integration and refuses every other source, so installing it permanently blocks the thing
that does work. Nothing clears that claim short of closing the pane. So the source id in the
hook is this repository's name on purpose, and the integration must stay uninstalled.

The pane id is a positional argument and it comes first. Both commands reject it when it
trails the options, which reads exactly like a broken parser and is not one. Believing that
is what sent the first version of this hook off to hand write JSON onto the socket with `nc`,
carrying a paragraph here explaining why the CLI could not be used. The CLI could be used.
The lesson is narrow and worth keeping, which is that a nonzero exit from a compound shell
command belongs to the last command in it, not to the interesting one earlier in the line.

### Hammerspoon

Before changing any Hammerspoon file, read `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md` first — it holds the mandatory reload step (`hs -c "hs.reload()"` — note the parentheses; without them the command only references the reload function and silently no-ops) and the test-lock discipline, both easy to get wrong from memory.

Configuration in `dotfiles/hammerspoon/.hammerspoon/`. See `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md` for the leader-key model (META / SUPER / HYPER), the shared ChordKey hold/tap engine, the Chooser-based list tools and the checklist for wiring a new picker, the shared CheatSheet and HelperPanel canvas overlays, the launcher, menu search, clipboard preview, VPN, keep awake, the eyedropper colour picker, DisplayProfiles, and the conventions for structuring a spoon.

Testing a Hammerspoon change live goes through `bin/hs-devlock`, a machine-wide test lock, since only one config can run at a time. Take it only for testing, release it back to main the moment testing stops being the focus, and never hold it across development. The full discipline is in the hammerspoon `CLAUDE.md` under "Testing a change in an isolated worktree, and the test lock", read it before making any Hammerspoon config live.

**Never propose an Olm plugin. Only build one when explicitly asked for one.** This is
strict and it has no exceptions. Offering a plugin as one option among several is still
proposing it, and a choice made from a menu somebody else wrote is not a request. Work that
belongs to a shell, a config file, or a script is solved in that layer, and if there is no way
to solve it there, say so plainly and let the person decide rather than reaching up into the
layer that runs everything else on the machine. The rule exists because a shell colour problem
became a new plugin this way, built, gated, loaded, and then reverted in full.

Any work that creates or changes an Olm plugin goes through the `olm-plugin` skill at
`.claude/skills/olm-plugin/SKILL.md`. It carries the decision rules and the gates, and it
routes to the authoring guide and the contract inside the spoon. Do not build or modify a
plugin from memory of the contract, the skill exists because the contract moves.

BrowserTabs is the one config here with a test suite, in `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/plugins/browsertabs/test/`, run through its own `suite.sh` which takes the lock and gives it back. It is an integration harness by necessity rather than by preference, since every fault it guards against lives in Apple Events or the accessibility layer and no test with a fake browser in it could see any of them. Run it before merging a change to that plugin. Its README says what it covers, what it deliberately does not, and why a green run is regression protection rather than proof.

Worktree convention. When you create a git worktree for a feature or fix, put it under a `.worktrees/` directory in the parent of the repo (beside this checkout, so `../.worktrees/` from the repo root), named for the feature, so worktrees stay in one place rather than scattered as bare siblings of the repo. Because that directory is outside the repo, it never shows up in the repo's own status. Never write the absolute path, always reach it relative to the repo.

### Herdr

Configuration in `dotfiles/herdr/`. See `dotfiles/herdr/CLAUDE.md` for the popup surface and its
one frame one name rule, why the three tools are a linked plugin rather than keybindings, the
requirement that escape closes everything, never typing into a busy pane, the two ways context
arrives, why registration needs its own setup script, how to read a reload's diagnostics as a
test, and the current keys.

### Tmux

Configuration in `dotfiles/tmux/`. See `dotfiles/tmux/CLAUDE.md` for binding conventions, priority system, scoped fzf switchers, popup workarounds, and status bar details.

### lf

Configuration in `dotfiles/lf/`. See `dotfiles/lf/CLAUDE.md` for why lf was chosen over yazi, the tmux popup nesting limitation, command type differences, and custom keybinding details.

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.

### Iris

Shell autocomplete, configured in `dotfiles/iris/.config/iris/` and built rather than
installed, because the released binary has two defects this repository does not want to live
with. `src/build-iris.sh` compiles it from `github.com/milosdjakovic/IRIS`, pinned to one
commit, into `~/.local/bin`. Updating means moving the pin, the same ritual as the Neovim
lockfile, so two machines build the same binary.

The fork carries the two fixes on their own branches, each a single commit above upstream so
either can be offered back without being rewritten first.

Staying current is the thing a fork is bad at, so `src/check-iris-upstream.sh` keeps asking the
question a fork stops asking. It reports what upstream has released since the pin, reading the
changelog rather than the log because upstream writes one line per thing that changed where the
log writes one per merge, and then it answers for each patch whether vanilla upstream still
needs it. That answer is measured rather than guessed. It lays the branch's own tests onto an
unmodified upstream checkout and runs them there, so a branch whose tests pass on vanilla is
describing behaviour upstream now has and the branch can go, while one that fails or does not
compile is still earning its place. It also rebases each patch onto the new upstream in a
throwaway worktree, so a conflict is known before anyone commits to resolving it.

It reports and changes nothing, the same split `check-dependencies.sh` keeps, because every
answer it gives leads to a decision. Taking an update means rebasing the patches still needed,
merging them into the fork's main, moving `IRIS_COMMIT` and rebuilding. Dropping a patch means
deleting the branch and reverting its merge, not only leaving it unbuilt. If both patches ever
go, the fork goes with them and iris becomes an ordinary tap line again.

The only hand written part is the list of patches at the top of the script. Which test files
prove a patch, and which packages they live in, are read out of the branch itself, so a third
patch is one line and nothing else. Which branch to watch was also worth settling once.
Upstream has a `dev` branch that reads like where new work lands and is not, it forked in May
2026 and carries four commits nobody merged, while every release since has been cut from `main`
through pull requests. The script says so in a comment, so the guess is not made twice.

`fix/alias-display-preserves-typed-command` is upstream issue 158. Iris expands a shell alias
so the target's spec can answer, which it has to do, and then never puts the typed word back,
so with `cd` aliased to zoxide the rows read `z /path`. Ghost text dies from the same cause,
since it only draws when the top result has the literal buffer as a prefix and `z ` never has
`cd ` as one. One bug, two symptoms, and no configuration option touches it. `expand-alias`
governs something else entirely, whether iris rewrites your literal prompt text on space.

`feat/appearance-aware-theme` gives `theme.toml` optional `[dark]` and `[light]` tables over
its flat keys, and asks the terminal which it is in. Stock iris has one flat set of colours
and no idea what is behind them.

The hook `iris init zsh` emits ends in `exec iris`, replacing the shell with one running
behind a PTY proxy. That is why it sits at the very top of the generated `.zshrc` above the
Powerlevel10k instant prompt, and why the PATH line is hoisted above it. Painting a prompt
into a process about to be replaced leaves a screen p10k never gets to tear down. `~/.local/bin`
comes first on that line so the built binary wins over any package manager copy left behind.

Because iris reads every keystroke before the shell does, a key it claims never reaches zle at
all, whether its menu is open or not. That was measured rather than assumed. So `toggle-mode`
is moved to ctrl+o, leaving ctrl+r for atuin, and `navigate-closed` is `shell` so a bare up
arrow reaches atuin too. `atuin-history` is 1, so iris reads atuin's database rather than
keeping a second history of its own. `ghost-text` is 1, so the menu opens as you type and
Shift+Tab toggles it away again when the ghost text alone is enough. Setting it to 2 inverts
that, ghost text only until Shift+Tab asks for the menu, and 0 turns both off.

Holding the tty has one consequence that reaches outside iris entirely. Anything that
identifies a program by reading a pane's foreground process sees iris and never sees what is
running behind it, and herdr's agents panel is exactly that, which is why a Claude session
now announces itself through a hook. That hook is written for the class rather than for iris,
so replacing iris or dropping it changes nothing about it. The mechanism, the proof that it is
a no op without a wrapper, and the three wrong turns are under Claude Code above. Anything else
added here that expects to be recognised by the process it runs will need the same kind of
answer, and `check-dependencies.sh` now warns when the two things that silently break it
happen.

#### The theme

Almost every value is an ANSI palette slot rather than a hex colour, so Ghostty stays the one
owner of the palette. Slots work because lipgloss v2 turns `"4"` into `ansi.BasicColor(4)` at
`color.go:66-85`, which goes out as SGR `34` and lands on the terminal's slot 4. An earlier
version of this file claimed the opposite, on the strength of a measurement that only matched
`38;2` and `38;5` sequences and never looked at the `30` to `37` range, so it reported zero
colours while the menu was drawing in palette colours the whole time. A detector that can only
see one encoding reports the absence of every other one, and that mistake cost several rounds.

Slots are worth it because `aura-dark` and `aura-light` mirror each other by role, so slot 4 is
the primary accent on both and slot 8 is the comment grey on both. Slot 4 reads 5.77 to 1 on
the dark half and 4.83 on the light one, against 4.14 for the hand picked mid tone it replaced.
Change the Ghostty theme and the menu follows with no edit here.

`text` and the three idle tag backgrounds are deliberately unparseable rather than any colour,
because lipgloss renders an unparseable foreground unstyled, which inherits whatever the
terminal is painting, and does not draw an unparseable background at all. The second half is
what leaves a tag as a word on the page instead of a chip stamped onto it. Those chips were
dark blocks on a white page for a while, and fixing that is what the second half of this file
is for.

The `[dark]` and `[light]` tables exist for the selection bar and almost nothing else. A bar
has to be a tint of the page under it, and no slot is dark on the dark palette and light on the
light one. Every single file alternative was measured. Keeping the bar fixed forces `match`
fixed with it, since `match` is drawn on the page on every other row and inside the bar on this
one, and a fixed `match` only clears a bar that is very dark or nearly white. Letting the bar
inherit forces `match` to inherit, and then the bar has to be dark enough for the dark half's
`#ffca85` and light enough for the light half's `#6b4400` at once, which lands at 2.05 on slot
8, 1.08 on slot 4 and 1.27 on slot 7. There is no single bar, which is why the feature exists.

The bars are herdr's `selection_bg` and the secondary text its `subtext0`, so the two surfaces
agree rather than each inventing a highlight. `text_sel` and `sel_text` also flip, because each
palette keeps its ink in a different slot and because one palette's accents are the bright ones
where the other's are the dark ones.

The appearance is asked for once by OSC 11 in the watchdog, which is the only moment iris holds
the tty with nothing else reading it, and after that the terminal reports changes on its own.
The wrapper turns on DEC private mode 2031, so a switch arrives as `CSI ? 997 ; 1 n` for dark
or `; 2 n` for light and the half follows without opening a new shell. That report lands on the
same stream as keystrokes, so the wrapper takes it out of the input before the shell or any of
the key handling sees it, otherwise it is printed onto the prompt as text. Only whole sequences
are recognised, since holding back a partial escape sequence would delay the arrow keys, which
begin the same way.

Taking it out is right for the shell and was wrong for everything else, and that cost a day of
every layer above iris being stuck. A program behind iris that asks for the same reports never
received one, because the terminal sends a single copy and iris consumed it. Herdr was the worst
case, since Neovim, Claude Code and the iris inside each pane all ask herdr rather than Ghostty,
so one report lost in front of herdr left the whole tree on the old half while iris itself, the
layer that ate it, switched perfectly. So the wrapper now reads the child's own `2031` switch
off the pty, the same way it reads the alternate screen switch, and relays each report to the
child verbatim while the child has asked for them. Zsh never asks, so the prompt stays clean.
Iris keeps the terminal's copy of the mode on regardless, answering a child's withdrawal by
turning it straight back on, and drops the child's request at every new prompt so a program
killed before it could withdraw cannot leave the line editor receiving reports.

Reloading the half is only part of it, because the box also has to be drawn again, and for a
while it was not. A terminal that changes appearance repaints its own palette, so every part
of the box drawn in a slot follows along with no help from iris, which made the switch look
like it worked. The selection bar is hex, for the reason the paragraph above gives, so it
stayed in the old appearance while everything around it changed, and closing the menu and
opening it again put it right. That is what proved the detection was already correct and only
the repaint was missing. It is asked for directly rather than through the usual render path,
which declines while the user is navigating the menu, the moment a stale bar shows most.

Two mistakes in that detection are worth not repeating, since both produced a terminal being
served the wrong half while plainly saying which it was. `IRIS_TERM_BACKGROUND` carries the
answer down to the process that draws, and it reaches the shell too, so an iris started from
that shell inherits it. Treating it as an override meant a decision made about an earlier
terminal outlived it and beat the one in front of you. It is rewritten on every start now, and
a value set by hand survives only when the terminal declines to answer, which keeps it useful
as a fallback for a terminal with no OSC 11 without letting it go stale. Separately, the query
paired the input tty with `os.Stdout`, and lipgloss refuses unless both handles are terminals,
which the watchdog's stdout is not always. That failure was invisible because
`HasDarkBackground` answers true for any error, so a query that never worked read as a terminal
that said dark. Asking through the tty iris already holds, and going through `BackgroundColor`
so a failure stays distinguishable from an answer, fixes both.
