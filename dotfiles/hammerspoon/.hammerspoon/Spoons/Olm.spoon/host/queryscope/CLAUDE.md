# QueryScope.spoon

The decision trail for this spoon. Cross cutting material stays in the hammerspoon
`CLAUDE.md`, which links here, and the launcher side of the contract lives in
`Spoons/Olm.spoon/host/launcher/CLAUDE.md`.

## What it is

A word the user types scopes a query driven list down to one tool. An alias plus a
space hands the whole list over, so `k 2h` reaches the keep awake picker from inside
the launcher, and deleting the space hands the list back. It is a query row source
like any other with one extra answer, a second return value saying this source claims
the query.

## Where a scope comes from now, and why that changed

It still names no scope, that has not moved. What moved is where the root builds the
seven scope bodies most tools carry, `caffeinate`, `dockAutoHide`, `vpn`, `browserTabs`,
`fileSearch`, `emoji`, and menu search. Each now lives on that tool's own registration in
`Spoons/Olm.spoon/lib/registry.lua`, under an optional `scope` field carrying exactly the
four verbs and the matcher this spoon's own admissible function already asks for, `rows`,
`run`, `peek`, `redirect`, and `act`, plus `matcher`. The root's `queryScopes` table reads
those bodies out through `registry.scopes(spec)`, which resolves an ordered list of tool
names into `{ name, opts }` pairs, warning by name for a spec entry naming a tool the
registry has never heard of and staying silent for one that is merely inactive or, for
emoji, active but carrying no scope this run. The root's own loop then passes each pair
through the same `scope(name, opts)` helper it always used, which is what still joins
`name`, `title`, `glyph`, and `aliases` from `config/keys.lua` before handing the finished
table to this spoon's own `configure`. So the contract this file enforces, four verbs plus
a matcher plus the identity fields, is unchanged, only the place those fields are
assembled from moved one step further from where they are consumed.

The three `launcherCatalogScope` scopes and the alias directory below still take the
older path, built directly in the root with no tool and no registration behind them,
since there is nothing for either to register against.

`spoon.QueryScope:catalog()` is also what `test/inventory.lua` now reads live, since the
scope field a tool's own registration carries is a declaration and not proof that a scope
actually entered this spoon's own map, a spec entry naming an unregistered tool resolving
to nothing that a descriptor cannot see happen. Reading the assembled catalog is what
turns that gap into something a committed file would catch.

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

## Some rows are signposts, so there is a third, optional verb

`redirect` asks what a row MEANS instead of what taking it would do, answering with a query the
field should hold. A query in reply and the surface changes the field, rebuilds, and stays open. It
is the mirror image of the verb above rather than more of it. Peek exists because a row cannot say
enough about itself, redirect because a row does not want to be taken at all.

The alias directory is what earned it, and it is the clearest case there is. A row there does not
do anything, it tells you the word for something else, and the useful outcome is that word in the
field with the list still up. Expressed as a run, which was the first version, the only thing such
a row could do was close the list and have something reopen it with the word typed. That worked and
looked broken, a whole list dismissed and rebuilt to deliver two characters, and the field it
handed back arrived with its text selected so the next keystroke deleted it.

Asking BEFORE the row is taken is the whole mechanism, because after is too late by construction.
A native chooser tears down on select and tells the consumer afterwards, so the surface has to take
the key away from the widget to keep the list alive. That is the atom's business and the main
`CLAUDE.md` has how it does it, including the mouse, which needed a way to learn which row was
clicked before letting the click through. What matters here is that this verb is a question rather
than a command, which is why a scope answering nothing at all is unaffected by its existence.

A scope with signpost rows should still answer `run`, and the reason is worth stating because it
looks like dead code. It is the fallback for a click whose row could not be resolved, which is the
one case the question cannot be asked in time. Validation matches `peek`, present but not callable
is rejected at load with the scope named, and an empty or non string answer reads as no redirect
rather than as an error, so a scope that cannot name the query right now is simply taken normally.

## Some rows are switches, so there is a fourth, optional verb

`act` is what a row means when choosing it should flip something in place rather than run,
redirect, or open anything. `actFor` asks for it, answering a callable that performs the flip
when invoked, or nil when the row is one of the other three kinds. The surface calls the
callable, the list refreshes from the top, and the row's own wording changes because it was
recomputed rather than patched, the same freshness every hosted page already has since nothing
here is ever cached.

It exists because a row that turns a setting on or off has nowhere useful to send you and
nothing to point at, the useful outcome is the flip and staying put to see it took, which `run`
cannot offer since taking a row closes the list and `redirect` cannot offer since a switch is not
a signpost to somewhere else.

The shape mirrors `redirect` on purpose. Both are optional, both are asked in the scope branch
of the root's row interception, and `act` is asked first, since a row can be a switch or a
signpost but has no reason to be both. Validation matches the other two, present but not
callable is rejected at load with the scope named. Calling the answer is where `act` differs
from `redirectFor`, the callable wraps `pcall` over the scope's own function the same way `run`
and `peek` do, so a scope that raises while flipping costs a console line rather than a broken
chooser, where `redirectFor` has already run its `pcall` by the time it answers since the query
it hands back is a value rather than a deferred effect.

## Choosing is not the only thing a hosted list is for either, so there is a fifth, optional verb

`verbFor(item, action)` answers a callable running the named verb this row's own scope declared
for it, or nil when the scope declares no such verb, when it declares no verbs at all, or when the
row is not a scope row to begin with. It mirrors `actFor` exactly, same routing home through the
item's own scope, same `pcall` wrapping, and answering a callable rather than having already run,
for the same reason `actFor` answers that way. Optional like peek, redirect, and act, so a scope
with nothing declared is unaffected rather than newly incomplete.

It exists because a hosted list can carry a tool's own list without carrying a way to act on a row
beyond choosing it, which is the gap the composition root's `actions.rowIntercept` named for itself
long before this spoon could close it. `run` is what choosing a row does, and it is the only verb a
hosted list had until now. A row inside file search's own picker can also be revealed in Finder or
have its path copied, keys that live in that picker's own Hyper context, and a hosted list has no
route to either because it is under the launcher's context instead. `verbFor` is that route.

The scope declares which of its verbs make sense away from its own picker, once, in a `verbs`
field on the same table `configure` already reads, a map from an action name to a function taking
the row's own payload. Nothing here decides which actions exist or what a verb does, that is the
tool's own business through its registration, and this spoon only ever asks whether one was
declared and hands back a way to run it.

Two callers ask it, and neither branches on hosting. The composition root's own `run`, injected
into `ActionPanel`, asks `verbFor` first and falls through to its ordinary action table only when
the answer is nil, and a row from a tool's own real picker is never a scope row, so it answers nil
by construction and the ordinary path runs exactly as it always did. The root's own `rowsFor`, when
asked for a context's hosted rows, keeps a verb row only when `verbFor` would answer non nil for
it, so a hosted list is never shown a verb it cannot actually run, and offers no greyed row and no
row that does nothing, the honest answer the design settled on. See `host/actionpanel/CLAUDE.md`
for the first and `Spoons/Olm.spoon/CLAUDE.md`'s Registry section for where `verbs` itself is
declared and validated.

## A scope is also what a launcher row hosts, and that came for free

A scope answers a whole list for a query that names it, which turned out to be exactly what was
needed to put a tool's list inside the launcher when its row is chosen, with no second window. The
launcher keeps the alias as a prefix it never shows and asks with it in front of whatever was
typed, so hosting is this same mechanism with the word hidden. Nothing was added here for it, no
scope knows it can be hosted, and a tool becomes hostable by being reachable by a word.

Which makes `queryFor` load bearing in a second place. It answers what text enters a scope, and the
launcher holds that text rather than a name, so which alias is canonical stays with the grammar
that owns it while the surface above stays ignorant of aliases entirely.

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

## Three questions about the live map, and no state behind any of them

`aliasesOf` reports one scope's live aliases, `catalog` reports every scope that can be
entered at all, and `queryFor` reports the text that enters one. All three are derivations
over the map `configure` already built, so none of them adds state, a file, or a lifecycle.

They exist because a surface that lists the aliases has to state what resolves rather than
what was asked for, and this is the only layer that knows the difference. Reading the config
the root built the scopes from would advertise an alias a collision refused, which is the
drift the derived hint was written to prevent, one layer further along.

`queryFor` also keeps the separator in here. It answers `"t "` and not `"t"`, so no caller
appends its own space and forms a second opinion about what entering a scope looks like. And
it decides that the first alias is the canonical one, first meaning the order they were
written in filtered to the ones that survived, so the short word written first is the one a
caller gets and that judgement is not made at each call site.

All three hand back data and no wording. How a list of aliases reads is the business of
whoever shows it, per the rule that human text lives in config and in the composition root,
so there is no formatter here and there should not be one.

## The directory is not a scope this spoon names

The list of every alias is a scope like any other, built in the composition root from
`catalog`, and it is deliberately not something this spoon offers about itself.

The tempting version was a built in reflexive scope, since the spoon holds the data and a
directory of its own grammar is arguably its own business, the way the separator is. It was
not taken, because the sentence above about naming no scope is worth more than the convenience.
Naming none at all is a rule with no judgement in it. Naming exactly one, itself, is a rule
that has to be argued each time something else looks reflexive enough to qualify.

Root policy costs nothing to reach that way. The contract asks for two functions and never
asks where they came from, which is already how menu search works with no spoon behind it, so
a directory built from a public method is the same shape. Its alias then lives in
`config/keys.lua` beside every other alias rather than as a constant in here, so it is changed
the same way and a tool that ever wants `?` collides with it loudly instead of quietly losing
to a built in.

## Where the aliases live, and why not here

In `config/keys.lua`, on the same entry that already holds the tool's key and
description. The row that advertises an alias and the resolver that answers it read
one piece of data, so the hint and the behaviour cannot drift, which is the same
reason the chord label on a row is derived rather than written. A tool with no
`aliases` field is simply not scopable, so nothing is switched on by accident.

The directory reads them and does not write them, so config is still the only source.
When editing arrives the stored choice takes precedence and the config entry becomes
the fresh machine seed, which is how the overlay display policy already works, and
that is also the change that earns this spoon the file split described below. Reading
first was deliberate. Seeing the words and being handed one is most of the value, and
it needs no store at all.

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
refresh after seeding or the tool opens on an unfiltered list. That prediction came
true, in the launcher's seeded open, which is what `queryFor` feeds and which refreshes
for exactly this reason.

Calling the launcher's `show` bumps the open id, which is exactly what invalidates a
scope's per open cache. So a test that shows, seeds, and selects in one breath selects
whatever the scope shows while its data is still being read, which for the menu scope
is a disabled row that cannot be chosen at all. The result is no dispatch and no error,
which reads as a broken route. Wait for the read between showing and selecting.

The general lesson is the one the clipboard timing work already recorded elsewhere in
this configuration. Measure, and be suspicious of a harness that reaches inside a
widget, because the paths a real keystroke takes and the paths a console call takes are
not the same.
