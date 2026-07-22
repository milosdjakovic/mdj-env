# Display profiles chooser, build handoff

Self contained spec and decision record for building the Hammerspoon display
profiles chooser in this worktree, branch `feat/display-profiles-chooser`. A
fresh session with no prior context can build the feature from this file plus the
repo `CLAUDE.md` files it points to. Remove this doc when the feature lands, its
lasting decisions move into the spoon's own `CLAUDE.md`.

## Read these first

- Root `CLAUDE.md`, the repo conventions, the worktree convention, and the pointer to the test lock.
- `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`, especially the spoon lifecycle contract, the picker checklist under "Wiring a list tool into the Hyper contexts", the overlay display policy, the DisplayProfiles and DisplayMemory sections, and the test lock section.
- The exemplar spoons whose patterns you reuse. `Caffeinate.spoon` for a single morphing row and the search field doubling as text entry. `Vpn.spoon` for a chooser as command policy over an engine plus provider. `Launcher.spoon` for the launcher rows and the Command pattern with serializable row descriptors. `Chooser.spoon` for the picker atom contract.

## Purpose, inspect and manage, not apply

DisplayProfiles already auto applies the matching profile on screen change, and
only one profile matches the attached displays, so there is nothing to switch.
The chooser inspects and manages instead. The one apply like action kept is
Reapply, shown only on the currently active profile, for when macOS scrambles the
layout with no hardware change so no screen event fired. It maps to the engine's
existing `reconcile(true)`.

## Structure, a nested menu stack over one hs.chooser

Use one Chooser instance with a screen stack, not chained instances, the same
live update pattern the other pickers use. Return goes deeper, a Back row pops a
level, Escape closes everything. Cache the attached display set at show and
invalidate it on the `hs.screen.watcher`, so the per keystroke row supplier never
shells out to displayplacer.

Screens.

- Top, the profile list. One row per profile, the active one marked. When the current arrangement matches no profile, a Capture current arrangement row appears here.
- Profile menu, entered from a profile. List displays, Reapply when this is the active profile, Rename when the profile is editable, Delete when editable, Back.
- List displays, read only, each monitor in the profile with resolution, position, and which is main. Back.
- Rename, the search field becomes the name entry and a row morphs to Save as 'X'. Back.
- Delete, a confirm screen with Yes and No.
- Capture, from the top level, the search field is the name entry, saves the current arrangement.

## Storage, locked

Captured profiles live in a git tracked JSON data file, `config/display-profiles.json`,
keyed by `LocalHostName` like `config/displays.lua`, read with `hs.json` and
written only by the tool. The curated `config/displays.lua` stays the hand
maintained reference, read only from the tool. The composition root reads both
and merges them into one list of name and command pairs for the engine. This
gives shared across the two machines via git (git sync, the user controls when it
moves, not live sync), editable without touching code, and no fragile rewriting
of the commented Lua. Per host keying plus portable external monitor serial ids
keep the two machines from colliding in the one file. Runtime scratch like which
profile was last applied may stay machine local in `hs.settings`.

Editability boundary. Only captured JSON profiles can be renamed or deleted from
the tool. Curated `displays.lua` profiles show only List displays with a note to
edit the file, so the tool never pretends it can rewrite the curated source.

Capture appears only when the current arrangement matches no profile, per the
user's framing of it as add new. Saving a variant of an already matched
arrangement is a possible later addition, not part of the first build.

## Architecture shape

Follow the Capture and Vpn layout. Refactor `DisplayProfiles.spoon` so `init.lua`
becomes the composition root and command policy, while the watch, match, apply,
capture, and current logic moves into an engine sibling loaded by absolute path
with the `debug.getinfo` idiom. The engine gains read methods, the attached id
set and per profile applicability, on top of what it already exposes. Add a small
store module for the JSON layer. Add the chooser as the command policy layer that
turns rows into engine and store calls. Add a per spoon `CLAUDE.md` recording the
decisions.

Wire the picker the full way per the checklist. A context block in
`config/keys.lua`, a predicate in `init.lua`, an entry in the choosers registry,
the docked shortcut panel through `shortcutPanelFor`, one launcher action row and
one special action in the Launcher wiring, and no dedicated key. The drill in key
uses its own action in this context so it does not disturb `insertSelected`
elsewhere.

No restow is needed for new files inside `DisplayProfiles.spoon`, since the spoon
is already symlinked and files resolve through the existing link.

## Testing, through the lock

Never make a config live without the lock. From this worktree run `bin/hs-devlock
acquire` for a short automated test burst, hold it across quick edit and reload
and test cycles, and release back to main the moment testing stops being the
focus. For a hands on test the user runs, acquire with `--manual` and hold with no
timer until they green light, then release. Verify live state with the `hs` CLI,
for example `hs -c "return spoon.DisplayProfiles:current()"`. The full discipline
is in the hammerspoon `CLAUDE.md`.

## Rules

No hardcoded absolute paths anywhere, use paths relative to the repo or env based.
Follow the user's writing style in all committed text, no em dashes or other
dashes, only periods and commas, plain flowing sentences.

## Done when

- The chooser opens from the launcher, lists profiles, and marks the active one.
- Enter a profile, see its menu, list its displays, and go back, all without closing the chooser.
- Capture appears only when the current arrangement is unsaved, and saving writes `config/display-profiles.json` and the new profile shows up.
- Rename and Delete work for captured profiles, with a Yes or No confirm on delete, and are absent or read only for curated profiles.
- Reapply appears only on the active profile and calls `reconcile(true)`.
- No per keystroke displayplacer calls, the attached set is cached and invalidated on screen change.
- A per spoon `CLAUDE.md` is added and the hammerspoon `CLAUDE.md` DisplayProfiles section is updated.
