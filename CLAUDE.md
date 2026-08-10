# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

macOS development environment bootstrap and dotfiles management using GNU Stow. All dotfiles are symlinked from `dotfiles/` to `$HOME` via stow.

## Commands

```bash
# Full setup (run once on new machine)
./setup.sh

# Run individual setup scripts
./src/install-homebrew.sh
./src/install-homebrew-packages.sh
./src/install-ohmyzsh.sh
./src/install-ohmyzsh-plugins.sh
./src/install-tmux-plugins.sh
./src/setup-stow-dotfiles.sh
./src/setup-zshrc.sh
./src/bootstrap-nvim.sh
./src/setup-dev-defaults.sh

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

### Dependencies, and which layer knows what

**A module declares what it needs on the machine and installs nothing.** That is the
whole rule. A module names a tool and says what breaks without it. It never knows
whether that tool arrives by Homebrew, by a cask, or by hand, and it never tells
anyone to install anything. This layer is the only place that knows about package
managers, and it is the layer responsible for making every declared thing actually
present and actually configured.

A module exposes its needs in one `DEPENDENCIES` manifest at its own package root,
six fields per line, name, kind, locator, policy, consumer, and reason. That file is
its entire contract upward. How the module produces it is the module's own business.
Every module writes it by hand, except hammerspoon, which generates it from small
declarations placed beside whatever actually knows each tool, so a spoon and even a
single provider stays self contained. The manifest is repo only, so each package's
`.stow-local-ignore` keeps it out of the home directory.

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

This layer's own setup scripts declare too, in `src/DEPENDENCIES`, because tools like
stow and duti would otherwise be the one category nothing checks.

`DEPENDENCIES.map` joins a tool name to where it comes from, a Homebrew formula, a
cask, a third party tap, the Xcode command line tools, the operating system itself, or
a manual step whose detail says exactly what to do. The Brewfile carries the actual
install lines. So when a module declares something new, the work happens here and
nowhere else. Add the line to `DEPENDENCIES.map`, add the matching Brewfile entry for
a package manager origin, and for a manual origin make sure the detail says both how
to install it and how to configure it, since an installed tool that is unconfigured is
still a broken dependency. Never answer a missing tool by editing the module to
mention Homebrew, which is the leak this split exists to prevent.

`src/check-dependencies.sh` reconciles all of it, and runs at the end of `setup.sh` or
alone at any time. It regenerates every generated manifest so a stale one cannot be
committed, then reports a declared tool with no mapping, a mapping nothing declares any
more, a mapped formula missing from the Brewfile, any module that hardcodes an install
prefix or probes for a tool itself instead of naming it, and any module that names an
install command at all. That last one matches every file type under `dotfiles`, not only
the scripted ones, because the two real leaks it was written for were both help text, a
chooser row offering to copy a `brew install` line and a generator script telling you to
run one. Help text is not exempt, since it duplicates an answer the map already holds and
the two then drift apart with nothing watching. Those are errors, because they are
repository defects and identical on every machine. Two things are only
warnings. A declared tool not installed here, since an optional one may legitimately
not be wanted on this machine, and a Brewfile entry nothing declares, since the
Brewfile is also a personal package list and an unclaimed entry is a question rather
than a defect. The warning names the entry so the question is answerable.

The script is module agnostic by construction, reading manifests and knowing no module
by name, so a future config joins in by writing a manifest, with no change to the
script.

Deciding whether something is genuinely a dependency, which origin it has, and whether
it is required or optional is judgment rather than pattern matching, so it belongs to a
person or to Claude reading the code. The reconciler only makes the result impossible
to drift unnoticed.

### Stow Packages

**Stowed by default:** ghostty, tmux, nvim, zsh, hammerspoon, claude, lf, lazygit

**Available but not stowed:** alacritty, kitty, wezterm

Each package mirrors the home directory structure (e.g., `dotfiles/nvim/.config/nvim/` → `~/.config/nvim/`)

### Claude Code

Configuration in `dotfiles/claude/.claude/` (stow managed):
- `commands/` - Custom slash commands (e.g., `/commit`)
- `statusline-command.sh` - Custom status line script

`settings.json` is not tracked in the repo because Claude Code modifies it
directly. Since it is not stowed, the `statusLine` key that points at
`statusline-command.sh` can't be symlinked in; `src/setup-claude-settings.sh`
merges it into `~/.claude/settings.json` with `jq` (idempotent, preserves other
keys) and runs from `setup.sh` after stow. `jq` is in the Brewfile because the
statusline script and this merge both depend on it (macOS ships `jq` since 15,
but the Brewfile guarantees it).

### Hammerspoon

Configuration in `dotfiles/hammerspoon/.hammerspoon/`. See `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md` for the leader-key model (META / SUPER / HYPER), the shared ChordKey hold/tap engine, the Chooser-based list tools and the checklist for wiring a new picker, the shared CheatSheet and HelperPanel canvas overlays, the launcher, menu search, clipboard preview, VPN, keep awake, the eyedropper colour picker, DisplayProfiles, and the conventions for structuring a spoon.

Testing a Hammerspoon change live goes through `bin/hs-devlock`, a machine-wide test lock, since only one config can run at a time. Take it only for testing, release it back to main the moment testing stops being the focus, and never hold it across development. The full discipline is in the hammerspoon `CLAUDE.md` under "Testing a change in an isolated worktree, and the test lock", read it before making any Hammerspoon config live.

BrowserTabs is the one config here with a test suite, in `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/plugins/browsertabs/test/`, run through its own `suite.sh` which takes the lock and gives it back. It is an integration harness by necessity rather than by preference, since every fault it guards against lives in Apple Events or the accessibility layer and no test with a fake browser in it could see any of them. Run it before merging a change to that plugin. Its README says what it covers, what it deliberately does not, and why a green run is regression protection rather than proof.

Worktree convention. When you create a git worktree for a feature or fix, put it under a `.worktrees/` directory in the parent of the repo (beside this checkout, so `../.worktrees/` from the repo root), named for the feature, so worktrees stay in one place rather than scattered as bare siblings of the repo. Because that directory is outside the repo, it never shows up in the repo's own status. Never write the absolute path, always reach it relative to the repo.

### Tmux

Configuration in `dotfiles/tmux/`. See `dotfiles/tmux/CLAUDE.md` for binding conventions, priority system, scoped fzf switchers, popup workarounds, and status bar details.

### lf

Configuration in `dotfiles/lf/`. See `dotfiles/lf/CLAUDE.md` for why lf was chosen over yazi, the tmux popup nesting limitation, command type differences, and custom keybinding details.

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.
