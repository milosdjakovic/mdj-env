# Hammerspoon Configuration

Configuration in `dotfiles/hammerspoon/.hammerspoon/`:
- `init.lua` - Entry point, orchestrates all Spoons
- `config/` - User-editable configuration (pure data)
  - `apps.lua` - App bundle ID registry
  - `keys.lua` - All keybinding definitions
  - `settings.lua` - Global settings (margins, timing)
  - `workspaces/` - Workspace definitions (dev.lua, vicert.lua)
- `Spoons/` - Real Hammerspoon Spoons (reusable logic). The authoritative list is the
  `Spoons/` directory itself and the `hs.loadSpoon` calls at the top of `init.lua`. This
  file does not re-list the spoons, because a hand-kept roster drifts the moment one is
  added, renamed, or removed. Each spoon that carries a non-obvious decision has its own
  `CLAUDE.md` beside its `init.lua`.

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
| Right Option | F16 | META | WindowLeader | the active window leader: bare arrow = **resize** (halves + full-height + reasonable), `WASD` = **move** (W up, A left, S down, D right); return = maximize; `C` = center; `,`/`.` = prev/next display; letters = presets + grow/shrink |
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

Combos the domains do not claim no longer die at the tap. With `passthrough`
on, a ChordKey `configure` default set once in `init.lua` and inherited by every
leader (overridable per key), a held leader that resolves to no handler leaks the
combo downstream as leader+key, so other apps can bind whatever we leave free.
This is the point of exposing the leaders, a recorder in another app sees F18+G
and can bind it, while a combo we do bind still runs here and never leaks. The
mechanism lives entirely in `ChordKey`, so `HyperKey` and `WindowLeader` stay
ignorant of it. Because the tap already swallowed the leader's own key-down, the
engine synthesizes it once on the first unbound press, then synthesizes the
pressed key carrying its live modifiers, swallowing the real events so the order
is the engine's, and emits the leader key-up on release (plus an up for any key
still leaked, so nothing sticks). Synthetic events carry a non-HID source id, so
the same guard that ignores the clipboard paste's Cmd+V keeps these from looping
back through the tap. Only eventtap-based apps (Raycast, BetterTouchTool,
Karabiner, another Hammerspoon tap) can bind a function key held as a modifier,
since F16/F17/F18 are not real modifiers and macOS's standard shortcut fields
reject them; the trade is that the three leaders stay distinct, which one shared
Hyper modifier combo could not give.

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
(META's resizes on the bare arrows and moves on WASD);
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

**Two discoverability mandates, and a binding is not finished until both hold.**
Every shortcut must be reachable two ways. First, a shortcut bound on a leader
appears in that leader's held cheat sheet, HYPER in `HyperCheatSheet`, a window
leader in `WindowCheatSheet`, and SUPER in whatever sheet it is later given, so
holding the leader always reveals the full set of what it does and nothing bound
is hidden from the hold. Second, every executable command shortcut also appears
as a launcher row, so the same action is found by name without knowing its key,
and an app toggle counts because its app row carries the shortcut. The only
things exempt from the launcher rule are the surfaces used to reach the launcher
itself, the launcher open key and the other discovery openers, since listing a
finder inside the finder earns nothing. Both surfaces read the same
`config/keys.lua` data, the cheat sheet through the sections the root assembles
and the launcher through its action rows, so a new binding is added to that data
and surfaced in both places rather than in code only one of them reads, and the
key and its listings can never drift. A binding whose `when` predicate is false
drops out of both together, so the rule still reads the same. A shortcut that
reaches neither surface is considered unfinished.

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

After any change to the Hammerspoon config always reload it, do not rely on the
pathwatcher alone. Run `hs -c "hs.reload()"` so the change is guaranteed live,
then verify with the `hs` command line tool, for example `hs -c "return
spoon.SomeSpoon._field"` to read live state. The `hs` CLI talks to the running
Hammerspoon over `hs.ipc`, so it both reloads and introspects, which is how a
change should be confirmed rather than assumed.

**Testing a change in an isolated worktree, and the test lock.** There is only
one Hammerspoon app on the machine, with one config directory and one set of
global event taps, so only one config can be live at a time. Editing files
touches nothing shared, so develop freely in a worktree, and many sessions can
work in parallel worktrees at once. The one serialized step is making a
worktree's config the live one for testing. The `bin/hs-devlock` script guards
exactly that step. On acquire it points the `MJConfigFile` default at the current
worktree's `init.lua` and relaunches Hammerspoon, so the worktree's own files and
Spoons run without touching the stowed main config or its per spoon symlinks. On
release it restores whatever was live before, which is always main, and
relaunches. The resting state is main. The lock is a directory created
atomically, held outside `~/.hammerspoon` so it never trips the pathwatcher, and
its holder file records who took it and what to restore.

The discipline every session must follow. Do not hold the lock across
development, only across testing. When you reach a point where you need the live
config, run `bin/hs-devlock acquire` from your worktree, or `bin/hs-devlock
acquire --wait` in the background when another session holds it, which polls
every five seconds and returns the moment it frees. Test with the `hs` CLI, then
run `bin/hs-devlock release` when done, which returns Hammerspoon to main. Hold
the lock across a tight burst of quick edit, reload, and test iterations, tens of
seconds to a couple of minutes, and do not release and reacquire between each one,
so the config is not relaunched needlessly. Release the moment testing stops being
the focus, before any stretch of analysis, planning, or longer implementation,
so a waiting session gets it. Never hold it speculatively. Whoever acquires must
release and restore afterward, whether the test was run automatically or handed
to the user to confirm.

The human in the loop exception. When you hand a feature to the user to try by
hand, to see how it looks, works, and feels, acquire with `bin/hs-devlock acquire
--manual` and keep the lock with no timer until the user gives an explicit green
light or says it is wrong. A manual hold is exempt from the stale reclaim, so a
long evaluation is never interrupted by another session, and it is freed only by
an explicit release. Do not release it on your own and do not let anything time
it out. The cycle is, acquire with `--manual`, the user tries it, then on a good
verdict you release, or on a bad one you release, do the analysis and the next
round of implementation off the lock, and acquire again with `--manual` when the
next hands on round is ready. A manual hold that is truly stuck is still
recoverable with `bin/hs-devlock break`.

Mechanics. `bin/hs-devlock status` shows whether the lock is free or held, who
holds it, and which config is live, so run it to see whether Hammerspoon is on
main. A lock left more than fifteen minutes with no release is treated as
abandoned and reclaimed by the next acquirer, a backstop for a crashed or
forgotten session, well above any real test burst. `bin/hs-devlock release
--force`, or its alias `bin/hs-devlock break`, clears a stuck lock and returns to
main. For ordinary in place work on the already live config, reload with `hs -c
"hs.reload()"` as above. The worktree lock is only for taking a worktree's own
copy live in isolation.

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
named one, for a manual fix when the displays did not change.

The spoon now follows the Capture and Vpn layout, split into `engine.lua` (the
watch, match, apply mechanism), `store.lua` (a git tracked JSON file of captured
profiles), `chooser.lua` (an inspect and manage surface), and `init.lua` (the
spoon composition root that merges the curated profiles with the captured ones
and exposes the api the chooser talks through). The public colon contract above
is unchanged and still delegates to the engine, so the overlay display policy
that reads `current()` is untouched. The new surface is a nested menu chooser on
`obj.chooser`, opened from the launcher with no dedicated key, that lists the
profiles, marks the active one, captures the current arrangement when it matches
none, and renames or deletes the captured ones, curated ones staying read only.
The main root wires it like the other native choosers: the curated profiles and
the JSON path (`hs.configdir .. "/config/display-profiles.json"`) are injected in
`configure`, the view deps and the docked shortcut panel in
`spoon.DisplayProfiles.chooser.configure`, plus the `displayProfilesOpen`
predicate, the `displayProfiles` Hyper context in `config/keys.lua`, the
`choosers` registry entry, and the launcher special action row. Because the JSON
lives inside the watched tree, the pathwatcher callback skips a reload when only
`display-profiles.json` changed, and the chooser rebuilds the engine in memory
after a write, so a capture is live with no reload. The internal decisions live
in `Spoons/DisplayProfiles.spoon/CLAUDE.md`. Adding the original spoon needed a
restow, but the new sibling files inside it did not, they resolve through the
existing symlink.

**Terminal placement, and remembering the display.** Option+\` toggles the
terminal through `TerminalHandler.spoon`, which now is pure mechanism. It no
longer decides which screen to place on; it depends on one injected contract,
`targetScreen()` returning an `hs.screen`, and never names how that is chosen. The
composition root in `init.lua` supplies it. This is Strategy wired through
injection, fed by an Observer, so the engine stays ignorant of both the default
and the memory.

`DisplayMemory.spoon` is the Observer and the only reusable part of the memory. It
watches one app's windows with an `hs.window.filter` on the terminal's bundle id,
and on every `windowMoved` records the display the window lands on, whether it was
dragged there or moved by the META leader's prev/next display. Identity is the
display UUID, stable across reboots, and the memory is a table from scope to
display UUID stored under one `hs.settings` key, `terminalDisplay`, surviving a
reload or a reboot. It answers `rememberedScreen()` with the display remembered for
the current scope while it is attached, else nil, so a caller can fall back. It
never decides a default and never decides what a location is; the root injects the
app to watch and a `scope`, a string or a function evaluated live.

The scope is what makes it location aware, and it is where DisplayMemory and
DisplayProfiles are mixed without being coupled. The root injects
`displayFingerprint()`, the sorted UUIDs of the attached displays joined into one
string, which is the same notion of a location DisplayProfiles matches on, namely
which displays are plugged in. So the office setup and the home setup each keep
their own remembered terminal display and switch automatically when displays are
docked or undocked, and a single per machine slot can no longer clobber itself
across places. The fingerprint is a small reusable helper in `init.lua`, separate
from both spoons, so a future per-location app placement scopes on the same value
with one line. `hs.settings` is per machine, so the built-in panel's
machine-specific UUID already keeps the fingerprint distinct across Macs without
naming one, which is why the terminal memory needs no `host` while DisplayProfiles
still does.

The default policy lives in one place in `init.lua`, `defaultTerminalScreen()`,
the built-in panel if there is one, else the first attached screen. That single
rule covers every machine, built-in on the MacBook and the iMac, first available
on the Mac mini which has none, so no per host table is needed, unlike
DisplayProfiles. Built-in is matched by the screen name containing "Built-in". The
root chains the two into the injected `targetScreen`, remembered display first
then default, so the terminal reappears wherever it was last placed on this
machine and lands built-in the first time on a fresh machine. `host` is resolved
once in the TerminalHandler block (`scutil --get LocalHostName`) and reused by
DisplayProfiles later. Dropping the DisplayMemory wiring leaves TerminalHandler on
the default alone, graceful degradation like HyperKey and AppToggler. Adding
DisplayMemory needed a restow, since `~/.hammerspoon/Spoons` holds one symlink per
spoon.

**Overlay display policy.** One place decides which display every transient
overlay appears on, the eight choosers (clipboard, VPN, menu search, launcher,
keep awake, display profiles, emoji, overlay display) with their docked shortcut panels, both cheat
sheets, and the colour toast. This is Strategy wired through injection, the same shape as
TerminalHandler's `targetScreen`. A small registry in `init.lua` maps a mode name
to a resolver returning an `hs.screen`, `config/settings.lua` picks the mode in
the pure-data `overlayDisplay` block, and the chosen resolver is injected into the
two atoms, `CanvasPanel.configure({ screen })` and `Chooser.configure({ screen })`.
Neither atom names the policy or the modes, so both the choosers and the cheat
sheets read one seam and land on the same display.

The live choice is set at runtime, not by editing config. The **Overlay Display**
launcher row (a launcher-only picker, no Hyper key, but on the shared j/k/i/x
navigation like every chooser) writes the choice to one `hs.settings` key,
`overlayDisplayPolicy`, and a second key `overlayDisplayNames` remembers each
display's friendly name so a detached monitor still reads by name. The resolvers
read through `effectiveMode` and `effectiveFixed`, which return the persisted choice
first and fall back to the `config/settings.lua` `overlayDisplay` block, so that
block is now only the fresh-machine seed and a picker choice takes effect on the
next overlay with no reload. The picker is a drill-in menu, root shows the modes
plus a Configure door, Configure lists the profiles each with its pinned display,
and a profile lists its displays to pin, committing straight to the store.

Three modes. `activeWindow` uses the screen with the focused window, the effective
default and the historical behaviour. `cursor` uses the screen under the mouse.
`fixed` pins overlays to a chosen display per display arrangement, keyed by the
`DisplayProfiles` profile name (resolved live through `DisplayProfiles:current()`)
to a displayplacer serial id, reusing the portable ids `config/displays.lua`
already holds. Resolvers run at overlay-open time, so they track live state and may
forward-reference DisplayProfiles, which is configured later in the root. An unknown
mode, an unmapped arrangement, or a serial that does not resolve all fall back to
`activeWindow`, logged once per arrangement.

Two mechanics make this reliable. The choosers place authoritatively rather than
trusting the native `hs.chooser` default: the Chooser atom resolves the target
screen once at show, before the chooser steals focus (resolving later would see the
chooser's own window as focused), then `_settleFrames` forces the window onto that
screen, centered horizontally and top biased, instead of adapting to wherever the
widget dropped it. Fixed mode needs a serial-id to `hs.screen` bridge because
`hs.screen` exposes no serial id; `displayplacer list` prints each screen's serial
id alongside its persistent id, and the persistent id is the CoreGraphics UUID that
`hs.screen:getUUID` returns, so serial resolves to persistent resolves to screen.
That parse is cached and cleared on an `hs.screen.watcher` change, the same event
DisplayProfiles reacts to, so fixed mode costs nothing per open after the first
resolve on an arrangement.

**Spoon lifecycle contract.** Every spoon is created and wired the same way, so
`init.lua` can treat them uniformly. This is a convention, not a base class,
because a Lua contract is structural, a documented set of methods plus validation,
not an inherited type. Two methods are required. `init()` returns self and does no
side effects. `configure(opts)` takes a single `opts` table holding every
collaborator and choice, defaults it, and returns self, so all injection goes
through one door. `start()` and `stop()` are optional and exist only when a spoon
owns live resources, a watcher, an eventtap, or a timer, that genuinely need to
begin and be torn down. A spoon that only binds keys keeps using `bindHotkeys` or
`bindToLeader` as its activation step rather than growing an empty `start`. Do not
add `start`/`stop` with nothing to do, that is the ceremony the design principles
reject. Both call styles are allowed, the colon and self spoons that are the norm
and the dot called module style Vpn and the clipboard submodules use, since the
contract is a method set and not an object model, so Vpn is not rewritten to
conform. `DisplayMemory` and `Launcher` are the worked examples of the full set,
each owns a watcher so each has a real `start` and `stop`, while `TerminalHandler`,
`WindowManager`, and `AppToggler` correctly stop at `init` and `configure`.

Layered composition follows from this. A plain spoon is a self sufficient
configurable mechanism, the bottom layer. When two or more of them are combined
into one feature, the deciding question is whether the combination carries behavior
or state of its own. If it is only a choice or an ordering, it stays a closure in
the composition root, that is still top down configuration and a separate entity
would be single caller ceremony, which is why `TerminalHandler.targetScreen` and
the overlay screen strategy are just injected closures in `init.lua`. If it has its
own state or lifecycle it becomes a coordinator, itself a spoon following this same
contract, instantiated in `init.lua` like any other, which is what `Launcher.spoon`
is. Most combinations already have a natural owning engine and the glue belongs
inside it as injected providers, the Capture.spoon layout below, so a standalone
coordinator is reserved for glue that has no natural owner and holds state.

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

**Documenting a spoon, and what this file keeps.** Decision records are split by
a single seam. This file keeps only what spans spoons, the leader key model, the
spoon lifecycle contract, the overlay display policy, and how `init.lua` wires
everything as the composition root, so it answers where a thing lives and how the
pieces connect. A spoon that carries a decision not obvious from reading it also
gets its own `CLAUDE.md` beside its `init.lua`, holding that spoon's internal
decisions, the tradeoffs it made, and why, what it deliberately does not do, what
it degrades to, and what would break if the shape changed. That file answers why
the spoon is shaped this way and never narrates the code line by line, since the
code sits right there. `Launcher.spoon` is the worked example, and `ChordKey` and
`HyperKey` document the hold, tap, chord engine and its adapter.

Create one only when the spoon earns it, a thin mechanism like `DockAutoHide`
or `KeyRemap` stays covered by its paragraph here, which is the same reject
ceremony rule the design principles set. Three rules keep the split honest. The
decision and its doc live together, so a change to a spoon's internals edits that
spoon's `CLAUDE.md` in the same commit, while a change to how spoons are wired
edits this file. And any concrete wiring choice stays here, so there is one
composition root of truth and the per spoon files stay ignorant of how they are
assembled. And a decision record describes only why a thing is shaped the way it
is, it never enumerates the set of spoons, restates a key binding, or copies a
method signature, because those already live in the `Spoons/` directory, in
`config/keys.lua`, and in the spoon's own code, so any copy here is a second source
of truth that drifts. When you need to point at one, point at where it lives rather
than restating it. Adding a `CLAUDE.md` inside an already symlinked spoon needs no
restow, it resolves through the existing link like any new file.

**A spoon never knows how it is used.** Which physical keys open a spoon and drive
its list, and any human wording that names those keys or the interaction, live only
in `config/keys.lua` and the composition root, and reach the user through the shared
deferred shortcut panel. A spoon supplies its rows as plain data, a title, a subtitle,
and an icon, plus the action a chosen row performs, and nothing more. It never bakes a
hint like "Return to copy", or the name of the key that opens it, into a row, a
placeholder, or an alert, and it never reads a binding to decide its behavior. When a
row's selection does something, express it as the action itself, "copy this command",
"connect to this relay", never as the key that triggers it, since the key is config data
that drifts the moment it is rebound. The rule covers the spoon's own doc comments too,
they describe what the tool does, not the keys that reach it. This is the invariant the
picker wiring below serves, the contexts, the predicates, and the shortcut panel are all
assembled in the root, so the spoon exposes only a control surface and its rows and
learns none of it. The payoff is that rebinding a key, or opening the tool another way,
touches config alone, and the hint and the binding can never disagree because there is
one source of truth. The Vpn spoon's unavailable install row is the worked example, it
shows the install command as plain subtitle data and copies it on selection, and says
nothing about which key copies it.

**Wiring a list tool into the Hyper contexts.** The picker atom gives only the
widget. `Chooser.spoon` wraps the native `hs.chooser` and backs every list tool,
the clipboard, the VPN locations, caffeinate, menu search, the launcher, the
display profiles menu, and the emoji picker. It
once had a second webview backend built on a `Surface.spoon`, selectable per
consumer, plus a `Panel.spoon` for short fixed lists, but every consumer settled
on native so the web backend, Surface, and Panel were all removed. Routing the
Hyper keys to a picker and drawing the hold overlay is not part of the atom,
because the atom deliberately knows nothing about HyperKey. It is opt in wiring done per consumer in the composition root.
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
5. Show the shortcuts. Every chooser now runs on the native backend and docks a
   deferred `HelperPanel` (a plain `hs.canvas`) below the list, so the hints stay
   hidden while the field is in use and reveal once the user pauses
   (`settings.shortcutsPanel.delayMs`). Build one with `shortcutPanelFor(name)` in
   `init.lua`, which reads the hints from `footerFor(name)` (the same `hyperContexts`
   bindings) and returns the three callbacks a native chooser is wired with, then
   pass `onPositioned`, `onActivity`, and `onClose` into the chooser. `onPositioned`
   arms the panel at the chooser frame, `onActivity` pokes its idle timer on each
   keypress, and `onClose` hides it and clears any peeked overlay. A consumer that
   already owns `onPositioned` (the clipboard, to place its canvas preview) composes
   the panel's inside its own and forwards the chooser frame out. `contextOverlays`
   stays as an empty seam, so a context that wants a real hold overlay again can
   register a model builder there without touching the reveal logic.
6. Inject the panel's `onClose` (which also runs the root's overlay teardown) as the
   surface's `onClose`, wire `onPositioned`/`onActivity`, and bind the open key as a
   base HyperKey binding.

A tool with two surfaces, like the VPN control panel and its location picker,
wires each surface as its own participant, its own context block, predicate,
registry entry, and overlay.

**A green circle marks the active row, never a checkmark.** When a chooser marks
one row as the live choice, the active display profile, the chosen overlay
display mode, the pinned display, it shows a green circle in the row's icon slot.
A checkmark reads as confirm this and a tick as done, while the list is showing
state, which one of these is current right now, so the green dot reads as that
status at a glance and never competes with the confirm and commit actions a menu
also carries. A new chooser that highlights its active row reuses the green
circle rather than inventing its own glyph, so the marker stays one thing across
every list.

**Back is the first row in a chooser menu.** For a menu style chooser with levels,
like DisplayProfiles, the Back row is always the first row, not the last, so
stepping out is the predictable default and the fresh highlight lands on it, and it
is never hunted for at the bottom. Two related cases follow the same spirit rather
than the letter. A confirm screen leads with the safe cancel, DisplayProfiles'
delete leads with Keep, so the default and a stray Return do the harmless thing. A
single input screen, where the field is a text entry and Return must commit the
typed value, leads with the confirm row instead, DisplayProfiles' rename and
capture lead with Save so Return saves, with Back trailing. So the rule is Back
first on a navigable menu, and the safe or committing action first where selecting
the first row on entry is what the user means.

**One matching policy for every chooser.** How a query filters a list is a single
policy, decided once at the root and shared by every chooser, the same Strategy
through injection shape as the overlay display screen. The matcher lives in one
file, `Chooser.spoon/match.lua`, a pure `match(query, hay) -> score or nil` where
nil drops a row and a number ranks it, higher first with the original order breaking
ties. `Chooser.matchers` exposes the strategies, `fuzzy`, `substring` (the pre-fuzzy
behaviour, a plain substring test where every match scores zero so the list keeps its
natural order), and `words` (a word tokenizer, see the clipboard below). `init.lua`
injects one through `Chooser.configure({ matcher = ... })`, so switching every list
between them is one edit. Today the root default is fuzzy, and the clipboard overrides
its own to `words`.

`fuzzy` is a small dynamic-programming subsequence scorer in the spirit of fzy, chosen
over a greedy scan because greedy locks onto the leftmost occurrence of each letter, so
it cannot find a term late in a long body and cannot tolerate a swapped letter, it
starves the rest of the query once it takes a wrong turn. The DP explores every
alignment for the query length times the haystack length per row, still well under a
frame over a few hundred rows at typing speed. It carries three decisions worth
knowing. Extending a contiguous run outscores landing on a word start, so a
near-contiguous match beats the same letters scattered across the separate words of a
keyword bag, the bug where Device Management outranked Displays for `dspl`. Inner gaps
between matched characters cost real points while the leading and trailing gaps are
nearly free, so a wide scattered span is penalized but a term sitting deep in a long
clipboard body is not. And it tolerates typos, a query character it cannot place is
skipped at a fixed cost, so a missed, misspelled, or swapped letter still hits, with no
hard budget since enough skips just sink the score. A relevance floor scaled to the
query length then drops whatever scores too low, the scattered tail, the absent letter,
the query that is mostly wrong. The weights, the floor, and the typo cost are named
constants at the top of `match.lua`, tuned so the floor cuts obvious noise while
staying loose enough to forgive a fumbled letter; raising the floor step cuts more.

The atom owns the filtering when a matcher is set and the field is in filter mode. The
supplier returns the full candidate list and the atom scores it, keeps the matches,
sorts by score, and styles only the survivors, so a supplier no longer writes its own
`:find` test and the matching logic exists in exactly one place rather than copied into
each tool. A row searchable by more than its visible text sets `filterText` to fold in
hidden keywords or synonyms, defaulting to the title plus the subtitle. On an empty
query the atom skips scoring and keeps the supplier's order, which is what makes the
launcher's recency order and the VPN action row survive until the user types.

Two knobs sit on the per-instance config, both the single `matcher` field. Omitting it
inherits the root default. Setting it to `Chooser.matchers.substring` keeps search but
drops fuzzy for that one tool. Setting it to `false` opts out of the shared matcher
entirely, for a tool whose query is not a plain filter over a list. Five tools do that.
Caffeinate's field is a value being typed, a time or a duration, parsed into one morphing
row, so a matcher would only filter that row against its own label. The DisplayProfiles
menu is the same shape, a stack of frames whose field filters at the top but is a name
entry on the rename and capture screens, so its supplier morphs the rows from the query
and the atom must not second-guess them, which would hide the Back row and the Save row.
The overlay display picker is the same drill-in shape, a per-view menu that does its own
substring filter over the current view's rows, so the atom must not rerank or hide its
Back and commit rows. The emoji picker filters over a hidden haystack, the folded name,
aliases, tags, and category rather than the visible title and subtitle, and caps its rows
to bound the glyph icon render, so its own supplier owns the query and the atom filtering
again would drop a tag only match and undo the cap. The clipboard parses a leading type
prefix (`img ...`) off its query, so it owns filtering and opts out at its own `new()`,
and for the free-text part it uses the `words` strategy rather than the shared fuzzy one,
keeping its rows in recency order rather than reranking.
So every list chooser is fuzzy by default with no per-tool wiring, and a future list
chooser inherits it for free, while the structured-query tools opt out in one word.

The clipboard uses `words` instead of fuzzy deliberately. Fuzzy earns its place in the
label choosers, where you type an abbreviation of a short known name and subsequence
matching with typo tolerance is the point. Clipboard entries are arbitrary prose and code
searched from the inside, where you remember and type a real word, and there fuzzy was both
the wrong fit and the performance cost. Its query-length times body-length cost per row,
run over uncapped clipboard bodies and rebuilt every keystroke, dragged worse the more you
typed, and the only ways to bound it (truncating the searchable body) lost content the
matcher was meant to reach. `words` splits the query on whitespace and keeps a row when
every word is a substring of the body in any order, so words need not be adjacent and a
prefix still hits. It is a plain byte scan with no dynamic program and no allocation, so it
searches the full body of every entry on each keystroke with nothing truncated, and its
only blind spot is a wrong letter inside a word, a fair trade on this kind of text. Two
smaller changes go with it: the clipboard caches each entry's lowercased searchable text
once (a weak-keyed table in `ui.lua`) instead of rebuilding it every keystroke, and the
row build filters and styles only survivors as before. A database-backed full-text index
(`hs.sqlite3`) would only matter if the 1000-entry in-memory history ever grew into the
tens of thousands; at this scale the scan is already well within a frame.

**Clipboard preview.** The clipboard is the third native panel in the pair. Its
manager reserves a companion pane beside the chooser (`layout.companionWidth`), and
the atom polls the highlighted row and fires `onHighlight`, which draws the copied
data into an `hs.canvas` docked in that companion frame, no webview. Rendering is
per kind: text and url wrap in a monospace block, image and video show the store's
downscaled preview PNG loaded straight as an `hs.image`, and a file shows its
header plus that image or a note. A text entry that is nothing but a single colour
literal (hex, rgb/rgba, or hsl/hsla) is a special case, it renders the colour's
three canonical forms and a large flat swatch filling the pane instead of the raw
text. Detection is strict, the whole trimmed string must be the colour, so prose
that merely mentions `#fff` stays ordinary text, and a translucent colour is drawn
over a checkerboard so its alpha reads. This lives entirely in the per-kind builder
in `ui.lua`, one consumer, so it is inline there with no new module or injection. Content taller than the pane scrolls with
Hyper+Cmd+j/k, clamped to the overflow and clipped to the inner box. The canvas
pane and the docked shortcut panel share the palette's `preview.bg`/`preview.border`
so they read as one surface. Crucially the file storage and the preview sizing are
decoupled from the UI: `manager/store.lua` owns the media lifecycle and
`manager/preview.lua` is a Chain of Responsibility that produces the downscaled
PNGs off the main thread (sips for rasters, ffmpeg for video, `hs.image` for
pdf/icns), knowing nothing about the UI. `ui.lua` only consumes the resulting
`e.prev`/`e.thumb` paths, so swapping the webview for the canvas touched neither.

**Launcher.** Hyper+Space opens a filterable app switcher and command runner, the built-in one, built over the Chooser atom. It is a coordinator spoon that owns the app scan caches and an `hs.application.watcher`, orders open apps by recency the way Command+Tab does, and follows the picker checklist above. Its decision trail and internals live in `Spoons/Launcher.spoon/CLAUDE.md`.

**Emoji.** Hyper+J opens an emoji picker. Emoji is a facade over interchangeable backends, the same shape as Chooser, so the root names which one the key opens in a priority ordered list by reference and the first available wins. Three backends ship, the built in picker over the Chooser atom, the macos Character Viewer triggered by Ctrl Cmd Space, and a custom backend that runs an injected callback so an external picker reached by a URL scheme or a trigger becomes a backend with no file of its own. The default is the built in picker, which owns one vendored dataset fetched once by its `regenerate.sh` and committed as `data.json`, merging the GitHub gemoji set with a safe slice of native Unicode symbols from the official Character Database, currency and arrows and math and the Mac modifier keys and more, so a query by name, shortcode, tag, or category finds a glyph without its exact Unicode name. Every matching emoji ranks above every matching symbol, so a query lists the emoji first and the plainer glyphs below. A pick is inserted into the focused field through an injected `onInsert`, so the backend never learns the effect, and it follows the picker checklist above. The root wires `onInsert` to the clipboard manager's `pasteText`, which pastes the glyph rather than typing it, because a synthesized keystroke mangles an astral glyph like an emoji in a terminal and in some native apps while a paste carries the real bytes everywhere, and `pasteText` snapshots the clipboard and restores it after so the paste stays invisible. It degrades to typing when the clipboard manager is absent. The provider strategy, the decision trail and internals, the safe symbol selection, the render based tofu filter, and the icon memory behavior, live in `Spoons/Emoji.spoon/CLAUDE.md`.

**TextCase.** Recases the current selection in place, opened from the launcher only with no
dedicated key. It is a picker over the Chooser atom that owns its own transform catalog, so
it is a lean spoon rather than inline wiring, the same reasoning as Emoji. It follows the
picker checklist, its `textCase` context giving it the shared j, k, i navigation with x to
close, and it reads the selection and lists every case with the selection previewed in each,
pasting the chosen one over the selection. The cross-spoon seam is that it names no
clipboard: the two mechanisms it needs, reading the selection and writing the result in
place, are injected from the root and backed by the ClipboardHistory manager, `read` by a
new `copySelection` and `apply` by `pasteText`, because that is where the pasteboard
snapshot and restore and the self-capture guard already live, so both leave the clipboard
and its history untouched. `copySelection` is the read-side mirror of `pasteText`, added
alongside it in the manager. The launcher special action fires deferred after focus returns
to the source app, so the selection is intact when the read runs. It degrades to a typed
paste with no read when the clipboard manager is absent, the same graceful fallback the
emoji insert takes. The decision trail and internals live in `Spoons/TextCase.spoon/CLAUDE.md`.

**Processes.** Finds the development servers you left running and stops them, opened from
the launcher only with no dedicated key. It follows the Capture layout, an engine over
interchangeable discovery sources, and the DisplayProfiles shape of a spoon whose surface is
its own `chooser.lua` beside the engine, so it is configured twice like DisplayProfiles is.
The spoon's own root reads the pure data in `config/processes.lua` and hands each source the
slice it needs, staying the one place that names both the concrete sources and their order,
and the main root injects only the view deps every chooser receives. It follows the picker
checklist, its `processes` context giving it the shared j, k, i navigation with x to close
plus two actions only it answers, a force stop and a rescan, routed through `routeNav` so
they are no ops on any other surface rather than naming this one directly the way the
clipboard-only append and delete do. It overrides the shared fuzzy matcher to `words`, the
same choice the clipboard makes, because a query here is a real fragment you remember, a
port number or a project name, not an abbreviation of a short known label. Adding it needed
a restow, since `~/.hammerspoon/Spoons` holds one symlink per spoon. The source contract,
the port claim rule that collapses the docker proxy listeners into named containers, the
group signalling and its guards, and two hs.task and lsof facts that will bite anyone who
touches the shellouts, live in `Spoons/Processes.spoon/CLAUDE.md`.

**Eyedropper.** A screen colour sampler on Hyper+2, on the native macOS
eyedropper. It is deliberately not a chooser, so the picker checklist above does
not apply. It is a lone mechanism like lock and sleep, wired as a base HyperKey
binding through `bindHyper` and surfaced as the color picker launcher row through
the special action dispatcher, so it needs no Hyper context, predicate, or
`choosers` entry. A pick shows Apple's own `NSColorSampler` loupe, the same smooth
magnifier the system colour pickers use, and a click copies the sampled pixel's
hex to the clipboard with a short alert. Escape cancels.

Hammerspoon has no binding for `NSColorSampler`, so the sampler lives in a tiny
Swift helper, `sampler.swift` beside the spoon, that shows it and prints the
picked hex. The spoon compiles that helper once with `swiftc` into a cached
binary and runs it per pick through `hs.task`, so there is no per frame screen
snapshot and no custom loupe, the magnifier is the real native one and there is
no lag. The cached binary lives under `~/Library/Caches`, deliberately outside the
watched `~/.hammerspoon` tree so compiling it never triggers a config reload, and
it is rebuilt only when the Swift source is newer than the binary. `init` warms
that build in the background so the first pick stays instant. The spoon exposes a
small contract, `pick` to start and `isActive` to query, plus an optional injected
`onPick(hex)` callback for a consumer that wants the value beyond the clipboard.
Adding it needed a restow, since `~/.hammerspoon/Spoons` holds one symlink per
spoon. `swiftc` ships with the Xcode command line tools, already a prerequisite of
this dev environment.
