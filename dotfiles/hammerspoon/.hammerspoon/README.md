# Hammerspoon Configuration

## Directory Structure

```
.hammerspoon/
├── init.lua                      # Main orchestrator (loads and wires everything)
├── config/                       # Configuration (pure data, edit these)
│   ├── apps.lua                  # App bundle ID registry
│   ├── keys.lua                  # All keybinding definitions
│   ├── settings.lua              # Global settings (margins, timing, etc.)
│   └── workspaces/               # Workspace definitions
│       ├── dev.lua               # Dev workspace
│       └── vicert.lua            # Vicert workspace
└── Spoons/                       # Hammerspoon Spoons (reusable logic)
```

The authoritative spoon list is the `Spoons/` directory and the `hs.loadSpoon`
calls in `init.lua`. This README does not enumerate them, because a hand-kept list
drifts as spoons are added or renamed. Each spoon with a non-obvious design keeps its
own `CLAUDE.md` beside its `init.lua`, and the cross-spoon design notes live in the
top-level `CLAUDE.md`.

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

Edit `config/apps.lua`:
```lua
NewApp = "com.example.newapp",
```

Edit `config/keys.lua`:
```lua
{ app = "NewApp", modifiers = HYPER, key = "W" },
```
App toggles fire by holding the Hyper key (**Caps Lock**, remapped to **F18** at the
HID level by `KeyRemap.spoon` from the `leaderKeys` catalog in `config/keys.lua`, and
driven by `HyperKey.spoon`) plus the letter.
A quick Caps Lock **tap** toggles real Caps Lock (via `hs.hid.capslock`).
Holding Caps Lock ~0.6s with no key shows `HyperCheatSheet`: an overlay of the
bindings, split into open vs not-running apps. Uninstalled apps (no resolvable
bundle path) are filtered out; names/icons are cached at load, only the
running-state split is recomputed per show.

## Adding New Workspaces

Create `config/workspaces/myworkspace.lua`:
```lua
return {
  name = "myworkspace",
  hotkey = { modifiers = { "shift", "alt" }, key = "M" },
  apps = { "App1", "App2", "App3" },
  secondaryDisplayApps = { "App3" },
  primaryDisplayApps = {},
  strategies = {
    primary = {
      App1 = { action = "percentage", width = 90, height = 90 },
      App2 = { action = "fullHeightReasonableWidth" },
      App3 = { action = "resizeDefault" },
    },
    secondary = { ... },
  },
}
```

Add to `init.lua`:
```lua
local myWorkspace = require("config.workspaces.myworkspace")
-- ...
spoon.WorkspaceEngine:registerWorkspace(myWorkspace)
```

## Strategy Actions

- `percentage` - Resize to percentage of screen (requires `width`, `height`)
- `fullHeightReasonableWidth` - Full height, capped width
- `resizeDefault` - Default size (1800x1200)
- `none` - Just launch, don't resize

## Useful Commands

Open Hammerspoon Console:
```bash
open -a Hammerspoon
```

Get app bundle identifier:
```bash
osascript -e 'id of app "APP_NAME"'
```
