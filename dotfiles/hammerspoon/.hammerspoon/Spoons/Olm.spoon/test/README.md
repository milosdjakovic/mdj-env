# Testing Olm

Run it.

```
Spoons/Olm.spoon/test/suite.sh              # everything
Spoons/Olm.spoon/test/suite.sh dry          # plain lua, no Hammerspoon, no lock, see below
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
in well under a second, with nothing started and nothing locked. It exists because a builder
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
`drygate.lua`'s own header for the full account of what each of its four checks actually
reuses, and `drygate-composewords.lua`'s own header for the one check, a root sourced word
against what `root/compose.lua` publishes, that is a structural scan of that file's source
text rather than a real read, and exactly what that scan can and cannot see.

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
