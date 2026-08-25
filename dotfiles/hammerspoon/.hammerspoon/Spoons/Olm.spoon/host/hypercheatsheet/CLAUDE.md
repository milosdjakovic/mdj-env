# HyperCheatSheet.spoon

The decision trail for this spoon. Cross cutting material stays in the hammerspoon
`CLAUDE.md`, which links here.

## What it is, and what it deliberately is not

A content builder for the overlay that appears while the Hyper leader is held. It resolves
and it renders, and it decides nothing about which apps get a letter or which letter each one
sits on. That choice belongs to the person configuring this machine, written once as
`config/keys.lua`'s `appToggles` list, and this spoon reads that same list rather than holding
an opinion of its own about it. A host that decided any of that for itself would risk the
overlay showing a key the actual app toggle bindings do not answer to, which is exactly the
drift the picker checklist and the two discoverability mandates elsewhere in this
configuration exist to prevent. So the overlay and the bindings can never disagree, because
both read the same data rather than each holding a copy that could quietly go stale against
the other.

## apps, toggles, and items

`opts.apps` is `config/apps.lua`, the person's own bundle id registry, a plain map from an
app's name to its bundle id. `opts.toggles` is `config/keys.lua`'s `appToggles` list, the
person's own map from a key to an app name. Neither is something this spoon could work out on
its own, both are this person's private knowledge of what is installed on this machine and
what has earned a letter on the Hyper leader, so both arrive from the composition root as
plain data rather than as anything computed here.

`configure` joins the two exactly once into `self._items`, one entry per toggle carrying its
key, its resolved application name, its bundle id, and its icon, and it drops any toggle whose
app cannot be found on disk rather than showing a row for something that is not actually
installed. This join happens once, at configure time, and never again on a later show, because
resolving a name and an icon is disk work, and paying that cost every time the leader is held
would make the overlay feel slower the more apps are toggled. What is not precomputed is which
of those items are currently running, since that is the one fact about an app that changes
while Hammerspoon runs, so the running and dormant split is read fresh on every show while the
items behind it stay the same list built once.

## What the manifest declares, and why each policy is what it is

The one lib dependency this spoon carries is the shared `cheatSheet` renderer, and it is
required. This spoon draws nothing of its own, every pixel of the overlay comes from that
shared renderer, so without it there is nothing for the row model this spoon builds to ever
become, and there is no lesser overlay to fall back to the way a missing optional dependency
elsewhere leaves one backend of a feature quietly excluded.

`apps` and `toggles` are both optional, and both for the same reason. Each is the person's own
data rather than anything this configuration ships, so a fresh machine with neither written yet
has not broken anything, it simply has no app section to show while everything else that does
not depend on it keeps working. `sections`, the static, non app rows the composition root
appends below the split for whatever else in this configuration carries its own Hyper chord, is
optional for a different reason, it is composed policy built out of other plugins' own
bindings, something this spoon could never derive by itself, and its absence only means the
overlay ends where the app grid ends.

## How the overlay degrades

Without `apps`, a toggle's app name has nothing to resolve a bundle id from, so no item is ever
built for it and the app section of the overlay comes up empty, which is exactly what the
manifest's own `apps` break sentence says. Without `toggles`, there is no list of keys to
resolve against the registry at all, so the same empty app section follows for the mirror
reason. Neither absence stops the overlay from opening or breaks the sections appended below
it, they only shrink the one part of the overlay that depended on the missing data.

Without `sections`, the overlay simply stops after the running and dormant split, since nothing
hands it anything to append there, and the app half of the overlay is entirely unaffected.

None of these three absences ever leaves the overlay with nothing to draw, because the one
dependency that genuinely would, the shared renderer itself, is the one dependency this spoon
actually requires. That is the whole shape of the policy here, a person's own data degrades
gracefully because the overlay's reason for existing does not depend on it alone, while the
mechanism that does all the drawing does not get to be optional.
