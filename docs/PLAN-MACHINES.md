# Plan, one directory per machine and tools that never know which machine they run on

Written 2026-10-22 with Milos and revised the same day after a review. The goal is the one he
stated. Each machine takes some things and not others, and some of its keys differ, and that
should be visible in the repository, picked up on its own on each machine, and easy to extend as
more tools arrive. No tool may learn which machine it runs on. A tool cares only about what it is
handed, such as which modifiers are held, never about which program produced them.

The facts below were checked against the tree on 2026-10-22. Recheck any citation before acting
on it. `decisions/machine-profiles.md` is the decision record this plan changes, and it is written
in the same change as each phase. `decisions/olm-leader-keys.md` takes phase 1, and a new
`decisions/kanata.md` takes phase 3.

This file lives in `docs/` at the root because it moves the repository as a whole, the machine
layer, the stow step, the reconciler and two modules. A plan that moves only Olm stays in
`Olm.spoon/docs`.

## What is true today

**One table says what each machine takes.** `MACHINES` at the root holds pipe rows of machine,
piece and value, a `default` row per piece, and a block per machine that differs. Seven pieces
exist, mise, hammerspoon, herdr, mole, docker, vpn and tools. `src/machine.sh` is its only reader,
with `name`, `get`, `on`, `listed`, `check` and `capture`. A machine is its `LocalHostName`, or
`MDJ_MACHINE` where it cannot be renamed.

**Four consumers ask that reader.** The stow step adds an optional package that is on,
`src/setup-stow-dotfiles.sh` at 18. `setup.sh` runs a piece's step through `step_if`. The Brewfile
guards a piece's lines with `on?`, handed the machine through `HOMEBREW_MDJ_MACHINE`. The checker
skips presence checks for a module switched off and verifies every row names a known piece. None
of them reads the file itself, but the name `MACHINES` appears in comments across the Brewfile,
`src/`, the root `AGENTS.md`, `README.md` and the decision records.

**Keys are shared and an absent app hides itself.** `config/keymap.lua` holds every key on every
machine, loaded in `init.lua` as `keymap = require("config.keymap")`. An app toggle for an app a
machine does not have is left off the Hyper sheet and does nothing, so most per machine
differences in keys already need no setting.

**One tool already reads machine data.** DisplayProfiles keeps captured profiles in
`config/display-profiles.json` keyed by `LocalHostName`, written by the plugin itself through its
`store.lua`, and picks this machine's entries by name. The plan has to say what it does about
that, see rule 2 below.

**A module declares its own seams and the stow step finds them by name.** `NO-FOLD` and
`SHADOW-PATHS` at a package root are read by `src/setup-stow-dotfiles.sh` through one
`declarations` function, tab separated, and the script names no module. The reconciler finds a
module's `dependencies-collect`, `grants-probe` and `config-probe` the same way.

**A leader is one trigger.** Hyper is Caps Lock remapped to F18 or the four real modifiers, never
both. One leader on two triggers is listed as out of scope in `Olm.spoon/docs/PLAN-LEADERS.md`
until a real case appeared. Kanata on this machine is that case.

**The two triggers answer the contract differently.** The held trigger owns every key while its
key is down, seals over open lists, and binds nothing per row. The modifier trigger claims one
`hs.hotkey` per row, never seals over a list since a modifier combination is the app's own key,
and warns at claim time about a row whose own modifiers overlap its base set, since that row can
never fire.

**Kanata was trialled and kept on 2026-10-22.** Homebrew's kanata 1.12.0 with Karabiner's driver
6.2.0, installed by hand from its notarized package, Caps Lock held as the four modifiers with a
tap for Caps Lock, Right Option held as shift, ctrl and alt, and the top row mapped to brightness,
Mission Control, Spotlight, Dictation, Do Not Disturb, media and volume with fn giving the plain F
keys, since the virtual keyboard kanata types through is not an Apple keyboard. About 19 MB in
three processes. Kanata 1.13, a prerelease today, needs driver 8, so the two move together. The
trial config is `~/Downloads/kanata-trial.kbd` and nothing of it is in git.

## The shape

```
mdj-env/
├── machines/
│   ├── default/pieces                       every piece's default row
│   ├── Miloss-MacBook-Pro-Vicert/
│   │   ├── pieces                           this machine's rows
│   │   └── hammerspoon/keymap.lua           only the keys that differ here, once one is wanted
│   └── Miloss-MacBook-Pro/
│       └── pieces
├── src/machine.sh                           still the one reader of machines/
└── dotfiles/<module>/
    ├── OVERLAYS                             the overlay seams a module accepts
    └── overlay-check                        how the module validates an overlay, found by name
```

**Three layers describe a machine.** Defaults are each module's own shared config plus
`machines/default/pieces`. Optional pieces are rows in `machines/<name>/pieces`, whether a
machine takes a whole thing. Overlays are files in `machines/<name>/<module>/`, how a shared
config differs on one machine, holding only the differences.

**The machine layer translates and no tool reads it.** This is dependency inversion. A module
declares where it accepts an overlay, in an `OVERLAYS` file at its package root found by name like
`NO-FOLD`. The stow step reads the machine's directory and links each overlay it finds to the path
the module declared, and removes a link the machine no longer supplies. The tool reads one
optional extra file at that path and knows nothing else. Adding a seam is a declaration in the
module, support for an optional file in its tool, and an `overlay-check`, with no edit to the stow
step or the reconciler.

**A piece row keeps its grammar.** `machines/<name>/pieces` holds `piece | value  # comment`, the
machine column gone since the directory names it. Every consumer still asks `machine.sh`, so
none of them changes in code.

**A leader listens for both forms.** Hyper and META each gain a second trigger of real modifiers,
Hyper on Caps Lock or shift, ctrl, alt and cmd, META on Right Option or shift, ctrl and alt. A
Composite trigger holds the two over the same four function contract, and Olm reacts to whatever
arrives. A machine without kanata sends F18 and a machine with it sends four modifiers, and Olm is
told neither.

The Composite is chosen over a per machine leaders overlay, which phase 4 would also make
possible, for one reason the overlay cannot give. On a kanata machine where kanata has crashed,
been stopped, or lost its Input Monitoring grant, Caps Lock still arrives as F18 through Olm's own
remap and Hyper keeps working. An overlay would leave that machine with no Hyper at all until
kanata came back. This goes into the Rejected list of `decisions/olm-leader-keys.md` with phase 1.

**Drift is checked on every machine at once.** Each module that accepts an overlay ships an
`overlay-check` that validates every machine's overlay for it offline. The reconciler finds it by
name like a `grants-probe` and knows no module, so an overlay naming an action that no longer
exists is an error wherever it is found.

## Rules that change

These replace the matching lines in the root `AGENTS.md`, the Hammerspoon `AGENTS.md` and the
decision records, each in the phase that makes it true.

1. A difference between machines is data under `machines/<name>/`, a piece row or an overlay at a
   seam its module declares. Never a branch, a fork or a full copy of a file per machine.
2. No tool chooses its behaviour by the machine it runs on. Configuration that differs reaches a
   tool as an overlay it does not know the origin of. The one exception is state a tool captures
   about the hardware under it and writes itself, which may stay with the tool keyed by machine.
   DisplayProfiles is that case and is named in the rule. Moving it under `machines/` would have a
   tool writing into the setup layer's tree through a link, and the keying is what lets two
   machines share its one tracked file without colliding. A second case is named in the rule, or
   it is not one.
3. An overlay holds only differences, and every machine's overlay is validated by its module's
   `overlay-check`. An overlay grown into most of its file means the shared default is wrong.
4. The reconciler stays module agnostic. It finds `overlay-check` by name and never runs a
   module's own reader itself.
5. Nothing is pinned to a version except a formula that must move in step with something
   Homebrew does not manage. Such a formula is held with `brew pin`, upgraded only through its
   module's own step, and named with its reason in its decisions file. Kanata and its driver are
   the first case. `decisions/homebrew-upgrades.md` and the root `AGENTS.md` say so.

The rules that stay are rule 2 of the machine rules, only the machine you are on is yours to
describe, and rule 4, nothing removes what a machine has.

## Phases

Each phase lands with its tests and its decisions entry, and anything that loads live is loaded
with a clean console before the next starts. The order is 0, 1, 2, 3 and 4. Kanata needs only
the directory, so it lands before the overlay seam, which waits for a real overlay to want it.

### Phase 0, measure kanata against Olm's remap

Olm remaps Caps Lock to F18 and Right Option to F16 through hidutil, and hidutil applies to every
keyboard including the virtual one kanata types through. Kanata seizes the physical keyboard, so
the real key may never reach hidutil, but what kanata sends back does. With kanata running and the
stowed main config live, Milos checks four things by hand.

1. Holding Caps Lock gives Hyper.
2. Tapping Caps Lock toggles Caps Lock. Kanata's tap sends Caps Lock to the virtual keyboard,
   hidutil probably turns that into F18, and Olm's held engine then reads it as a tap and toggles
   Caps Lock itself. That would work, by a route worth writing down.
3. Holding Right Option gives META, and tapping it does nothing harmful.
4. A held F18 and four held modifiers do not both fire on one press.

If 1 or 3 fails because kanata sees the remapped key, the Composite cannot keep the remap on, and
phase 1 gains a held half that skips its remap when the modifier half has been heard, decided with
Milos then. If 4 fails, the Composite needs a guard so one physical press fires once. The results
go into `decisions/olm-leader-keys.md`.

### Phase 1, a leader on two triggers

`lib/leader/triggers/composite.lua` holds a held half and a modifier half and answers the contract
per method, not by a blanket or.

- `start` starts both. A half that fails says one console line and the other keeps working, and
  the Composite fails only when both do.
- `bound` passes every row to both halves. The modifier half claims a row only when the row's
  own modifiers do not overlap its base set, and skips one that does without a warning, since
  that row stays reachable through the held half. One note line at load counts what was skipped.
  On a kanata machine those rows are unreachable, the accepted limit of 2026-10-22, Hyper with
  Shift and 4 and Hyper with Cmd and j or k in the clipboard and file search previews.
- `isActive` is true when either half is.
- `owns` and sealing follow the half that is pressed. An F18 press behaves exactly as a held
  leader does today, owning every key and sealing over open lists. A four modifier press behaves
  exactly as a modifier leader does, owning nothing beyond its claimed combinations and
  sealing only when its leader hosts a list key, which Hyper does. How `lib/leader.lua` reads that
  is settled in the phase, and a fixture pins both.

The leaders reader accepts `triggers = { { key = ... }, { mods = ... } }` beside the two single
forms, and `SHIPPED_LEADERS` gives Hyper and META both. A person's entry that writes `key` or
`mods` alone replaces both halves with that one trigger, and one that writes `triggers` replaces
both with its list, so a machine that wants only one form says so plainly.

The keymap reader gains a collision check that holds with or without the Composite. Two rows on
different leaders that resolve to the same physical combination are a problem line naming both,
for example a META row adding cmd and a Hyper row on the same key once both have modifier halves.

The cost is said once in the decisions entry. A plain machine also claims the four and three
modifier combinations its Hyper and META rows use. Fixture goldens show both forms bound with
nothing else moved, every existing golden is unchanged, and a live load on this machine shows no
new console lines.

### Phase 2, machines as a directory

`MACHINES` moves to `machines/default/pieces` and one `pieces` file per machine block, and
`src/machine.sh` reads the directory with the same commands and the same answers. `capture`
rewrites `machines/<name>/pieces`. A machine name is checked against the characters a directory
may safely carry, and `default` is refused as a machine name. The check is a before and after of
`machine.sh get` for every piece on every machine name, which must be identical, then the
Brewfile listing for this machine and for an unlisted one. A grep for `MACHINES` across the tree
is clean afterwards apart from the dated text in the decision records. `README.md` under
"Capturing a machine" and the root `AGENTS.md` follow.

### Phase 3, kanata as a module

**The piece and the module.** A `kanata` piece, off by default and on for this machine, with a
probe in `capture` that finds the binary and the active driver extension. `dotfiles/kanata/` holds
the trial config under `.config/kanata/kanata.kbd`, its `AGENTS.md`, `CLAUDE.md`, `DEPENDENCIES`,
`DRIVER`, `grants-probe` and `.stow-local-ignore`. `brew "kanata" if on?(:kanata)` in the
Brewfile, and `DEPENDENCIES.map` naming kanata a formula and the driver a manual origin installed
by `src/setup-kanata.sh`, the way Homebrew itself is.

**The driver pairing, like the Neovim lockfile.** `DRIVER` is a small tracked table, one row per
kanata minor version, naming the driver version it needs, the package URL and its SHA 256. It is
the pin for both, and it is the one place either version is written.

**Setting up.** `src/setup-kanata.sh`, run through `step_if kanata on`, reads the installed
kanata version, finds its `DRIVER` row and stops with a clear line when there is none. It
downloads that package, refuses it unless the hash matches and its signature and notarization
check passes, installs it, requests activation, installs the driver daemon and kanata as two
launchd daemons, holds the formula with `brew pin kanata`, and restarts kanata when the stowed
config changed. Each step is skipped once done.

**Upgrading, as its own deliberate act.** `src/setup-kanata.sh --upgrade` asks Homebrew for
kanata's current stable version, stops unless `DRIVER` has a row for it, so the pair is written
first from kanata's release notes and committed, then unpins, upgrades kanata, installs and
activates the paired driver, restarts both daemons, pins again, and runs the grants probe. That
is how kanata and the driver stay current without a bulk `brew upgrade` ever breaking the
keyboard. Whether driver 8 replaces 6.2 cleanly is measured on the first real upgrade and
recorded.

**Gates, not only notes.** Approving the driver extension and granting Input Monitoring are
declared as `grant` gates in the module's `DEPENDENCIES`. The kanata `grants-probe` answers
both without asking for its own permission. The driver comes from `systemextensionsctl list`,
which needs no privilege. Input Monitoring comes from kanata itself, running and holding the
keyboard means granted, and its own refusal in its log means denied. Anything else exits 2, a
machine fact and a warning. The probe also catches a grant lost when an upgrade moves the
binary's Cellar path, which is checked on the first upgrade. What only a person can do still goes
through `mdj_note` as well, the password, approving the extension, and allowing kanata in
Input Monitoring.

**Root reads a file the user can write.** Kanata runs as root and reads the stowed config, which
lives in a user writable checkout. That is safe only while the binary cannot run commands, so the
setup step proves it on every run, checking a config with `danger-enable-cmd yes` with
`kanata --check` and refusing to start the daemon unless that config is rejected. If that cannot
be proven on some kanata version, the step instead copies the config to a root owned path and
the daemon reads that copy.

**Switching it off.** A machine that turns the piece off keeps its daemons and driver, since
nothing removes what a machine has. The step says so through `mdj_note`, with the commands to
remove them as a one off act.

`decisions/kanata.md` records why kanata over Karabiner Elements and hyperkey, the 19 MB
measured, the top row and issue 975 upstream, the driver pairing, the pin and its upgrade
command, and the root and command reasoning. `decisions/homebrew-upgrades.md` gains the pin
exception with a pointer.

### Phase 4, the overlay seam

The stow step reads `OVERLAYS` declarations, `source  target  reason` tab separated, the source
relative to `machines/<name>/<module>/` and the target relative to the home directory. It links
what the machine supplies, removes a link it made that the machine no longer supplies and never
anything else, and refuses a declaration whose target lies inside a stowed tree. The Hammerspoon
module declares `keymap.lua` over `.config/olm/keymap.local.lua`, outside the stowed
`~/.hammerspoon`.

`init.lua` loads that file when it exists, under a pcall, and hands it as `keymapLocal`. Olm lays
it over `config/keymap.lua` the way `config/keymap.lua` lays over the shipped keys. A chord in
`keys` replaces the shared chord and `false` frees it. A `leaders` entry replaces the shared entry
of that name whole. A role in `roles` replaces that role. An `aliases` entry replaces that plugin's
words. A list's keys merge key by key. A file that throws, or that is not a table, is one problem
line naming the local file, and the shared keymap is used alone.

The Hammerspoon `overlay-check` runs every machine's `hammerspoon/keymap.lua` through the keymap
reader offline the way a keymap fixture does. The reconciler finds it by name, and with no Lua on
the machine that is a warning rather than an error.

Testing an overlay under the devlock. The overlay link points into whichever checkout ran the
stow step, so a worktree holding the lock tests its own overlay by running the overlay step from
that worktree. Releasing the lock runs it again from main. The Hammerspoon `AGENTS.md` devlock
section says so. No machine carries an overlay until one is wanted.

## Not in this plan

- An overlay seam for any tool but Hammerspoon. Each is a declaration, that tool's own optional
  include and an `overlay-check`, added when a real difference asks for it.
- Moving DisplayProfiles under `machines/`, which rule 2 names as the exception instead.
- Rewriting what `capture` probes for the existing pieces.
- Running the first kanata upgrade. That happens through `--upgrade` once Homebrew carries 1.13
  as stable and its `DRIVER` row is written.
- Removing anything from a machine, which stays a one off act with the person's go ahead.
