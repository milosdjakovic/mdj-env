# Testing Olm

Run it.

```
Spoons/Olm.spoon/test/suite.sh              # everything
Spoons/Olm.spoon/test/suite.sh structure    # no screen needed, fast, safe any time
Spoons/Olm.spoon/test/suite.sh surface      # opens and closes every picker
Spoons/Olm.spoon/test/suite.sh behaviour    # the hand written per plugin scenarios
Spoons/Olm.spoon/test/suite.sh input        # posted leader chords, keys rather than actions
```

It takes the test lock only if this worktree is not already live, and gives it back. If you
already acquired it for a hands on session, it reuses your hold and leaves it alone.

## The idea

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
