# Work packet, the Dock row becomes a page with two toggles

Written 2026-08-09 against feat/olm at `34cc514`, on the user's request of this date. The
single Dock row in the launcher becomes a doorway. Stepping into it shows two rows, one
turning Dock hiding on or off, one switching the Dock's show delay between instant and the
macOS default. Choosing either acts in place, the chooser stays open, and the row's wording
flips where it stands.

## The facts from the scout of this date

The launcher hosts another tool's list inside its own chooser through `enterPage(prefix,
title)`, which stores an opaque query prefix in `self._page`, sets the placeholder to the
title, and makes `_commandRows` answer from `_queryRows(self._page .. query)` instead of the
static catalog. `leavePage` is the way back, wired as the atom's back hook and reached by
backspace on an empty field, already listed in the hint panel gated on
`launcherHostingList`. Which rows may host is root policy, a `hostedInPlace` table in the
root's `rowIntercept`, which answers a callable that calls `enterPage` for a special row
named in that table.

A hosted page's rows come from a QueryScope scope, a plain adapter of functions, `rows`,
`run`, and the optional `peek` and `redirect`. Three existing scopes are root policy with no
spoon behind them at all, so a scope needs no chooser and no widget of its own. Crucially,
`QueryScope:rows` calls the scope's own row builder fresh on every call, and every layer
above it does the same, so a page's rows are rebuilt on every keystroke and every refresh
with nothing cached anywhere. A live title inside a page therefore needs no seam and no memo,
it is simply read when the row is built, exactly as the BrowserTabs settings rows read the
enabled state each time.

The atom already has the act and stay open path. When the launcher's `intercept` hook answers
true for a row, `Chooser:_intercept` calls `self:refresh(true)`, which rebuilds the list from
the row supplier for the current query and leaves the window up. What is missing is a verb, a
scope today can `run` after the chooser closes, `peek`, or `redirect` a query, but there is no
way for a scope row to say it acted in place. The root's `rowIntercept` reaches
`QueryScope:redirectFor(item)` for a scope row and `enterPage` for a hosted special row, and
nothing else.

The Dock's hiding boolean can be pushed to the running Dock through System Events, which is
what the existing plugin does and why its change is felt immediately. The delay cannot.
Asking System Events for the dock preferences properties on this machine returns autohide and
a number of other properties and no delay of any kind, proven rather than assumed, so nothing
exists to push. On this machine `autohide-delay` reads 0, and `autohide-time-modifier` is
absent rather than zero, which are different states. Line numbers drift, rescan everything.

## Decisions already made, build to these

One, the doorway. `keys.dockAutoHide.description` becomes the plain noun `Dock`, matching how
every other hosted tool's outer row reads a name rather than a verb, and the row joins the
root's `hostedInPlace` table so choosing it steps into the page instead of acting.

Two, the title provider seam comes back out. It was added yesterday for this row, and with
the row becoming a doorway it has no consumer left. Remove `actions.titles` from the
launcher's configure, remove the `_rowTitle` method and the `_titleCache` and
`_titleCacheOpenId` fields, restore the two list building sites to reading `row.title`
directly, and remove the wiring in the root and the paragraph in the launcher's module
documentation. An indirection with no caller is a cost, and the mechanism is recoverable from
history if a future row needs it. Every other row must be byte for byte unchanged in
behaviour afterwards.

Three, the new verb, and it stays generic. QueryScope gains one optional verb beside
`redirect`, letting a scope say that a row acts in place. Mirror `redirect` exactly in shape,
a scope may supply the function, QueryScope exposes a lookup answering a callable or nil for
a given item, and the root's `rowIntercept` asks for it in the scope branch before it asks
about redirects. The callable performs the action and returns, the atom refreshes, the page
rebuilds its rows, and the wording flips because it was recomputed rather than patched.
QueryScope names no tool, and the launcher needs no change at all for this.

Four, the plugin grows what the page needs and nothing more. It keeps reading and writing the
hiding boolean as it does today, unchanged. It gains reading whether the show delay is
currently instant, meaning the `autohide-delay` key is present and zero, and setting it either
way. Making it instant writes the key as zero. Restoring the default deletes the key rather
than writing a number, because the original value is unknowable on a machine where it has
already been overridden and an absent key is the genuine default state. The delay governs
`autohide-delay` only. The separate `autohide-time-modifier` animation key is absent on this
machine, the user has never set it, and this feature does not touch it.

Five, applying the delay. A delay change is invisible until the Dock re reads its preferences,
so the plugin restarts the Dock after a delay change, and only after a delay change. Hiding
keeps its System Events push and never restarts anything. The restart tool is a dependency
like any other, declared beside the code and resolved through the shared scope rather than
named as a bare command, and the plugin's own documentation records why the two toggles apply
themselves so differently, which is the empirical System Events finding above.

Six, the two rows and their wording. The plugin owns every string. The hiding row reads Turn
Dock Hiding On when hiding is off and Turn Dock Hiding Off when it is on, the wording that
exists today. The delay row reads Make the Dock Instant when the delay is not instant and
Restore the Default Dock Delay when it is, and its subtitle says plainly that the Dock
restarts, since a visible relaunch should never be a surprise. Both subtitles follow the house
voice of the other rows. The row order is hiding first, delay second, as the user asked.

Seven, documentation. The plugin's `CLAUDE.md` gains the page, the two toggles, the delay
default reasoning, and the restart, and drops the claim that the launcher row itself reads the
action, which stops being true for the doorway. QueryScope's own documentation gains the new
verb beside its account of redirect. The launcher's documentation loses the title provider
paragraph. Wherever the hammerspoon module documentation describes this tool, it gains the
page.

Eight, nothing else. No keyboard binding anywhere, no change to any other scope or row, and no
new chooser for the plugin.

## Gate

`luac -p` on every touched lua file. `test/units.sh` passes. `src/check-dependencies.sh`
passes with no new warnings and reconciles the new declaration. `test/inventory.sh` three
times, each passing. After the land and the scheduled reload the console is clean and the
resolver reports all present. The live proof is the user opening the launcher, choosing Dock,
seeing two rows, running each, and watching the wording flip without the chooser closing.

## Deliverable

Commits on the branch in small steps, the packet, the seam removal, the QueryScope verb, the
plugin, the wiring, then the docs. A report with the merge hash, each gate's numbers, the
resolver line, the exact shape of the new verb, what the empirical delay check showed, and any
decision that did not survive contact with the code, flagged loudly.
