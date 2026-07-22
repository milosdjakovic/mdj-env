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
- `src/` - Modular setup scripts (all idempotent, support Apple Silicon and Intel)
- `dotfiles/` - Stow-managed configurations, each subdirectory is a stow package

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

Worktree convention. When you create a git worktree for a feature or fix, put it under a `.worktrees/` directory in the parent of the repo (beside this checkout, so `../.worktrees/` from the repo root), named for the feature, so worktrees stay in one place rather than scattered as bare siblings of the repo. Because that directory is outside the repo, it never shows up in the repo's own status. Never write the absolute path, always reach it relative to the repo.

### Tmux

Configuration in `dotfiles/tmux/`. See `dotfiles/tmux/CLAUDE.md` for binding conventions, priority system, scoped fzf switchers, popup workarounds, and status bar details.

### lf

Configuration in `dotfiles/lf/`. See `dotfiles/lf/CLAUDE.md` for why lf was chosen over yazi, the tmux popup nesting limitation, command type differences, and custom keybinding details.

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.
