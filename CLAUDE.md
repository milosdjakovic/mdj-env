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

# Rewrite every tool's theme file from the one palette, and report any that had drifted.
# Run after changing a colour, then commit what it regenerated. --show prints every role.
./src/check-theme.sh
./src/check-theme.sh --show

# Set default editor for dev file types manually (setup-dev-defaults.sh asks which app, Enter skips)
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
- `theme/` - The one palette every tool is painted from, and the contract for adding a tool

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

### Colour, and the one place it is declared

`theme/` holds the palette, and every tool that has a theme is painted from it by a generator
that lives with the tool. Read `theme/CLAUDE.md` before adding or changing a colour anywhere
under `dotfiles`, and before adding a tool that has a theme. The short version is three
layers. The palette knows nobody, plain colours by name plus which colour answers each role.
A map at a tool's package root knows only that tool's keys and points each at a role, never a
colour. An emitter beside it knows only that tool's file syntax and writes the generated file.
`src/check-theme.sh` is the root that ties them, module agnostic the same way
`check-dependencies.sh` is, and it regenerates every file and reports any that had drifted.

The generated files are committed, so a fresh machine generates nothing and stow puts them
where each tool reads them. `theme/active.toml` says which palette paints each half and
whether the machine follows the system or is held to dark or light, and that word never
reaches a running tool, it decides what is written into both halves when the files are
generated, so holding a half adds no watcher and no dependency. A hex value written into a
tool's config by hand is the drift this exists to end, and the checker names it.

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

What this layer guarantees is that everything declared is present, and only that. It does not
move a thing already present to a newer version, because nothing here is pinned to a version
and a setup run has no reason to change one on the way past. Upgrading is a deliberate act
taken on its own, the same way the Neovim lockfile is. `decisions/homebrew-upgrades.md` has
the reasoning and what it cost to learn.

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

**Stowed by default:** ghostty, tmux, nvim, zsh, hammerspoon, claude, lf, lazygit, herdr

**Available but not stowed:** alacritty, kitty, wezterm, mole

fut was carried here too, installed and never stowed, and was dropped on 2026-09-24 since
nothing ran it. `decisions/fut-vs-herdr.md` keeps what was measured, so it can be rechecked.

mole is the odd one there. It declares a tool and ships no
configuration at all, because mole writes its own two config files through its own interactive
commands and neither has ever been written on this machine. The module exists so the layer
knows a fresh machine needs the tool, which it did not before, and it joins the stow list the
day there is a whitelist worth keeping. `dotfiles/mole/CLAUDE.md` says what has to happen then,
starting with a `NO-FOLD` declaration, since mole writes a debug log beside its config.

Each package mirrors the home directory structure (e.g., `dotfiles/nvim/.config/nvim/` → `~/.config/nvim/`)

### Putting this on another machine

`./setup.sh` is the whole answer and it is meant to be run on a machine that is already in
use, not only on a blank one. Four things make that true, and each of them replaced a
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

**A directory the configured program writes into stays a real directory.** Stow folds a whole
directory into one symlink when the path is not there yet and one package supplies it, which is
wanted everywhere else, since a file added inside an already linked package then appears without
restowing. It is wrong where the program writes its own state beside its config, because the
fold points that state at this checkout and the program's sockets, logs and caches land in the
repository. Which directories those are is a module fact, so a module declares its own in a
`NO-FOLD` file at its package root and the stow step finds them by name, the way the reconciler
finds a collector or a prober. It refuses a declaration the package supplies no directory for,
makes each one real before linking, unfolds a machine where one is already a symlink into this
checkout and moves the untracked files back to the home directory, and fails after stowing if
any of them is a symlink again. Declaring is opt in,
because one folded directory here is deliberate. `decisions/stow-folding.md` has the whole of
it, the rejections first.

**An app Homebrew did not install is left alone.** `brew bundle` adopts an existing app into
a cask install and cannot be told not to, and a cask that then fails, on a password nobody can
type, rolls back and deletes the app it adopted, which is how a Docker.app was lost. So
`install-homebrew-packages.sh` skips any cask whose app is already on disk but not Homebrew's,
and says so at the end. `decisions/homebrew-upgrades.md` has it.

**What a step asks of you is said again at the end.** An unfold owes one line, that the program
writing into that directory has to be restarted, and printed where it happens that line sits at
line twenty of a two hundred line run, which is how it was missed the one time a machine needed
it. So a step says such a line through `mdj_note` in `src/lib/backup.sh`, which prints it in
place and, inside `setup.sh`, also into a notes file the run repeats in its closing block, on an
abort as well as on a finish. A step run alone finds no notes file and says its line once. This
is the same argument as the backup listing, and it is the channel for anything else a step
cannot finish by itself.

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
otherwise stops to ask for it. The guard is the condition Homebrew itself checks before any
formula without a bottle, which is the command line tools installed with an SDK for the running
macOS. Homebrew reads the SDK from the command line tools whenever they exist, whatever
`xcode-select` points at, so asking `xcode-select -p` as the guard once did let an old Xcode or
tools from before a macOS upgrade through, and the Homebrew step then failed. It installs
headless through `softwareupdate` first, the way Homebrew's own installer does, which asks for a
password, and falls back to Apple's dialog. It is the one step that stops the run when it cannot
finish, since the steps after it would fail less legibly. `decisions/developer-toolchain.md`
has it.

The `hs` CLI used to be listed here as a manual step too, and it never was one. The Hammerspoon
cask declares the copy inside the app bundle as a binary artifact, so Homebrew symlinks it into
the prefix as it installs the app, which is where the one on this machine came from, to the
second. Calling `hs.ipc.cliInstall()` from the config would have made that worse rather than
better, since it defaults to `/usr/local`, which is root owned, and pointed at the Homebrew
prefix instead it finds a bin link it did not make and no man page beside it, calls that broken,
and declines to repair it while saying so on every load. The map calls it a cask now, like every
other command a cask ships.

What no script can do is the part macOS will not allow, and the default editor is the newest
of those. On macOS 27 changing a file type's default handler raises a dialog for the person to
answer, and `duti` returns success the moment it has asked, so `set-dev-defaults.sh` reads
every handler back rather than trusting that answer, reports an extension still on its old
handler as pending rather than as bound or failed, and exits zero on it. Which editor is asked
rather than assumed, since it is a personal choice, and a run with no terminal skips the step
with a note. A fresh machine will see one dialog per typed extension on its first run, up to
forty, and the step says to run it again once they are answered. On a machine already on the
chosen editor it says one line. `decisions/dev-defaults.md` has the measurement. Two others are now
declared gates rather than prose. The Accessibility grant, which the whole Hammerspoon module stands on,
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

`settings.json` is not tracked in the repo because Claude Code modifies it
directly. Since it is not stowed, the keys that point at the stowed scripts cannot be
symlinked in, so `src/setup-claude-settings.sh` merges them into `~/.claude/settings.json`
with `jq` and runs from `setup.sh` after stow. It writes two things, the `statusLine`
command and `theme = "auto"`, because Claude Code paints hex
colours per theme rather than palette slots and only `auto` makes it ask the terminal which
half it is on. A fresh install defaults to `dark`, which is why the second machine showed the
dark half's slash command blue on a light terminal. `decisions/claude-code-theme.md` has it.
`jq` is in the Brewfile because the statusline script and this merge both depend on it (macOS
ships `jq` since 15, but the Brewfile guarantees it).

That merge used to exit the moment it found a `statusLine` key already set, which made it a
script that could configure a machine exactly once and never again. Anything added under
that guard would have reached every new machine and no existing one, so it now builds the
settings it wants, compares, and writes only on a difference. Foreign keys survive, so Claude
Code's own writes and anything added by hand are left alone. It also prunes a retired hook of
ours from every event it was wired into, so a machine that carries it is repaired by the same
run. `setup-zshrc.sh` carried the same trap and was rebuilt on the same pattern, comparing the
whole file it would write rather than grepping for one line, so both steps now reach a machine
that was set up before the change.

Nothing here announces a session to anything else. A hook that told another program which
pane a session was running in was tried and removed, because the program it told treats a
reported state as the pane's authority and the session then never moved off the state the
hook announced. `decisions/iris.md` has the measurements.

### Upstream defects, and what this repository does about one

Nothing here is built from a fork, pinned to a commit, or patched around a defect upstream has
not fixed. That was tried in September 2026 for two tools at once and undone the same day,
because a pin stops taking upstream's releases the moment it is set and the price is a rebase
every week for as long as upstream declines, which for a project that refuses outside pull
requests is forever. `decisions/iris.md` is the record and the reason, and it is written so
each fix can be rebuilt from the description alone if that is ever wanted again.

What is done instead is to write the defect down where it can be rechecked. The tool, its
version, the mechanism in the tool's own source, a reproduction anyone can run, the upstream
links where it is reported, and the date. A tool that is more trouble than it is worth at that
version is removed rather than carried, and the record says what would have to change upstream
for it to come back. Any question about whether upstream has since fixed something starts from
that record, the reproduction first, and never from a script that watches for it.

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

### Ghostty

Configuration in `dotfiles/ghostty/`. See `dotfiles/ghostty/CLAUDE.md` for the generated theme
pair and the reload keystroke, the four slots it declares for fzf, tmux and the Claude
statusline, and why ANSI black and white swap by half.

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
