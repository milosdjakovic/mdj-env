# QueryScope.spoon

The decision trail for this spoon. Cross cutting material stays in the hammerspoon
`CLAUDE.md`, which links here, and the launcher side of the contract lives in
`Spoons/Launcher.spoon/CLAUDE.md`.

## What it is

A word the user types scopes a query driven list down to one tool. An alias plus a
space hands the whole list over, so `k 2h` reaches the keep awake picker from inside
the launcher, and deleting the space hands the list back. It is a query row source
like any other with one extra answer, a second return value saying this source claims
the query.

## The decision everything else follows from, no state

The scope is derived from the query on every keystroke and nothing is remembered.
There is no mode to enter and none to leave.

The rejected alternative is worth recording because it is the obvious one. Consume
the alias, clear the field, and keep a scope variable, then treat a backspace on an
empty field as leaving. That needs the field and a hidden variable to agree about
which scope is live, and they can disagree. It also cannot be built on the query
callback at all, since a backspace against an already empty field changes no text and
fires nothing, so it would take an event tap plus one consumed key, in a spoon that
otherwise has no live resources and therefore no `start` or `stop`.

Deriving instead means stepping out is ordinary text editing. Back needs no code, no
tap, and no cooperation from the presenter or from any scoped tool. The visible cost
is that the alias stays in the field rather than becoming a pill, which is a fair
price for a mechanism with nothing to get out of sync.

## The separator is grammar, not configuration

A single space, deliberately not a setting. It is this spoon's own grammar rather
than a binding, and it is the one character whose removal has to mean leave the
scope, so making it configurable would only create a way for two consumers to
disagree about what leaving looks like. This is also why the no match row may name
the space, unlike the rule that a spoon never states the keys that reach it. A key is
injected config that drifts when rebound. The separator is this spoon's own contract,
so describing it cannot drift from anything.

## Exclusivity, and why a claim holds even when nothing matched

A claimed query is claimed whatever the scope returns. Falling back to the full list
on an empty result would make one keystroke mean two different things depending on
whether a hidden filter happened to hit, which is the worst kind of surprise in a
list you are typing into. An empty result becomes one disabled row instead, so the
list explains itself rather than coming up blank. That mirrors Caffeinate's own
reason for showing a disabled hint row where the calculators stay silent, a list with
nothing else in it must say something.

A claim also discards whatever earlier sources contributed and stops the loop, so a
claimed query means exactly one thing however the composition root ordered its
sources. Ordering the scopes first is then clarity rather than correctness.

## Two things `_present` does, both load bearing

The row's item is nested under a descriptor naming its scope, so a chosen row routes
home. It stays plain data because a presenter hands every row to a native chooser
that serialises it and would drop a function.

The nesting depth was measured rather than assumed, because a row silently dropped by
that serialisation is a known failure mode here and it leaves nothing in the console.
Three levels survive the round trip intact, a scope descriptor holding a payload
holding an array, verified through a real widget. So no flattening and no per build
reference table is needed, and a payload is handed over directly.

A reference table was briefly built here on a wrong diagnosis and then removed, which
is worth recording so it is not rebuilt. A menu row appeared not to dispatch, the
nesting looked like the obvious culprit since a menu path is the deepest payload of
any scope, and it was not the cause. Two harness artifacts were, both listed at the
end of this file. If a row ever really does fail to dispatch, measure the depth again
before adding indirection, since the measurement takes a minute and the indirection
couples a build to a selection by array index forever.

`filterText` becomes the raw query including the alias. Filtering already happened,
against the scope's own query, so this is what stops the presenter's matcher scoring
these rows a second time against a string carrying a word they were never meant to
contain. Every row then scores alike and the order decided here survives. A computed
row already uses the same trick for the same reason.

## Filtering mirrors the atom rather than inventing a policy

A scope inherits the shared matcher and may set `matcher = false` to own its
filtering, which is exactly the Chooser atom's own contract. Keep awake opts out
because its field is a value being typed rather than a filter over rows, the same
reason its own chooser opts out. Mirroring costs nothing to understand and means a
list shaped scope is one entry in the root with no filter loop of its own, which is
what the next few scopes need.

## What a scope may be, which is more than a tool

Three shapes have earned themselves, and the spoon knows about none of them, which is the point
of the contract being four fields.

A tool exporting its own rows and its own select is the ordinary one. A piece of root policy
with no spoon behind it works identically, since the contract asks for two functions and never
asks where they came from. And a scope may narrow the presenter's own catalog rather than reach
outward at all, which is what the window and settings scopes do, reading the launcher's built
rows of one kind and handing a chosen row straight back to it. That last one is worth naming
because the instinct is to rebuild those rows in the root from the same injected data. Reusing
the presenter's rows instead means a narrowed list cannot disagree with the whole list about
what a row says, what hidden words it answers to, or what choosing it does, and the predicate
gating comes along for free.

## Choosing is not the only thing a list is for, so there is a second, optional verb

A scope could once say only what a row is and what happens when you take it. `peek` is the third
answer, show me more about this row without choosing it, routed home exactly as running one is and
optional in exactly the way `run` is not.

It exists because a file row is the case where a line of text cannot settle the question. Two rows
matched, both plausible, and the thing that decides between them is the contents. The tool behind
the scope already answers that, so without a route the alias reaches a version of the tool that
can find a file but not tell you which one it is, and the rule below is precisely that a scope may
be smaller than its tool but not smaller than the reason for it.

Optional is what keeps it honest for every other scope. A surface asks `canPeek` before it offers
anything, so a scope with nothing to show never advertises a key, and a scope written before this
verb existed is unaffected rather than newly incomplete. A `peek` that is present but not callable
is rejected at load with the scope named, since the alternative is a keystroke that fails later
with nothing pointing at the cause.

The teardown belongs to whoever asked. A peek can open something that outlives the keystroke, a
window rather than a row, and the scope has no idea which list is showing its rows. So the surface
that asked is the surface that puts it away when its own list closes, which is one line in the
composition root and no knowledge on either side of the other.

## A scope may be smaller than its tool, but not smaller than the reason for the tool

Browser tabs is the good case. It cannot offer its settings level, since that is a step into a
second list and a scope shows one. So the scope lists tabs, the tool stays the way to the
switches, and the guidance shown when there are no tabs points at the tool rather than at a row
below, which is why that tool takes the phrase as a parameter instead of hardcoding the word
below. Nothing was lost that the scope was for.

Text case is the case that failed this test, and it was built before it failed. A scope cannot
read your selection, since that needs the keyboard in the app the presenter is covering, so the
rows could only demonstrate each case on a fixed sample with the real read moved to the pick. It
worked. It was removed anyway, because seeing your own text in each case is the reason to open
that tool, and a list of case names without it is a menu you guess at. Its own `CLAUDE.md` holds
the longer version.

So the rule has two halves. Let a scope be smaller than its tool and say so, and drop the scope
when what it must leave out is the point of the tool. The first half stops a mechanism with one
job from growing four to imitate a whole tool. The second stops the alias list filling up with
lesser copies, where the same word reaching a tool one way and a diminished version of it another
way is worse than there being one way in.

## What cannot be scoped in place, and why that is a presenter limit

A tool whose list is only half of it, the other half being a canvas docked beside the rows,
cannot come along. The presenter reserves no companion pane and the pane width is fixed when a
chooser is built, so the clipboard and Processes would arrive stripped of the preview that is
most of what they are. That is a limit of the presenter rather than of this spoon, and lifting
it means a companion pane a scope can claim and drive, which is a change to the Chooser atom.
Recorded here because the question comes up per tool and the answer is the same every time.

## Why one file, and what would split it

There is no `engine.lua`, no `store.lua`, and no `contract.lua`. The dependency
inversion is already achieved by the scopes being injected, and the smallest
structure that inverts is the one to prefer. The split earns itself when the alias
store arrives, because `init.lua` then becomes the root that merges the config
defaults with the stored overrides and hands a resolved alias map to an engine that
knows nothing about where a map came from. Splitting before that would be a file with
one caller.

## Where the aliases live, and why not here

In `config/keys.lua`, on the same entry that already holds the tool's key and
description. The row that advertises an alias and the resolver that answers it read
one piece of data, so the hint and the behaviour cannot drift, which is the same
reason the chord label on a row is derived rather than written. A tool with no
`aliases` field is simply not scopable, so nothing is switched on by accident.

When the editor arrives the stored choice takes precedence and the config entry
becomes the fresh machine seed, which is how the overlay display policy already
works.

## Validation is loud, and order decides a collision

A scope is repository data rather than user input, so a malformed one is a defect
worth stating in the console by name, and dropping only that scope keeps the rest
working. The first scope to claim an alias keeps it and a later claim is refused by
name, so a collision resolves identically on every machine rather than depending on
table order. `aliasesOf` reports the aliases a scope actually holds rather than the
ones it asked for, so a surface that lists them cannot advertise one that was
refused.

## What it deliberately does not do

It does not open anything, does not know what a launcher is, and does not know what a
chooser is. It does not know which tools can be scoped, since the root names them. It
owns no live resources, so it has no `start` or `stop`, per the lifecycle contract.
And it holds no per open state, which is what lets a presenter call `rows` on every
keystroke with no lifecycle to manage.

## Two harness artifacts that both looked like real bugs

Testing this from the console produced two false failures, and both cost a wrong
conclusion, so they are written down rather than rediscovered.

`hs.chooser:query(text)` sets the field but does not fire the query changed callback,
so a seeded query leaves the rows as they were until something refreshes. A seeded
query therefore looks like a claim that did nothing. This one matters beyond testing,
because a handoff scope that opens a tool seeded with the rest of the query has to
refresh after seeding or the tool opens on an unfiltered list.

Calling the launcher's `show` bumps the open id, which is exactly what invalidates a
scope's per open cache. So a test that shows, seeds, and selects in one breath selects
whatever the scope shows while its data is still being read, which for the menu scope
is a disabled row that cannot be chosen at all. The result is no dispatch and no error,
which reads as a broken route. Wait for the read between showing and selecting.

The general lesson is the one the clipboard timing work already recorded elsewhere in
this configuration. Measure, and be suspicious of a harness that reaches inside a
widget, because the paths a real keystroke takes and the paths a console call takes are
not the same.
