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

## What Spotlight cannot see, measured

It holds **no path containing a dot segment**. Not the dot entry and not anything beneath
it, so all 599 files in `~/.config` come back as zero results. This is not a filter that
can be switched off, the data is absent, which is the entire reason a third source exists.
Anyone tempted to collapse the hidden source into a Spotlight flag should re run that
query first.

The blind spot is about **245 thousand paths and 33MB**, walked in roughly a second. Too
slow per keystroke and too much to hold in Lua, so it is written to a file and filtered by
a tool.

## Four predicate facts, each one learned the hard way

Every one of these cost a wrong first attempt, so they are recorded rather than left to be
rediscovered.

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

## Two mode split on a scope, and why browse is one level

With no text a scope is a browse, so it lists one level sorted newest first. Type anything
and it becomes recursive. One level is not a limitation, it is what a file manager shows,
and it is the only form that can be ordered by date with no recursion and no stat calls,
because `ls` does the sort itself in C. Ordering by date any other way means stat'ing every
entry.

## Why the recent window is three days

Three days matched 3,136 files and answered in **207ms**. Fourteen days matched **108,569**
and took **4.2 seconds**, because the cost tracks how many results are gathered rather than
how far back the bound reaches. Widening `recentDays` is the single setting here that can
make opening the picker feel slow.

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

## What it deliberately does not do

No preview pane. The companion pane and the Chain of Responsibility for generated
thumbnails are a second feature, and that is where a configured cache directory would
genuinely belong.

No content search. Spotlight's text index answers it in about 135ms and ripgrep is the
gitignore aware fallback, so the shape is known, it is simply not built.

No delete or trash action. A destructive key in a fast picker is a bad trade without a
confirm step, and this has no confirm screen.

## What it degrades to

Every tool is optional. Without the walker, scoped search stops and Spotlight still answers
everything unscoped. Without fzf, unscoped hidden search stops and a scoped hidden search
still works through the walk. Each source reports itself unavailable with one console line
naming why, and the key stays worth pressing in every case.

## What would break if the shape changed

Making the row supplier asynchronous. The chooser atom calls it synchronously on every query
change and expects rows back, which is why the engine answers from what it holds and
schedules separately. An async supplier would need the atom to change.

Letting the atom filter. The surface passes `matcher = false` because the query is
structured. Turning the shared matcher back on would re rank the engine's ordering and hide
the status row.

Losing a held handle. The Spotlight query object and every timer are held in fields for the
same reason, an unreferenced one is collected and its callback silently never arrives, which
looks exactly like a search that found nothing. `check-timers` enforces half of this and
nothing enforces the query object, so that one is on the reader.
