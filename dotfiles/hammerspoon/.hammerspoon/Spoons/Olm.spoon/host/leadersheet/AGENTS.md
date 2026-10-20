# LeaderSheet

The decision trail for this host. Cross cutting material stays in the hammerspoon `AGENTS.md`,
which links here.

## What it is, and what it deliberately is not

One content builder for the overlay a held leader reveals. It replaced two hosts in phase 4 of
the keymap plan, one for the Hyper leader and one for the window leader, which built their rows
two different ways and kept their layout in two files. It lays out and hands to the renderer an
ordered list of sections, and it decides nothing about what is in them. It names no leader, no
plugin and no plugin's data, and it knows no layout of its own. The promise it keeps is that every
global key bound on a leader is on that leader's sheet and nothing is on it that is not bound
there, and that promise is kept by where the rows come from rather than by anything this host
checks.

The leader adapter calls `show(keyCode)` with the key it was built on and `hide()` on release, and
holds the reveal back over an open list, so this host never decides when a sheet appears. It only
answers what it draws for a keycode.

## Where a leader's sections come from

Three things, all assembled by the composition root in step K and handed over in the one second
configure, as `opts.sheets`, a list with one record per leader whose policy states a sheet.

The leader's own rows are every global chord the keymap holds on that leader, read by
`lib/hints.lua`'s `sheetRows`. Registered tools come first in registration order, then each
plugin in plan order with its host key, its other bindings and its keyed special rows, one row per
chord. The list keys are left out, since they are not global keys. The provided rows, which the app
toggler's bridge answers, come last, unless their plugin supplies sections for the leader's role,
as the toggler does, since its sections already list them. A row
wears the binding's description, else the descriptor's, else a tool's detail, else words made of
the action name.

`LeaderSheet.ownSections` turns those rows into sections. A descriptor's `group`, a word, files
its row under a section of that name, and a row with none goes under the layout's `title`.
Sections appear in the order their title first appears. A `group` that is a function is asked at
every show with nothing, a failure or an answer that is not a word files the row under the title,
and when any row has one the whole block is one function instead of a built list.

The rest come from plugins that declare `provides.cheatSheetSections` and state the role the
leader answers as `defaults.leader`, found by the set this host declares. Each arrives as a
function the host calls on every show, so a section may read live state, which is how the toggler
splits running from dormant apps. `lib/contributions.lua` resolves each member, wraps it so one
that raises costs only its own sections, and orders everything by `defaults.cheatSheetOrder`, the
toggler at ten and a leader's own block at fifty. That channel stays until phase 6 of the keymap
plan, when the toggler's apps become descriptors with a running group.

## The gate

A row whose `when` is false is hidden, asked on every show against the shared predicate table, so
it tracks live state such as the display count, and a section left with no rows is dropped. That
is the same condition the leader uses to swallow the key, so a key shows exactly while it works.
An unknown name is treated as active and warned, the rule the key dispatch follows. The Hyper
sheet ignored `when` before phase 4, and no Hyper row carries one on this machine, so nothing
changes there today, but a gated Hyper row now hides like a gated window row.

## Layout

The layout is the leader's, in its policy beside `sheet`, as `sheetLayout`, and the host copies
the renderer fields it states into each show. `lib/leader.lua` validates the table and fills the
defaults. A section with `icons = true` renders in the panel's icon grid. Any other section takes
the leader's own columns and column width with no icon gutter, so a long label such as Screenshot
to clipboard is not cut. A row that states its own `badge` keeps it, any other row is spelled by
the shared glyph helper, so Hyper+Shift+4 reads as shift 4. A sheet whose rows are all hidden is
not drawn at all.

## What the manifest declares, and why each policy is what it is

The shared `cheatSheet` renderer is required. This host draws nothing of its own.

`sheets` is required, root computed. Without it the host holds no leader and a hold shows
nothing, which is a refusal worth naming rather than an empty panel.

`predicates` is optional. Without it a gated row is shown, which is only a lost nicety.

The set question answers nothing on an install with no app toggler, and with the toggler switched
off the Hyper sheet simply has no app section. Every other bound key is still listed.

## The tests that guard it

`test/cases/leader-sheets.lua` builds a plan over the real manifests, runs the code that binds
with recorders standing in for the leader engines, shows this host for each leader into a
recorder, and fails on any key bound and not shown or shown and not bound. `test/leadersheet.lua`
holds the plain Lua cases for the model, groups, the gate and the layout validation.
`test/sheets.golden` is the model each leader would draw, read through `test/sheets-project.lua`,
proved byte identical across the merge by running the old probe against live main and the new
projection offline.
