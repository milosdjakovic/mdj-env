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
pane shows is read on Hammerspoon's main thread. `search` is compiled together with the shared
search's Swift copy, `app/Sources/OlmSearch/Match.swift`, whose path the root hands the plugin as
the `matchsource` lib, and keeps a name exactly when the list would, behind a byte prefilter that
passes over a name lacking any word, less one letter, in order. Every query is a round trip after
the debounce, the held rows shown only until its answer lands, from the first letter typed, on the
Lua side and in Olm.app. This agrees with the plugin AGENTS.md.

## Rejected

Ranking the held rows again with no round trip when a text only grew, the narrow. Rejected
2026-11-09, after holding since the plugin was written. A longer word can match a name a shorter
one did not under the shared search, one typo from four letters and inside a word from three, so
`heelo` typed slowly held only what `hee` found and never showed `HelloWorld.jsp`, which `heelo`
typed quickly did.

Holding a query under three letters on the recent list. Rejected 2026-11-09, by Milos, who asked
for the search to start on the first letter. It dated from Spotlight answering in process. The
helper answers one letter in about 100 ms in its own process.

Making the narrow as strict as the helper, so a typo finds a file neither way. Rejected
2026-11-09. File search would be the one list where a word one typo away finds nothing, which the
unified search settled against for every list, and the narrow would need a weakened matcher of its
own.

A third copy of the matcher, written into the helper by hand. Rejected 2026-11-09. Lua and Swift
already hold one each, pinned to each other by fixtures, and a third would drift with nothing
watching. Compiling the Swift copy in costs one more argument to swiftc.

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

### 2026-11-07 11:13, the example the searchText comments gave was not what the grammar does

Five comments and docs said `~/dev .js foo` ranks by foo, `engine.lua`, `chooser.lua`,
`manifest.lua`, `lib/chooser/rank.lua` and the hammerspoon `AGENTS.md`. It does not. Types and
sigils are read only in the leading slot, before the scope, as `query.lua`'s own header says, so that
query is the scope `~/` with the text `dev .js foo`. Writing the grammar's fixtures for step 0.3a of
the standalone plan found it. The comments now say `.js ~/dev/ foo`, which does rank by foo, and the
grammar was not changed. Reading a type after the scope too would be a change of grammar, for Milos
to decide, and the fixture case for `~/dev .js foo` pins today's reading until then.

### 2026-11-09 12:40, a fresh search and typing on found different files

Reading the shadow's log for step 1.3e of the standalone plan found eight lines that were not the
same, 49 lines from 2026-11-08 to 2026-11-09. One, ids 900 and 901 with `/nonexistent/report.pdf`,
is taken to be a made up answer written while the shadow was built, from its time and its path,
and not traced to the command. The seven others were one fault. The helper kept a name only when
it held every word whole, while the list ranks with the shared search, which keeps a word one edit
away and a word spelled in pieces. Lua typed on over rows a shorter word brought back, so `repo`
brought `repost.svg` and `report` then kept it, while the app was handed only the settled `report`
and asked afresh, and the helper never answered it. The app's counts were a fresh helper search's
exactly, 155, 10, 8, 135 and 0, and Lua's held rows the shorter words returned. So which files a
query found hung on how it was typed, which the plugin AGENTS.md says must never happen.

The helper now asks the shared search itself, compiled with `Match.swift`. Over the real index of
about 160 thousand entries a fresh `report` gives 156 files, as the narrow did, `scre` 630 against
135, and a search takes 20 to 60 ms in its own process against about 10 ms, one and two letters
about 100 ms. Without the prefilter the same answers took 70 to 90 ms. Three cases in
`olm-index-check` pin it, a word one typo away, a fresh search agreeing with the narrow, and an
accent folded either way. A scoped search still hands its first word to fd as typed, so a typo in
that word finds nothing inside a folder, which is step 1.4e's to answer.

### 2026-11-09 13:20, typing slowly and quickly still found different files

Milos tried the helper fix on the Lua file search. `heelo` typed quickly led with
`HelloWorld.jsp`, typed slowly showed only the Heebo fonts. The fast one was a round trip, and the
slow one the rows `hee` had brought back, ranked again, since the engine asked nothing more when a
text only grew. `hello` is one typo from `heelo` and a three letter word gets no typo, so `hee`
never brought it. The narrow was sound only for a substring, and the earlier entry today fixed the
helper half without seeing that the narrow had the same fault the other way.

So the narrow is gone, in `engine.lua` and in Olm.app's `Source.swift`. A query over the held
population shows the held rows ranked by the new text with the searching row, and the round trip
after the debounce replaces them, so typing quickly still asks once. He also asked for the search
to start on the first letter, so `minChars` is 1 in `config/filesearch.lua`, the engine's default
and the app's, which was step 1.4g of the standalone plan. One letter costs about 100 ms in the
helper and the shared search then ranks the 2000 rows the cap holds.
