# ActionPanel.spoon

The decision trail for this spoon. Cross cutting material stays in the hammerspoon
CLAUDE.md, which links here.

## What it is

The measurement phase eight's action panel is built on, packet one of three, and the panel
itself, packet two, the chooser it opens a chord away from a chooser already open. A panel
lists a chooser's verbs and never its navigation, and before packet one that distinction did
not exist anywhere in this repository, every binding in config/keys.lua was one
undifferentiated shape. verbsIn answers the one question a panel needs answered, given a
context's bindings, which of them are verbs, the things a person forgets the chord for,
rather than navigation, the shared moving up and down, inserting, closing, and scrolling the
preview that every context already carries, and the panel's own chord besides, since a panel
must never list its own way in among the verbs it offers. decorate, toggle, and isOpen,
packet two's own additions, are the panel itself, described from "The panel itself, packet
two" onward below.

## What a kind is, and why the set is named rather than written as a string

A kind is one of exactly two answers, navigation or verb, and obj.kinds is where both
live, obj.kinds.navigation and obj.kinds.verb. Two members, closed. Navigation, since
packet two, means every binding the panel does not list, not only the eight shared moving,
inserting, closing, and scrolling actions packet one named but the panel's own chord too,
joining that same kind rather than earning a third member of its own.

Writing them as a named set rather than as bare strings scattered through the composition
root and this module is the same named values rule the rest of this configuration already
follows for a predicate name, an app key, and a shortcut kind. The alternative is every
caller agreeing by hand that the word is "verb" and not "verbs" or "action", with nothing
to catch the day one of them drifts. Referencing obj.kinds.verb instead means a
misspelling is a nil field rather than a string that quietly matches nothing.

That protection stops at spelling. verbsIn carries one branch for verb and one for
navigation and nothing else, so a third member added only to this table would not be
handled for free, it would fall into the same branch an unclassified action already falls
into, dropped and reported as a defect. Growing this set to three members is a new member
here and a new branch in verbsIn together, never one without the other.

## Why the classification is the root's, and not config/keys.lua's

The design says the kind is stamped by the host, from a named set, per the named values
rule. Read that as the host, this module, owning the set of possible kinds, and the
composition root owning the map from an action name to a kind, since init.lua already
keeps contextActions, the one place that knows what every action name means. Putting a
kind field on each of the sixty odd bindings in config/keys.lua by hand would repeat the
same word forty times for navigation alone, and the twelve contexts would drift against
each other the moment somebody added a thirteenth without remembering to stamp it there
too.

So config/keys.lua stays the pure data it already claims to be, this module names the two
possible answers, and the composition root's own actionKinds table, written beside
contextActions, is the concrete policy joining an action name to one of them. Adding an
action still costs exactly one line in that table, and a load time completeness check,
also in the root, warns by name for a binding whose action has no entry there and for an
entry no context uses any more, so a gap is visible rather than found the day the panel
draws a row wrong.

## Why an unclassified action is dropped rather than kept

verbsIn answers three ways to an action, keep it as a verb, drop it in silence as
navigation, or drop it with a warning naming the action, the third case covering deps.kindOf
answering nil or answering something that is not a member of obj.kinds at all.

Dropping is the safer of the two answers open to an unclassified action, because the two
mistakes it could be do not cost the same to get wrong. Keeping an unclassified action that
turns out to be navigation breaks the panel's whole promise, a navigation row silently
present in a list that swears it never lists one. Dropping an unclassified action that
turns out to be a verb only goes missing, and it goes missing loudly, one warning naming
the action, which is enough for whoever reads the console to find it and add it to
actionKinds. A defect that announces itself and is one line to fix beats a defect nobody
sees until they wonder why a chord nobody remembers still works.

## Why this module knows nothing about needs, when, or an open chooser

verbsIn takes a context's bindings and nothing else. It never asks whether a binding
applies given a needs field, never asks whether its when predicate currently holds, and
never asks whether any chooser is even open. Those filters already exist in the
composition root, named bindingApplies and bindingActive, and composing them with this
module is a later packet's work, not this one's.

Keeping them out here is what makes verbsIn a statement about the declarations themselves,
a fact that only changes when config/keys.lua or actionKinds changes, rather than a
statement about a moment that could answer differently from one call to the next with
nothing in the source having moved. That is exactly what test/inventory.lua's own
actionpanel section leans on, since it can only be a stable measurement, checked byte for
byte across three separate runs, if the function underneath it never asks a question whose
answer depends on the clock or on what happens to be on screen.

## Why the snapshot section is unfiltered, and stays that way

test/inventory.lua's actionpanel section calls spoon.ActionPanel:verbsIn directly against
each context's raw bindings, with no needs filter and no live predicate layered on top, on
purpose and permanently. A later packet may add exactly that filtering to the panel itself,
narrowing what a person actually sees when one context's needs are not met on this
machine, but it must never narrow what this section measures, since the two numbers answer
different questions. The panel's live filtered count can legitimately differ from one
machine to the next depending on what needs happens to resolve to today. The section's
unfiltered count can only differ when the classification itself changes, which is the one
thing packets two and three of this phase are not allowed to touch, since neither of them
changes what a verb is. Filtering this section to match the panel would make the golden
file start answering the wrong question, one that changes for reasons that have nothing to
do with a defect in the classification.

## Why it is a configured singleton and not a factory

There is exactly one classification policy for this whole configuration, the one
actionKinds describes, so there is exactly one instance, colon called, in the shape
host/launcher and host/queryscope already use. lib/registry.lua is a factory, M.new,
because a registry is state a config might reasonably want more than one of. Nothing here
is state at all beyond the two injected functions configure stores, so a factory would be
a second way to build a thing this configuration only ever needs once, with nothing to
show for the extra layer.

## The panel itself, packet two

Packet one built only the measurement, no panel, no chord, no visible change. Packet two
builds the panel a chord opens, a chooser opened by its own key, showing that chooser's own
verbs and nothing more. decorate, toggle, and isOpen are what packet two adds, on top of the
classification packet one already built, and both packets stay in this one file since there
is exactly one panel for this whole configuration, the same reason kindOf and verbsIn are a
configured singleton rather than a factory.

## The decorator shape, and why it installs at one seam rather than at twelve call sites

The chooser atom is the one component this whole configuration already shares, a factory,
Chooser.new, called twelve times, once per context, each handing in its own rows,
intercept, back, onSelect, onHighlight, and onClose. A panel that needed a plugin to opt in
would be ten edits today, since only two of the twelve pass intercept and only one passes
back, and a silent gap the day somebody adds a thirteenth chooser and forgets it.

So the panel is a Decorator over that one component, wrapping the same six functions rather
than replacing any of them, installed through decorate, one function handed to
Chooser.configure and called once for every instance the facade builds, right after
native.new returns and before new hands the instance back. Every chooser behaves exactly as
it did whenever the panel is closed, which is almost always, and no file under
Spoons/Olm.spoon/plugins is edited and none of the twelve consumers learns the panel exists.

This rests on two small additions to the atom itself, made first and used by nothing until
this module reached for them, Chooser:selectedRow and Chooser:selectRow, the plain public
counterpart of selectedItem, and the decorate option on Chooser.configure. The atom stored
config.rows once at construction with no setter and answered the highlighted row number
from nowhere outside itself, so a panel that needed to put the highlight back where it
found it, on a row number rather than an item, needed both before it could exist at all.

## What each wrapped function is for

decorate wraps six functions on the config table native.new was handed, and every wrapped
closure checks self._openInstance against the one instance it closes over on every call,
since eleven of the twelve decorated instances are not the open one at any given moment and
must behave exactly as they always did.

rows is the swap, and there is no other. While the panel is open on this instance the
supplier answers the panel's own rows instead of the tool's own.

intercept answers a chosen row. Absent on ten of the twelve consumers today, file search and
the launcher being the two that already pass one of their own, so decorate supplies one
where there was none and falls through to the original where there was, exactly the way an
original intercept keeps a tool's own drilling in behaviour once the panel closes again.

back answers Backspace on an empty field, one of the two ways out of the panel, the other
being choosing its own Back row through intercept. Absent on eleven of the twelve, only the
launcher passing one of its own, same treatment.

onSelect should never see a panel row at all, since every chooser here runs in filter mode
and intercept answers before a row is ever allowed to complete. Reaching onSelect with the
panel open is a defect, not an absence, so the wrapper warns naming the row instead of
calling the original, which would otherwise treat a panel row as one of the tool's own items
in silence.

onHighlight is deliberately not called at all while the panel is open, rather than an
omission. The item a companion pane was already showing is exactly what a chosen verb acts
on, so leaving the preview on it is more honest than blanking it or describing a menu row as
though it were a file.

onClose is where the panel's own state clears, whatever tore the chooser down, escaping,
clicking away, or the tool closing itself. Without this an escape out of an open panel would
leave the state set, and the next chooser opened anywhere would come up already showing
stale panel rows, the worst failure available here.

## Why the highlight is captured and restored, not merely left alone

toggle captures the highlighted item and row the moment it opens, and a chosen verb, once
_choose records the action and closes the panel, restores the row through
instance:selectRow before running it. The reason is the design's own argument for why the
panel and the chord must never disagree about what a verb means. Running an action against
whatever the panel's own list happened to leave highlighted, its own first row rather than
the row the chord would have acted on, would be a second, quieter definition of a verb
living beside the first one. Restoring the row first is what lets deps.run reach through
exactly the same contextActions entry the chord itself runs, against exactly the row the
chord would have acted on, so the two cannot disagree about what a verb does the way they
already cannot disagree about what a verb is called.

## Why the deferral cannot be removed

_choose schedules the restore and the run on a continuation, self._defer defaulting to
hs.timer.doAfter(0, ...), rather than doing either synchronously before returning. This
looks removable and is not. _intercept in providers/native.lua calls refresh(true) on the
instance the moment a handler answers true, and it does that AFTER the handler has already
returned, which is exactly what decorate's own wrapped intercept is. So anything _choose did
to the highlight synchronously would be undone a moment later by that very rebuild, since
refresh(true) resets the highlighted row to the first one. Answering false instead, so the
row completes on its own, is not available either, since that tears the chooser down, and
several verbs, browsing into a folder chief among them, must leave it open. So the restore
has to run after the atom's own rebuild, on a fresh runloop tick, which is the only order
that works, and the deferral is that order's one door. self._defer exists only so a unit
case can hand in a synchronous stand in and read the continuation's own effect back without
a real wait, the same reason self._log exists, and the composition root never sets it.
