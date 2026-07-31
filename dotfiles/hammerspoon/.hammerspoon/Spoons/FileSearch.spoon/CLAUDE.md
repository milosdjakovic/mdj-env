# FileSearch.spoon

Why this spoon is shaped the way it is. The code sits beside this file, so nothing here
narrates it. What is recorded is the decisions, the measurements behind them, and the
several things that were tried and turned out to be wrong.

## The one idea the performance rests on

One round trip per search, not one per keystroke. Typing eleven characters fires one
query, because once results are held, a longer text over the same population can only
match a subset of them, so it is filtered locally with no dispatch. Everything else here
is ordinary.

This is why there is no result cache and why one was deliberately refused. A cache is
wrong at the exact moment this tool is used, right after something was downloaded or
built, while narrowing is always as live as the results it narrows. The only cache in the
spoon is the hidden index, and that exists because there is no index behind it at all
rather than as an optimisation, which is the distinction that decides whether a cache is
worth its staleness.

The narrowing guard has four conditions and all four are load bearing. The population must
be identical, the text must have grown rather than changed, the held set must not have been
truncated by its cap, and the held set must be a real search result. The first two live in
`query.lua` where they can be tested, the last two only the engine knows. Retaining well
above what is displayed is what keeps the truncation condition true in practice.

The fourth condition is the one that is easy to miss, and it was missed. The picker opens
showing recent files, whose parse shape is the empty query, and any typed text grows from
the empty string over an identical population, so the first three conditions are all
satisfied by the recent list. The result was that every search silently answered from the
forty most recently modified files and no search ever ran. It looked like Spotlight
returning nothing, and the headless run had found the same file moments earlier, which is
what made it worth chasing. So `_narrowable` is set only by `_publish`, and every other
path that fills the retained set clears it. There are two such paths and both had to be
found by hand, the recent branch in `rowsFor` and the recents callback itself.

## Three sources, and why the order is the design

Order is the whole conflict resolution. Each source says whether it supports a query shape
and the first that says yes owns it, so `init.lua` is the only file that can decide who
wins.

Walk is first, on two independent measurements rather than a preference. Walking Downloads
took **13ms** where the index takes about **105ms**, and the walk also sees dotfiles the
index does not hold at all. So a scoped query going anywhere else would be both slower and
less complete.

Hidden is second and claims only what Spotlight physically cannot answer, an unscoped
search for paths with a dot segment. First would steal every scoped hidden query from the
walk and answer it from an index that can be minutes stale when the live filesystem was
right there.

Spotlight is last because it is the only source with no precondition. Anything after it
would never be reached.

## Two searches run at once, and one cancel slot could not tell them apart

This is the fault that made the picker useless, and the shape of it is worth more than the fix.
The reported symptom was that opening the picker showed the recent files row saying it was
gathering, with nothing under it, every single time.

There are two independent searches in flight here, a typed query and the background recent files
fetch, and both go through the Spotlight source because that is the only source with no
precondition. Each source kept ONE in flight slot and exposed a module level cancel, so starting
either search abandoned the other. Cancelling is silent by design, an abandoned search must never
paint rows the user has moved past, so nothing called back and nothing complained.

That silence is what turned a race into a permanent break. The fetch was guarded by a boolean set
before it started and cleared only by its callback, so an abandoned fetch left the flag set with
nothing behind it, every later open returned from that guard immediately, and the recent list
stayed empty for the life of the process. A reload was the only cure. Two everyday actions
triggered it, typing within the fetch window and closing the picker within the fetch window, since
closing cancels what is in flight.

So cancelling is per search rather than per source. A search hands back a handle carrying its own
cancel, the engine holds one per channel, and neither can reach the other. Two things follow that
are easy to undo by accident. The handle IS the in flight flag, because a separate boolean saying
the same thing is what wedged, and a state that can only be set by starting and cleared by
finishing will outlive any path that does neither. And closing the picker cancels the typed search
only, deliberately leaving the fetch to land, since it answers what you touched lately rather than
what you asked for, so nothing a query does can invalidate it and letting it finish is what makes
the next open instant.

The general lesson, since this is the second bug in this spoon of exactly this kind after the
narrowing guard, is that a flag meaning something is happening must be owned by the thing that is
happening. Here that is the handle, so there is nothing left to get out of step.

## What you use is the fourth ordering, and it is applied two different ways

Every other ordering here is a file date or a text score, so the list you land on before typing
was really answering which files CHANGED rather than which files you reach for. Those are
different questions, and on this machine the date ordered top of the list was a generated
manifest, a spec file and source files touched by a build, not one of which anyone chose.

macOS looks like it already answers this and does not. `kMDItemLastUsedDate` is its own record of
when a file was last opened by any application, which would beat anything we can record because it
sees every app. Measured over the same scopes and window it returned **16** files against **342**
for the modification date, far too sparse to rank anything, so the store has to be ours.

The mechanism is deliberately dull, one number per path, decayed by a half life and incremented on
use, so a file opened ten times last year sinks below one opened twice this week with no list of
timestamps to keep. Every action counts the same, since weighting opening above copying a path
would be a claim about intent that cannot be backed, and copying a path is often the strongest
signal there is.

**The two applications are the part worth understanding, and they are not the same.** With a query
typed, the score only REORDERS, and its weight is smaller than the gaps in the search ranking, so
it separates files that matched the query equally well and can never lift one that matched it
worse. Without a query it CHOOSES rows outright, and it has to, because that list is a date bound
capped at a few dozen rows, so a file you open daily but have not modified in a month is not in
the candidate set at all and no amount of sorting could surface it. That is the one place in the
spoon where a row appears that no source returned.

It is bounded there on purpose, a few rows and then the dates. Letting it fill the page would make
the default view the same handful of files forever, which is the opposite of what landing on it is
for, since right after a download or a build is exactly when this gets opened and a file that did
not exist a minute ago has no history to rank. The same argument the header makes for refusing a
result cache protects the date half of that list.

Two smaller decisions. A floated path the date list already returned is MOVED rather than rebuilt,
so it keeps the modification date Spotlight gave for free, and only a genuinely absent row is built
and stat'd, which is why the floated rows read the same as their neighbours instead of being the
ones with no age beside them. And dead paths are pruned at read time among only the handful about
to be shown, so a deleted file cannot squat at the top and the long tail nobody is looking at
costs nothing.

The store sits in `hs.settings` rather than anywhere under `~/.hammerspoon`, and that is not a
preference. It is written on every action, and that tree is watched, so a store living in it would
reload the whole config every time you opened a file.

**A row reports both ages, and it names them.** The first report on the finished feature was that a
folder floated to the top by a path copied a second earlier read `4d ago` underneath, which is the
folder's own date and was read as something the user did four days ago. A bare age invites that,
because the one thing on a row that is about the person is indistinguishable from the one thing
about the file. So the line labels them, `used 34m ago` for the last time you reached for it and
`changed 4d ago` for the file system, with the use first, since on the list you land on before
typing it is the field explaining why the row is there at all. One word covers both files and
folders on the second one, because a folder's date moves when something inside it is added, removed
or renamed, which is a change and not an edit.

The surface asks for that as the row is drawn, through `usedAt` on the same injected seam as
`onUse`, so the write and the read of a use sit together and neither one names the store. Asking at
draw time rather than stamping the row upstream is the point. Rows are retained and redrawn for the
local narrow between round trips, so a stamp would still be reporting the previous answer on the
one row that was just acted on, which is exactly the row being asked about.

Worth knowing when reading a row, an age is not on every row and that is a cost decision one layer
down. The modification date is read from Spotlight only for the recent list, because it is a per
row attribute read and the note in the harvest measures what asking for it costs, and no source
reads a size at all. So the only rows carrying a size are the ones `_float` stats itself, and a
browse or a search shows the directory alone.

## Case is folded in four places and three of them were wrong

The first hands-on report was that typing `Downloads` matched nothing while `Download` matched.
That reads like a broken search and was a broken FILTER, which is why it is worth recording.

The shared words matcher folds only the query and compares the haystack verbatim, deliberately,
because it is built for long clipboard bodies that must not be refolded per keystroke. The engine
was handing it a raw path. So a query with a capital letter narrowed to nothing, and typing the
same text quickly worked because the debounce meant one dispatch and no narrow at all, where
`LIKE[cd]` had folded case for us. That is exactly the pattern to distrust, the same text
behaving differently depending on how fast it was typed means the narrow and the search disagree.
The fold now happens once in `util.row`, half a millisecond for two thousand rows.

Both tools are SMART CASE, which is the right default for a shell and the wrong one for a
picker. One capital letter anywhere silently made a scoped or hidden search case sensitive, so
the walker takes `--ignore-case` and the filter takes `-i` explicitly.

## The scope roots were invisible to the source that searches them

Found while checking the case fix. Every top level folder in home is a Spotlight search scope, so
a query searches INSIDE each one and the folders themselves are never results. Typing `Downloads`
found everything called downloads except `~/Downloads`, and those are the shortest, most obvious
names anyone types first.

They are about ten entries, so `sources/spotlight.lua` matches them in plain Lua and adds them to
what the index returned. It lives there rather than in the engine for the same reason the hidden
source exists at all, a blind spot is owned by the source that has it. The engine knows nothing
about scopes and must not start.

## Where an unscoped search starts, half derived and half declared

The starting points are the top level of home minus the pruned names, and that derivation is not
laziness. Spotlight cannot be told to leave a subtree out, so naming the siblings of `~/Library` is
the only way to exclude it, and the list has to keep up as folders come and go. Anyone tempted to
collapse it to one scope should know that, since it looks like a pointless fan of sixteen paths.

It could only be that, which meant nothing outside home was reachable. Applications live in
`/Applications`, so they were unfindable and the `app` type token was decoration. `searchAlso` in
config names extra starting points and is ADDED to the derived list rather than replacing it, so
the adaptive half keeps working and nothing has to be maintained by hand. An entry may be absolute,
relative to home, or written with a tilde, and one that is not a directory here is skipped, so one
list travels between machines. The folders themselves become findable for free, since the source
already matches its own scope names as results.

**Breadth is close to free, and that is worth knowing before tuning it.** Three terms measured
against the derived list, the whole of home and the whole volume all answered in the same 120 to
175 millisecond band once the index was warm, and reading a page of two hundred rows cost 3.5ms
whether the result held 3,781 rows or 52,246. Spotlight is reading an index, not walking a tree.
The first query on a fresh term costs several times any of that, which is the index warming and is
the number that misleads, since a first measurement blamed the scope list for a cost that simply
fell on whichever list ran first. So the reason to keep the declared list short is RELEVANCE.
Adding `/` would cost nothing measurable and would still be a bad trade.

A scoped search is the opposite case. That one goes to the walk source and really does traverse,
measured at 13ms on a small tree against 353ms on one holding 196 thousand entries, so there
naming a narrower folder genuinely is faster.

## The recent list was the one result set the noise filter never saw

Everything else reaches the noise filter through `_publish`. The recent list fills itself in
straight from its own fetch, so it never did, and the view everyone lands on could open on a
`__pycache__` directory with two `.pyc` files under it, all three named in the prune list that
exists to remove exactly those. It is filtered before it is merged now, and the order is the
decision worth keeping. Filtering first and floating second lets your own history override the
filter, so a pruned path you deliberately used still comes back by name while the date half of the
list stays clean.

The same fix exposed a second half of it. Matching only an inner path segment left a pruned
DIRECTORY standing while its contents were removed from under it, which reads as a filter that
half works. A name in that list is a name nobody searches for in either position, so the directory
itself counts too.

## A bare type token is a third query shape, and treating it as the second broke it

`.py` found nothing, reliably. It parses as kind recent, because nothing was typed, so the predicate
ANDed the type filter with the recent date bound and asked for python files modified in the last few
days. Worse, the date bound made it slower rather than cheaper, **4839ms to return zero** against
**475ms** for the same name pattern with no bound at all. A date bound sitting next to a name pattern
costs on both counts, so the fix is simply not to add one when a type filter is already the bound.

Ordering it then needs two separate mechanisms and both are load bearing. The sort descriptor decides
which rows the query holds at the top, and therefore which ones a capped harvest reads at all. A Lua
sort decides the order of what came back. They come apart the moment a gather stops early, because a
query that has not finished gathering has not sorted anything.

That is also why the early stop is now off for anything ordered by date. Waiting is affordable
because the gather is the cheap half, sixty thousand results in about **60ms** and the entire js
extension, 204 thousand files, in **385**, while reading rows out is the expensive half and only a
page is ever read. A cold index is the exception, where the same gather measured **6.3 seconds**, and
the timeout covers it.

## Filtering noise has to happen while harvesting, not after

The engine can only filter what a source handed it, so a source that returns a capped sample first
has the filter throw most of the sample away. That is why `.js` came back with **eleven** rows.

It cannot be fixed by reading deeper either. Only **0.12 percent** of the 204,496 js files here live
outside a pruned directory, so filling two hundred rows means reading **161,334** of them and five
seconds. So the scan is bounded, and because the list is date sorted the budget is spent on the
newest candidates, which makes a very common extension return FEWER rows rather than take longer.
That is the right way round, and the eleven rows it returns are the newest javascript actually
written here rather than eleven arbitrary ones. `py` fills a page by row 204 and `png` by row 799,
so neither comes near the bound.

Pushing the prune into the predicate was tried first and does **nothing**. Excluding
`*/node_modules/*` through `kMDItemPath` left the count at 204,496 unchanged, three different ways,
so that attribute is not queryable like that whatever the syntax suggests.

Cost of the whole shape, measured as the largest gap between fires of a 20ms repeating timer, which
is the only metric that catches a stall wherever it lands. A bare type token blocks **114 to 145ms**
once per dispatch, an ordinary search **26ms**, and the recent list does not register above the
idle floor. Use that method rather than timing a single delayed callback, which misses any block
that does not overlap the moment the callback is due, and gave three misleading readings here.

## Two files dated 2050

The recent list was led, and later tailed, by MIDI files carrying a modification date of
`2524579200`. A single file with corrupt metadata would otherwise squat at the top of the default
view permanently, so a date beyond tomorrow is treated as unknown and sorts last. They still occupy
a slot, since a 2050 date does satisfy "modified since last week" and excluding them would mean a
second rule for one fact.

Worth knowing when verifying an ordering, because a checker that does not apply the same rule reports
the deliberate demotion as a sorting bug, which is exactly what happened here.

## What Spotlight cannot see, measured

It holds **no path containing a dot segment**. Not the dot entry and not anything beneath
it, so all 599 files in `~/.config` come back as zero results. This is not a filter that
can be switched off, the data is absent, which is the entire reason a third source exists.
Anyone tempted to collapse the hidden source into a Spotlight flag should re run that
query first.

The blind spot is about **245 thousand paths and 33MB**, walked in roughly a second. Too
slow per keystroke and too much to hold in Lua, so it is written to a file and filtered by
a tool.

## Five query facts, each one learned the hard way

Every one of these cost a wrong first attempt, so they are recorded rather than left to be
rediscovered.

An attribute is cheap to read only if the query was told about it. This was the second hands-on
report, severe lag part way through a word, and it was one line. An undeclared
`kMDItemContentType` is fetched per row on demand at **0.284ms**, so harvesting two thousand rows
blocked the main thread for **567ms**. Named through `valueListAttributes` the same read costs
**0.008ms**. Measured by alternating the declaration over six fresh terms, since running the same
term twice measures a warm index rather than the change, mean harvest **300ms against 21** with
the gather unchanged at 128 against 110. So nothing is traded, the cost is simply removed, and
the live figure went from about 465ms of blocked main thread to **1ms**. `kMDItemPath` is already
cheap undeclared at 0.011 and the modification date needs no declaration either, because the
recent query already names it as its sort key.

The mdfind wildcard form is rejected. `kMDItemFSName == "*x*"c` works on the command line
and `hs.spotlight` refuses it outright as an unparseable format string. The working form is
the proper NSPredicate one, `LIKE[cd]` with explicit wildcards.

`$time.now` is rejected too. mdfind accepts `$time.now(-259200)` and `hs.spotlight` fails
to parse the selector. A date bound has to be `CAST(n, "NSDate")`, and an NSDate counts
from 2001-01-01, so the reference offset must be subtracted or the bound lands thirty one
years early and matches everything.

`inProgress` fires far too rarely to bound a broad gather at the default rate. A probe
asking to stop at two hundred results was first notified at three thousand eight hundred,
by which time a full second had passed. `updateInterval` is what makes the early stop work,
which is why it is set low deliberately.

The search scope is not the home directory. Every broad probe came back dominated by
`~/Library`, thousands of logs and caches that cost gather time and are then discarded. So
the scope is the top level of home minus the pruned names, and the noise never enters the
gather.

## Why fzf, the one place a second tool earns its keep

Over the full hidden index, ripgrep is faster, **0 to 20ms** against **20 to 130ms**, and
it was still the wrong choice. It cannot rank. A one word query like `nvim` matches
**42,559** of these paths, so capping ripgrep's output hands back two hundred arbitrary
rows from wherever the walk began. fzf ranks first, so a cap after it gives the two hundred
best.

It also matches a subsequence, so a fumbled `hmrspn` finds hammerspoon paths in 60ms where
a substring tool finds nothing. Since narrowing means one invocation per search rather than
per keystroke, the worst case is paid once.

nucleo is measurably faster still and was rejected because it is a Rust library, so it
would add a cargo toolchain to this repository for a tenth of a second on one code path.
Television was rejected for a different reason, it is a terminal application rather than a
component, so adopting it means giving up the shared chooser surface entirely.

## The one shell in the spoon

fzf reads candidates from standard input and takes no file argument, and pushing 33MB
through a task's stdin from Lua on every keystroke would be far worse than a redirect. So
`sources/hidden.lua` goes through `/bin/sh` to get `fzf --filter=... < index | head`, which
also bounds the output at the pipe. The query is quoted through `util.shellQuote` because it
is arbitrary typed text. Every other shellout here runs a binary with an argument list where
no quoting question arises, and the browse deliberately calls `/bin/ls` by absolute path
because `ls` is commonly shadowed in a user's shell.

## Every empty state is a real row

An icon, a headline naming what the state is, and a detail saying what to do about it. So the hidden
prompt reads "Search hidden files" over "type something to search hidden files" rather than putting
the second line on its own with nothing beside it. The icon is an emoji rendered through an
offscreen canvas and cached by the string, which is how the launcher, the clipboard, Processes and
three others do it, since this Hammerspoon has no SF Symbol api. Cached permanently rather than
through the injected memo, because a glyph cannot go stale the way a file type icon can when its
default application changes.

The table is keyed on the status text the engine and the sources produce, and that seam is worth
being honest about. Those strings are free text rather than identifiers, so a producer rewording one
drops it out of the table. That is exactly why the fallback carries the raw status as its detail. An
unmapped state loses its tailored headline and stays perfectly readable, which is a fair price for
not making every source declare a presentation key it has no interest in.

One wording moved DOWN a layer rather than up. An empty directory used to report as no matches
found, which is a different thing and reads as a failed search. Only the walk source knows it listed
a directory cleanly and got nothing, so it says so, and the surface has a row for it.

Nothing here names a key, including the details. A rebind is a config edit and no wording in the
spoon may be able to disagree with it, so "there is nothing in this one" replaced a first draft that
helpfully told you which key goes back up.

## Walking the tree is two verbs and no history

Down is `browseInto` and up is `upQuery`, and both answer with a QUERY STRING rather than
performing a move. So there is no history stack, no notion of where the picker has been, and
nothing that can disagree with what is in the field. Going anywhere is typing something the user
could have typed themselves, which is also why browsing into a search result needed no new
concept.

The back row while browsing is an ORDINARY DIRECTORY ROW for the parent, titled with two dots, not
a special kind of entry. That is what keeps it from needing special cases, reveal and copy path and
open folder all mean the obvious thing on it because it really is that directory, and browsing into
it really does go back.

It carries one flag, read by `insertSelected`, and that one has to be there. Choosing a row goes
through the atom's completion, which tears the picker down immediately after and cannot be vetoed
by a consumer, so going up through the completion path would close the picker on the way. Checking
before delegating is what lets the primary key on the back row move up and leave the picker open.

## Two mode split on a scope, and why browse is one level

With no text a scope is a browse, so it lists one level sorted newest first. Type anything
and it becomes recursive. One level is not a limitation, it is what a file manager shows,
and it is the only form that can be ordered by date with no recursion and no stat calls,
because `ls` does the sort itself in C. Ordering by date any other way means stat'ing every
entry.

## Why the recent window is seven days, and why it used to be three

It was three, on a measurement of 3,136 files in 207ms taken BEFORE the search scopes were narrowed
to exclude `~/Library`. Almost all of those were logs and caches, so once the noise was gone the
same three days matched **22 real files** and the list was nearly empty while looking perfectly
healthy. That is the hazard in tuning a number against a measurement, the measurement can go stale
when something else changes and nothing points at it.

Seven days matches about **38 thousand** and gathers in under a tenth of a second, because only a
page is read out of the result set. So this is no longer the setting that can make opening the picker
slow, and it should be wide enough to be useful rather than as narrow as possible.

Counts per window are lumpy rather than smooth, since one checkout writes tens of thousands of files
at once. Here six days matched 494 and seven matched 38,172. Nothing depends on which side of such a
step the window lands, which is the point of not tuning to it.

## Why the grammar is pure, and where it is not

`query.lua` touches no filesystem, no Hammerspoon api and no clock, so the trickiest part
of the spoon is exercised by a standalone `lua` with 66 assertions and no running
Hammerspoon. That is the whole reason it is a separate file.

Scope resolution is deliberately outside it, in the engine, because it needs the filesystem.
It is also deliberately synchronous and shells out to nothing. A frecency tool would be the
obvious fourth resolution step and would make an unaliased project directory resolve, but it
is a shellout, and an asynchronous scope resolution means two hops before any row appears.
That is a fair trade to revisit, not a gap to fix carelessly.

## Registry membership decides a dot token, not spacing

`.js` and `.jshintrc` both have a dot attached and both are things people type. Rather than
a rule about whether a token looks finished, the remainder is looked up in the type
registry. Known means a type filter, unknown means a hidden filename fragment. Both readings
are what you would want and neither needs explaining.

The cost is that an extension absent from the registry does not filter strictly, and that is
survivable rather than a defect, because an extension is part of a filename so it still
matches as text. The registry therefore does not need to be exhaustive, which is the answer
to the maintenance worry it otherwise invites.

A bare word is never a type. That is what makes `js hello there` find a file actually called
that and `hi everyone` an ordinary search. Two earlier designs were built and thrown away
here, a compound predicate expressing both readings at once and a retry when the type
reading came back thin. Making the dot mandatory removed both, along with a quoting escape,
which is roughly a hundred lines and three rules a user would have had to remember.

## The bang sigil has exactly one meaning

Do not filter out noisy paths. It reads the same whichever source answered, and it is
implemented once in the engine plus one extra flag on the walk so the tree is not pruned
either.

It applies to unscoped results only, and that exception matters. Naming a directory is an
explicit statement about where to look, so scoping into `node_modules/` must not then have
every row filtered out for being inside node_modules.

## Icons are cheap, which was a surprise

A lookup costs **0.08ms**, two hundred uncached rows **6.6ms**, and the same two hundred
through the injected memo **0.2ms**. `iconForFile` on real paths measured the same as
`iconForFileType`. So the row build was never the jank risk it was assumed to be, and the
memo buys smooth repaints while typing rather than rescuing a broken frame.

Nothing is written to disk and there is deliberately no directory to configure. These are in
memory handles NSWorkspace already caches, which is why a lookup is that fast. A folder of
our own PNGs would be slower to read than asking again and would turn a changed default
application into staleness that outlives a reload. Because the whole table rebuilds in
2.3ms, it is simply dropped when the chooser closes, so a changed default app is correct on
the next open with no invalidation logic at all.

## The pane answers the question the row cannot afford to

A row is one line, and one line cannot say whether this is the file you had in mind. The
subtitle already carries the directory and the two labelled ages, which is as far as a line
honestly goes, so the pane beside the list shows what is actually inside.

It also owns the facts a list cannot pay for. No source reads a size and only the recent list
reads a date, because either one costs a call per row and a page is two hundred rows. The
pane describes exactly one row, so it stats that row and reports the size, both dates and the
kind for the cost of a single call. That is why the row subtitle deliberately has no size
field. It used to have one, filled by nothing, which is the defect this replaced.

The header draws for every row and is not part of the chain below, because a name, a location
and a handful of dates are true of everything, and a pane that sometimes had no header would
be answering a different question depending on which row you were on. Both ages stay labelled
there for the same reason they are labelled on the row, and the last used line is drawn in the
accent tone because it is the one fact on the pane that is about you rather than about the
file.

## What the body shows is a Chain of Responsibility, and declining is half of it

`BODIES` in `preview.lua` is an ordered list of describers, each offered the row and free to
answer or to pass. The first answer wins and nothing else is consulted. Adding a kind of file
the pane can show is a new describer plus one line in that list.

Declining is a real part of the mechanism rather than an error path, and three cases need it.
A text file that cannot be opened, an image type with no generator behind it because
`qlmanage` is missing, and a binary that no describer claims at all. Each one falls through to
the row being described by its header alone, which reads as a file the pane has nothing to add
about rather than as a heading over an empty box.

The order is not a preference. A folder is claimed first, since a directory can never be
anything else. A picture is claimed second and gated on the EXTENSION rather than on sniffed
content, which is what makes an svg draw as a picture rather than having its markup printed at
you. Text is claimed last and gated on looking rather than on a table, a NUL byte in the first
block being what says a file is not text, so a source file, a json, a markdown and a config
with no extension at all are all covered without any of them being listed anywhere.

The text head is read synchronously with `io.open`, bounded by the configured cap. That is a
deliberate exception to this spoon's rule that nothing blocks, and it is affordable because
the read is a few tens of kilobytes off a local disk and going asynchronous would mean a task
per highlight fire. The case it would cost is a file on a slow network mount.

## Pictures are a second chain, and only one member of it caches

`thumbs.lua` is the same shape as the clipboard's generator chain, and the contract is
deliberately AN IMAGE RATHER THAN A FILE. That is what keeps the pane ignorant of whether
anything was written to disk, so the cache is a private detail of the one generator that needs
it instead of a concept the whole feature carries.

Two generators. A raster or an icon set is decoded in process, immediately, so the pane draws
it on the first paint with no repaint at all, guarded by a size cap because a decode happens
on the main thread and Hammerspoon owns every leader key in this config. Everything else goes
to Quick Look, which is a process launch and a few hundred milliseconds, and which is also the
reason a file type this config has never heard of still draws correctly as long as something
on the machine knows how.

Only the Quick Look generator caches, and it has to. Writing a raster out would cost more than
decoding it again. A render is keyed on what the file WAS, its size and its modification time,
so an edited file renders again and an unchanged one is free on every later open, and the
directory is bounded by a file count swept once per session rather than checked per write.
`qlmanage` writes into a scratch directory per render rather than to a named output file,
because it appends `.png` to the source name rather than substituting it, so the result is
found rather than guessed at.

A render is asynchronous, which the pane has to survive. The generation counter is what makes
a late answer honest. Moving the highlight bumps it, so a render finishing after you have left
the row is kept for next time and paints nothing.

## The pane is one canvas docked into a rect it did not choose

The same arrangement the clipboard preview and the Local Servers pane use. It draws through
the shared surface so the three read as one component, and it is not a `CanvasPanel` instance
because that atom computes its own placement from an anchor while this has to land exactly on
the companion rect the Chooser atom already reserved and reported. That rect is also the one
the click watcher counts as part of the picker, so a pane drawn a few points outside it would
turn a click on itself into a dismissal.

`onPositioned` is composed rather than replaced, docking the pane and then handing the
shortcut panel an anchor spanning both panes, so the hints sit under the pair. The pane is
destroyed rather than hidden on the atom's one idempotent teardown, so nothing outlives a
dismissal.

Two things must be re rendered explicitly. The atom compares the highlighted ROW NUMBER, so a
result set landing under a stationary highlight fires nothing, which is why `refresh` re
renders. And the atom seeds the highlight before it positions anything, so the first
`onHighlight` lands with nowhere to draw, which is why `onPositioned` renders once it has
docked.

The same reasoning found a defect one layer down, in the atom rather than here. `Chooser:refresh`
rebuilt the list without clearing `lastRow`, so browsing into a folder while the FIRST row was
highlighted left the pane describing the old first row, since the number had not moved. The
query callback already cleared it for typing, with a comment saying exactly why, so refresh was
simply missing the same line. Fixing it there rather than here means every companion pane gets
it, and the explicit re render above stays only because it repaints at once rather than on the
next poll tick.

## hs.fs.dir raises, it does not return nil

Worth its own note, because the guard everyone writes for it does nothing. `hs.fs.dir` on a
directory it cannot open RAISES, so `local iter = hs.fs.dir(path); if not iter then return end`
never runs its second half, and the iterator can raise part way through a walk as well. The
folder describer runs inside the highlight poll, where an unhandled error is exactly that, and a
row naming a folder that no longer exists is ordinary rather than unlikely, since the index goes
stale and the recent list outlives what it lists. So every directory read here is wrapped, and
failing to read one means declining, which leaves the row described by its header.

Checked against the cases that produce it, a folder that does not exist, a folder macOS
protects, a file that does not exist, a file macOS protects, an empty folder, and a binary
claimed by nothing. All six draw a header and no body rather than raising.

## Scrolling the pane belongs to the atom, not to the pane

A canvas has no scroll callback, so a trackpad over a pane could not be noticed at all. The
watcher for it lives in the Chooser atom beside the click watcher that already owns these
rects, gated on a consumer passing `onScroll`, and it answers only for the companion rect so a
scroll over the list still reaches the list. The atom normalises both the unit, since a
trackpad reports pixels and a wheel reports notches, and the direction, since the event
measures fingers while a pane measures content. One negation there rather than one per
consumer, all of which would have to agree.

That is why this arrived as a fix to the clipboard as much as a feature here. The clipboard
pane could only be moved by its two keys before, and it now takes the same gesture through the
same seam. Both surfaces route their keys through their own one scroll verb, which is also
what the atom calls, so there is one notion of where a pane is scrolled to.

The offset is clamped in paint rather than where it is changed, which is what lets a key
press, a trackpad gesture and a rebuild at a new height all be written without any of them
knowing how tall the content turned out. It resets whenever the row changes, since an offset
carried over would open the next file part way down for no reason a reader can see.

## What it deliberately does not do

No content search. Spotlight's text index answers it in about 135ms and ripgrep is the
gitignore aware fallback, so the shape is known, it is simply not built.

No delete or trash action. A destructive key in a fast picker is a bad trade without a
confirm step, and this has no confirm screen.

## What it degrades to

Every tool is optional. Without the walker, scoped search stops and Spotlight still answers
everything unscoped. Without fzf, unscoped hidden search stops and a scoped hidden search
still works through the walk. Each source reports itself unavailable with one console line
naming why, and the key stays worth pressing in every case.

Without `qlmanage` the pane loses one describer. A raster still draws through the in process
generator, a text file still shows its head, a folder still lists itself, and every other row
is described by its header exactly as before. Only the pdf, the video and the office document
lose their picture, and the describer declines rather than promising one.

Without the shared canvas surface injected, there is no pane at all. The atom reserves no room
beside the list, no highlight poll runs, and the picker is exactly what it was before the pane
existed. That is one line in the main root, which is what makes the whole feature removable.

## What would break if the shape changed

Making the row supplier asynchronous. The chooser atom calls it synchronously on every query
change and expects rows back, which is why the engine answers from what it holds and
schedules separately. An async supplier would need the atom to change.

Letting the atom filter. The surface passes `matcher = false` because the query is
structured. Turning the shared matcher back on would re rank the engine's ordering and hide
the status row.

Losing a held handle. Every timer and every in flight search are held in fields for the same
reason, an unreferenced one is collected and its callback silently never arrives, which looks
exactly like a search that found nothing. A search handle now carries its query, so holding the
handle is what holds the query and there is one rule instead of two. `check-timers` enforces the
timer half and nothing enforces the handles, so that one is on the reader.

Two surfaces reading the engine at once. There is one engine instance, and the query it is
answering is state, so two lists driven at the same time would each be changing what the other
asked about. The launcher scope and the picker are never both on screen, and the failure would be a
confused list rather than a broken one, so this is a note and not a mechanism. It is also the trap
that ate two probes. Driving the row supplier by hand while the picker was open had the picker's own
refresh cycle answer with the recent list branch, which cancels the dispatch, so both dumps were
the recent list wearing a browse header.
