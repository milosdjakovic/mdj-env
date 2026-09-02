# LinkRouter, decisions worth not rediscovering

## A chooser row carries plain data only, and this one bit the hardest

An entry holds a live reference to its provider, and a provider's members are functions. A
chooser row is serialised to native objects, functions cannot be converted, and LuaSkin
does not skip the offending field. It rejects the WHOLE choices table, so the chooser renders
completely empty with no visible cause. The only trace is the console.

```
LuaSkin: dictionary key (claims) cannot be converted into a proper NSObject
LuaSkin: hs.chooser:choices() table could not be parsed correctly.
```

This shipped. Rows carried the entry itself, both the router and the configuration page went
blank, and it survived several rounds of probing because every probe read `rows()` in Lua and
never through the widget. A row now carries an id and the entry is resolved when acting on it.

The lesson generalises past this plugin. A probe that calls a presentation's `rows` proves the
data, never the rendering, so anything a row carries that is not a string, number, boolean, or
a table of those has to be checked separately. Walking every row's payload for functions and
userdata is a two minute check and it is the one that would have caught this.

## matcher = false means the widget does not filter, and it cost search

`presentation.matcher = false` does not mean use the default. It means inject no strategy and do
not filter, which is correct only when the plugin's own `rows` reads the query and filters
itself. Every child level here was written with `matcher = false` copied from the menu style
pages in this tree, and their rows ignore the query, so typing in the More list did nothing at
all. Declaring nothing inherits the shared fuzzy strategy, which is what a destination picker
wants.

The menu pages that do declare false have a reason, a fixed short list where filtering could
hide the Back row. That reason does not transfer to a list of browsers you want to reach by
typing two letters. Copying the field without copying the reason is what went wrong.

## Why everything not in the main list goes under More rather than off

Turning a destination off used to remove it from the router entirely. It now moves one level
down, behind a More row, so a person can keep a two or three row main list without losing access
to anything. That makes the main list a genuine preference rather than a commitment, which is
what makes emptying it to reorder safe.

## Why Start over empties rather than resets

Appending is the only way an entry joins the main list, so reordering means emptying it and
picking again. The row writes an explicitly empty list, NOT nil. Nil means never configured and
brings the built in default back, every ordinary destination in discovery order, which is the
exact opposite of starting over and was the first thing this row did wrong.

## Why there is no second application bundle

Every comparable tool ships an application whose only job is to be registered as a browser and
forward the link somewhere. None is needed here. Hammerspoon's own `Info.plist` already
declares `http`, `https` and `mailto` under `CFBundleURLTypes`, and `hs.urlevent` exposes the
callback and the handler claim directly. Anyone who starts by looking for the forwarder app
will not find one, and should not build one.

## Why the handler is claimed once and never restored

`hs.urlevent.setRestoreHandler` exists to hand a scheme back when Hammerspoon exits or reloads
and reclaim it on start. It is deliberately unused. macOS puts up a confirmation panel on every
http handler change, so a restore and reclaim cycle would mean two panels on every reload, and
this config reloads many times a day. A claim written to LaunchServices survives a reload on
its own, so start has nothing to do beyond installing the callback.

The price is real and is not a defect. A link clicked while the config is reloading, or while an
error has it down, is lost. That was weighed against two panels per reload and judged the
cheaper failure. Anyone tempted to fix the lost click with `setRestoreHandler` should reread
this paragraph, and anyone who genuinely needs the click never to be lost needs the forwarder
application the section above says not to build, with its own fallback for when Hammerspoon is
not answering.

## Why there are no keyboard shortcuts

There were, briefly, six of them, two for ordering, one for a private window, two for making
rules and one for deleting one. Milos asked for them all to go, and he was right, a tool you
reach for by clicking a link is not a tool anybody memorises chords for. Everything is now an
ordinary row you choose, and the design changes below are what made that possible rather than
merely hidden.

Only the shared navigation keys remain, which is why the manifest declares no `surface.extra`
and no `registry.surface` at all.

## Why shown and ordered are one stored fact

The obvious model is a set of flags for what appears plus a separate arrangement for the order,
and it needs keys to move things. Collapsing both into one ordered list of ids removes that
entirely. Choosing a destination on the configuration page appends it to the list, which is
both what makes it appear and what fixes its place, so picking Safari then Chrome (Milos) then
Chrome (Vicert) produces exactly that order with three ordinary selections. Choosing one already
on the list removes it. The number shown beside each row is its real position in the router, so
the page reads as the list it produces rather than as settings you then have to arrange.

This also killed an earlier problem rather than working around it. Ordering used to be move to
top and move to bottom, because the stage owns the highlight and keeps it on a row number, so a
swap with the neighbour would leave the highlight on whichever entry swapped into that position
and the second press would undo the first. Appending on choose has no such tension, since the
gesture is complete in one press and nothing is expected to continue on the same row.

## Why never configured is different from configured to be empty

The stored value is nil until something is chosen, and nil means show every ordinary
destination in discovery order. A fresh machine therefore has a working router instead of an
empty one, which for a tool that has just taken over every link on the machine is the difference
between useful and broken. The moment anything is chosen the stored list governs completely,
including being deliberately empty.

Private windows sit outside that default on purpose. Offering everybody a private window for
every profile they own would double the list for something most people want once or never.

## Why a private window is an entry and not a modifier

A private window is a destination you turn on and place in the order like any other, emitted by
the provider as a second entry beside the ordinary one. It was briefly a key, and as a key it
needed the engine to answer whether a given destination was even capable, which meant either a
capability flag every provider had to keep true or a method whose absence carried the meaning.
As an entry the question disappears. A provider that cannot do it simply never emits the entry,
so nothing anywhere has to ask, and the row cannot offer something that will not work.

Safari and Arc emit none, and never will. macOS offers no way to ask either for a private window
from outside, no launch argument and no scripting door.

## Why profile support is a provider chain

Profile expansion is the one thing that genuinely varies by browser family, so it is the one
thing that earned an engine, a contract and a file per provider. Chromium reads its own
`Local State` and opens with launch arguments. Everything else is one row opened by bundle id.
The engine holds the state and names no browser, the composition root in `init.lua` fixes the
chain order, and the provider claiming everything must be last or nothing else is ever asked.

The Chromium provider decides whether it claims an application by reading from disk, never from
a list of bundle ids. A list would be stale the day anything new shipped. Finding the support
directory from a bundle id is the awkward part, since no rule guarantees it, so candidates are
built structurally out of the bundle id and the application name and each is proved by opening
the file. Helium is reached by its bundle id alone, Chrome by the vendor and product pair its
own bundle id spells. When nothing proves out the application is not claimed and gets the single
row it always had, which is the correct degradation rather than an error.

## Why Safari and Arc have no profiles

Safari has had profiles since macOS Sonoma and exposes no supported way to open a url in a
particular one. Discovery is not the obstacle, so finding where Safari keeps its profiles would
not help. Arc is the same conclusion by a different route, its spaces are not profiles and it
exposes no argument for them. Both are deliberate absences and neither is waiting on work.

## Why rules are made from the router

A rule needs a condition, a destination, and the intent to make one. Standing in front of a link
you just clicked, all three are in hand, so the last row of the router offers to make one and
pushes a page of destinations. A form on the configuration page would ask you to retype from
memory what the router already knows. The configuration page only lists and deletes, and
deleting is choosing the rule, since a page whose rows are all deletable needs no separate verb.

Making a rule opens the link too. Asking somebody to choose the same destination twice, once to
teach and once to act, is asking a question already answered.

## Why the newest rule is asked first, and why one can still decline

Rules are prepended. A rule made now is the most specific thing currently known, and somebody
adding a narrower rule later expects it to beat the broad one from last week. Re-adding a rule
for the same kind and value replaces it rather than sitting in front of it, so the list cannot
grow shadowed duplicates.

A rule stores a destination id, and the browser behind it can be uninstalled. Rather than
matching and then opening nothing, a rule whose destination no longer resolves is skipped and
the next is asked, so the chooser opens exactly as it would have without the rule. A rule that
silently swallows links is far worse than one that stops applying.

## Why a domain rule matches on a dot boundary

A rule for example.com matches example.com and anything under it, compared as a suffix on a dot
boundary rather than a plain suffix. A plain suffix would let a rule for example.com also
capture notexample.com, which is a different site owned by somebody else, and in the wrong hands
that is a way to steer a link somewhere it was never meant to go. This has a probe case rather
than being left to reading.

## Why one presentation serves two lists

The composition root publishes `stagePresent(name)` and nothing that hands the stage an
arbitrary presentation table, so an identity has exactly one top level list. This plugin has two
genuine ways in, a link arriving from outside Hammerspoon and a launcher row, and they want
different lists. Both are answered from the one registered presentation, with the waiting link
itself as the discriminator, so no separate mode flag exists that could disagree with it.

`onPresent` rewords the field for whichever list just became current, which is why the rewording
lives there rather than beside either caller. `onClose` drops the waiting link, which is what
makes an escaped link a cancelled link rather than one still sitting in a variable waiting to be
answered by a window opened later for something else entirely.

If a root word for presenting an arbitrary page ever lands, this collapses into two plain
presentations and should.

## Why the self exclusion is not a roster

Hammerspoon is removed from the destination list by comparing against `hs.processInfo.bundleID`,
never by name. It is not a judgement that this application is uninteresting, it is the one
structural exclusion the design requires, since Hammerspoon is the registered handler and
offering it would loop. Every other application LaunchServices reports is listed and left to the
person to turn off, including other link routers.

`hs.processInfo.bundleID` is read inside a function rather than into a module level local. The
dry gate loads these modules under a permissive stub where `hs.processInfo` autostubs to a
table, and a bundle id concatenated at module scope raises there and reports the plugin unknown
instead of checking it.

## Why a pasted url bypasses the stored rules

A clicked link asks the rules first, since nobody standing at that click typed anything and a
rule is how they said in advance what should happen without being asked again. A url pasted or
typed into the launcher is the opposite case, the person is standing right there choosing to
route it by hand, so `routeURL` sets the pending link directly and never calls `engine.routeFor`.
Asking the rules on this path would let a rule silently override a choice the person is making at
that very moment, which is a worse surprise than a rule never firing here at all.

## Why the pinned row pushes the shared presentation rather than building its own rows

The pinned row's whole point is to hand a person exactly what a clicked link already shows,
their ordered destinations, More, Copy link, all of it, rather than a second, thinner list built
to look similar. Rebuilding that shape in the launcher would be a second copy of every row this
file already knows how to build, drifting from the real one the moment either changes. So the
row's own choosing is not answered by this module at all, `M:rows` answers a plain data item and
the composition root pushes this plugin's own registered presentation the identical way it
already pushes one for a `special` row, `routeURL` handing over the url first since this module
has no way to reach its own presentation to push it itself.

## Why the presentation's own rows member was renamed

The launcher's own query door is hardcoded to ask a source for a member literally named `rows`,
`host/launcher/init.lua`'s own `provider:rows(query)`, and no string written in any manifest
changes that. A presentation's own member carries no such rule, `lib/registrar.lua`'s own
`callMember` resolves whatever name the manifest states, which is why filesearch answers
through `chooser.rowsForQuery`, browsertabs through `chooser.rows`, and clipboard through
`manager.rows`, three different names for the identical contract. So the collision here was
never structural, it was this plugin's own presentation happening to be called `rows` too, the
one name the query door cannot be talked out of wanting. The fix is renaming the side that is
free to be renamed, the presentation's own member is now `presentationRows`, and the query door
keeps the bare name, since that is the only name it is ever asked by.

## A trap for other plugins in this spoon

`hs.urlevent.openURL` resolves the system default handler and opens the url through it. Once
this plugin holds the handler for https, any other plugin in this spoon that calls
`hs.urlevent.openURL` with an http or https url no longer opens a browser, it lands back in this
chooser. Nothing in the tree does that today, every current caller passes a private scheme such
as `raycast://`, and this is written down because the next one to reach for `openURL` will not
expect the bounce. A plugin that means one specific browser should say so with
`hs.urlevent.openURLWithBundle`.
