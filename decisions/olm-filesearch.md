# Olm file search, the hidden index memory

Status. The hidden files index is written by fd straight to disk through a shell redirect, and a
finished `util.run` keeps no output.

## Now

The rebuild in `sources/hidden.lua` runs `/bin/sh -c "exec fd ... > tmp"` and moves the tmp file
into place when it is non empty. The listing never passes through Hammerspoon. fd exits nonzero
when any folder under home is unreadable, so only the size of the tmp file decides success.
`util.run` replaces its chunk tables and clears its timers and task when it finishes or is
cancelled, and ignores any stream data that arrives after that. This agrees with the plugin
AGENTS.md.

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
