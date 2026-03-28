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

# Set default editor for dev file types
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

**Stowed by default:** ghostty, tmux, nvim, zsh, hammerspoon, claude

**Available but not stowed:** alacritty, kitty, wezterm

Each package mirrors the home directory structure (e.g., `dotfiles/nvim/.config/nvim/` → `~/.config/nvim/`)

### Claude Code

Configuration in `dotfiles/claude/.claude/` (stow managed):
- `commands/` - Custom slash commands (e.g., `/commit`)
- `statusline-command.sh` - Custom status line script

`settings.json` is not tracked in the repo because Claude Code modifies it directly.

### Hammerspoon

Configuration in `dotfiles/hammerspoon/.hammerspoon/`:
- `init.lua` - Entry point, orchestrates all Spoons
- `config/` - User-editable configuration (pure data)
  - `apps.lua` - App bundle ID registry
  - `keys.lua` - All keybinding definitions
  - `settings.lua` - Global settings (margins, timing)
  - `workspaces/` - Workspace definitions (dev.lua, vicert.lua)
- `Spoons/` - Real Hammerspoon Spoons (reusable logic)
  - AppToggler, WindowManager, StageManager, WorkspaceEngine, TerminalHandler, DockMenuToggle

Config auto-reloads when files change. Get app bundle ID: `osascript -e 'id of app "APP_NAME"'`

### Tmux

Configuration in `dotfiles/tmux/.tmux.conf`. Prefix is `Alt-z` (with `Alt-Z` as secondary for caps lock tolerance).

**Binding conventions.** Every custom prefix binding must use `-N "description"` so it appears in `tmux list-keys -N`. The `?` binding shows a searchable cheat sheet of all noted bindings via fzf.

**Priority tags for binding order.** Custom bindings that should appear first in the cheat sheet use a `[p:N]` prefix in their `-N` note, where N controls sort order. For example `-N "[p:1] Sessions (fzf switcher)"`. The `?` cheat sheet strips the `[p:N]` prefix before display using awk, so the user only sees the clean description. Bindings without a `[p:N]` tag appear after all prioritized bindings.

**FZF switchers.** Sessions (`s`), windows (`w`), and panes (`f`) each use fzf in a `display-popup`. They sort by last used, exclude the current item, and show context in the header. Uppercase variants (`S`, `W`, `F`) open native tmux tree views.

**Status bar.** Changes color based on state. Green background when prefix is active, yellow when in copy mode, transparent otherwise. Copy mode state is tracked via a global `@copy_mode` variable propagated through hooks because `pane_in_mode` only works for the evaluated pane.

**Plugins.** Managed through TPM. Resurrect and continuum handle session persistence. tmux-fzf provides additional management via `m`.

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.
