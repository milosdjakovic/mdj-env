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

**Stowed by default:** ghostty, tmux, nvim, zsh, hammerspoon

**Available but not stowed:** alacritty, kitty, wezterm

Each package mirrors the home directory structure (e.g., `dotfiles/nvim/.config/nvim/` → `~/.config/nvim/`)

### Hammerspoon

Configuration in `dotfiles/hammerspoon/.hammerspoon/` with modular spoons:
- `init.lua` - Entry point, loads all spoons
- `spoons/` - Feature modules (appToggler, windowManagement, stageManager, workspaces, terminalHandler)
- `spoons/keyBindings.lua` - Centralized key binding definitions

Config auto-reloads when files change. Get app bundle ID: `osascript -e 'id of app "APP_NAME"'`

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.
