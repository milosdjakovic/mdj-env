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

**A row reported both ages, it named them, and then it gave the room back to the path.** The two
fields are worth recording because both the reason for having them and the reason for dropping them
are still live, and the second reason only became visible once the row could measure itself.

They were labelled rather than bare, and that was a real fix. The first report on the finished
feature was that a folder floated to the top by a path copied a second earlier read `4d ago`
underneath, which is the folder's own date and was read as something the user had done four days
ago. A bare age invites exactly that, because the one thing on a row that is about the person is
indistinguishable from the one thing about the file. So the line said `used 34m ago` and `changed
4d ago`, with the use first, since on the list you land on it was the field explaining why the row
was there at all.

The measurement is what ended them. THE TWO OF THEM TOOK 57 PERCENT OF THE SUBTITLE, and the
subtitle's whole job is telling four files called `init.lua` apart, which is a thing only the path
does. Every point they held was a point the path did not have, and the paths that lost most were
the deep ones, which are exactly the rows where knowing the folder decides anything. Dropping both
turned `~/…/impeccable/public` into `~/.claude/plugins/marketplaces/impeccable/public`.

Neither was earning that price. When a file last changed almost never decides which one you open.
When you last used it was only ever an explanation for the ordering of the list you land on, and
the ordering already shows that by putting the row near the top. Both are still one keystroke away
in the pane, on the row you are actually asking about, which is the same argument this file already
makes for keeping a size off the row. A searched row never carried an age anyway, since only the
recent list reads a date and frecency rarely holds a record for a path you just searched for, so on
the list you spend most of your time in this changed nothing.

`usedAt` stays, on the same injected seam as `onUse`, so the write and the read of a use sit
together and neither names the store. The pane is its only reader now. It is still asked as the row
is drawn rather than stamped upstream, and that is the point. Rows are retained and redrawn for the
local narrow between round trips, so a stamp would report the previous answer on the one row that
was just acted on, which is exactly the row being asked about.

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

## One entry in the prune list is a file, and it is the only artifact that ever showed

`Icon\r` is the macOS custom folder icon, and the trailing carriage return is genuinely part of its
name. Every other artifact of that family is dot prefixed, `.DS_Store` and the AppleDouble `._`
files, so an ordinary search never reaches them. This one is not, which is exactly why it is the
only one that turned up in a list.

It is a file rather than a directory, which the list is otherwise made of, and that is fine because
`_denoise` matches a terminal path segment as well as an inner one, and the rule the list states is
a name nobody searches for in either position. A filename satisfies that as well as a directory
does.

Worth recording how it was nearly fixed wrongly. The row that exposed it was inside
`Chrome Apps.localized`, and the obvious move was to prune that folder, which would have taken the
icon with it. The frecency store said otherwise. That folder is the THIRD highest scoring path on
this machine, above four real files, so it is something reached for deliberately and pruning it
would have removed a real answer to kill an artifact one level down. Check the store before
concluding that a folder near the top of the recent list is noise, since being there is evidence of
the opposite.

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

The atom has since grown a general form of exactly that, `redirect`, asked for the highlighted row
before it may complete and answering with a query the field should hold. Answering it here would
make Return on the back row browse up too, instead of only the insert key, which is the one place
the two keys currently disagree. It is left alone deliberately, since it is a behaviour change to
a working tool rather than a fix, and it is recorded because the special case above now has a
sanctioned way to stop being special.

The browse did take one fix from that work for free. `setQuery` used to leave the text it wrote
selected, so typing straight after browsing into a folder deleted the scope rather than searching
inside it. The atom collapses the caret now, and the main `CLAUDE.md` has the detail.

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

## The subtitle is fitted to the row, and measuring it is what ended the ages

A row's subtitle used to be the directory and the two ages concatenated and handed over, so the
widget cut whatever ran past the edge. The complaint that started this was truncation, and the first
fix was to measure the ages, reserve them, and fit the directory into the remainder, so that a deep
path could no longer push them off the row. That worked. It also put a number on them for the first
time, 57 percent of the line, and once that number existed the fields did not survive it. The
section above has why. The row is now the directory alone, fitted to the full width.

Reserving is still how the fit works and is still exercised, because the browse row leads with
`up to ` and has to fit the rest of the line around it. So `fitDir` takes the rest of the line
verbatim, its separator included, and a caller states what shares the row rather than the fitter
having to know where each caller puts it. That is what keeps the mechanism honest for the next
field that earns a place, rather than it being quietly special cased to one layout.

**The title is cut in the middle, and that one needs no measuring.** Every title here is a filename,
and the last few characters of a filename are its extension, so a tail cut spends the one field
saying what KIND of thing the row is before it spends anything else.
`1Password Emergency Kit A3-B4NHF6-canvasmedi` became
`1Password Emergency…NHF6-canvasmedical.pdf`, which keeps both the extension and the part that
tells it from its sibling. This is `layout.titleLineBreak` on the atom, defaulting to the tail
everywhere else, and AppKit does the work from the paragraph style so nothing is measured. It is a
knob with one caller, which the repo normally pushes back on, and it earns itself because there is
no other way to say a per consumer text policy and the default leaves every other picker alone.

**Counting characters was never going to work, which the numbers settle.** At the row's 12 point
system font ten `i` render at 29.6 points and ten `m` at 104.4. A character budget is wrong by a
factor of three and a half depending on what you happen to write. So nothing counts characters at
any point, the room is pixels and every candidate is measured. The atom answers both halves of
that, `textBudget` and `textWidth`, for the reasons in the hammerspoon `CLAUDE.md`, and this file
only decides what to do with the answer.

**Whole components are dropped from the middle, not letters from the end.** `util.elideDir` keeps
the leading components and as many trailing ones as fit, so a long path reads
`~/Development/…/.hammerspoon/Spoons`. The tail is protected because the leaf directory, and the
one above it, are what tell four files called `init.lua` apart, and the head survives because it
says which world the path lives in.

**The head is two components, which is a correction to the first version.** It kept one, and one
component is nearly always a bare `~`, or an `/opt` or a `/usr`, a glyph or two of pure structure
telling you what you already knew, so nearly every shortened row read `~/…/something/else`. The
component under it is the opposite. `Downloads` and `Development` and `Library` say what kind of
thing a file is more than any middle component does, and they say it for very few pixels. Over
thirty six real directories at the 354 point budget, seventeen shortened and every one of them
gained its domain. The trade is that ten of those seventeen paid a tail component for it, so
`~/…/file-history/2d24d8ee` became `~/.claude/…/2d24d8ee`, and that is accepted rather than
overlooked. The leaf is never what gets paid, since the leaf is what tells two candidates apart
while the head is only context, so the wide head stands down whenever it cannot keep the last
component inside the budget, and a path of three components keeps the narrow head because
`a/b/…/c` is the same path spelled longer. It costs no measurable time, because the extra head
component is one more width to add and one fewer tail component to walk, and a cold page of two
hundred came out at the same 7.9 ms either way.

The variant that takes the wide head only when it is free, so the tail never shrinks, was built
and measured against the same corpus and rejected. It left ten of the seventeen still reading
`~/…`, which is the whole complaint, in exchange for keeping a generic `extensions` or a
`file-history` that the row above and below it also carry.

The alternative considered and rejected was squeezing middle components to their first letter, the
shell prompt idiom, giving `~/D/p/m/dotfiles/hammerspoon/Spoons`. It fills the budget better, and it
preserves depth so two candidates differing only in a middle component stay apart. It lost on three
counts. Every character the elide shows is a real one, where `~/L/A/Google` leaves you guessing
whether that `A` was Applications, Application Support or Audio. It degrades honestly at a tight
budget, where the squeeze collapses to `~/D/p/m/d/h/./Spoons` with a lone dot standing in for
`.hammerspoon`. And it is the macOS idiom, what the Finder path bar and `NSPathControl` do. The
depth argument is real but rarely bites here, because the difference between two candidates is
almost always near the leaf and the leaf survives. The signal that it has started to bite is two
visible rows shortening to the same string, and that is the moment to revisit rather than now.

The elide's one genuine cost is undershoot. It drops a whole component at a time, so it can leave a
stripe of unused room where the squeeze would have filled it. That is a cosmetic loss on a subtitle
and a fair price for a line that reads without decoding.

**A third option was free and still wrong.** Setting the subtitle's `lineBreak` to `truncateMiddle`
makes AppKit keep both ends for zero cost and no measurement at all. It is exactly wrong here,
because the two ends of this string are the tilde and the ages, so it would eat the leaf directory,
the one thing you actually choose by. Worth recording because it is one word and looks like the
obvious answer.

**Fitting is a single pass, and it is exact.** The first version rebuilt a candidate and remeasured
it for every component it dropped, which is quadratic and cost 13.3 ms on a cold page of two
hundred long paths. It now measures each component once and adds, growing the tail until the next
one would not fit, which is 6.9 ms for identical output. That decomposition is exact rather than an
approximation, because the injected width is itself a sum over characters, so the width of a joined
string really is the sum of its pieces. Above that sits a cache of fitted directories keyed by the
path and the room it had, since a page of results is many files across few folders and the ages
cluster into a handful of phrasings, so the budgets cluster too. It is dropped when the picker
closes, because the next open may land on a display of another width.

## Two preview providers, and the contract carries WHEN as well as how

How the highlighted file is shown is a Strategy with two implementations, `PreviewProvider.SidePanel`
and `PreviewProvider.QuickLook`, and the main root names one by reference. The surface calls the
contract and never learns which it got.

The members of that enum are the modules themselves rather than names, so a caller writes
`PreviewProvider.SidePanel` and no provider string exists at any call site. A mistyped member
raises, because the table's `__index` says so, which is as close to an enum as a structural
language gets and is worth the four lines. Reading a nil there would otherwise leave the picker
with no preview and nothing to explain it.

**The contract carries `followsHighlight`, and that field is the design rather than a detail.** A
canvas already on screen redraws for nothing, so it can track the highlight poll and be a
permanent summary in the corner of your eye. A window cannot. Tracking would mean killing one
process and launching another on every arrow key, and a large window reopening over the list
every time you paused would be worse than no preview. So the providers differ in WHEN they show,
not only in how, and the surface reads that one field to decide whether to run a poll at all and
whether the scroll keys mean anything. Pretending they were interchangeable would have produced a
Quick Look mode that flashed a window over the list as you moved.

Two things follow from it that are easy to miss. Room beside the list is asked of the provider
rather than read from config by the surface, since the panel wants 420 and the window wants none,
and that number is fixed when the picker is built. And the keys follow the provider, because a
binding may declare what it `needs` and the root answers it once, so the two scroll keys exist
only under the panel and the peek key only under Quick Look. The shortcut panel is filtered by the
same answer, so a key is never listed while doing nothing, which is the discoverability rule
holding rather than a nicety.

**That filter is applied to the DATA once rather than evaluated per press, and the reason is the
shortcut panel.** A binding gated on live state stays bound and simply does nothing when its
predicate is false, which is right for something that changes while you use the tool, like whether
there is a level above the one you are browsing. A provider is chosen at wiring time and cannot
change, and the panel is built from a static hint list, so a runtime predicate would have hidden
the key while still printing it in the hints. Answering it once, before either the key wiring or
the panel reads the bindings, is what keeps the two from disagreeing. The requirement is named in
the pure data and answered in the root, so neither layer learns the other's business, and an
unknown requirement keeps its binding and says so, since a typo should cost a stray key rather
than a silently missing one.

The chain is the chosen provider with the side panel behind it, the same first available wins
shape the emoji backends use, so an unavailable first choice degrades to a working picker with one
console line instead of to no preview.

**The panel is built by a Swift helper because the command line tool is a dead end, and that was
measured rather than assumed.** `qlmanage -p` starts, registers as a running application and spawns
the system's preview generation extension, and owns ZERO windows. Activating it shows nothing.
Checked both as a child of Hammerspoon and straight from a shell, screenshotted both times. The
tool is present on every Mac and the panel never appears, which is the one failure a provider whose
whole point is a window cannot work around. Hammerspoon has no binding for Quick Look either, so
the only route left to a real panel is AppKit.

So `quicklook.swift` sits beside the viewer, on the Eyedropper precedent. A single file compiled
once with `swiftc` into a cache under HOME, run per preview, the same shape as `sampler.swift`.
The cache is outside the watched config tree on purpose, since Hammerspoon reloads on a change
under that tree and a compile landing in it would reload the config every time the helper is
built. The build is warmed in `configure` rather than on the first press, so the first preview of
the session is instant, and it is a no op on every run after the first because the binary is
compared against the source by modification time. `available` now answers true when the binary is
current or the compiler that builds it is present, which is the check the earlier note said it
would become. Only the mechanism behind `show` changed. The enum, the contract, the reserved
width, the keys and the teardown are exactly as they were designed.

**Two lines in that helper are about the picker rather than about Quick Look, and they matter more
than they look.** The panel is a `nonactivatingPanel` ordered front with `orderFrontRegardless`
rather than made key, because the thing it covers is a Hammerspoon chooser that hides the moment
it stops being key. Showing the preview the ordinary way would dismiss the very list the preview
exists to describe. Verified by screenshot, the panel over a full screen terminal with the
terminal still holding focus in the menu bar, and the picker reporting itself still open behind
it. And the window sits ONE STEP ABOVE the pop up menu level rather than at it. Matching it was
the first attempt and it was not enough, because the picker's docked shortcut hints are a canvas
at exactly that level and drew straight over the preview. A window that covers the list should
cover what the list draws around itself too.

**The chrome is trimmed to what Finder's panel has, which is a filename and one grey close disc,
and the header is drawn here rather than being the system titlebar.** A plain titled panel arrives
with the full set of traffic lights, and a red light belongs to a document window you are editing
while this is a thing you glance at and dismiss. Getting from there to Finder's header took three
attempts and every one of them failed for a reason worth keeping, since each looks like the
obvious answer.

Restyling the close light is impossible. It is drawn by a private cell that ignores an image set
on the button, so the only way past it is to hide it and supply another. Hiding all three and
adding a leading titlebar accessory puts the replacement a third of the way across the bar, because
a hidden traffic light still reserves its slot and a leading accessory begins where the lights end.
Hiding the close light and adding a sibling at its exact frame lands the disc correctly and moves
the TITLE to the left edge, since laying out one unexpected child is enough to make the bar treat
itself as having an accessory. So the system bar is made transparent and empty and the strip is
ours, which is also the only version where the disc's inset from the left is guaranteed to equal
its inset from the top and from the content below, because all three come from one number.

The disc is drawn rather than assembled from a button and a symbol image, for that same reason. A
symbol renders at whatever intrinsic size it has for a given point size, so it sits a little
smaller than the box holding it and the gap it leaves is not the gap that was asked for. Filling
the view's own bounds makes the margins true by construction. The cross is knocked out of the disc
rather than painted over it, so the titlebar material shows through the way the system's own
button does, which a painted cross cannot do without naming a colour that has to match a
translucent background. And it answers the first click explicitly, because a control on a window
that is not key normally spends the first click on becoming key, and this panel never becomes key
at all.

The strip sits ABOVE the content rather than floating on it, which was the correction to the first
attempt. Floating is what the real panel does, but it puts the first inch of the document under the
title, so the filename reads against whatever that document happens to be and the top of the
content has to be scrolled back into view. A preview whose header you have to scroll away from is
worse than one that costs a strip of height.

**Any mouse click on the panel closes the picker, and therefore the panel.** Not a defect and not
fixable from here, it is the same focus rule the whole provider is built around. The chooser hides
when it stops being key, a click on the panel is enough to take key away from it, and the picker
closing tears the panel down on its way out. So the close button and a click anywhere on the
preview do the same thing, everything goes away, and the panel is a keyboard surface in practice.
Escape is the way to put only the preview back.

**Escape closes the preview and leaves the list, and that costs an event tap because of the very
thing that makes this provider work.** The panel is deliberately never the key window, which is
what keeps the picker alive underneath it, and the price is that it cannot receive a key press of
its own. So the press is caught outside and consumed, since Escape reaching the list behind would
close the list too and putting a preview away should leave you where you were. Pressing it again
closes the list, which is what it always did. The tap exists only while a panel does, so nothing
here touches Escape the rest of the time, and it is torn down on the panel's own exit as well as
on ours. That last part is not symmetry for its own sake. The helper can end without this side
asking, since it is a process and a window that both have their own ways of going, so a teardown
that only ran on our own paths would leave a tap eating Escape for a window that is not there, and
Escape would quietly stop closing the list.
The teardown itself is deferred by one turn of the loop, because stopping a tap from inside that
tap's own handler drops the last reference to it mid call.

**Asking for the file already on screen means close, and asking for a different one means
replace.** That makes the key a toggle the way the space bar is one in Finder, without making it a
toggle in the case where a toggle is useless. Closing on a row you have moved off would mean
pressing the key twice to walk a preview down a list, and a preview that follows what you asked
for is the entire point of asking. The comparison is made after the tilde is expanded, since the
same file arrives as a short path from the back row and as a full one from a search, and those are
the same file to everyone but a string compare.

The helper is a child process, and that is what makes closing it clean. It lives exactly as long
as its window, so terminating the task takes the panel with it and closing the panel by hand ends
the process. The task handle is held for that reason and holding it also keeps the task from being
collected mid flight. Both directions are covered, `close` on the picker closing and the callback
clearing the handle when the panel goes first, since a stale handle would make the next preview
terminate something already gone.

One consequence for the manifest. The viewer declares `swiftc` and no longer declares `qlmanage`,
because it no longer runs it. `thumbs.lua` still does and still declares it for itself, which is
the declaration rule working, a need sitting beside whatever actually knows the tool rather than
in a list at the package root.

**Two bugs came out of driving it live, and both are about a preview being a PROCESS rather than a
drawing.** Neither could exist for the side panel, which is why neither was predicted.

The first was the exit callback clearing the task handle unconditionally. Replacing a panel
terminates the old helper and starts a new one in the same breath, but the old one's exit arrives
later, so by the time its callback ran it wiped the handle to the panel that was actually on
screen. Closing the picker then terminated nothing and left a window floating over a list that no
longer existed. The fix is an identity check, a captured handle the callback compares against
before clearing, which is the same token shape the async thumbnail render already uses for the
same reason, a late answer must not act on behalf of a request that has been superseded.

The second is that `peekPreview` now refuses once the picker is not showing, and that guard is
about lifetime rather than about the row. Every other verb here is a one shot, so acting on a
stale highlight would at worst reveal the wrong file. This one opens a window whose only teardown
is the picker closing, so a peek that lands after that teardown has already run leaves a panel
nothing owns and nothing will ever take down. It cost one orphaned window during testing that only
a kill would clear.

What the live pass confirmed, on a repeated cycle, is that the picker opens as a plain list with no
reserved room, the panel renders a pdf over it while the picker stays open behind, asking again on
another row replaces the panel rather than stacking one, the process id changes when it does, and
closing the picker leaves nothing running and no timer held.

Two bugs came out of building it and both were about the difference between a canvas and a window.
`onPositioned` seeds the first highlight with a direct call rather than through the atom's poll,
and `refresh` does the same after a rebuild, so both bypassed the `followsHighlight` gate and
merely opening the picker threw a panel on screen for whatever row was first. And the back row
carried `~` as its path, because going up collapses home for the query FIELD and the row was built
from that string. A row is not a field, its path goes to Finder, to open, and to whatever a
provider shells out to, and none of those expand a tilde. What hid it is that `hs.fs.attributes`
DOES expand one, so every guard of the shape does this path exist passed happily and only the
external process failed.

## Three smaller decisions in the provider split, each one asked about at least once

**Why the providers live in a directory.** The pane used to be `preview.lua` at the spoon root. A
second implementation of the same contract makes it a backend rather than a component, so it moved
to `viewers/`, beside `sources/` and for the same reason. Having one backend at the root and one
in a folder would say the two are different kinds of thing when the whole point is that they are
not. It was a rename rather than a rewrite, so the history follows it.

`thumbs.lua` deliberately did NOT move. It is only used by the side panel today, which is an
argument for putting it in there, but what it does is produce a picture of a file, which is a
capability rather than a viewer's private machinery. Leaving it at the root also leaves its
declaration where it was, and moving a declaration relabels the consumer column in the generated
manifest for no gain anyone can point at.

**Why the surface holds a Null Object rather than nil.** With no provider available the surface
would otherwise guard six call sites, every one of them on a path that runs per highlight or per
keystroke. A table of empty functions is fewer lines than the guards, and it means the no preview
case is exercised by the same code as the working one instead of by a branch nobody takes.

**Why a provider is configured before it is asked whether it is available.** The side panel's
answer depends on whether the shared surface was injected, and it learns that in `configure`. So
the resolution loop configures each candidate and then asks, rather than asking first, and the
cost of configuring one that then steps aside is storing a table. Asking first would have made
the side panel permanently unavailable, which is the kind of ordering bug that looks like the
feature was never wired.

## The pane answers the question the row cannot afford to

A row is one line, and one line cannot say whether this is the file you had in mind. The subtitle
spends everything it has on the directory, which is as far as a line honestly goes, so the pane
beside the list shows what is actually inside.

It also owns the facts a list cannot pay for, and it owns more of them since the row gave up its
ages. No source reads a size and only the recent list reads a date, because either one costs a call
per row and a page is two hundred rows. The pane describes exactly one row, so it stats that row
and reports the size, both dates and the kind for the cost of a single call. That is why the row
subtitle carries no size, and now no age either. The size field used to exist filled by nothing,
which is the defect this replaced, and the ages were removed once measurement showed they were
taking more than half the line from the one field that identifies the row.

The header draws for every row and is not part of the chain below, because a name, a location
and a handful of dates are true of everything, and a pane that sometimes had no header would
be answering a different question depending on which row you were on. Both ages stay labelled
there, for the reason they were labelled on the row before it dropped them, since a bare age
cannot be told apart from something you did. The last used line is drawn in the
accent tone because it is the one fact on the pane that is about you rather than about the
file.

## What the body shows is a Chain of Responsibility, and declining is half of it

`BODIES` in `viewers/sidepanel.lua` is an ordered list of describers, each offered the row and free to
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

## A budget in source lines bounds nothing, and a clip does not bound layout

Two separate costs, both found from one report that scrolling over a `tsconfig.tsbuildinfo`
lagged.

The head budget was four hundred LINES, and that file is one line of a hundred and thirty
thousand characters, so the budget bounded nothing at all and the sixty four kilobyte read
wrapped to about eleven hundred display lines. It is counted in DRAWN lines now, applied
where the wrapping happens rather than before it, so it holds whatever shape the file turns
out to have. A minified file is not an unlikely case either, since every build writes one.

The second cost sat underneath that one and applies to every long text file rather than only
to minified ones. A clip bounds what is VISIBLE and not what is laid out, so handing the
canvas one text run of the whole body made every paint cost the whole body, and a paint
happens on every scroll event. Only the visible slice is drawn now, rebuilt per paint, which
is affordable precisely because it is a slice.

Measured as the largest gap between fires of a sixteen millisecond timer, the same method
the type token measurement used and the only one that catches a stall wherever it lands.
That file stalled the main thread for **383ms** on show and **355ms** per paint while
scrolling, with nine of a hundred beats firing, so the thread was busy almost the whole
time. The budget fix alone took that to **81 and 102**. Windowing took every case, a small
source file, a long prose file and that one, to between **23 and 45** with essentially no
dropped frames, against an idle floor of **17**. An ordinary four hundred line file cost
**50 to 60ms** per paint before windowing, which is why this was never only about minified
files.

Since Hammerspoon owns every leader key in this config, a stalled paint is a stalled
keyboard rather than a slow pane, and that is what makes both mechanisms worth having rather
than one.

## The budget has a slack zone, because a hard edge is a bad trade near it

A file four lines over the budget would lose those four lines and gain a notice about them,
which is a worse thing to read than the four lines were. So the budget is where the trim
lands and the slack is how far past it a file is shown whole anyway. Four hundred and fifteen
lines is complete and says nothing, four hundred and twenty one is trimmed to four hundred
and says so. Both numbers are config, and the slack exists so the second case is always worth
the interruption.

When it does trim, the last line of the body is an ellipsis and a line under it says what is
missing. The ellipsis sits in the body tone as a line of the text, because it means the text
stopping, while the count sits in the meta tone because it is the pane talking about the file
rather than more of the file.

**The count is only in units that are known.** Characters always, from the stat, so it covers
the whole file rather than the part that was read. Lines only when the file really has lines
AND the read reached the end, since a minified bundle is one line and telling you seven
hundred more lines would be describing the wrapping rather than the file. That condition is
also why the source line cap was removed. It used to stop at four hundred source lines, which
bounded nothing on a minified file and, worse, meant nothing downstream could know how much
had never been looked at, so any count would have been a guess. The read cap is the bound now
and everything read is wrapped, which costs a few thousand iterations at worst and buys an
exact number.

One off by one came out of this and is worth not repeating. Appending a newline to a blob that
already ends with one yields a phantom empty last line. It was an invisible blank while
nothing counted the lines, and became a wrong number the moment something did, reporting five
hundred and one left where five hundred were. The terminator is added only when missing.

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

**A size decides which backend does the work, and never whether the pane can show the file.**
There is no maximum size here, and the code once behaved as though there were. The in process
generator claimed every raster by extension and then refused the large ones on size, and
because the chain gave the whole file to the first backend that claimed the type, the row ended
there with a heading reading no preview. Quick Look was sitting directly behind it, in another
process, perfectly able to draw the thing. Measured on a 35MB png, the chain answered nil while
`qlmanage` rendered the same file to a 768KB thumbnail and exited clean.

So `handles` answers about the TYPE and a new optional `accepts` answers about the FILE, and
declining passes it along, which is the rule the describer chain upstairs already ran on and
the only one this chain was missing. The in process generator steps aside past its cap, Quick
Look claims the raster types as the backstop behind it, and order still means every ordinary
photo takes the cheap path. The cap protects the main thread, which is the only thing it was
ever for, and the backend that is not on the main thread has no reason to have one.

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

**Both of those are DIRECT calls rather than calls the atom makes, and that is exactly why they
each need the `followsHighlight` gate.** The atom's own poll is wired only for a provider that
follows the highlight, so it can never reach one that does not. These two bypass the poll, so
without the gate they reach any provider at all, and under Quick Look that meant merely opening
the picker threw a panel onto the screen for whatever row happened to be first, and a result set
landing threw another. It reads as a shortcut worth removing until you know what it is for, so it
is written down here rather than left as two conditions that look redundant beside a poll that is
already gated.

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

All of this is the side panel's, not the feature's. A window scrolls itself and its keys are the
system's, so the other provider answers nothing to the scroll verb and the two keys are not bound
under it at all. That is why the verb is on the contract as optional rather than required, and
why the trackpad watcher is wired only for a provider that reserved a rect for one to happen
over.

## A second surface joins a session, it does not begin one, and the difference was a loop

The engine has an open, and the picker has one, so opening resets the session and refetches the
recent list. The launcher's alias has no open at all. It is asked for rows on every keystroke and
again every time it is told the rows changed, and it began a session on each of those asks, which
looked harmless and was not.

`reset` clears the parsed query, and the parsed query is what `rowsFor` compares against to
recognise a repeat and hand back what it already drew. Cleared, every ask did the full work again
and ended by announcing that the rows had changed. The launcher answers that announcement by
asking again, which reset again, which fetched again. A loop with a Spotlight round trip in it,
running for as long as the alias sat there with nothing typed after it, and the list it left on
screen was whatever that churn happened to produce rather than the recent files.

So there are two verbs. `beginSession` is what an open calls and it still resets. `ensureSession`
starts one only when there is neither a list held nor a fetch on the way, and costs nothing
otherwise, which is what a surface with no open of its own must call. Naming them separately is
what makes the choice visible at the call site, since both are one line and only one of them is
right for a caller that will make it a thousand times.

The same split runs through the preview. `peekPreview` acts on this picker's own highlight and
refuses once this picker has gone, because the window it opens is torn down when this picker
closes. `peekRow` takes a row it was handed and makes no such refusal, since the caller is a
different owner with a different close, and it takes on the matching duty instead, calling
`closePreview` when its own list goes. Two callers, one preview, and whoever asked is whoever
puts it away.

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
lose their picture, and the describer declines rather than promising one. A raster too large for
the in process generator loses its picture too, since that one steps aside on size and Quick Look
is what it steps aside TO.

Without the shared canvas surface injected, the side panel reports itself unavailable. That is
one line in the main root, and it is the same path a provider takes for any other reason, so the
chain moves to the next one and lands on nothing if there is no next one. With no provider left
the picker reserves no room, runs no highlight poll and binds neither the scroll keys nor the
peek key, which is exactly what it was before any preview existed.

A provider that steps aside says why, once, in the console. That matters more here than for a
source, because a missing preview is silent by nature. Nothing is drawn either way, so without
the line there is no difference between a provider that was never chosen and one that could not
run.

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
