# Hammerspoon Configuration

## Directory Structure

```
.hammerspoon/
├── init.lua                      # Main orchestrator (loads and wires everything)
├── config/                       # Configuration (pure data, edit these)
│   ├── apps.lua                  # App bundle ID registry
│   ├── keys.lua                  # The two leaders and the app toggles
│   └── settings.lua              # Global settings (margins, timing, etc.)
└── Spoons/                       # Hammerspoon Spoons (reusable logic)
```

The authoritative spoon list is the `Spoons/` directory and the `hs.loadSpoon`
calls in `init.lua`. This README does not enumerate them, because a hand-kept list
drifts as spoons are added or renamed. Each spoon with a non-obvious design keeps its
own `AGENTS.md` beside its `init.lua`, and the cross-spoon design notes live in the
top-level `AGENTS.md`.

## Adding a New Spoon (re-stow required)

`~/.hammerspoon` and its `Spoons/` are **real directories** (they hold non-repo
files like `.git` and `work.toml`), so stow links each *item inside* them
individually rather than symlinking the whole folder. A brand-new Spoon folder
added to this package therefore has **no symlink** under `~/.hammerspoon/Spoons/`
until you re-stow — Hammerspoon simply won't find it (common after pulling on
another machine).

Fix: re-run stow for the package, which adds the missing per-item symlinks
without touching existing links or untracked files:

```bash
cd dotfiles && stow -t ~ hammerspoon
```

Then reload Hammerspoon (`hs -c "hs.reload()"` or the menu) so it picks up the
newly linked Spoon.

## Adding New Apps

Edit `config/apps.lua`. The `apptoggler` entry in `config/plugins.lua` hands this catalog and
the toggle list below to the app toggler as its own data:
```lua
NewApp = "com.example.newapp",
```

Edit `appToggles` in `config/keys.lua`, using the same name as in `config/apps.lua`.
An entry with no `modifiers` binds into the Hyper modal:
```lua
{ app = "NewApp", key = "W" },
```
App toggles fire by holding the Hyper key (**Caps Lock**, remapped to **F18** at the
HID level by Olm's core `lib/keyremap.lua` from the root's own shipped leader catalog,
and held through Olm's leader adapter) plus the letter.
A quick Caps Lock **tap** toggles real Caps Lock (via `hs.hid.capslock`).
Holding Caps Lock ~0.6s with no key shows the Hyper sheet of `LeaderSheet`: an overlay of the
bindings, split into open vs not-running apps. Uninstalled apps (no resolvable
bundle path) are filtered out; names/icons are cached at load, only the
running-state split is recomputed per show.

## Useful Commands

Open Hammerspoon Console:
```bash
open -a Hammerspoon
```

Get app bundle identifier:
```bash
osascript -e 'id of app "APP_NAME"'
```
