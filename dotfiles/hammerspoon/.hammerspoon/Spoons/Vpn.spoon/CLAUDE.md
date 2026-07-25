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
app installs. On macOS that is `brew install --cask mullvad-vpn`, and the CLI lands at
`/opt/homebrew/bin/mullvad` on Apple Silicon or `/usr/local/bin/mullvad` on Intel, the
two paths the provider probes before falling back to a login shell PATH lookup.

The cask is deliberately not in the repo Brewfile. VPN is a per machine, optional thing,
so a fresh machine boots without it and the tool degrades rather than every machine being
forced to install Mullvad. If you want VPN controls working out of the box on a new
machine, add `cask "mullvad-vpn"` to the Brewfile. Otherwise install it by hand when you
want it, and the running config picks it up on the next reload.

## Install knowledge lives in the provider, not the root

How to get the backend is provider knowledge, the same as its human name, so both are
metadata the provider carries. `providers/mullvad.lua` exposes `M.name` and an optional
`M.install` of `{ note, command }`. The composition root and the panel read those and
never name Mullvad or brew themselves. This keeps the inversion honest, the earlier code
hardcoded the brew line in the root's log message, which leaked the concrete backend and
the platform into the spoon. A future provider supplies its own install line and both the
log and the chooser follow with no edit here. `contract.validate` does not require this
metadata, since it is optional, a provider without it still gets a titled row and a
generic log.

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
opens the chooser on a single row that names the missing backend and shows its install
command as plain data. Selecting the row copies the command to the clipboard. The row
carries no text about which key does that, since how a row is driven is the root's
concern and shows through the shared shortcut panel, the spoon only supplies the row and
the action. The reason is logged too, so the gap shows both in the UI and in the console.

This replaced the old behaviour where a missing CLI logged once and made the open key do
nothing, which gave the user no on screen signal at all. The trade is that the tool is
never silently dead, opening it always shows something that explains itself. The engine
is only wired when the backend is present, so the unavailable panel makes no provider
calls and cannot stall.

The `available` flag is resolved once at start, not per open, because whether the CLI
exists does not change while Hammerspoon runs. The separate `unavailable` state a live
daemon reports, when the CLI is present but the Mullvad service is not answering, is a
different thing the engine already handles through `status()`, and it is not this panel.
