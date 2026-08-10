# ActionPanel.spoon

The decision trail for this spoon. Cross cutting material stays in the hammerspoon
CLAUDE.md, which links here.

## What it is

The measurement phase eight's action panel is built on, and packet one of three builds
nothing else. A panel lists a chooser's verbs and never its navigation, and before this
packet that distinction did not exist anywhere in this repository, every binding in
config/keys.lua was one undifferentiated shape. This module answers the one question a
panel needs answered, given a context's bindings, which of them are verbs, the things a
person forgets the chord for, rather than navigation, the shared moving up and down,
inserting, closing, and scrolling the preview that every context already carries.

## What a kind is, and why the set is named rather than written as a string

A kind is one of exactly two answers, navigation or verb, and obj.kinds is where both
live, obj.kinds.navigation and obj.kinds.verb. Two members, closed.

Writing them as a named set rather than as bare strings scattered through the composition
root and this module is the same named values rule the rest of this configuration already
follows for a predicate name, an app key, and a shortcut kind. The alternative is every
caller agreeing by hand that the word is "verb" and not "verbs" or "action", with nothing
to catch the day one of them drifts. Referencing obj.kinds.verb instead means a
misspelling is a nil field rather than a string that quietly matches nothing, and a third
kind added later is one new member here rather than a new literal every caller has to
learn and spell the same way.

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
