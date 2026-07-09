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

Configuration in `dotfiles/hammerspoon/.hammerspoon/`:
- `init.lua` - Entry point, orchestrates all Spoons
- `config/` - User-editable configuration (pure data)
  - `apps.lua` - App bundle ID registry
  - `keys.lua` - All keybinding definitions
  - `settings.lua` - Global settings (margins, timing)
  - `workspaces/` - Workspace definitions (dev.lua, vicert.lua)
- `Spoons/` - Real Hammerspoon Spoons (reusable logic)
  - HyperKey, HyperCheatSheet, AppToggler, ClipboardHistory, WindowManager, WindowLeader, StageManager, WorkspaceEngine, TerminalHandler, DockMenuToggle

**Leader keys (META < SUPER < HYPER).** Three keys are remapped to unused
function keys by `src/setup-capslock-hyper.sh` (one `hidutil` LaunchAgent, ~0
RAM; all three mappings must share one `UserKeyMapping` or a later `--set`
clobbers earlier ones). They are named for the classic X11/Emacs modifier
hierarchy, ascending with the Fn number:

| Key | Remap | Name | Spoon | Role |
|-----|-------|------|-------|------|
| Right Command | F16 | META | WindowLeader | hold + arrow = switch display; + Shift + arrow = move window |
| Right Option | F17 | SUPER | WindowLeader | hold + key = base window ops (halves, maximize, center, sizes) |
| Caps Lock | F18 | HYPER | HyperKey | hold + letter = app toggles; quick tap = `hs.hid.capslock.toggle()` |

Why remap at all? Raw Caps Lock is a toggle key and emits no usable key
up/down; Right Command / Right Option are real modifiers, but a held modifier
stamps its flag onto every keystroke **and** `hs.hotkey` can't tell left from
right (both report `cmd`/`alt`). Remapping each to a plain function key gives
clean, side-specific events an `hs.eventtap` can measure and swallow. No
Karabiner or extra daemon.

`HyperKey.spoon` adds hold-vs-tap: holding F18 ~0.6s with no key fires
`onHold` → `HyperCheatSheet`, an overlay of the app bindings split into open vs
not-running (uninstalled/unresolvable apps filtered out; names+icons cached at
load, only the running split recomputed per show). `WindowLeader.spoon` is
simpler — no tap fallback (these keys only drive window management) — and
supports mods-aware bindings so META hosts two tiers (bare arrow vs Shift+arrow)
via exact-match-then-catch-all resolution.

Most toggles focus or cycle their app. A toggle in `keys.lua` may instead carry
an optional `url`, and `AppToggler` opens it with `open` so the app lands on a
specific pane rather than wherever it was last. Hyper+, uses this to open System
Settings on the General pane, and pressing it again while frontmost hides it.
These toggles still show in the cheat sheet like any other app, resolved by
bundle id, so the overlay stays complete without extra wiring.

Coupling is contained: `HyperKey` is an optional injected dependency of
`AppToggler` only. If it is not wired up in `init.lua`, `AppToggler` falls back
to binding the literal `HYPER` (⇧⌃⌥⌘) combo from `keys.lua` — so removing the
Hyper key degrades gracefully, it does not break other spoons. Window management
has no such fallback: it goes only through `WindowLeader`, so it needs the F16/
F17 remap applied. Trade-offs: the remaps are machine-wide (Caps Lock, Right
Command and Right Option are F18/F16/F17 in every app — the right-side modifiers
lose their normal function everywhere; the left ones still work), and all three
keys only do anything while Hammerspoon runs. Undo steps are in
`src/setup-capslock-hyper.sh`.

Config auto-reloads when files change. Get app bundle ID: `osascript -e 'id of app "APP_NAME"'`

### Tmux

Configuration in `dotfiles/tmux/`. See `dotfiles/tmux/CLAUDE.md` for binding conventions, priority system, scoped fzf switchers, popup workarounds, and status bar details.

### lf

Configuration in `dotfiles/lf/`. See `dotfiles/lf/CLAUDE.md` for why lf was chosen over yazi, the tmux popup nesting limitation, command type differences, and custom keybinding details.

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.
