# Vpn.spoon

VPN controls in one native chooser that merges the connect and disconnect action with
the location search into a single flat list. `init.lua` is the composition
root and the command policy, `engine.lua` is the mechanism that drives a provider through
`contract.lua`, and `providers/` holds one file per backend. Today the only backend is
Mullvad. This is Strategy wired through injection, the engine names no backend and the
provider is the one file that knows the concrete CLI.

**Why this file exists.** It records the backend dependency and how the tool behaves when
that dependency is absent, so the reasoning survives even though the code only shows the
result. Update it whenever the provider contract or the unavailable behaviour changes.

## The backend dependency

The Mullvad provider shells out to the `mullvad` command line tool, which the Mullvad VPN
app installs. The provider probes for nothing. The plugin's manifest declares the tool,
with unit naming this provider, the shared resolver in `lib/deps.lua` finds it once
for the whole config, and `init.lua` hands the resolved absolute path to the provider
through `configure`. So no install prefix appears anywhere in this spoon and the same
files work on either architecture.

The declaration used to sit in its own file beside `providers/mullvad.lua`, because that
provider is the only file that knows the tool exists, so adding a backend was a new provider
file plus its own declaration with nothing shared to edit. It sits in the plugin's single
`manifest.lua` now, and that is a real cost paid on purpose. Adding a backend means one entry
in a file two backends share, so the provider is no longer quite self contained. What was
bought for it is that a tool is described exactly once, since the old arrangement had the
running config reading one place and the layer above reading another, and the two drifted
until ten tools had quietly stopped being declared at all. The `unit` field on the entry is
what keeps the half of the old placement that was load bearing, so a missing tool still names
this provider rather than the whole plugin.

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
reload or a reboot, the same persistence idea `DisplayMemory` uses. It is kept an inline
closure rather than its own module because it is a single consumer with a little state, so a
wrapper would be ceremony without a second caller.

The action row is deliberately outside this. It is added ahead of the list on the empty query
and always leads, so only the cities reorder and the connect or disconnect control never moves.
The reorder happens once when the relay list lands on open, not per keystroke, and a typed
filter reranks by match score anyway, so recency only decides the resting order of the
unfiltered list. An id that no longer names a relay simply never matches, so a stale entry is
inert rather than an error.

## Missing CLI degrades to a self explaining panel, not a dead key

When `provider.available()` is false at start the spoon still builds the chooser but
leaves the engine unstarted. `M.show()` then skips the live status and relay reads and
opens the chooser on a single row that names the missing backend and, as its subtitle, the
application that provides it. The row is built with `enabled = false`, so the chooser dims
it and never dispatches it. It is a label, not an action, because the only useful action
would be to install something and this layer may not know how. The reason is logged too, so
the gap shows both in the UI and in the console, and the repository answers the rest.

This replaced the old behaviour where a missing CLI logged once and made the open key do
nothing, which gave the user no on screen signal at all. The trade is that the tool is
never silently dead, opening it always shows something that explains itself. The engine
is only wired when the backend is present, so the unavailable panel makes no provider
calls and cannot stall.

The `available` flag is resolved once at start, not per open, because whether the CLI
exists does not change while Hammerspoon runs. The separate `unavailable` state a live
daemon reports, when the CLI is present but the Mullvad service is not answering, is a
different thing the engine already handles through `status()`, and it is not this panel.
