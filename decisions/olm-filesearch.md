# Olm file search, the index and its memory

Status. Every unscoped search and the recent list are answered by a Swift helper over a file index
it builds itself, so Spotlight and the hidden files index are gone and no listing enters Hammerspoon.

## Now

`sources/index.lua` runs `sources/fileindex.swift`, compiled into the cache on first use. `build`
crawls home and `searchAlso` with fts, never entering a pruned name or a bundle, and writes one
`mtime TAB flags TAB path` line per entry to a tmp file it moves into place. `search` and `recent`
map that file and print at most the cap, then exit. A rebuild runs only when the picker opens on an
index older than `indexMaxAgeSeconds`, in the background, and the engine answers again when it
lands, with Updating index or Building index in the pinned status row meanwhile. The walk still
answers a scoped query live. `util.run` replaces its chunk tables and clears its timers and task
when it finishes or is cancelled. The preview pane's stat, folder scan and text head are the same
helper's `peek`, one run per row the highlight settled on, cancelled by the next, so nothing the
pane shows is read on Hammerspoon's main thread. This agrees with the plugin AGENTS.md.

## Rejected

Keeping the listing in Lua and only clearing it afterwards. Rejected 2026-10-30. The peak comes
from the transit itself, chunks, then one joined string, then the write, so clearing afterwards
cannot lower it and malloc does not return the freed small pages.

Keeping Spotlight and only clearing each query's callback. Rejected 2026-10-30. It ended the leak,
and the footprint still settled near 230 MB after a few searches, since a query gathers its results
inside Hammerspoon and malloc keeps the pages a collect frees.

Running the Spotlight query in a small helper process instead. Rejected 2026-10-30. It would have
kept the footprint down, and it still left the dot folders to a second index with a second tool,
and the top level folders of home unfindable without adding them by hand. One crawl answers both.

Copying tinycast's file search. Rejected 2026-10-30. It is licensed AGPL 3.0. Its ideas were taken
instead, a crawl in a process of its own, an index that is mapped rather than read, and the recent
list answered from the same index, and its FSEvents watcher was left out to keep this small.

A helper that stays running between searches. Rejected 2026-10-30. A search measured about 10 ms
including the process start, so a resident process would save nothing a person can feel and would
put the index pages back into a long lived process.

Reading the text head on the main thread because a task per highlight fire costs too much.
Rejected 2026-11-06, after holding since the pane was written. A helper run is about 7 ms in a
process of its own, and the highlight fires for every key, so the settle timer removes most of them
anyway, while the read it replaced held the keyboard for 1.6 seconds.

The answer on stdout rather than in a file. Rejected 2026-11-06. `hs.task` hands stdout over as text,
and a head need not be valid UTF-8 or be cut on a character boundary.

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

### 2026-10-30 15:43

Spotlight and the hidden index were replaced by one index built by a Swift helper. After the
callback fix, `heap` found no NSMetadataItem held once Lua had collected, and the footprint was
still 231 MB against 45 MB of live allocations. Measured with the helper over 160,317 entries
and a 20,667,418 byte index, a build took 3.6 seconds cold and 1.2 warm at 8 MB resident, and
`search` and `recent` each took about 10 ms including the process start, at 26 to 33 MB resident in
the helper. An `fd` crawl of the same roots for comparison listed 475,402 entries in 1.0 to 1.2
seconds, the difference being bundles, which the helper lists and does not enter. `fzf` and the
hidden unit of `fd` are no longer declared. The recent list now leaves out a date more than a day
ahead rather than sorting it last.

### 2026-10-30 17:10, the preview pane held decoded photos until Lua happened to collect

After a session of searching, Hammerspoon stood at 299 MB, 168 MB of it Image IO. A forced collect
took it to 131 MB, so nothing leaked. The pane's in process generator decodes a raster whole, a
phone photo near 48 MB, and Lua sees the hs.image as a few bytes, so it never hurried to free one.
The pane now collects just after the picker closes when it held a picture, measured at 14 to 24 ms,
and the in process cap went from 20 MB to 1 MB, so a photo goes to Quick Look and comes back the
size of the pane, near 1.4 MB decoded, at the price of a moment on its first preview.

### 2026-11-06 17:59, a preview held the keyboard for 1.6 seconds

Timers wrapped around the steps of a keystroke in the running config caught one stall of 1728 ms
while typing, 1643 ms of it in the presentation's `onHighlight`, reached from `fieldChanged` through
the row supplier and the engine's refresh. Building the launcher's rows took under 1 ms and ranking
them under 5 ms, so neither the catalog nor the shared search was it. `onHighlight` stated the
highlighted row, read its head or listed up to 2000 entries with a stat each, all on the main thread
and on every key, since each list has a new first row. Which row it was was not recorded, so
whether a folder scan, a read or a stat took the time is not known. The fix does not depend on it,
since all three moved. The highlight now arms `preview.settleMs`, and `fileindex peek` does the
reads. Still on the main thread for a pane are the decode of a small image and the load of a cached
render, and every paint, none of them a read of an unknown file.


### 2026-11-07 10:08, the trial of the helper read, on glass

The first hand trial ran on the default chooser without anyone meaning it to. Taking the test lock
for a worktree built that worktree's own swift library in the background, so the provider served
its fallback until a reload, and the only signs were the look of the window and a probe that read
nil. After a reload `serving()` said swift and the trial was repeated. About twenty seconds of
typing, arrows and backspace gave 43 stalls over 25 ms, median 43 ms, largest 169 ms against the
1728 ms before, and the person called it decent. No keystroke's `lua text` passed 28 ms. The other
two stalls past 100 ms, 135 and 150 ms, sat around opening the chooser. The trial was short and the
stalls were not attributed to a step, and the ordinary dropped frames in the list swap, the redraw
and the bottom bar are separate work and were not changed.
