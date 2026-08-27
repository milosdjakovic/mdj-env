# Menu search cache brief, track two of the chooser stage plan, 2026-08-27

Orchestrator decisions from the conversation of 2026-08-27 and PROBE-FINDINGS section
B, menu walks cost 50 to 552 milliseconds with Safari worst at 552 and 1259 leaves,
which is the entire perceived open cost of menu search. Build this only after
menusearch has migrated onto the stage in phase 5, so the correction wires once
against the final shape.

## The mechanism as agreed

Open draws instantly from a per app snapshot on disk and never waits for the walk.
The fresh accessibility read runs in the background on every open. When it lands,
equal means nothing happens at all, no refresh call. Different means a quiet
correction, new items append at the bottom, gone items dim in place through the
enabled false row style, nothing above the highlight ever moves, and the corrected
snapshot persists. The correction defers while the person has moved the highlight
off the first row, applying on the next open instead. A first open with no snapshot
shows the one disabled reading row the launcher scope already shows. A fresh read
that never returns leaves the cached list standing.

## Decisions

1. Snapshots are one json file per bundle id under the cache root through
   lib/storage.cacheDir("menusearch"), regenerable data, holding the flattened
   paths and shortcut glyphs only. Enabled state is never cached, it flips
   constantly, Undo and Paste, and caching it would make every open look changed.
   Unknown until the fresh read says otherwise.

2. No checksum. Both lists are in memory when the read lands, compare them
   directly, the walk that produced them dwarfs the comparison.

3. Recency is per app, keyed by the joined menu path, one lib/recency instance per
   bundle id built lazily, settings key namespaced by bundle id. The fresh read's
   path set feeds prune, so the remembered order repairs itself one open behind at
   no cost. The recency sort applies once at open, never while the list is up.

4. The two read paths in the plugin, the hotkey open and the launcher scope, must
   collapse into one source owning the read, the cache, the recency, and the late
   correction, with the picker and the scope as two consumers. The openId guard
   shape for stale answers already written in scopeMenuRows carries over.

5. Pruning is hygiene, deferred minutes after the first open per Hammerspoon load,
   never at load time. Delete a snapshot whose bundle id no longer resolves to an
   installed app, and one untouched for over sixty days. Never on the open path.

6. Everything stays plugin internal, no new lib unit until a second slow source
   asks, per the repo's own rule against single consumer indirection. No new tools,
   DEPENDENCIES unchanged.

## Acceptance

Hyper e on Safari appears in the reshow cost of the window, tens of milliseconds,
not the walk's half second. A menu item added or removed by an app shows correctly
on the open after next at worst. Running an item touches its recency and reorders
only the next open. The launcher scope path behaves identically to the picker path.
Console clean, reconciler clean.
