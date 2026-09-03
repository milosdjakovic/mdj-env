# Vpn.spoon

VPN controls in one flat list that merges the connect and disconnect action with the
location search. `init.lua` is the composition root and the command policy, `engine.lua`
is the mechanism that drives a provider through `contract.lua`, and `providers/` holds one
file per backend. Two backends exist, Mullvad and IVPN, and one drives at a time. This is
Strategy wired through injection, the engine names no backend and a provider is the one
file that knows its concrete CLI.

**Why this file exists.** It records the backend dependencies, how the tool behaves when one
is absent, and the decisions behind supporting more than one, so the reasoning survives even
though the code only shows the result. Update it whenever the provider contract, the
switching behaviour, or the unavailable behaviour changes.

## Adding a backend

A new file in `providers/`, one line in `PROVIDER_FILES` in `init.lua`, one entry in
`needs.tools` in `manifest.lua` naming the new provider as its `unit`, then the repository
half, a `DEPENDENCIES.map` line and a `Brewfile` entry. Nothing else in the plugin is
touched, and the page picks the new backend up on its own.

A scan of `providers/` was considered instead of that roster line, so a forgotten line would
be impossible. It was rejected because the dry contract gate loads this module against a
permissive `hs` stub where `hs.fs.dir` answers another stub rather than an iterator, so the
scan would hang the very gate that catches mistakes of this kind. The provider page recovers
most of what the scan would have given, since a file with no roster line is a row that never
appears in the one place a person goes to look for it.

## One backend at a time, not every backend merged

Merging every provider's locations into a single list was considered and rejected on three
grounds. Two VPN daemons cannot usefully both hold the routes. A single action row cannot
carry two tunnel states. And choosing a foreign city would flip the daemon underneath a
person as a side effect of picking a place, which is a surprise nobody asked for. So the
providers are a choice rather than a union, and the choice is a page rather than a config
file.

The page is a child presentation returned from `select`, so the stage pushes it in place.
Choosing a backend answers `"stay"`, which holds the page open with the highlight on the row
just pressed, because a page of options a person flips is not somewhere they should be
ejected from. Back is the one row there that is a real level change, so it pops and answers
plain `true`. It is placed last in the location list on purpose, since the row directly under
the action row is the most recently used location and that is the whole point of the
ordering, so a settings row in second place would push the thing a person came for down by
one on every open. Its `filterText` carries settings, config, and provider, so the placement
stops mattering the moment it is wanted.

The page is deliberately absent from the launcher's scoped rows. A scope's own `run` door
discards whatever `select` answers, so a row whose entire job is to answer a child
presentation would look live in the launcher and do nothing at all when chosen.

## The contract shrank when the second backend arrived

`selectedLocation` used to be required and is now optional, probed for by name in
`engine.lua` before it is called. Mullvad holds a persistent location constraint that can be
read while the tunnel is down, so it can say where a connect would go. IVPN holds no such
thing, its own answer lives in a root owned settings file this layer may not read, and the
CLI exposes no reader for it. A method only one backend can answer is not a contract, it is
an interface extracted from a single implementation, so requiring it would force every future
provider to invent an answer it does not have.

What that costs is visible and was accepted rather than hidden. On IVPN the disconnected
action row reads a bare `Connect` instead of naming a place. Falling back to the top of the
recency list was rejected, since that is a guess rather than a read and it goes wrong the
moment somebody connects from IVPN's own app. For the same reason IVPN's own `connect` asks
the CLI for the last used parameters, which is the honest equivalent and is self limiting,
because choosing a location is the normal first move anyway and every connect after it has a
last to return to.

The other shape change is `detail` on a location entry, optional, the provider's own subtitle
text for a location. The two backends do not spell a place the same way, one naming a country
and a city code and the other a gateway host, and neither spelling is the general case, so a
caller assuming either would be reading one backend's vocabulary into every other.

## Switching is a generation, not an assignment

`M.prepare` runs three reads off the main thread and none of their callbacks knows which
backend asked for them, so a switch mid flight would let one provider's location list land in
another's cache. Every switch bumps a counter, and every landing checks it before writing
anything and before counting itself down.

Both halves matter and the second is the less obvious one. Without the write fence a backend's
locations and its status land under another backend's name. Without the count fence the
abandoned round's own countdown still reaches zero, which clears the `fetching` guard and
flushes the pending list while the surviving round is still in flight, leaving the surviving
round unable to complete its own bookkeeping.

The order that exposes this is the abandoned backend answering **last**, which is the ordinary
case whenever the backend being left is the slower of the two. An offline probe that landed
the stale legs first passed with the fence entirely removed, because the surviving round's
writes simply overwrote them, so a test of this has to drain adversarially or it proves
nothing.

## Every provider is resolved, not only the active one

`resolveAll` hands every provider the path the shared resolver found before anything asks
which backend can drive. A provider reports itself unavailable until it has been given a
path, and both the provider page and the initial choice ask each provider that question.
Resolving only the active one, which is what the first version of this did, meant every other
provider answered a confident false however installed it actually was, so the page read
`Not installed` for a working backend and the initial choice fell through to the first entry
in the roster rather than to the stored one. An offline probe caught it, nothing static would
have.

## The stored choice, and why a fallback is not persisted

The active backend is remembered under `olm.vpn.provider`, storing the provider's own file
stem rather than its display name, since the name is presentation and can be reworded while
the stem is the identity everything joins on. At load the stored choice wins when it still
names a provider that can drive, otherwise the first provider in the roster that can.

A fallback is deliberately not written back. A stored choice whose app has since been removed
keeps standing, so reinstalling that app puts the tool back where the person left it rather
than silently making a temporary fallback permanent. When nothing is available at all the
first provider is still returned, so the list opens to that one's missing tool row with the
page beside it rather than to nothing.

## One recency instance is shared across backends

The shared lift to front service is one instance for the whole plugin rather than one per
backend, which is safe because it partitions on whether a key is remembered and leaves
everything else in arrival order, and because no two backends spell a location the same way.
One says `us/lax` and the other `gb.wg.ivpn.net`, so a key stored by one is never matched
while the other orders its own list. Sharing it also means an order somebody already built up
survived this change, which a per backend key would have discarded for nothing.

Nothing here may call the service's own `prune`, which would read one backend's ids as the
complete set of valid keys and forget every other backend's.

## The placeholder claims nothing that can change

`M.placeholder` resolves once, when the plugin registers, and the presentation contract wants
a plain string rather than something to call again later. So it names no backend and no
availability, since either would be frozen at registration and would then quietly contradict
the list the first time somebody switched. The rows say both of those things and are rebuilt
every time they are asked, which is where a claim that can change belongs.

## The backend dependency

Each provider shells out to one command line tool that its own VPN application installs,
`mullvad` and `ivpn`. A provider probes for nothing. The plugin's manifest declares both
tools, each with `unit` naming the provider that wants it, the shared resolver in
`lib/deps.lua` finds them once for the whole config, and `init.lua` hands each provider its
resolved absolute path through `configure`. So no install prefix appears anywhere in this
spoon and the same files work on either architecture.

The declaration used to sit in its own file beside `providers/mullvad.lua`, because that
provider is the only file that knows its tool exists, so adding a backend was a new provider
file plus its own declaration with nothing shared to edit. It sits in the plugin's single
`manifest.lua` now, and that is a real cost paid on purpose. Adding a backend means one entry
in a file every backend shares, so a provider is no longer quite self contained. What was
bought for it is that a tool is described exactly once, since the old arrangement had the
running config reading one place and the layer above reading another, and the two drifted
until ten tools had quietly stopped being declared at all. The `unit` field on the entry is
what keeps the half of the old placement that was load bearing, so a missing tool still names
the provider that wanted it rather than the whole plugin.

## What the provider knows, and what it must not

How to get the backend is not provider knowledge. `providers/mullvad.lua` exposes `M.name`
and an optional `M.install` carrying only a `note`, a plain sentence naming the application
that ships the CLI. That is a fact about the backend. Which package manager delivers that
application is a fact about the machine, and it lives one layer up, in `DEPENDENCIES.map`
at the repository root, joined to the declaration by the tool name.

An earlier version carried an install command here and let the unavailable row copy it to
the clipboard. It was removed. The command duplicated an answer the repository already held
exactly once, so the two could drift apart silently, and it put package manager knowledge in
the one layer whose whole rule is to declare a need and never answer it. What is left is the
honest division. The panel and the console line say Mullvad is missing, and
`src/check-dependencies.sh` in the repository says it comes from the `mullvad-vpn` cask, is
optional, and costs the VPN controls.

`contract.validate` does not require the install metadata, since it is optional. A provider
without it still gets a titled row and a generic log.

## Cities are ordered most recently used, the action row stays pinned

The cities under the action row are shown most recently used first, so the last place you
connected to leads them and the ones before it follow, with everything never chosen keeping
the provider's own order below. Choosing a city lifts it to the front, so it sits right below
the action row on the next open. This is command policy, so it lives in `init.lua`, the policy
file, not the engine or the provider, which stay ignorant of ordering. The order is a plain
list of location ids, newest first, persisted under one `hs.settings` key so it survives a
reload or a reboot. It is kept an inline closure rather than its own module because it is a
single consumer with a little state, so a wrapper would be ceremony without a second caller.

The action row is deliberately outside this. It is added ahead of the list on the empty query
and always leads, so only the cities reorder and the connect or disconnect control never moves.
The reorder happens once when the relay list lands on open, not per keystroke, and a typed
filter reranks by match score anyway, so recency only decides the resting order of the
unfiltered list. An id that no longer names a relay simply never matches, so a stale entry is
inert rather than an error.

## Missing CLI degrades to a self explaining panel, not a dead key

When the active provider's `available()` is false the engine is left unwired and the list
presents a row that names the missing backend and, as its subtitle, the application that
provides it. The row is built with `enabled = false`, so the stage dims it and never
dispatches it. It is a label, not an action, because the only useful action would be to
install something and this layer may not know how. The reason is logged too, so the gap shows
both in the UI and in the console, and the repository answers the rest.

This replaced the old behaviour where a missing CLI logged once and made the open key do
nothing, which gave the user no on screen signal at all. The trade is that the tool is
never silently dead, opening it always shows something that explains itself. The engine
is only wired when the backend is present, so the unavailable panel makes no provider
calls and cannot stall.

That row used to be the whole list and therefore a dead end. It is not one any more, because
the provider row is shown beside it, so somebody who switches to a backend they have not
installed can always reach the page again and switch back. Making that reachable is what lets
this row stay a label rather than having to grow an action.

The `available` flag is resolved once per activation, not per open, because whether a CLI
exists does not change while Hammerspoon runs. The separate `unavailable` state a live daemon
reports, when the CLI is present but the service is not answering, is a different thing the
engine already handles through `status()`, and it is not this panel. IVPN's own read of that
distinction is worth naming, since its CLI prints a failure sentence instead of a status
block when the daemon is unreachable, so a missing `VPN` line reads as unavailable rather
than being guessed at as disconnected. Reporting disconnected there would be confidently
wrong in the one case where being wrong matters, a tunnel that is actually up while the
daemon is merely unreachable.
