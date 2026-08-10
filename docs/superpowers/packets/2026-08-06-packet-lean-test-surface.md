# Work packet, the lean test surface

Written 2026-08-06 against `feat/olm-recency-core` at `d92973a`, with main at `03b2e9b`. This is
test infrastructure the user asked for after resting main broke silently, a way to live test one
tool in isolation where nothing else can be the cause, switchable between the olm side and the
original with one comment. It builds in the phase 2 worktree as a second commit on the same
branch, since phase 2's live test is its first user.

## Goal

`bin/hs-devlock acquire` accepts a `--lean` flag that makes the worktree's lean surface live
instead of its full config, and `dotfiles/hammerspoon/.hammerspoon/lean-init.lua` exists as that
surface, a minimal composition root loading only the tool under test and its direct needs, with
the vpn toggle carried over so one comment flips between the olm copy and the original. Release
is unchanged and always restores main.

## Model

Sonnet. The surface is a strict subset of wiring that already exists in the full root, and the
devlock change is one flag threaded through one path builder.

## Read

`bin/hs-devlock` in full. The parts that matter, `config_for` builds the file `MJConfigFile`
points at, `write_holder` records what to restore, and `status` reports what is live. The flag
only changes which file `config_for` answers with on acquire, everything else, the lock, the
stale rules, `--manual`, `--wait`, and release, stays identical.

`dotfiles/hammerspoon/.hammerspoon/init.lua`, the full composition root, for the exact wiring the
lean surface borrows. The settings require near the top, the Dependencies spoon and the `depsFor`
helper, the Chooser spoon, the Olm toggle block and the storage configure, the Vpn toggle at the
load site, and the Vpn configure block with its `recency` field. Copy the wiring shapes from
here rather than inventing new ones.

`Spoons/Olm.spoon/plugins/vpn/init.lua`, the copy under test, to see which configure fields are
required, theme, chooser, deps, and recency, and which are optional and may be left out of the
lean surface entirely.

The testing section of `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`, including the two console
and stow paragraphs added on 2026-08-06, since this packet adds a paragraph beside them and the
lean surface must obey them.

`dotfiles/hammerspoon/.stow-local-ignore`, because the lean surface is repo only test
infrastructure like the manifest, and it must be listed there so stow never links it into the
home directory and the new top level entry hazard never applies to it.

## Read only

`dotfiles/hammerspoon/.hammerspoon/init.lua`, the full root is not edited by this packet.
`Spoons/Vpn.spoon` and `Spoons/Olm.spoon/plugins/vpn/`, both sides of the toggle are read only
here. `test/units.sh`, `test/inventory.sh`, and `test/inventory.golden`, the golden must not
change, this packet adds no spoon and no binding to the real surface.

## Deliverable

`dotfiles/hammerspoon/.hammerspoon/lean-init.lua`, beside `init.lua` because `hs.configdir`
becomes the directory of whatever file `MJConfigFile` names, and spoons only resolve from there.
It requires `hs.ipc` as its very first act, so the port is alive even when something later in the
file dies, honouring the console rule that a dead port must mean something. It then prints one
console line naming itself, saying the lean surface is live and which tool it carries. It loads
settings, the Dependencies spoon, the Chooser spoon, and Olm with the storage configure, then
carries the same two line vpn toggle the full root has, olm side active and the original one
comment away, and configures whichever side is live with only the fields the copy requires,
theme, chooser, deps scope, and the recency instance built against the same settings key the
full root uses, then starts it. One plain `hs.hotkey` binding opens the chooser, and a console
line names the key so the tester never guesses. The file is written in two clearly commented
halves, the permanent scaffold that every future lean test keeps, and a section marked as the
tool under test that a later phase swaps for its own tool. No absolute path appears anywhere in
it, everything locates through `hs.configdir` and the environment.

The `--lean` flag on `bin/hs-devlock acquire`. It makes `config_for` answer with the worktree's
`lean-init.lua` instead of its `init.lua`, composes with `--manual` and `--wait` unchanged, and
`status` says the lean surface is live rather than implying the full config is. Release stays
untouched and restores main exactly as before. Acquiring `--lean` from a worktree whose
`lean-init.lua` does not exist dies with a readable message rather than pointing Hammerspoon at
a missing file.

The `lean-init.lua` line in `dotfiles/hammerspoon/.stow-local-ignore`, keeping the surface out
of the home directory.

One paragraph in the testing section of `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`, beside
the console and stow paragraphs, saying what the lean surface is for, isolating the tool under
test so nothing else can be the cause, how to take it live with `acquire --lean`, that
`--manual` composes with it for a hands on test, and that release restores main as always.

## Style

The repository rules. Comments in plain prose following the punctuation rules, no colons or
semicolons in any output or error string, no install commands anywhere, no absolute paths
written in any file, no package manager named anywhere.

## Gate

From this worktree with Hammerspoon running. `bin/hs-devlock acquire --lean` brings the lean
surface up, the port answers with `hs.configdir` pointing at this worktree, and the console is
clean, read through `hs.console.getConsole()` with a dofile script. Prove the tool works by
probing `spoon.Vpn` over the port, it exists, `prepare` or `show` produces rows, and the recency
settings key reads back. Flip the toggle in `lean-init.lua` to the original, reload with a
scheduled `hs.reload` and poll until it takes, confirm the console is clean on that side too,
and flip back. `bin/hs-devlock release` restores main, and main's console is clean after the
restore. Then the standing gates, `test/units.sh` exits zero, `src/check-dependencies.sh` exits
zero, `test/inventory.sh --check` exits zero with the golden untouched, and `bin/hs-devlock
status` at the end shows the lock free and main live.

## Out of scope

Editing the full composition root. Landing anything on main. Any change to either Vpn, the copy
or the original. Converting any other tool onto the lean surface, later phases swap the marked
section themselves. Any manifest, map, or Brewfile edit.
