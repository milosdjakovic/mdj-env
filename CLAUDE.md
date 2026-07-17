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
  - ChordKey, CheatSheet, HyperKey, HyperCheatSheet, AppToggler, ClipboardHistory, Capture, WindowManager, WindowLeader, WindowCheatSheet, StageManager, WorkspaceEngine, TerminalHandler, DockMenuToggle, KeyRemap, DisplayProfiles

**Leader keys (META < SUPER < HYPER).** Three physical keys can be remapped to
unused function keys, named for the classic X11/Emacs modifier hierarchy,
ascending with the Fn number. Hammerspoon owns the remap now, not a login
LaunchAgent. `config/keys.lua` holds a pure `leaderKeys` catalog, one row per
remappable key giving only its physical source and target Fn key, and
`KeyRemap.spoon` turns the active rows into one `hidutil` `UserKeyMapping` and
applies it on load, clearing on quit. A single `--set` replaces the whole table,
so each apply is idempotent and frees any dropped key.

| Key | Fn | Name | Spoon | Role |
|-----|-------|------|-------|------|
| Right Option | F16 | META | WindowLeader | the active window leader: bare arrow = **resize** (halves + full-height + reasonable), `Shift`+arrow = **move**; return = maximize; `C` = center; `,`/`.` = prev/next display; letters = presets + grow/shrink |
| Right Command | F17 | SUPER | WindowLeader | in the catalog but **unreferenced**, so it is not remapped and Right Command is a normal key; point `windowLeader` at it to swap |
| Caps Lock | F18 | HYPER | HyperKey | hold + letter = app toggles; quick tap = `hs.hid.capslock.toggle()` |

A catalog key is "active" only by being **referenced**. The catalog names no
consumer, so the dependency points one way, apps and windows name their leader
and the catalog stays ignorant of both. `config/keys.lua` sets `appLeader =
"HYPER"` and `windowLeader = "META"`; `init.lua`, the composition root, applies
the remap for exactly that referenced set, resolves each `fkey` to a keycode via
`hs.keycodes.map`, and stamps the chosen window leader onto the (leaderless)
window bindings so `WindowManager` and `WindowCheatSheet` never learn the
catalog. So moving all of window management to another physical key is one edit,
`windowLeader = "SUPER"`, which also frees Right Option and claims Right Command
automatically. An unreferenced key is neither remapped nor tapped, so it stays a
normal key with no extra step. `src/setup-capslock-hyper.sh` no longer installs
anything, it only removes the legacy LaunchAgent on older machines.

Why remap at all? Raw Caps Lock is a toggle key and emits no usable key
up/down; Right Command / Right Option are real modifiers, but a held modifier
stamps its flag onto every keystroke **and** `hs.hotkey` can't tell left from
right (both report `cmd`/`alt`). Remapping each to a plain function key gives
clean, side-specific events an `hs.eventtap` can measure and swallow. No
Karabiner or extra daemon.

The hold/tap/chord mechanism is one shared spoon, `ChordKey.spoon`: a single
`hs.eventtap` serves every registered key (each added via `addKey` with
overridable hold/tap defaults), so N leaders cost one tap, not N. Today that is
Caps Lock and Right Option; Right Command is defined but not registered. It owns only
the state machine — swallow other keys while held, fire `onTap` on a quick
release (Caps Lock's real toggle), fire `onHold(keyCode)` once ~0.6s pass with
no other key. `HyperKey.spoon` and `WindowLeader.spoon` are thin domain adapters
over it: they keep their public contracts (`HyperKey:bind`/`isActive` for
AppToggler/ClipboardHistory, `WindowLeader:bind`/`addLeader` for WindowManager)
and supply the per-key lookup. Both now share one mods-aware resolver (Hyper and
the leaders): optional per-binding `mods`, exact-match on shift/ctrl/alt/cmd,
ignoring the `fn` flag macOS stamps on arrow keys, then a catch-all fallback. A
binding with no `mods` is the catch-all, so most keys stay a single press. Hyper
uses it for capture, where Hyper+4 saves an area screenshot to a file and
Hyper+Shift+4 sends it to the clipboard; the leaders use it so a bare arrow can
differ from Shift+arrow.

`onHold` reveals a cheat sheet, and both cheat sheets draw through one shared
grid renderer, `CheatSheet.spoon` (dark panel, key-badge rows filled row-major
across columns). `HyperCheatSheet` and `WindowCheatSheet` only build the content
model, so the drawing never diverges. Its appearance (opacity, background,
corner radius, font, padding) is global: set once via `CheatSheet:configure`
from the `cheatSheet` block in `config/settings.lua`, so one edit restyles every
overlay. Per-overlay layout (columns, badge width, icons) stays in the builders,
where it legitimately differs. Holding F18 shows `HyperCheatSheet`, the
app bindings split into open vs not-running (uninstalled/unresolvable apps
filtered out; names+icons cached at load, only the running split recomputed per
show). Holding a leader shows `WindowCheatSheet` — just that leader's bindings
(META's resizes and moves, each arrow appearing twice, bare and `Shift`);
pressing any bound key cancels it. It reads
the same `keys.windowManagement` config, so it never drifts; each row's label is
the action name humanized (`nextDisplay` → "Next Display") unless the entry sets
an explicit `description` override.

A binding may also carry an optional `when = "<predicate>"` that gates it on live
state. When the named predicate returns false the key becomes a no-op (still
swallowed by the held leader, so no raw character leaks) and its cheat-sheet row
is hidden. The predicate registry (`windowPredicates` in `init.lua`) is the one
place the logic lives, injected into both the dispatch gate
(`WindowManager:bindToLeader`) and the overlay filter (`WindowCheatSheet`), so
the key and the overlay never disagree, and `config/keys.lua` stays pure data.
Predicates are evaluated live (at dispatch and at each overlay show), so they
track runtime state; an unknown name is treated as always active so a typo fails
visibly rather than silently disabling a binding. Today the only predicate is
`multipleDisplays`, which hides `previousDisplay`/`nextDisplay` when a single
display is attached.

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
has no such fallback: it goes only through `WindowLeader`, so its leader must be
referenced in `config/keys.lua` (which is what applies its remap). Trade-offs:
the remaps are machine-wide, so each referenced physical key loses its normal
function in every app (today Caps Lock is F18 and Right Option is F16; the left
modifiers still work, and Right Command is unreferenced so it stays a normal
key). The remapped keys only do anything while Hammerspoon runs, and now the
remap itself is applied only while it runs, KeyRemap sets it on load and clears
it on quit. To free a key, stop referencing it; to disable everything, quit
Hammerspoon.

Config auto-reloads when files change. Get app bundle ID: `osascript -e 'id of app "APP_NAME"'`

**DisplayProfiles.** Keeps display arrangements deterministic on top of what
macOS remembers, using the `displayplacer` command line tool (in the Brewfile).
macOS still scrambles the main display, scaling, or window positions when a dock
wakes monitors in a different order, and the Settings UI cannot force a layout
back. `DisplayProfiles.spoon` watches screen changes with `hs.screen.watcher` and
reapplies the saved arrangement that fits whatever is attached. It is the
mechanism only, it never names a machine or a layout. `config/displays.lua` holds
the pure data, a list of profiles per machine keyed by `LocalHostName` (read with
`scutil --get LocalHostName`), each profile a name plus a full `displayplacer`
command. `init.lua`, the composition root, resolves this machine's name, the one
place the per host split is decided, and injects that machine's list. The spoon
stays ignorant of hostnames and of the catalog, and a machine with no entry does
nothing, logged so the reason shows.

Per host keying exists because the built in laptop panel has a different id on
every Mac, so a profile that names it belongs to one machine. External monitors
also expose a serial id, printed as `Serial screen id: sXXXX`, that stays stable
even on another Mac, so profiles are written with serial ids and the same
physical monitors following you to another machine keep working once that machine
has its own entry. A profile is chosen when its screen count equals the number
attached and every id it names is attached, comparing both persistent and serial
ids, so the multi screen desk profile and the single screen laptop profile never
collide and either id type matches. The first matching profile wins.

Capturing a profile is copy and paste. Arrange the displays, run `displayplacer
list`, and copy the full `displayplacer ...` line it prints. `spoon.DisplayProfiles:capture(true)`
does the same from the console and copies the current arrangement to the
clipboard. Tweaking is editing any value in a command and saving, since the
config reload reapplies the match at once. Applying a layout fires the watcher
again, so the loop guard skips when the match is the profile already applied,
which holds because applying changes only the arrangement, not the set of
attached displays. `reconcile(true)` forces a reapply and `apply(name)` forces a
named one, for a manual fix when the displays did not change. Adding this spoon
needed a restow, since `~/.hammerspoon/Spoons` holds one symlink per spoon.

**Structuring a spoon with swappable behavior.** When a spoon has a mechanism
plus interchangeable backends, follow the Capture.spoon layout, which is the
concrete form of the design principles in the global config. init.lua is the
composition root and only that. It loads the pieces, names the concrete
providers, sets the default order, and returns the assembled spoon. engine.lua
is the Context. It owns the behavior and talks only through the contract, naming
no provider. contract.lua declares the required methods and a validate helper,
added once it has a real consumer rather than up front. providers/ holds one
file per backend, each self contained, implementing available, supports, and
trigger, and knowing nothing about the chain or each other. Adding a backend is
a new file plus one line in init.lua, with no edit to the engine.

Load sibling files by absolute path with debug.getinfo plus loadfile, since a
spoon directory is not on package.path. Resolve and validate providers once at
load, but check liveness at dispatch when the underlying state can change while
Hammerspoon runs, as Capture does for macshot being quit. Keep a spoon's public
contract stable, HyperKey exposes bind and isActive, WindowLeader exposes bind
and addLeader, so adapters over the shared ChordKey engine degrade gracefully.
When two adapters need the same behavior, share it rather than duplicating.
HyperKey and WindowLeader use one resolver that matches optional modifiers, so
Hyper plus Shift plus a key can differ from Hyper plus that key.

Adding a whole new spoon requires stowing again, because `~/.hammerspoon/Spoons`
holds one symlink per spoon. Adding files inside an already symlinked spoon does
not, they resolve through the existing symlink.

**Wiring a list tool into the Hyper contexts.** The picker atoms give only the
widget. `Chooser.spoon` is for a long filterable list like the clipboard and the
VPN locations, and `Panel.spoon` is for a short fixed list like caffeinate and
the VPN control panel. Routing the Hyper keys to a picker and drawing the hold
overlay is not part of the atom, because the atoms deliberately know nothing
about HyperKey. It is opt in wiring done per consumer in the composition root.
Forgetting it does not break the tool, it just leaves it without the Hyper
shortcuts, which is exactly how the VPN location picker started before it was
brought in line with the clipboard. The checklist to plug a new picker in, each
step mirroring what the clipboard already does.

1. Expose a control surface. The tool, or each of its surfaces, offers dot called
   `isShowing` plus the navigation methods its bindings name, such as
   `selectNext`, `selectPrev`, `insertSelected`, and `hide`. A Chooser instance
   uses colon methods, so wrap it in a thin dot called adapter, as `Vpn.spoon`
   does for its location picker.
2. Add a context block in `config/keys.lua` under `hyperContexts`, with a name, a
   `when` predicate name, a priority, and the bindings by action name. This stays
   pure data.
3. Add the predicate in the registry in `init.lua`, the `when` name mapped to a
   function returning whether that surface is open.
4. Register the surface in the `choosers` list in `init.lua`, so `activeChooser`
   and `routeNav` send the navigation actions to whichever surface is open.
5. Show the shortcuts. A searchable list on the web backend carries a persistent
   footer bar inside its own window, so the shortcuts are always visible under the
   surface rather than peeked in a separate window on a Hyper hold. Build the hints
   with `footerFor(name)` in `init.lua`, which reads the same `hyperContexts`
   bindings, and pass them as `config.footer`. A picker built directly takes it in
   its config; one built inside a spoon is handed a `withFooter(spoon.Chooser,
   footerFor(name))` decorated factory, so the spoon stays ignorant of Hyper
   contexts. A single window hosts both the list and its footer, so nothing
   competes for the frosted backdrop, which a second peek window did. `contextOverlays`
   stays as an empty seam, so a context that wants a real hold overlay again can
   register a model builder there without touching the reveal logic. The native
   backend has no footer, so on native a context shows no shortcut hints.
6. Inject the root's overlay teardown as the surface's `onClose` and bind the open
   key as a base HyperKey binding.

A tool with two surfaces, like the VPN control panel and its location picker,
wires each surface as its own participant, its own context block, predicate,
registry entry, and overlay.

**Command palette / switcher.** Hyper+Space opens a filterable app switcher and
command runner. It lists every installed application, open ones first then not
running, and below them the Hyper and window leader actions. An app that has a
Hyper toggle shows its shortcut, the rest are launchable by name, and typing
filters by name or shortcut. Return, or Hyper+i, runs the highlighted row. It
adds no spoon. The reusable mechanism is the Chooser atom, the same widget behind
the clipboard and the VPN locations, so the palette is pure composition root
policy in `init.lua`. It is the one place that maps the app list and the pure
binding data in `config/keys.lua` (`appToggles`, `capture`, `clipboardHistory`,
`caffeinate`, `vpn`, `lock`, `sleep`, and `windowManagement`) onto the domain
spoons, reusing `AppToggler:focusOrCycle` / `toggleURL`, `Capture:capture`,
`WindowManager:actions()`, and the show functions the base Hyper bindings call.

Each row carries only a small serializable descriptor, its kind plus a name or
bundle id, never a function. This matters because the Chooser hands every row to
`hs.chooser`, which serialises it to a native object, and a function there cannot
be converted, so a row holding one is silently dropped and the list comes up
empty. One dispatcher turns the descriptor back into the right call, so this is
the Command pattern with the command encoded as data, and the palette still never
learns what a row does. Adding a row is a new entry in the build, never a change
to the presenter. The installed app list is scanned once, lazily on first open,
from the standard app directories and cached, so config load stays fast and a
newly installed app appears after the next reload, which is automatic on file
change. Running state is recomputed per open so open apps sort first, and a
running app not on disk in the scanned dirs is included when it has a dock
presence, to skip background helpers. Window rows carry their live `when`
predicate, so the display switch rows drop out on a single display, matching the
cheat sheet.

App rows show the real app icon. The action rows have none of their own, so each
gets a generic icon drawn from a glyph, since this Hammerspoon has no SF Symbol
API and the named system images are too sparse. The glyph is rendered to an image
once through `hs.canvas` and cached, so it lines up in the row with the app icons.
Window actions share one glyph, the chord in the subtitle telling them apart,
while capture and the system actions get a per-action one.

The palette follows the picker checklist above like any other list tool. It has
a dot called navigation adapter over the Chooser instance, a `commandPaletteOpen`
predicate, a `commandPalette` context block giving it the shared j, k, and i
navigation with Space to close (the open key doubles as the close, the way the
clipboard's X does), a `footer` built from `footerFor("commandPalette")` so its
shortcuts show in its own footer bar, and `hideShortcuts` injected as its
`onClose`. Native arrows,
typing, Return, and Escape work whenever Hyper is released. The chosen row runs
deferred by a short timer, so it fires only after the chooser tears down and
macOS restores focus to the window that was frontmost before the palette opened,
which the window actions need since they act on the focused window.

### Tmux

Configuration in `dotfiles/tmux/`. See `dotfiles/tmux/CLAUDE.md` for binding conventions, priority system, scoped fzf switchers, popup workarounds, and status bar details.

### lf

Configuration in `dotfiles/lf/`. See `dotfiles/lf/CLAUDE.md` for why lf was chosen over yazi, the tmux popup nesting limitation, command type differences, and custom keybinding details.

### Neovim

LazyVim-based configuration. Run `nvim` after setup to bootstrap plugins.
