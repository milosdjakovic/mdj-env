# Testing Olm

Run it.

```
Spoons/Olm.spoon/test/suite.sh              # everything
Spoons/Olm.spoon/test/suite.sh dry          # plain lua, no Hammerspoon, no lock, see below
Spoons/Olm.spoon/test/ranking.lua           # one of the three dry runs, standalone, see below
Spoons/Olm.spoon/test/icons.lua             # the icon engine, the config file, the row resolver and the two sources
Spoons/Olm.spoon/test/leaders.lua           # the two leader adapters' resolvers as they stand, see below
Spoons/Olm.spoon/test/keys.sh               # every bound chord in the live config, diffed against keys.golden
Spoons/Olm.spoon/test/keys.sh --bound       # what the binder bound under the stub, diffed against keys.golden
Spoons/Olm.spoon/test/views.sh --offline    # the launcher's catalog and every leader's cheat sheet under the stub, against their goldens
Spoons/Olm.spoon/test/goldens.sh            # every golden the keymap plan holds a phase to, offline, in one command
Spoons/Olm.spoon/test/suite.sh structure    # no screen needed, fast, safe any time
Spoons/Olm.spoon/test/suite.sh surface      # opens and closes every picker
Spoons/Olm.spoon/test/suite.sh behaviour    # the hand written per plugin scenarios
Spoons/Olm.spoon/test/suite.sh input        # posted leader chords, keys rather than actions
```

## The dry gate

`dry` is a different kind of tier from the other four, run through `drygate.sh` rather than
through the lock and report machinery every other tier shares, and it is worth understanding
why before reaching for it.

Every other tier proves something about a plugin actually RUNNING, which means a live
Hammerspoon, the test lock that guards one, and the several seconds a reload costs. The dry
gate proves something narrower and earlier, that every manifest is well formed, plain lua,
in about two seconds, with nothing started and nothing locked. It exists because a builder
agent has no way to acquire the lock or start Hammerspoon at all, and this repository's own
review trickle this week named the cost of that gap directly, a presentation member naming a
function that does not exist and a root sourced word nobody publishes, each shipped at least
once before a person or the live suite caught it.

It reuses `lib/registrar.lua`'s and `lib/registry.lua`'s own validation wherever it can,
rather than restating their rules a second time to drift from, loading each plugin's real
module under a permissive stub, attempting its own configure too, since a real tool commonly
assembles the very members this checks against inside configure rather than at load. A
module that will not load or will not configure under that stub is reported UNKNOWN rather
than guessed at as passing or failing, since an honest unknown beats a false green. Read
`drygate.lua`'s own header for the full account of what each of its checks actually
reuses, and `drygate-composewords.lua`'s own header for the one check, a root sourced word
against what `root/compose.lua` publishes, that is a structural scan of that file's source
text rather than a real read, and exactly what that scan can and cannot see.

It also enforces the layer rule, no file outside `plugins/` names a plugin, in two layers.
`drygate-leaks.lua` scans core source for the shapes a name takes in code, and
`drygate-rename.lua` runs the person's `init.lua`, and so `root/compose.lua`, under a sandboxed
stub through `drygate-composerun.lua`, once as the spoon is and once with every plugin renamed,
and fails on any difference in what core decided. That run is the one place the composition root
runs without a live Hammerspoon, and it adds about a second.

It enforces the binding rule too, `drygate-binding.lua`. Olm binds every key from its keymap, so
a call of `hs.hotkey.bind`, of `hs.hotkey.new` or of any bind function in a file under `plugins/`
or `host/` is a finding naming the file and the line. And it checks each plugin's
`provides.actions` and `provides.bindings` through the registrar's own validation, against the
module it configured, so a malformed descriptor is refused here in the words a live load uses.

Run it standalone too, straight from the shell, no suite.sh, no lock, no Hammerspoon:

```
Spoons/Olm.spoon/test/drygate.sh
Spoons/Olm.spoon/test/drygate.sh --strict   # an unknown module fails the gate too
```

**A clean tree exits zero.** A gate that turns red on a tree nobody broke gets ignored
within a week, and an ignored gate protects nothing, so an UNKNOWN never fails this gate by
default, only `--strict` asks for that harder stance, and a finding verified by hand and
genuinely not worth blocking on is named once in `drygate-accepted.txt`, one line, the exact
text this gate would otherwise print, then ` | `, then the reason. An accepted finding still
prints, as its own ACCEPTED line, it is never silent, it only stops failing the gate. The
match is exact text on purpose, so an accepted line that stops matching anything this run,
because the wording changed or the underlying question is now answered differently, becomes
a finding of its own rather than quietly going on covering whatever the wording now means,
which is what keeps that file from rotting into a list nobody rechecks.

`drygate-accepted.txt` travels with the tree, the same as every other file this gate reads.
This gate runs against whatever Olm looks like at the moment it is asked, never a fixed
snapshot of today's plugins, so a migration that reshapes several manifests at once,
`feat/chooser-final`'s own final batch adds a presentation to six more plugins plus one the
composition root builds for itself, is exactly the kind of change this gate will meet at its
next run and, correctly, at its next reconciliation with whatever `drygate-accepted.txt`
still says by then. An accepted line a migration makes true again for a different reason
than the one written beside it is still worth a person's own second look, exact text
matching alone cannot tell the difference, only catch the ones where the words no longer
match at all.

## The key inventory

`keys.golden` is every chord the running configuration has bound, one line each, and every
phase of the keymap plan must reproduce it exactly unless that phase says what changes. One
command dumps the live config and diffs it against the golden, exit zero when identical.

```
Spoons/Olm.spoon/test/keys.sh            # dump and diff, exit 1 on a difference
Spoons/Olm.spoon/test/keys.sh --update   # overwrite keys.golden, only when a change is intended
```

It only reads. It takes no lock, reloads nothing and posts no key, and it bounds its `hs` call
and writes to a file rather than answering over the port. The live config is whichever checkout
is stowed, so a worktree that is not live describes main, and checking a branch means taking the
test lock first and giving it back after. `keys-probe.lua` carries the line format, how an owner
is worked out, and what the probe cannot see. A `?` in the owner column is a chord nothing in
the plan declares.

The keymap is proven complete by projecting its own rows into the golden's line format and
comparing. `keys.sh --keymap` does that against the live config once the config holding the
keymap is the live one, and `keys.sh --offline` does it with no Hammerspoon, by running the
composition root under the dry gate's stub. The stub cannot know the real keycode table, so a key
is only lowercased unless `DRYGATE_KEYCODES` names a Lua file returning one dumped from a live
session, and it cannot tell which tools are installed, so the offline run reports every one
present. Both runs matched the golden byte for byte when the keymap landed. `keymap.lua` is plain
Lua cases for the read model itself, collisions by layer, leader, key and modifiers, a person's
row displacing a default, the spelling, the function each row runs and the binding order, and the
registrar's descriptor validation, and `keymap-person.lua` is the person's own file,
`config/keymap.lua`, its chord grammar, every problem an entry can raise, displacement, false,
the leaders, roles and aliases sections and which leaders a keymap puts in use. `suite.sh dry`
runs both.

Since the keymap binds, a projection of its rows is not the whole proof, so a second offline
check records what was actually bound. `keys.sh --bound` runs the composition root under the
same stub with every call into the two leader engines' `bind` and into `hs.hotkey.bind`
recorded, writes each call in the golden's format with its owner found from the keymap the way
the live probe finds one, and diffs that against `keys.golden`. The stub hands out a keycode
table that answers the same code for a name every time, since the root compares two leaders'
keycodes and a stand in would never agree with itself.

```
Spoons/Olm.spoon/test/keys.sh --bound                     # bound calls against keys.golden
Spoons/Olm.spoon/test/keys.sh --bound-order               # bound calls per engine and key, in call order
Spoons/Olm.spoon/test/keys.sh --bound-order <spoon dir>   # the same for this spoon and another, diffed
```

The order matters as much as the set, since an engine keeps every binding on a key in the order
it arrived and resolves a press by walking that list. `--bound-order` groups the calls by engine
and key and keeps call order inside each group, with the lists' own keys sorted after the global
ones, since the root walks its contexts with `pairs`. Handed a copy of main's spoon, extracted
with `git archive` into a scratch directory, it records both against this config and diffs them,
which is how a change to who binds proves it left the order alone.

Two more goldens hold what a person sees rather than what is bound, since phase 2b of the plan
moved where launcher rows and sheet labels come from. `launcher.golden` is every row of the
launcher's own catalog except the apps, in resting order with no recency applied, one line each
with the key its recency and query memory remember it by, its title, its subtitle with the chord
inside it, its icon key and the manifest that icon is read against, its gate, its keywords and the
launcher order number it was placed by. The remembered key is the field that must never change,
since a change makes the launcher forget every pick a person made. App rows are left out, a disk
scan and the running set a stubbed run cannot see. `sheets.golden` is the content model each held
leader's sheet would draw, the Hyper sheet's sections and rows and the window sheet's rows, with
badge, label, section and fade, everything except pixels. One sheet host draws every leader since
phase 4, and the golden kept the two line families the old hosts wrote, so it proved the merge by
staying byte identical. A section a plugin supplies, the app
toggler's running and dormant apps, is written as its headers alone, title, fade and layout, and
nothing about its rows, since which apps are installed and running is a fact about one machine
and the goldens are the same on every machine. Those rows are checked by eye, holding Hyper and
reading the app sections against the toggles. `launcher-project.lua` and `sheets-project.lua` are the one place each format
is spelled.

```
Spoons/Olm.spoon/test/views.sh             # both, live and read only, against the goldens
Spoons/Olm.spoon/test/views.sh --offline   # both, from a stubbed run of the root
Spoons/Olm.spoon/test/views.sh --update    # rewrite both goldens from the live config
Spoons/Olm.spoon/test/goldens.sh           # keys.sh --offline, keys.sh --bound and views.sh --offline, then the fixtures
Spoons/Olm.spoon/test/goldens.sh --live    # keys.sh and views.sh against the running config
Spoons/Olm.spoon/test/keys.sh --fixture keymap-fixture [--update]   # the bound keys under a fixture keymap
Spoons/Olm.spoon/test/views.sh --fixture keymap-fixture [--update]  # the launcher rows and sheets under it
```

A person's keymap is proved offline through fixtures, a Lua file under `test/` returning a keymap
table, which the stubbed run hands to Olm as `cfg.keymap` in place of `config/keymap.lua`.
`keymap-fixture.lua` is the person's own case, `keymap-fixture-roles.lua` the window role moved
alone, and each golden beside them is named for its fixture, `keymap-fixture.keys.golden` the
bound keys followed by one remap line naming the held leaders put in use, and
`keymap-fixture.launcher.golden` and `keymap-fixture.sheets.golden` the two views. `goldens.sh`
diffs all of them.

The live probes, `launcher-probe.lua` and `sheets-probe.lua`, read the running config only. Each
asks a host to build its rows afresh without touching the caches an open uses, shows nothing,
posts no key and writes to a file. Every golden
matched its offline projection byte for byte on six runs in a row once the plan's own order was
made stable, see `decisions/olm-keymap.md`.

`leadersheet.lua` is plain Lua too, run by `suite.sh dry`, and pins the one sheet host, the model it
builds from a leader's rows, a descriptor's group, the gate on `when`, what it hands the renderer
and the validation of a leader's sheet layout.

`leaders.lua` is the other half, plain Lua with no Hammerspoon, run by `suite.sh dry`. It pins
the resolver of `lib/leader.lua` under both shipped policies, HYPER's with contexts and META's
without, every case the two old adapters had and with the two behaviours phase 3 of the keymap
plan changed marked FLIPPED in the case name, a gated key swallowed on every leader and an
unknown predicate warning once on every leader. It also drives `lib/binder.lua` into real leaders,
a row landing on the leader its name names with its gate, repeat and release wait, a plain combo
reaching the plain leader, the order kept, and a missing engine or function reported, and it
covers what the merge added, the two triggers, the quiet rule, the reveal and the release wait.

## The idea

The other four tiers, `structure`, `surface`, `behaviour`, and `input`, run through
`runner.lua` against a LIVE Hammerspoon, `hs -c` and the test lock, proving something the
dry gate cannot, that a plugin actually behaves once it is running rather than only that its
own declarations are well formed. `suite.sh` takes the lock only if this worktree is not
already live, and gives it back. If you already acquired it for a hands on session, it
reuses your hold and leaves it alone.

**Almost nothing here is written by hand, and that is the point.** A plugin that declares a
`registry` block in its manifest is checked for registering, for being active, for owning a
key, for having a row a person can find, for its scope answering rows, and for its picker
actually opening and closing. It earns all six by declaring, not by anybody writing them down.

This is the same rule the configuration itself answers to. If the suite can work out a check
from what a plugin already declared, the plugin must not restate it as a test. So adding a
plugin adds its own coverage, and there is no roster here to forget to update, which is exactly
the failure the launcher's hand kept row list used to have.

The derived checks read the **live plan and the live registry**, never the manifest files on
their own. A suite that read only manifests would agree with itself, and self agreement is
precisely what let a manifest naming a deleted capability pass for weeks.

## What you write by hand

Only behaviour no declaration implies. A copied string reaching the top of the history. A sum
computing. A recase replacing a selection. Those live in a `test.lua` beside the plugin they are
about, and the runner finds them by scanning rather than from a list.

```lua
return {
  feature = "Clipboard history",
  scenarios = {
    {
      scenario = "something copied reaches the top of the history",
      given  = function(w) w.pasteboard("hello " .. w.stamp) end,
      expect = function(w)
        local rows = w.rows("clipboard", "")
        if #rows == 0 then return false, "the history is empty" end
        return true
      end,
    },
  },
}
```

`expect` answers `true`, or `false` and a sentence saying what was seen instead. The sentence is
required in spirit. A bare `false` says something did not hold without saying what did, which is
the difference between a report that leads somewhere and one that only says look again.

`w` is everything a scenario may do, and it is the whole vocabulary. `w.open(name)`,
`w.close(name)`, `w.showing(name)`, `w.rows(name, query)`, `w.module(name)`, `w.pasteboard(text)`,
`w.down(leader)`, `w.up(leader)`, `w.press(key)`, `w.escape()`, `w.keyFor(name)`, `w.stamp`. A
scenario never touches `hs` or Olm's internals directly, so a change in how a picker is opened is
one edit in the runner rather than one per test.

There is no way to wait, on purpose. A scenario that needs time says so by splitting into `steps`,
each a function and the gap to leave after it, and the runner leaves that gap with a real timer.
Sleeping would block the main thread, which is the thread every answer this suite waits for is
delivered on, so a scenario that sleeps is preventing the very thing it is waiting for. That
mistake has been made twice here and both times it reported a working config as broken.

```lua
steps = {
  { fn = function(w) w.open("processes") end, wait = 0.9 },
  { fn = function(w) w._saw = w.showing("processes") w.close("processes") end, wait = 0.4 },
},
```

## Three verdicts, not two

`pass` and `fail` mean what they always mean. **`manual` means only a person can judge it**, and
those are collected into a checklist at the end rather than guessed at. Whether OCR read the
screen correctly, whether the colour picker sampled the right pixel, which monitor an overlay
landed on. A suite that quietly scores an unjudgeable thing as passing is worse than one that
admits the gap.

## The tiers

**structure** needs no screen and no lock beyond being live. The plan, the registry, every
context binding naming an action something can answer, every gated key naming a predicate that
exists, every required tool actually being on this machine. Run this one freely.

**surface** opens and closes every registered picker in turn. It takes over the screen for a few
seconds. This is the tier that proves a tool works rather than merely that it was configured.

**behaviour** is the hand written scenarios.

**input** posts real leader chords rather than calling actions, which is the only way to prove
the key path itself. Everything else proves the action behind the key.

## Three Hammerspoon facts this suite is shaped by

Each was learned by watching it fail rather than by reading anything, and each will bite anyone
extending this.

**Opening a chooser from inside an `hs -c` call kills the ipc port.** The caller gets nothing
back and it looks like a hang. So the run is scheduled and returns at once, and `suite.sh` polls
for a report file rather than waiting for an answer.

**A timer whose handle nobody holds is garbage collected before it fires.** The first version of
the runner scheduled a chain of steps, retained none of them, and produced no output and no
error, which is the least helpful failure there is.

**A chooser needs real time on the main thread to appear.** The run is a queue walked one step
per tick rather than a loop, because a loop asks whether a picker is showing before the window
exists and scores every one of them as broken.

## What it does not cover

It does not prove a key binding reaches the right application, only that pressing it reaches the
right action. It cannot judge anything visual. It does not test the tmux status bar, the shell
side of anything, or Hammerspoon itself. And a green run is regression protection rather than
proof, the same honest limit the BrowserTabs harness beside it states about its own coverage.
