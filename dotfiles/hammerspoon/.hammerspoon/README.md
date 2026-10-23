# Hammerspoon Configuration

## Directory Structure

```
.hammerspoon/
├── init.lua                      # Main orchestrator (loads and wires everything)
├── config/                       # Configuration (pure data, edit these)
│   ├── apps.lua                  # App bundle ID registry
│   ├── keymap.lua                # Every key, list key and alias a person sets, app toggles included
│   ├── plugins.lua               # Per plugin data and switches, no keys
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

Edit `config/apps.lua`. The `apptoggler` entry in `config/plugins.lua` hands this catalog to
the app toggler as its own data, and every app in it becomes an action named after it,
`apptoggler.NewApp`:
```lua
NewApp = "com.example.newapp",
```

Give it a key in the `keys` section of `config/keymap.lua`:
```lua
["hyper+W"] = "apptoggler.NewApp",
```
An app that needs more than focus or cycle, show and hide or a placement, takes a style in
`config/toggles.lua`, `{ app = "Ghostty", style = "popup" }`, and its key still names the app,
`apptoggler.Ghostty`.

App toggles fire by holding the Hyper key (**Caps Lock**, remapped to **F18** at the
HID level by Olm's core `lib/keyremap.lua` from the key the root's own shipped leaders table gives Hyper,
and held through Olm's leader adapter) plus the letter.
A quick Caps Lock **tap** toggles real Caps Lock (via `hs.hid.capslock`).
Holding Caps Lock about 0.6s with no key shows the Hyper sheet of `LeaderSheet`, an overlay of the
bindings, with the apps split into open and not running. Uninstalled apps (no resolvable
bundle path) are filtered out, names and icons are resolved at load, and only the
running state split is recomputed per show.

## Useful Commands

Open Hammerspoon Console:
```bash
open -a Hammerspoon
```

Get app bundle identifier:
```bash
osascript -e 'id of app "APP_NAME"'
```
