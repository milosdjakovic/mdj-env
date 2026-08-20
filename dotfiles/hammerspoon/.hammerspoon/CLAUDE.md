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

**External tools, and the one door to them.** A plugin that needs something from
outside Hammerspoon declares it in its own `manifest.lua`, under `needs.tools`, where an
entry carries a name, a kind, a locator, a policy, and what breaks without it. The
dependency door, `Spoons/Olm.spoon/lib/deps.lua`, is TOLD that set by the composition
root, probes the whole of it in one pass, and hands out a scoped adapter. That adapter is
the only way a plugin may obtain an external tool, and it answers only for what was
declared, so an undeclared ask returns nothing and names the asker in the console.
Declaring a tool is one entry and no wiring. The kinds, the policies, and where the line
is drawn on what is worth declaring at all are documented in `lib/deps.lua` and in
`Spoons/Olm.spoon/docs/PLUGIN-CONTRACT.md`.

**One tool, described once.** There used to be a second declaration system, plain files
named `dependencies` or `<base>.dependencies` sitting beside whatever knew each tool, and
for a while both existed at once. That is the arrangement where one tool is described in
two places and the two drift with nothing watching, and it went exactly that way, eight
plugins moved their declarations into their manifests, and the twenty files left behind
went on being read by the collector alone. The layer above then lost ten tools without a
word, `qalc` and `tmux` among them, so a fresh machine could have been set up without the
calculator the convert plugin is entirely built on. All twenty files are deleted and the
manifests are it.

What the per file placement was FOR still matters, though, and it is worth keeping the
reason rather than only the mechanism. A declaration beside one provider meant a missing
tool named the provider responsible rather than the whole plugin, so a backend stayed self
contained and adding one was a new file with nothing shared to edit. A tool entry carries
an optional `unit` field for that, naming the file inside the plugin that wanted it, so a
console line still reads `capture/macshot` rather than `capture`, and the generated
manifest one layer up still stamps that owner into its consumer column.

The adapter stays scoped to the plugin rather than to the unit, because the plugin root is
what the composition root injects into and what wires its own providers. The unit label
decides what a message says, and the plugin still decides who may ask.

**A plugin names a tool and never names how to install one.** This is the layering rule
that makes the rest work, and one half of it has been sharpened rather than dropped. A
declaration says it needs a binary called `displayplacer`, and it may also say that the
binary is the `displayplacer` formula, because a plugin built to travel to another machine
has to carry that answer with it and this repository's map will not be there. What it may
never do is name an install command, since that is a second copy of an answer the
repository already holds and the two drift apart. The declarations travel upward, collected
by `dotfiles/hammerspoon/dependencies-collect` into one generated `DEPENDENCIES` manifest
at the package root, and that manifest is this module's whole contract with the layer above,
which holds the complete map from a name to a formula, a cask, a tap, or a manual step and
refuses to disagree with anything a declaration states. So the layer above never looks
inside a plugin and nothing under this directory ever runs a package manager.

Reading those manifests takes Lua, since that is what they are written in, so the collector
finds them and hands them to a real interpreter rather than pattern matching at them from a
shell. `lua` is therefore declared like any other tool, in `dependencies-module`, as
optional, because only regenerating the contract stops working without it.

Four places used to break
this rule and all of them are gone, a set of hardcoded Homebrew prefixes, two console
lines advising a `brew` command, a chooser row offering to copy a `brew install` line to
the clipboard, and a generator script telling you to run one. The last two survived
longest because they were help text rather than code, which is exactly why the
reconciler now greps every file type under `dotfiles` for an install verb. Data flowing
the other way is fine, an upper layer injecting something downward is just
configuration, which is what the whole root already is.

The most useful thing that removal taught is why help text is not exempt. The install
line in the VPN row was a second copy of an answer the repository already held once, in
`DEPENDENCIES.map`, so the two could drift apart with nothing to catch it. What replaced
it is a disabled row and a console line that name the gap and stop, and the repository
answers where the tool comes from.

**A capability from Olm's own lib is not a dependency, and used to be declared as one.**
There was a `core` kind for it, so a plugin named `paste` or `recency` in the same
declaration form and the map carried an `olm` origin pointing at the lib file that answered.
It is retired. It made sense when these were separate spoons that could not legitimately
see each other, so a capability really did arrive from outside. Everything is one bundled
spoon now and a lib module arrives by injection, declared as `needs.lib`, which makes a
capability internal structure rather than a thing the machine has to provide. Nothing was
ever installed for that kind, which was the clue.

What survives is the boundary, which was always the half that mattered. No file under
`Spoons/Olm.spoon/plugins/` may reference `spoon.Olm` at all. A plugin receives its slice
through its own `configure` and never opens that door itself, and the reconciler above still
proves it.

A need that belongs to the whole module rather than to any plugin goes in
`dotfiles/hammerspoon/dependencies-module`, which the collector folds in first and
stamps with the module name. Today that is the Hammerspoon application itself, which
has no runtime consumer because nothing here would be running without it, and `lua`,
which only the collector needs. The resolver sees neither, and only the layer above acts
on them. The composition root's own two tools are different again, since the root is a real
consumer that reaches for `scutil` and `displayplacer`, so it declares them in
`Spoons/Olm.spoon/root/manifest.lua` and joins the set as a declarer beside the plugins. That file is deliberately
not called `dependencies`, because this filesystem is case insensitive and a file with
that name beside the generated `DEPENDENCIES` is literally the same file. That mistake
was made once and it silently re-stamped every consumer column on each run rather than
failing, so the collector now refuses to read its own output.

The consumer column of the manifest is stamped from where the declaration sits rather
than written by hand, so a file cannot mislabel itself and a rename cannot leave a stale
owner behind. A leaf declaration is therefore five fields and the generated manifest is
six. Regenerate after editing a declaration, and the reconciler one layer up regenerates
too so a stale manifest cannot be committed.

**What happens when a tool is missing is a declared policy, not a habit.**
`optional` means the feature, or one backend of it, is quietly excluded from every
list and overlay, with one console line naming what was dropped and why, which is how
a missing `ffmpeg` already left video previews out. `required` means the root refuses
to wire the spoon at all, so no key, no launcher row, and nothing that would fail when
chosen. Required is reserved for a spoon that is only a front end onto its tool, where
a dead surface would be worse than no surface, and `Convert` is the one example. The
choice is about what the user sees rather than how badly the spoon wants the tool, so
`Eyedropper` is optional even though its sampler cannot be built without a compiler,
because it already answers a failed build with an alert and its key stays worth
finding. Every reload logs one summary line, how many tools were declared, how many
resolved, and what each absent one disables, so a feature that quietly vanished always
has a stated reason.

**Leader keys (META < SUPER < HYPER).** Three physical keys can be remapped to
unused function keys, named for the classic X11/Emacs modifier hierarchy,
ascending with the Fn number. Hammerspoon owns the remap now, not a login
LaunchAgent. `config/keys.lua` holds a pure `leaderKeys` catalog, one row per
remappable key giving only its physical source and target Fn key, and Olm's
KeyRemap plugin turns the active rows into one `hidutil` `UserKeyMapping` and
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

The hold/tap/chord mechanism is one shared engine, `Spoons/Olm.spoon/lib/chordkey.lua`, a single
`hs.eventtap` serves every registered key (each added via `addKey` with
overridable hold/tap defaults), so N leaders cost one tap, not N. Today that is
Caps Lock and Right Option; Right Command is defined but not registered. It owns only
the state machine — swallow other keys while held, fire `onTap` on a quick
release (Caps Lock's real toggle), fire `onHold(keyCode)` once ~0.6s pass with
no other key. Olm's HyperKey and WindowLeader plugins are thin domain adapters
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
grid renderer, `Spoons/Olm.spoon/lib/cheatsheet.lua` (dark panel, key-badge rows filled row-major
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

The discipline every session must follow. Ask before you start, and wait to be
told to. Nothing that seizes the screen or the keyboard begins on an announcement,
not taking the lock, not running a suite, not opening a chooser, and not posting a
key or a chord, because a run drives this machine with synthesised events and lands
in the middle of whatever the person is doing. Do the reading and the patching off
the machine first, then say what the command is and roughly how long it holds the
screen, and leave the checkout clean while waiting so nothing sits half applied if
the answer is not now. Do not hold the lock across
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

The lean test surface, a minimal `lean-init.lua` composition root loading only the
tool a given build phase was testing, served the olm build plan through its run of
phases and was retired once the last of them landed. `bin/hs-devlock` no longer
carries the `--lean` acquire it once used to take that surface live.

The console is a gate, read it after every load. The unit runner and the
inventory snapshot only see what they ask about, and a spoon that fails to load
still leaves both green while the console carries the error. So after every
reload, every lock switch, and every land that goes live, read the console and
treat any error line as a failing gate. With the port up, ask
`hs.console.getConsole()` through a dofile script and grep the text. With the
port dead, the config almost certainly died before reaching the `hs.ipc` require
near the end of `init.lua`, which means the dead port is itself the symptom of a
load error, and the console can still be read from outside through accessibility,
`osascript` asking System Events for the text area of the Hammerspoon Console
window. Never relaunch Hammerspoon to recover before capturing the console,
since a relaunch wipes the scrollback that holds the only copy of the error.

Stow only links what existed the last time it ran. The resting main config at
`~/.hammerspoon` is a folded stow tree, a real `Spoons` directory holding one
symlink per spoon, so a spoon directory born after the last stow run is simply
absent from it, and `hs.loadSpoon` fails on resting main while every worktree
test passes, because the devlock points Hammerspoon at the checkout directly and
the checkout always has every file. After landing anything that adds a new top
level entry to the hammerspoon package, a new spoon or a new file beside
`init.lua`, rerun stow for the package and then confirm resting main loads with
a clean console. Landing on main is not done until the stowed view proves it.

**DisplayProfiles.** Keeps display arrangements deterministic on top of what
macOS remembers, using the `displayplacer` command line tool (in the Brewfile).
macOS still scrambles the main display, scaling, or window positions when a dock
wakes monitors in a different order, and the Settings UI cannot force a layout
back. Olm's DisplayProfiles plugin watches screen changes with `hs.screen.watcher` and
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
in `Spoons/Olm.spoon/plugins/displayprofiles/CLAUDE.md`. Adding the original spoon
needed a restow, but the new sibling files inside it did not, they resolve through
the existing symlink.

**Terminal placement, and remembering the display.** Option+\` toggles the
terminal through `TerminalHandler.spoon`, which now is pure mechanism. It no
longer decides which screen to place on; it depends on one injected contract,
`targetScreen()` returning an `hs.screen`, and never names how that is chosen. The
composition root in `init.lua` supplies it. This is Strategy wired through
injection, fed by an Observer, so the engine stays ignorant of both the default
and the memory.

Olm's DisplayMemory plugin is the Observer and the only reusable part of the memory. It
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
overlay appears on, every chooser with its docked shortcut panel, both cheat
sheets, and the colour toast. The list is not enumerated here on purpose, a hand kept
roster drifts the moment a picker is added, and the `choosers` registry in `init.lua` is
the authority. This is Strategy wired through injection, the same shape as
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

**Transient feedback surface.** Routine feedback a feature produces while it is
working is drawn on the shared `CanvasPanel`, never on `hs.alert`, so the UI stays
one surface and the message lands on whatever display the policy above chose.
`hs.alert` is the reason this needs saying, it draws itself with no knowledge of
that policy, so a stray alert shows up somewhere no other overlay ever does. The
colour toast in `init.lua` is the worked example, a content function returning
`preferredSize` and `draw` fed into a single panel that is reused across messages
and hidden by a timer, with a mutable state table so a burst replaces the message
rather than stacking a column of panels. A spoon does not name the surface. It
takes an injected callback, the way Eyedropper hands its confirmation out through
`onPick`, and the root decides how the message is drawn, the same seam as the
overlay display screen.

`hs.alert` stays right for one case, a failure that stopped the feature running at
all. "Terminal not configured" in TerminalHandler, "No focused window!" in
WindowManager, and the "Color picker unavailable" fallback in Eyedropper are all
that shape, and they stay as they are. The rule governs the working path, not the
broken one. One place does not follow it yet, the copy confirmation in Vpn, which
is routine feedback sitting on an alert because it predates the convention.

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
contract, instantiated in `init.lua` like any other, which is what Olm's Launcher
host is. Most combinations already have a natural owning engine and the glue belongs
inside it as injected providers, the Capture plugin's layout below, so a standalone
coordinator is reserved for glue that has no natural owner and holds state.

**Structuring a spoon with swappable behavior.** When a spoon has a mechanism
plus interchangeable backends, follow the Capture plugin's layout, which is the
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

**Never start a timer without keeping its handle.** A Hammerspoon timer is
userdata whose finalizer stops it, so a pending timer nothing refers to can be
collected before it ever fires. The delayed call then simply never happens, with
no error, nothing in the console, and nothing to grep for, and the odds rise with
whatever else is allocating during the wait. That last part is what makes it so
misleading, since the same line works in isolation and fails under a busy list,
which reads as an intermittent macOS problem rather than a defect here. It cost a
long session to find once, in a conversion row stuck on `Converting` forever
because rebuilding the launcher's rows on every keystroke allocated enough to
collect the debounce inside its quarter second.

So the handle lives in a field on the object that owns the wait, and re arming
stops the previous one when the newer call supersedes it, as `Convert` does for
its debounce and `Chooser` for its frame settle. When several can be outstanding
and a later one must not cancel an earlier one, hold them in a table keyed per
call that each entry clears as it fires, as `ChordKey:_defer` does so a fast
chord sequence never discards its own first handler, and as the clipboard monitor
does so no step of a paste sequence can cancel the snapshot restore behind it.
That holder is written out per file rather than shared across spoons, because a
spoon reaches only its own siblings and a five line workaround for a platform
behaviour does not earn becoming a spoon and being injected into ten places. The
one place it is shared is within a single spoon that already has a helper module
its siblings load, which is why `Processes` carries `util.after` instead of the
same lines twice, its own `util.lua` setting the bar at a second consumer.
Reaching across a spoon boundary for it is still wrong. `check-timers` beside
this module enforces the rule, and `setup.sh` runs it.

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
code sits right there. Olm's Launcher host is the worked example, and `ChordKey` and
`HyperKey` document the hold, tap, chord engine and its adapter.

Create one only when the spoon earns it, a thin mechanism like `KeyRemap`
or `Eyedropper` stays covered by its paragraph here, which is the same reject
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
widget. `Spoons/Olm.spoon/lib/chooser` wraps the native `hs.chooser` and backs every list tool,
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
   uses colon methods, so wrap it in a thin dot called adapter, as Olm's Vpn
   plugin does for its location picker.
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
   already owns `onPositioned` (the clipboard, Local Servers and file search, each to
   place its canvas preview) composes the panel's inside its own and forwards an anchor
   spanning both panes out. `contextOverlays` stays as an empty seam, so a context that
   wants a real hold overlay again can register a model builder there without touching
   the reveal logic.
6. Inject the panel's `onClose` (which also runs the root's overlay teardown) as the
   surface's `onClose`, wire `onPositioned`/`onActivity`, and bind the open key as a
   base HyperKey binding.
7. Decide how this list is entered from another one. If a launcher row, an alias, or any other
   list can lead here, that entry must replace the rows of the chooser already open rather than
   opening this one over it, which means a query scope that the launcher hosts and not a `show`.
   The rule and the two ways to replace a list are below under one list becoming another in place.

A tool with two surfaces, like the VPN control panel and its location picker,
wires each surface as its own participant, its own context block, predicate,
registry entry, and overlay.

**How much a row can say is a question only the atom can answer, so it answers it and decides
nothing.** `Chooser:textBudget()` gives the pixel room a row's text has and `Chooser:textWidth(str,
which)` gives what a string renders as in the row font, `which` being `"title"` or `"sub"`. Both
live in the atom because answering needs the chooser's pixel width, the row font, the row font size
and the row inset, and the atom is the only layer holding all four. It stops there on purpose. A
consumer gets two numbers and decides for itself what to do about them, since handing back a
shortened string would put policy in the widget and how to shorten a path is a file tool's business.
File search is the first consumer, fitting a directory into what the ages left it.

The inset from the chooser's own width down to the text column was MEASURED, not derived, by
walking a live chooser through the accessibility API, since `hs.chooser` exposes no geometry and its
window comes from a compiled nib. It is 126 points, 61 leading for the pad and the icon column and
65 trailing for the pad and the row's command number badge. Four things were checked before trusting
one number. It held at 360, 480 and 640 point windows, so it is a constant to subtract and not a
fraction to scale. It was the same on a row with an icon and a row without, since the column is
reserved either way. It did not change past the ninth row where the badge stops being drawn. And the
title and the subtitle reported the same column, which is why one budget answers for both. At the
uniform 480 width that leaves 354 points.

Where a title too long for its row loses characters is a per consumer choice, `layout.titleLineBreak`,
defaulting to `truncateTail`. It differs genuinely rather than by taste. A consumer whose titles are
FILENAMES wants `truncateMiddle`, because the last few characters of a filename are its extension
and a tail cut spends them first, while the clipboard's titles are snippets where the front is
everything. Only file search sets it. Subtitles are always cut at the tail, since nothing has asked
otherwise, and this costs no measurement at all since AppKit does it from the paragraph style.

`textWidth` sums memoised per character widths rather than measuring whole strings, which is what
makes it usable on every row of every keystroke. A whole measure is 0.11 ms, so a page of two
hundred would cost 22 ms; the sum is 0.003 ms a string. The price is kerning, and measured against
true widths the sum runs 0.7 percent high on real paths, under two pixels on a 254 pixel string.
High is the direction that matters, since over counting shortens marginally early where under
counting would let a string through that then gets cut, so there is no fudge factor and none is
wanted.

**A binding may declare what it `needs`, which is different from `when`, and the difference is
when the question is asked.** `when` gates a binding on LIVE state, resolved by name on every
press, so the key stays bound and does nothing while its predicate is false. That is right for
something that changes while you use the tool, and the launcher's peek key is the example, since
whether there is anything to preview depends on the row under the cursor. `needs` gates a binding
on a CHOICE this root made at wiring time, and it is answered once against the `bindingNeeds`
registry before either the key wiring or `footerFor` reads the bindings, so the binding is removed
from both together and stays removed for the session. File search is that consumer, where the
preview provider decides whether the two scroll keys or the peek key are the ones that mean
anything. Config names the requirement and the root answers it, so neither learns the other's
business, and an unknown name, a requirement or a predicate, keeps its binding and logs, since a
typo should cost a stray key rather than a silently missing one.

Both gates are honoured by the hints as well as by the keys, and the second half of that was
added later than the first. A docked shortcut panel used to bake its hint list once when the panel
was built, so a binding gated on live state would be unbound at the press and printed in the hints
anyway, which is precisely the disagreement the two discoverability mandates exist to prevent. The
panel now takes its hints as a QUESTION rather than as a list and asks it on every reveal, and
`footerFor` drops a binding whose predicate is currently false as well as one whose requirement
was not met. So a key appears in the hints exactly while it does something, and `when` is a real
option for a chooser binding rather than a trap. The cost is rebuilding a small list each time the
panel is revealed, which happens once per pause rather than per keystroke.

ASKING ON REVEAL IS NOT ENOUGH, and that took a second report to see. The panel latches visible,
so the reveal shows the truth and then nothing redraws while the state carries on changing
underneath. Entering a tool's list after the panel was already up left the way out unlisted, and
stepping back out of one left it listed, and the same staleness was quietly true of every other
gated key, the preview one included, since moving the highlight changes whether it means anything.
So `CanvasPanel` polls while it is visible. Content may offer `state()`, one comparable string
saying what is currently being said, and the panel compares it four times a second and redraws
only when it differs. A poll rather than every consumer telling the panel after every event that
might matter, because that is a list nobody keeps complete and the entry already missing from it is
the reason this exists. Content without `state` runs no timer, and a steady panel costs a string
comparison and nothing else. The guard is the canvas being up rather than the reveal flag, since
that flag tracks only the delayed reveal and stays false for a panel configured with no delay.

**A binding may be a LISTING rather than a binding, which `chord = false` says.** Some keys belong
to the Chooser atom and are read there directly, Backspace on an empty field being the one, so
there is nothing for this root to bind. Such an entry still sits in its context's bindings, because
the panel is where a key becomes visible and a plain key nobody can see is a key nobody presses.
The wiring loop skips it and `footerFor` prints the bare key with no `Hyper+` in front, since
binding it as a chord would invent a second way to press it that the hint would then be wrong
about. It is gated like anything else, so the way out of a hosted list appears exactly while there
is a list to leave, and is absent in a tool's own picker and absent when a typed word did the
scoping, where deleting that word is already the way out and says so by itself. The alternative
tried first was a sentence in the placeholder, which did a hint panel's job worse and put wording
somewhere nothing else keeps it.

**A rebuilt list tells the highlight poll.** `Chooser:refresh` clears `lastRow` after setting
choices, because the poll that drives `onHighlight` compares the row NUMBER and the row under a
given number changes when the list is rebuilt. Without it a companion pane keeps describing
whatever used to sit there, which showed up as browsing into a folder from the first row leaving
the file search pane on the old first row. Typing already did this in the query callback, so
refresh was missing the same one line. Any consumer that swaps its list wholesale, a menu
drilling into a level or a rescan, gets the correction for free.

**One list becomes another in place. A chooser never closes so that a second one can open.**
This is the rule the two paragraphs below serve, and it holds however far apart the two lists
are, a level of a menu, a folder a search stepped into, or a whole separate tool that owns its
own rows. Whatever the user is about to look at goes into the chooser that is already up.

Closing and reopening is wrong for two reasons and both were seen for real. It rebuilds a window
in the same screen position, which reads as a flicker and as something having gone wrong, and the
reopen has to reconstruct the field, the highlight and the focus that the first one already held,
so each of those is a place the state comes back slightly different. The alias directory blinked
on every drill and the query it seeded came back fully selected, and those were the same defect
counted twice.

There are two ways a list is replaced and they are not interchangeable. A row that names a WORD
seeds the field with it, which is the alias directory and nothing else, since handing over the
word is the whole purpose of that list. A row that names a LIST is hosted, meaning the rows
change and nothing else does, no second window and no text appearing in a field nobody typed in.
Getting that backwards is what the first attempt here did, typing `v ` into the launcher when
the VPN row was chosen, and being told so is what produced the split. Choosing a tool should
hand you the tool.

Hosting costs nothing per tool because it reuses the alias as an invisible prefix.
`Launcher:enterPage(prefix, title)` keeps that prefix and puts it in front of whatever the user
typed before asking the query sources, so the field holds only the typing and the rows are the
tool's own. There is no second row mechanism, no second matcher, and no second definition of
what choosing a row does. A tool is hostable exactly when it is already reachable by a typed
word, `hostedInPlace` in the composition root names the rows that are, and a name whose alias
does not resolve falls back to opening the picker on its own. The placeholder names the list, since
the word that reached it is no longer visible. Backspace on an empty field leaves it, which is the
atom's `back` hook and the same press that steps out of a typed scope, and it is listed in the hint
panel as a key with no chord, gated on there being a list to leave, see `chord = false` above.

What a hosted list does not carry is the keys that are the tool's own rather than the shared j,
k, i and x, so reveal, copy path and browsing a folder in file search, and the settings level in
browser tabs, are still a chord away. Closing that means letting a scope carry a tool's extra
verbs, which is worth doing and has not been done.

So a new list tool is asked one question before it is given a chooser of its own, which is
whether anything ever reaches it from another list. If something does, that entry hosts or seeds
rather than showing, and a chooser is opened only by the paths that have no live list to replace,
the tool's own chord and a click whose row could not be resolved.

**A row may mean this list becomes another list, and saying so takes a key away from the
widget.** `Chooser`'s optional `intercept` is asked for the highlighted row before that row is
allowed to close, and true in reply means the consumer has already done whatever the row meant,
so the atom rebuilds the list from the top and stays open. The atom deliberately does not learn
what the row meant, only that it was not a completion, which is why one hook covers both seeding
a word and hosting a whole tool. `back` is the pair to it, asked on Backspace while the field is
empty, the one press that otherwise does nothing at all.

There is no polite way to do the first part. `hs.chooser` hardwires Return to complete and offers
nothing before that, so a consumer is told a row was chosen only after the window is gone, and a
row whose whole meaning is that this list becomes another has nothing left to change by then. So
the atom's key watcher, which existed to observe for the idle hint panel, now also consumes Return
when the highlighted row answers. That was verified rather than assumed, an eventtap returning
true on Return leaves the chooser open with nothing chosen where the same press let through closes
it and selects the row. `insertSelected` asks the same question through the same helper, because
that key is ours and Return is the widget's and the two agree only by asking one thing.

ASKING WHAT A ROW WOULD DO MUST NOT DO IT, which the launcher's side learned the hard way. A
shortcut hint used to ask on every highlight move purely to decide what to call the primary key, and
an answer that acted while answering hosted the tool under the cursor the moment the panel looked at
it. So `Launcher:_replacementFor` hands back the work as a callable rather than a yes and only the
take calls it. That hint no longer asks, so there is one caller now, and the shape is kept because
collapsing it would put the effect back inside the answer for whoever asks next.

A CLICK IS ANSWERED THE SAME WAY, and getting there is the one part that needed something new.
A click carries no row number the widget will admit to, and it cannot be asked for one while the
button is down, because it moves its highlight on the RELEASE. Measured, not assumed, the
selected row was still 1 after holding the button on the fourth row for 120ms. So the row comes
from the accessibility tree, where each row carries its own frame and a point can simply be
tested against them. That is also why it is not computed from `rowH`, since the widget renders
rows at its own height and settles to a more compact one after the first show, so arithmetic
would be right on some opens and off by one on others. The press is consumed once a row answers,
and the release with it, so the widget never sees half a click it might act on after the list
under the pointer has changed. A consumer should still answer `run`, which is what a click whose
row could not be resolved falls back to.

**Seeded text leaves the caret after it, never selected.** `hs.chooser:query` leaves everything
it just wrote selected, so text handed to a field on the user's behalf turned the next character
typed into a deletion of the whole thing. Seeding `t ` and typing silently dropped the scope and
searched for the letter, which reads as the seeding never having worked. `Chooser:setQuery`
collapses it, reaching the field through the accessibility tree because `hs.chooser` exposes no
field object and no caret api, the same route the row text inset was measured by and the same
one-visible-chooser-window assumption the frame settle already makes. It takes effect at once, so
no timer is involved. Doing it in the atom rather than at the caller fixed the file search folder
browse at the same time, which had the identical bug for the identical reason.

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
is never hunted for at the bottom. It reads Back and it carries the ⬅️ glyph, one
label and one glyph across every menu here, so stepping out looks the same wherever
it is met rather than each menu inventing its own way out. Two related cases follow
the same spirit rather than the letter. A confirm screen leads with the safe cancel,
DisplayProfiles' delete leads with Keep, so the default and a stray Return do the
harmless thing. A
single input screen, where the field is a text entry and Return must commit the
typed value, leads with the confirm row instead, DisplayProfiles' rename and
capture lead with Save so Return saves, with Back trailing. So the rule is Back
first on a navigable menu, and the safe or committing action first where selecting
the first row on entry is what the user means.

A nested list that is a query scope rather than a level of a menu has no Back row at
all, and that is not an exception to the rule but the case the rule is not needed for.
Deleting the space that entered the scope is what steps out, so back is ordinary text
editing with nothing to bind, nothing to draw, and nothing that can disagree with the
field about where you are. The alias directory is that shape. When a nested thing can be
entered by typing, prefer it, because a row is only worth adding where there is no text
to delete.

**One matching policy for every chooser.** How a query filters a list is a single
policy, decided once at the root and shared by every chooser, the same Strategy
through injection shape as the overlay display screen. The matcher lives in one
file, `Spoons/Olm.spoon/lib/chooser/match.lua`, a pure `match(query, hay) -> score or nil` where
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
Hyper+Cmd+j/k or with a trackpad over the pane, both through one `scrollPreviewBy`,
clamped to the overflow and clipped to the inner box. The trackpad half is not the
clipboard's own, a canvas cannot report a scroll, so the atom watches for one over the
companion rect and calls `onScroll` with a distance in points, normalising a wheel
notch against a trackpad's pixels and flipping the sign once so a pane never has an
opinion about direction. See the file search pane, which was where that gap was found. The canvas
pane and the docked shortcut panel share the palette's `preview.bg`/`preview.border`
so they read as one surface. Crucially the file storage and the preview sizing are
decoupled from the UI: `manager/store.lua` owns the media lifecycle and
`manager/preview.lua` is a Chain of Responsibility that produces the downscaled
PNGs off the main thread (sips for rasters, ffmpeg for video, `hs.image` for
pdf/icns), knowing nothing about the UI. `ui.lua` only consumes the resulting
`e.prev`/`e.thumb` paths, so swapping the webview for the canvas touched neither.

A frozen file, one small enough to copy rather than only link, lives in its own directory
named for a freshly drawn id, with its original basename kept inside, `filesDir/id/basename`
rather than one flat directory of generated names. The directory is what stops two frozen
copies of the same name from colliding, which is what a flat generated name used to be for,
so moving the id onto the directory frees the basename to stay exactly what was copied. A
current layout copy's basename happens to be exactly what a receiving app names the pasted
file after, but only because `writtenFilePaths` in `monitor.lua` names it from the entry's
own path rather than from this copy, since trusting the copy's own basename was the real
defect an older version of this code carried, a file pasted back out of history losing its
name to a flat layout copy's generated basename, `file-1785616767-83059.jpg` in place of the
screenshot it actually was. An entry frozen before this layout still has its old flat path and
still works forever, every read site follows whatever path is stored rather than assuming a
shape, and `media.release` and `media.enforceBudget` both derive the directory to remove from
the configured `filesDir` rather than from the stored path's own parent, so an old flat entry
is never mistaken for owning a directory and eviction can never be pointed at removing
`filesDir` itself.

A paste out of history always lands under the name the user copied, because `writtenFilePaths`
in `monitor.lua` pairs each file's bytes with the basename of the entry's own path and hands
that pair to `manager/media.lua`'s `resolveForPaste`, the one function that turns it into the
path actually written to the pasteboard, and the cache copy is never consulted for a name, only
for bytes. That holds for every layout and every app. Pasting into a Finder window that already
holds a file of that name gets one thing more, Finder's own same folder numbering, `report
2.txt` then `report 3.txt`, in place of its cross folder prompt, Keep Both, Stop and Replace, a
prompt easy to miss and one that dies unanswered after a few seconds, quietly losing the paste.
That extra step alone needs the destination, so it runs only when `manager/finder-target.lua`,
the one file in the feature that knows Finder or AppleScript exist at all, answers a folder by
asking Finder's own insertion location, while every other app hands `resolveForPaste` no folder
and gets the corrected name with no numbering. Either way a changed name is made real on disk by
staging, a hard link when possible since that costs no space whatever the file's size, and a
copy only for a file within `maxFileSnapshot`, written fresh into its own directory beneath a
staging root kept separate from every frozen copy and every original. A folder is never staged,
since a folder cannot be hard linked and copying one is not worth it, and a file that cannot be
staged any other way is passed through unchanged too, so both fall back to meeting Finder's own
prompt exactly as before rather than something worse. `manager/init.lua` is the only file that
names this concrete adapter, injecting it as an overridable config key so the numbering can be
swapped or turned off without either of the other two files learning that Finder exists.

**Clipboard append and sequential paste.** Two clipboard actions need no list, so they are the
only clipboard keys not on Hyper. They are global Ctrl and Option combos, on C and V, because
they extend the plain copy and paste keys and are pressed mid edit rather than reached through a
leader, the same reasoning that leaves the terminal toggle on a plain combo. Ctrl and Option is
the free corner of the keyboard, since Apple keeps Cmd in every menu shortcut, so a Ctrl and
Option letter is almost never an app command. Cmd and Option was the first choice and is not
usable, Finder puts copy as pathname and move item here there and the design tools put copy and
paste properties there, and an app by app pass through list was rejected as more confusing than
the feature is worth. Being global they sit in no leader's cheat sheet, so their launcher rows
are their only listing, which is why both carry a `description`.

Every step of a walk says what it handed over and not only where it is. A step whose entry the
receiving field refuses is otherwise indistinguishable from a key that did nothing, which is not
hypothetical, a screenshot at position two of history walked into a plain text notes app read
exactly like a dead key and was reported as one. The refusal cannot be detected from here,
because the pasteboard write succeeds and only the app's response is missing, so the message names
the kind instead. A field that stays empty under a message reading `2 of 4, file Screenshot.png`
explains itself.

A step landing on a multi file entry says so as well when part of it has since been deleted, the
same report a user asked for after a file step looked like it silently did nothing. The chooser
already carries this fact as a row badge, Deleted or Linked, from `media.fileBadge`, and the walk
draws on that same rule rather than keeping its own copy of it, so the two can never disagree
about one entry's state. What differs is how each asks. The chooser memoizes the check because
filtering rebuilds every row on every keystroke, while the walk asks fresh at the moment of the
press, since the whole point is the file's state right then rather than a stale answer, so
`fileBadge` takes the existence check as a parameter and knows nothing about either caller's
cache. It only ever has something to add once a step's paste already succeeded. A single vanished
link leaves nothing for the write to put on the pasteboard at all, which the existing `is gone`
failure message already reports, so the gap this closes is the one that message cannot see, a
multi file entry where some elements survive and paste while one has been deleted, which used to
read as an ordinary paste that quietly dropped part of what it carried.

Both live in `manager/session.lua`, the transient session state over the persistent history. They
share a file because they end on the same signal, a genuine copy, and splitting them would
duplicate that wiring. The module still owns no watcher and no timer of its own, and still has no
`start` or `stop`, because most of what ends a run is observable when the next key is pressed and
is read there, the frontmost app and the idle window. One ending is not, a plain Cmd+V, which
changes nothing on the pasteboard and so cannot be read at a press the way the other two are.
`manager/monitor.lua` watches for that one with an event tap, since a tap is the only way to see a
key that writes nothing, and calls `resetSequence` the moment it sees a real one, the same seam a
genuine copy already uses through `onCapture`. That tap is a real cost this module did not carry
before, a global listener sitting in the path of a very common keystroke, so it is built to only
ever observe, reading the event and returning it unchanged, never swallowing, delaying, or
rewriting it. The walk pastes by posting a synthetic Cmd+V of its own through `pasteOp`, and the
tap would otherwise see that keystroke too and mistake it for a user press, resetting every walk
mid burst. `pasteOp` already reasons about exactly that keystroke for its self capture guard, so it
counts itself in and back out across that same window, and the tap stays quiet while the count is
above zero rather than guessing from a timestamp or a suppression delay. The tap lives in
`monitor.lua` rather than in `session.lua` because the monitor already owns every pasteboard and
keyboard concern in this folder, including the guard state the count above reuses, while
`session.lua` would have needed a start and a stop it does not otherwise carry just to host a tap
of its own. The two timers `session.lua` itself still holds drive nothing, one spaces out a queued
press and one releases a claim whose release never arrived. Four decisions are worth knowing.

The append glues onto row 1 only when row 1 is text that arrived by a real copy, and otherwise
starts a new row, so the first press always behaves like a plain copy and only the presses after
it accumulate. A plain copy is what ends an accumulation, so there is no key for that. The real
copy test cannot be replaced by an age test, which is the trap here, because floating an entry to
the front refreshes its recency, so an old snippet just pasted out of the picker looks brand new
and an append would silently rewrite it. Only the capture side can still tell, which is why the
monitor grew one hook, `onCapture`, fired after a genuine copy and nowhere else.

An append is the one thing that changes an entry's content after capture, which two places had
assumed could never happen. `store.replaceText` is the only way it happens, so the dedupe key
recompute that keeps identity honest lives there alone, and `ui.entryChanged` drops that entry's
cached searchable text, without which a search would keep missing the words just appended.

Both keys, the append and the sequential walk, are built on the shared insertion primitives that
used to live only here, direct insertion against a paste, the restore guard, the held chord hazard,
the queue against the receiving app's own clock, and how to measure any of it. That trail moved to
`Spoons/Olm.spoon/CLAUDE.md`, in its Paste section, once the primitives themselves moved into the
core as `lib/paste.lua`. It stayed duplicated here for a while on purpose, since the original spoon
still embodied it on the other side of the composition root's toggle and a reader landing on this
file needed it to be true there too. The original is retired now, so this file keeps only this one
pointer where that whole trail used to sit, and the full account lives beside the code it describes.

Both actions report what they did, since each changes something invisible, an entry growing
offscreen and a position in a list. The message goes out through an injected `onMessage` and the
root draws it on the shared `CanvasPanel`, following the transient feedback surface rule above.

**Launcher.** Hyper+Space opens a filterable app switcher and command runner, the built-in one, built over the Chooser atom. It is a coordinator spoon that owns the app scan caches and an `hs.application.watcher`, orders open apps by recency the way Command+Tab does, and follows the picker checklist above. Its decision trail and internals live in `Spoons/Olm.spoon/host/launcher/CLAUDE.md`.

Besides its catalog of apps and commands it also shows rows *computed* from what is
typed, supplied by injected query row sources the root composes in order. A source is
any table answering `rows(query)`, so the launcher learns nothing about what any of
them computes, the same shape as its leaf action dispatch but for producing rows
rather than running them. Two ship, `Arithmetic` and `Convert`, and they are two
spoons rather than one calculator precisely because they fail differently, which makes
them the worked example of the dependency policies above. Arithmetic is native Lua and
can never be unavailable. Convert declares its calculator tool required, so when that
tool is absent the root leaves it out of the source list and no conversion row exists
at all, while arithmetic is untouched. Choosing a computed row hands its value to an
injected `copy` action, so the launcher still never learns what a clipboard is. Neither
source is a bound shortcut, so both are exempt from the two discoverability mandates.

A source may also *claim* the query, meaning its rows are the whole list and the catalog is
not shown at all, which is how a typed word hands the launcher over to one tool. An alias
plus a space scopes the list, so `k 2h` reaches the keep awake picker without leaving the
launcher and deleting the space hands the list back. Olm's QueryScope host is the source that
claims, and it names no tool. This root names the concrete scopes, each a thin adapter over
a tool that already answers a rows and a select, so a tool never learns it can be scoped.

Adding one is two edits and there is no third. The `aliases` and `glyph` fields go on that
tool's existing `config/keys.lua` entry, and one `scope(name, policy)` line goes in the list
here, where the policy is only where the rows come from, what choosing one does, what
previewing one does, and whether the shared matcher applies. Everything a scope says about
itself is read from that one entry by that helper, and one identity ties it together, the
tool's key in the pure data, which is also what its launcher row descriptor carries and what
the scope is registered under. So the hint on its row, its place in the alias directory, and
the text that enters it all follow from the two edits, and there is nowhere left to state a
title, a glyph, or an alias a second time and have the two copies disagree. That identity is
also why the keep awake scope is named `caffeinate` rather than `keepAwake`, since a scope
this root cannot find by the tool's own name is a scope every derived surface has to be told
about separately.

The aliases live in that pure data so the row advertising them and the resolver
answering them read one thing and cannot drift, the same reason a key is data rather than
something each surface knows. The `glyph` is there for the same reason and only where it
earns it, a scoped tool being drawn both on its launcher row and on the rows its scope
produces, while a row that appears in one list only keeps its glyph at that call site. Exposing the pair is the one change a scoped tool takes,
`Caffeinate` exports the `rows` and `select` its own chooser was already built from, which
hands out the data rather than inviting a second copy of the parse, so two surfaces cannot
disagree about what a typed value means. Nothing here is a bound shortcut, so the mandates do
not apply, and discoverability is the alias hint on the tool's existing launcher row. The
grammar, why no scope is remembered between keystrokes, and why a claim holds even when nothing
matched, live in `Spoons/Olm.spoon/host/queryscope/CLAUDE.md`. Adding the spoon needed a restow, since
`~/.hammerspoon/Spoons` holds one symlink per spoon.

The scopes come in three shapes, which is the useful thing to know before adding one. Some are
the plain shape above, a tool exporting its rows and its select, which is keep awake, VPN,
emoji, browser tabs, and file search. Menu search is an olm plugin configured from the root
now. The alias directory alone is root policy rather than a spoon, so the root is both the
adapter and the thing adapted there. Apps, window
actions and System Settings panes
are neither, they narrow the launcher's own catalog, so they read `Launcher:rowsOfKind(kind)` and
hand a chosen row back through `Launcher:runItem`, which keeps one row builder and one dispatcher
however a row is reached. Those three scope a group of rows rather than one row, so like menu
search they have no row of their own to advertise an alias on, and their `config/keys.lua`
entries carry a description and an alias and no key because they open nothing. The alias
directory is where they are found instead.

**The alias directory, and the one door back into the launcher.** Every alias that scopes the
launcher is listed in one place, reached by the Aliases launcher row and by `?` and a space, and
choosing a row hands the launcher back with that tool's own word already typed. So a scope with
no row of its own is still discoverable, and a word is learned by being handed it rather than by
being told it.

Three wiring facts about it are worth knowing here. It is a scope like the tools it lists rather
than a second chooser, which is what makes Back ordinary text editing, deleting the space, and
which is why it needs no context block, no predicate, no `choosers` entry, and no shortcut panel
of its own. It is this root's policy over `QueryScope:catalog()` rather than something that spoon
offers about itself, so the resolver still names no scope at all including its own, and its
alias sits in `config/keys.lua` like every other rather than as a constant inside a spoon. And
whichever way the word arrives, it is asked of `QueryScope:queryFor(name)`, so which alias is
canonical and the separator after it stay with the grammar that owns them.

Choosing a directory row seeds the field, by Return, by the insert key or by the mouse, so the
word arrives under the list that is already there and nothing closes. It was a reopen at first,
and it worked while looking broken, a list closing and another opening to deliver two characters.
The Aliases row itself is hosted, so opening the directory costs no reopen either, and
`enterScope` is what remains for the one way in with no list to replace, a click whose row the
accessibility tree could not resolve, which arrives after the chooser has already gone.

This is the one list here whose rows hand over a WORD rather than a list, which is the whole point
of it, so it is also the one place seeding is right. Every tool row is hosted instead. Both are
under one list becoming another in place, above, along with why confusing them is a defect and not
a preference.

How the aliases read is one closure here, `aliasHint` and `aliasLabel`, because both surfaces
state them, the tool's launcher row and the directory's own rows, and phrasing it twice is how
the same tool ends up reading two ways depending on where you met it. The launcher takes the
question rather than the answer, asking per row as it builds, which is what made the hint
impossible to forget on a row after it had already been forgotten on file search. Both are asked
live, so they state the aliases that resolved rather than the ones config requested, which a
collision can make different.

File search is the first scope whose alias is punctuation, `/` then a space, which the grammar
already allowed since its only rule is one word with no whitespace. It matches that tool's Hyper
key, so there is one thing to remember rather than two, and a slash reads as a path everywhere
else. It is also the first scope over an ASYNCHRONOUS list that is not merely slow to arrive but
stateful, so two things had to be added rather than adapted. Entering the scope needs a session,
which is what makes an empty query answer with the recent list instead of a loading row nothing
ever resolves, and it JOINS one rather than beginning one. Beginning it was the first version and
it was a loop, since a scope is asked for rows on every keystroke and again on every redraw, so a
reset each time cleared the very state the tool uses to recognise a repeat, and each answer
announced a change that caused another ask. The tool's own `CLAUDE.md` has the full trail, and the
general lesson is that a scope has no open, so anything a picker does on open has to be expressed
as make sure this exists rather than as start this. And the tool's `onResults` is composed rather
than replaced, so both surfaces are told when rows land and each one's redraw does nothing while
it is off screen. Its rows come from the tool's own row supplier and its choosing from the tool's
own select, so a row cannot say one thing in the picker and another in the launcher, and a use is
recorded once wherever it happens.

It is also the scope that earned `QueryScope` a second verb. Choosing was the only thing a scope
could do to a row, and a file list is the case where a line of text cannot settle which of two
matches you meant, so the preview comes along through an optional `peek` and the alias reaches the
whole reason for the tool. The launcher gates that key on live state, since only a claimed row
from a scope offering a peek has anything to show, and asks the same question before printing it
in the hints. What stays behind in the picker is reveal, copy path and moving up a level, since
those are that tool's Hyper context.

The directory then earned the third, `redirect`, for the opposite reason. Peek exists because a
row cannot say enough about itself, redirect because a row does not want to be taken at all, it
wants to put a word in the field. Both are optional, both route home the same way, and a scope
offering neither is unaffected by either.

A scope may be narrower than the tool it reaches, and browser tabs is the case that works.
Its settings level is a step into a second list, which a scope cannot show, so the scope lists
tabs and the tool stays the way to the switches. Nothing the scope was for is missing. Text case
is the case that failed the same test and was removed after being built, because a scope cannot
read your selection and so cannot preview it, which is the reason to open that tool at all. The
rule is that a scope may be smaller than its tool but not smaller than the reason for the tool,
and an alias reaching a diminished copy of a tool is worse than there being one way in.

A tool whose companion pane IS the reason for the tool cannot be scoped in place, which rules
out the clipboard and Local Servers. The launcher's chooser reserves no companion pane and the
width is fixed when a chooser is built, so a scope always shows the rows without the pane. For
the clipboard that means losing the preview, which is most of what it is, and for Local Servers
the process tree, which is what makes pressing stop safe. Scoping either would mean teaching
the launcher a preview pane a scope can claim, and that is a real change to the atom rather
than another entry in the scope list.

File search has both a pane and a scope, and it is the case that shows the rule is about the
pane's WEIGHT rather than about panes. Its reason is finding a file by name and acting on it,
which the scope does in full, and the pane only helps you decide between two rows that already
matched. So `/ ` lists rows with no pane, exactly as it did before the pane existed, and
nothing the alias was for is missing. The same test the text case scope failed and the browser
tabs scope passed, applied to a pane instead of to a second level.

**ActionPanel.** Hyper and period opens a searchable list of the live chooser's own verbs,
the things a person forgets the chord for, never its navigation, the shared moving,
inserting, closing, and scrolling every context already carries. It is a host spoon like
Launcher and QueryScope, but a decorator rather than a coordinator, installed once at
`Chooser.configure`'s decorate seam so every chooser gains it with no edit to any of the
twelve places one is built and no consumer learning it exists. Opening it swaps a chooser's
own rows for the panel's, built by the same `rowsFor` the docked hint bar reads, so the two
cannot print two different words for the same chord, and choosing a verb restores the
highlight to the row the panel was opened over before running it, so the panel and the chord
act on exactly the same row. Every action is classified first, verb or navigation from a
named set the root's own `actionKinds` maps an action name onto, and a panel row is never
navigation, the panel's own chord included. What it does not yet reach is a list hosted
inside the launcher, whose own verbs are still a chord away rather than in this list. The
decision trail and internals live in `Spoons/Olm.spoon/host/actionpanel/CLAUDE.md`.

**Emoji.** Hyper+J opens an emoji picker. Emoji is a facade over interchangeable backends, the same shape as Chooser, so the root names which one the key opens in a priority ordered list by reference and the first available wins. Three backends ship, the built in picker over the Chooser atom, the macos Character Viewer triggered by Ctrl Cmd Space, and a custom backend that runs an injected callback so an external picker reached by a URL scheme or a trigger becomes a backend with no file of its own. The default is the built in picker, which owns one vendored dataset fetched once by its `regenerate.sh` and committed as `data.lua`, merging the GitHub gemoji set with a safe slice of native Unicode symbols from the official Character Database, currency and arrows and math and the Mac modifier keys and more, so a query by name, shortcode, tag, or category finds a glyph without its exact Unicode name. That artifact is a Lua table rather than json because `hs.json.decode` is quadratic in the number of objects in an array, three seconds for that set against six milliseconds through `loadfile`, and a spoon that loads a dataset in `configure` pays it on every reload rather than once. It is worth knowing beyond this spoon, since any file holding thousands of objects meets the same cliff, and `ClipboardHistory` still spends about 176 ms of every reload decoding its history for exactly this reason. Every matching emoji ranks above every matching symbol, so a query lists the emoji first and the plainer glyphs below. A pick is inserted into the focused field through an injected `onInsert`, so the backend never learns the effect, and it follows the picker checklist above. The root wires `onInsert` to the clipboard manager's `pasteText`, which pastes the glyph rather than typing it, because a synthesized keystroke mangles an astral glyph like an emoji in a terminal and in some native apps while a paste carries the real bytes everywhere, and `pasteText` snapshots the clipboard and restores it after so the paste stays invisible. It degrades to typing when the clipboard manager is absent. The provider strategy, the decision trail and internals, the safe symbol selection, the render based tofu filter, and the icon memory behavior, live in `Spoons/Olm.spoon/plugins/emoji/CLAUDE.md`.

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
emoji insert takes. The decision trail and internals live in `Spoons/Olm.spoon/plugins/textcase/CLAUDE.md`.

**BrowserTabs.** Hyper+W lists every open tab across the browsers that are switched on,
ordered most recently looked at first, each row carrying its browser's application icon, and
opening one selects that tab and raises its browser. The last row is a Settings door leading to
a level where each browser is switched on or off and shows whether it is installed, open, and
allowed to be scripted. It follows the picker checklist, its `browserTabs` context giving it the
shared j, k, x navigation with i bound to the tool's own in-place `enter` rather than
`insertSelected`, the same as DisplayProfiles, since it is a menu and a drill into settings must
not close and re-show.

The wiring choice that matters is where the browsers are named. The spoon exposes its backends
as `spoon.BrowserTabs.providers` and the root names the concrete three and their order, the
Emoji precedent, so adding a browser is a line in that block plus a file in the spoon's
`providers/`. `providers.chromium` is a factory taking a name and a bundle id, because Chrome,
Brave, Edge, Vivaldi and Opera all share one AppleScript dictionary, so which application is a
parameter the root supplies; Safari and Arc each have their own dictionary and own their bundle
id. The root also decides `defaultEnabled`, which is Safari alone, so a fresh machine scripts
one browser and raises one Automation prompt and the rest are switched on deliberately. Those
choices persist in `hs.settings` rather than a git tracked file, since they are per machine
preference, matching the overlay display policy rather than the DisplayProfiles store.

Three cross-cutting facts worth knowing here. A browser that is switched off or not running is
never scripted at all, so it costs no Apple Events and raises no permission prompt. Nothing
watches the browsers, so the list is ordered by what you have opened through the tool and by
nothing that happens in a browser, which is what stops it rearranging itself between one open and
the next. And the tool opts out of the atom's shared matcher and scores its tab rows itself with
the matcher the root injects, because it is a stack of frames with pinned rows and uniform
filtering would rank away the Back row and pull the Settings row into the tab ranking, so the
matcher is passed in explicitly rather than inherited. Everything else, why the order stopped
being observed and what that cost, why the last tab you opened leads and what was tried on top of
that before it was taken back out, why a window is placed by its id and never by its index, why tab
identity is the bundle id plus the URL and what that costs when a page navigates, why the
permission probe is a Swift helper, why Arc reports no active tab, and why Firefox is absent, lives
in `Spoons/Olm.spoon/plugins/browsertabs/CLAUDE.md`. Adding it needed a restow, since `~/.hammerspoon/Spoons`
holds one symlink per spoon.

`BrowserTabs:explainOrder(n, cb)` prints the top rows with the rank the memory gave each one, for
settling an argument about the order against the machine rather than against the code.

**Processes.** Finds the development servers you left running and stops them, opened from
the launcher only with no dedicated key. Its launcher row reads Local Servers rather than
Processes, because the list is local port holders, containers and portless watchers and
never the whole process table, and the old label promised a system monitor this is not.
The spoon keeps its own name, since that one is an internal identifier nobody reads. The
words the title dropped live on the row's hidden `keywords`, so typing process still finds
it. It follows the Capture layout, an engine over
interchangeable discovery sources, and the DisplayProfiles shape of a spoon whose surface is
its own `chooser.lua` beside the engine, so it is configured twice like DisplayProfiles is.
The spoon's own root reads the pure data in `config/processes.lua` and hands each source the
slice it needs, staying the one place that names both the concrete sources and their order,
and the main root injects only the view deps every chooser receives. It follows the picker
checklist, its `processes` context giving it the shared j, k, i navigation with x to close
plus three actions only it answers, a force stop, a rescan and a sort by load, routed through `routeNav` so
they are no ops on any other surface rather than naming this one directly the way the
clipboard-only append and delete do. It overrides the shared fuzzy matcher to `words`, the
same choice the clipboard makes, because a query here is a real fragment you remember, a
port number or a project name, not an abbreviation of a short known label. Adding it needed
a restow, since `~/.hammerspoon/Spoons` holds one symlink per spoon. The source contract,
the port claim rule that collapses the docker proxy listeners into named containers, the
group signalling and its guards, and three hs.task and lsof facts that will bite anyone who
touches the shellouts, live in `Spoons/Olm.spoon/plugins/processes/CLAUDE.md`.

**DockAutoHide.** A launcher row named Dock that is a doorway rather than a toggle, opened
from the launcher only with no dedicated key, stepping into a page of two rows, one for the
Dock's own auto hide setting and one for its show delay, covering the Dock alone since
StageManager, which was meant to be its companion, was removed from the config entirely
before this plugin was written. Choosing either row flips it in place, the chooser stays
open, and the row's own wording changes because it was rebuilt fresh rather than patched, a
QueryScope page like any other. The hiding row reads Turn Dock Hiding On while hiding is off
and Turn Dock Hiding Off while hiding is on, and the delay row reads Make the Dock Instant or
Restore the Default Dock Delay, so both always name the action choosing them is about to
take rather than the state the Dock happens to be in. Restoring the default deletes the
delay key rather than writing a number, since an absent key is the genuine default state on
a machine where it has already been overridden. Hiding is felt at once through a System
Events push, and a delay change is invisible until the Dock re reads its preferences, so a
delay change restarts the Dock through `killall` and hiding never does, an empirical
difference rather than an inconsistency. Every tool it shells out to, `defaults`,
`osascript`, and `killall`, is resolved through the shared dependency door rather than being
named in this file or probed for. The decision trail and both findings live in
`Spoons/Olm.spoon/plugins/dockautohide/CLAUDE.md`.

**FileSearch.** Hyper+/ finds a file by name and does something with it, opening,
revealing, browsing into, or copying the path of whatever is highlighted. Activity
Monitor moved to Hyper+\ to free the key, the two reading as a pair, one for what the
machine is doing and one for what is on it. It follows the Capture layout, an engine over
interchangeable search sources, and the DisplayProfiles shape of a spoon whose surface is
its own `chooser.lua` beside the engine, so it is configured twice. It follows the picker
checklist, its `fileSearch` context giving it the shared j, k, i navigation with x to close
plus four actions only it answers, browse into a folder, reveal in Finder, open the
containing folder, and copy the path, routed through `routeNav` so they are no ops on any
other surface. It also answers the two `scrollPreview` actions the clipboard already used,
which is what made them worth routing rather than naming at one surface.

Its subtitle is fitted to the row rather than left to be cut, and it is the first consumer of the
atom's `textBudget` and `textWidth` above. It is elided at component boundaries, keeping two head
components and as much of the tail as fits, so a long path reads
`~/Development/…/.hammerspoon/Spoons`. The head is two rather than one because one is nearly always
a bare tilde, which spends a separator to say what you already knew, while the folder under it
names the domain. The row carried two labelled ages until measuring
put a number on them, 57 percent of the line, at which point both were dropped and the room went to
the path, which is the only field that tells four files of one name apart. Both are still in the
pane for the row under the cursor. Why whole components rather than squeezing each to a letter, why
the free `truncateMiddle` was wrong here, and the longer version of the ages decision, are in the
spoon's own file.

How it shows the highlighted file is a Strategy this root chooses, `PreviewProvider.SidePanel` or
`PreviewProvider.QuickLook`, named by reference so no provider string appears at any call site.
The chosen one leads a chain with the side panel behind it, first available wins, the same shape
the emoji backends use. The contract carries WHEN as well as how, because a canvas already on
screen can follow the highlight for nothing while a window would have to relaunch on every arrow
key, so the providers differ in their trigger and the surface reads one field to decide whether to
run a highlight poll and which keys mean anything. That is also why the choice is made near the
top of this file rather than at the configure call, since the bindings depend on it. Quick Look
opens a real native panel, built by a small Swift helper beside the viewer on the Eyedropper
precedent, because `qlmanage -p` opens no window on this macOS and Hammerspoon binds nothing for
it. The panel is nonactivating and sits at the pop up menu level so the chooser under it keeps
focus and stays visible, which is the whole reason it can be a preview of a list rather than a
replacement for it.

The side panel reserves a companion pane and describes the row in it, the name, the location, the
kind, the size, both dates and when you last reached for it, then a folder's newest entries, a
file's head, or a rendered picture of anything Quick Look can draw. The row subtitle deliberately
carries no size, because reading one costs a call per row and a page is two hundred rows, while
the pane describes one row and gets every fact from a single stat. What the pane shows is a Chain
of Responsibility over describers where declining passes the row along, and the pictures behind it
are a second chain of generators where only Quick Look caches. It exists only because the root
injects `CanvasPanel.surfaceElements`, and without that line it reports itself unavailable and the
chain moves on.

Two wiring choices are the ones worth knowing here. It opts the atom out of matching
entirely with `matcher = false`, because its query is structured rather than a plain
filter, and the root's `words` matcher is injected into the *engine* instead, where it
narrows a held result set between round trips. So the shared matching policy still applies,
one layer further down than anywhere else. And it is the first consumer of the shared row
icon memo, a closure in the root beside the other view deps, keyed by extension rather than
by path and dropped when the chooser closes.

It is also the one tool here that accumulates state about the person using it, a decayed
count of the paths you act on, which floats what you use to the top of the list you land on
and breaks ties between equally good matches when you have typed something. That store is
per machine behaviour rather than configuration, so it lives in `hs.settings` like the
overlay display choice and the browser toggles rather than in a git tracked file like the
display profiles, and it is named in the spoon's own root. It must stay out of
`~/.hammerspoon` whatever else changes, since it is written on every action and that tree is
watched, so a store inside it would reload the config every time you opened a file. Why the
score is applied two different ways, and why macOS's own last used date could not be used
instead, are in the spoon's `CLAUDE.md`. That memo is a closure and not a spoon because
it has no lifecycle, and it holds in memory handles rather than files because NSWorkspace
already caches them, so there is deliberately no cache directory to configure. The
clipboard has its own equivalent today and is the obvious second consumer, left alone until
this one has been used in anger.

Its own `config/filesearch.lua` holds the pure data, the type registry that decides what a
dot attached token means, the directory aliases, the prune list, the pane's read caps and
cache location, and the caps and timings.
The grammar, the source ordering and the two measurements behind it, why one round trip per
search rather than per keystroke is the whole performance story, why there is deliberately
no result cache, and four Spotlight predicate facts that will bite anyone who touches the
queries, all live in `Spoons/Olm.spoon/plugins/filesearch/CLAUDE.md`. Adding it needed a restow, since
`~/.hammerspoon/Spoons` holds one symlink per spoon.

**Eyedropper.** A screen colour sampler on Hyper+2, on the native macOS
eyedropper. It is deliberately not a chooser, so the picker checklist above does
not apply. It is a lone mechanism like lock and sleep in that it needs no Hyper
context, predicate, or `choosers` entry, but unlike them it is a registered tool,
`colorPicker`, so its base HyperKey binding is wired through the tool registry's
`shortcuts()` rather than through `bindHyper`, which still binds only lock and
sleep, phase seven's fifth packet. It is surfaced as the color picker launcher row
through the same special action dispatcher every registered tool's row goes
through. A pick shows Apple's own `NSColorSampler` loupe, the same smooth
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
