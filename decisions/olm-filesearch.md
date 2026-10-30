# Olm file search, the hidden index memory

Status. The hidden files index is written by fd straight to disk through a shell redirect, and a
finished `util.run` keeps no output.

## Now

The rebuild in `sources/hidden.lua` runs `/bin/sh -c "exec fd ... > tmp"` and moves the tmp file
into place when it is non empty. The listing never passes through Hammerspoon. fd exits nonzero
when any folder under home is unreadable, so only the size of the tmp file decides success.
`util.run` replaces its chunk tables and clears its timers and task when it finishes or is
cancelled, and ignores any stream data that arrives after that. A Spotlight query is released
by stopping it and clearing its callback, since a callback left set keeps the query and all its
results alive. This agrees with the plugin AGENTS.md.

## Rejected

Keeping the listing in Lua and only clearing it afterwards. Rejected 2026-10-30. The peak comes
from the transit itself, chunks, then one joined string, then the write, so clearing afterwards
cannot lower it and malloc does not return the freed small pages.

## Log

### 2026-10-30 10:23

Measured during one rebuild of the 35.6 MB index, the Lua heap went from 16 to 88 MB and
Hammerspoon's physical footprint peaked at 478 MB. Idle footprint stayed near 270 to 340 MB
afterwards. A rebuild fires whenever the picker opens with an index older than five minutes.
`util.run` also kept the last output alive, because the drain timer callback stayed registered
with the closure. The rebuild now writes through a shell redirect and `util.run` releases what it
held before calling back.

### 2026-10-30 14:40

Hammerspoon settled near 190 MB after ordinary use, and `heap` showed 92,048 NSMetadataItem
objects held. hs.spotlight stores a query's callback in the LuaSkin registry as a strong
reference, and the callback closes over the query, so `q:stop()` alone never let a query be
collected. Every typed search and every recent files fetch kept its results for the life of the
process. Run live, three queries without clearing the callback took the count from 92,048 to
210,836 after a collect, and three that cleared it with `q:setCallback(nil)` added none.
`sources/spotlight.lua` now stops and clears the callback on delivery and on cancel. A reload
does not free what already leaked, only a restart of Hammerspoon does.
