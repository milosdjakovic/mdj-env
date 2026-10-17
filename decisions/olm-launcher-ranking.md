# Olm launcher ranking

Status. Once something is typed the shared search ranks the launcher like every other list, and
what this query has been used to pick before reaches it as a bonus, which orders only rows that
match equally well. The resting list on an empty field is unchanged and still the plain recency
timeline.

## Now

Two memories, answering two questions. `_mru` under `launcherRecency` says what was picked last
and is what an untouched list opens on. `lib/queryassoc.lua` under `launcherQueryAssoc` says
what a query has come to mean and orders equal matches once a character is typed. Both are keyed
by the same `recencyKey`, so they can never disagree about what a row is.

A pick records the query in the field together with the row chosen, and every prefix of that
query two characters or longer, so shorter searches improve on the way to longer ones. A single
character is recorded only when it was the whole query. Strength is one decaying number per
pair on an event clock counted per query, so a score converges on a ceiling and the picks
needed to overturn a settled favourite are the same handful whatever its history. The leader is
sticky by a margin. The two numbers are `ranking` in `host/launcher/manifest.lua`.

The launcher ranks nothing itself, Milos's decision of 2026-10-17 that search never differs per
list. Its presentation declares no matcher, and its supplier hands the query rows first, then
the catalog in its resting recency order, each catalog row carrying a `bonus` that is its place
in `orderFor(query)`, one for the leader down to one over the count, nothing for a row with no
memory. The engine reads a bonus only among rows it calls equally good, so ma learns Maps over
Mail, both at the start of a name, and lose keeps Local Servers, spelled in pieces, above a
remembered Loes, one typo away. `test/ranking.lua` proves it through the real path, the supplier
ranked by `rank.apply` with the shared matcher, and the dry gate refuses a launcher, or any
list, that ranks its own rows again.

`host/launcher/AGENTS.md` carries the working detail.

## Rejected

- **Leaving the ordering to the chooser atom.** Until 2026-09-22. The atom scores with the
  shared strategy and breaks a tie on arrival order, which is the recency order, so the design
  was already right on paper. The tie never happens. Two rows matching equally well differ by
  hundredths of a point over incidental things, chiefly subtitle length, since the scorer
  charges 0.02 for every character after the last one matched. Measured, `ma` scores Mail at
  21.8600 and Maps at 21.7200, identical matches separated only by `Not running` being nine
  characters longer than `Open`. So nothing a person did ever changed the order while typing.
- **A wall clock half life, the shape of `plugins/filesearch/frecency.lua`.** 2026-09-21. It is
  the settled store in this repository for exactly this kind of question and it is the wrong
  one here, because its score is unbounded. A thing picked a thousand times needs ten half
  lives, about 140 days at that plugin's setting, to fall back within reach of something picked
  twice this week. That is the complaint this work started from, stated in those words.
- **A global popularity score, one number per row rather than per pair.** 2026-09-21. Designed
  in full and dropped once the ask was stated precisely. It measures launcher picks, which is
  not what a person means by most used, since the apps used most here are the ones bound to a
  chord and those are never picked through this list at all. It would have needed the app
  watcher to mean anything, which reverses the decision of 2026-08-07, and it answers a
  different question from the one asked.
- **A hard band, treating scores within a fixed distance as equal and ordering inside it.**
  2026-09-21, measured and rejected the same hour. A band has a cliff at each edge, so two rows
  0.9 apart reorder and two rows 1.1 apart do not, and entering and leaving the neutral zone is
  itself a reorder. Simulated over four hundred picks at an even split it made the top row
  change more often rather than less, 110 changes at a band of 1.0 against 96 with no band at
  all.
- **A bare comparison with no margin.** 2026-09-21. It overturns on the same pick as the margin
  does, so it costs nothing to add and the margin is free. Without it a single stray pick hands
  the top row straight back. Simulated over twenty runs of four hundred picks at decay 0.80, a
  margin of 0.6 cut leader changes from 106 to 49 at an even split, from 70 to 30 at 65/35, and
  from 5.6 to 1.6 at 85/15, while the overturning pick stayed the fourth.
- **A decay whose overturn formula lands on a whole number.** 2026-09-21. `0.5^(1/4)` gives
  exactly four picks, and with a long history the leader sits at the ceiling and the challenger
  arrives on top of it, measured at a gap of 4e-15, so which one leads is decided by floating
  point rounding. 0.80 gives 3.11 and is clear of it.
- **Letting a remembered pick lead unconditionally.** 2026-09-22, found by the test rather than
  by reasoning, having been asserted as safe in the plan. Every remembered spelling answers for
  the longer queries it begins, which is what makes the memory fill in, so a pick made at `ma`
  is consulted when you type `mail`. Maps does match `mail`, weakly, by spending the scorer's
  typo allowance on the letter it cannot place. So this ordered Maps above Mail while Mail was
  spelled out in full.
- **Extending `lib/services.lua`'s `perPlugin` to build the instance.** 2026-09-22. It builds
  one only for a field literally named `recency`, so a second name needs a second hardcoded
  branch in a shared file for one consumer. It would also widen an existing asymmetry, since
  that function does not run under the dry gate, so the host would receive an instance live and
  a raw module dry. The consumer calls `new` itself instead and both paths hand it the same
  thing.
- **Pruning everything the catalog no longer lists.** 2026-09-22. A row can disappear because
  its tool was switched off rather than removed, and the launcher cannot tell those apart, so
  this would silently destroy a tool's history for an afternoon's experiment. Only applications
  are pruned, where the disk scan is a real answer. A dead key costs nothing, since a pair is
  only ever looked up for a row already in the list.

- **Locking a pick to the best row's tier.** 2026-10-17, built at 6539235 and found by the
  adversarial review. A remembered row had to sit in the best row's tier of the shared search,
  so a pick at a lower tier could never be learned, Docker Desktop for dd against Hidden Bar, which
  held dd whole. The gate keyed on a score shape rather than on the one case the memory must not
  bridge, a best row the person spelled out.

- **The nearness rule, a remembered row leading rows scoring close to the best as a
  proportion.** 2026-10-17, removed in phase four of `docs/PLAN-UNIFIED-SEARCH.md`. Milos
  decided search never differs per list and the launcher's memory orders only equal matches,
  exactly like recency everywhere else, so a better match always leads. Nearness let a
  remembered row cross a level, Loes, one typo from lose, over Local Servers spelled in pieces.
- **The atStart lock, a remembered row never leading a best row matching every word at a name
  word start.** 2026-10-17, removed with it for the same reason. It existed only to stop the
  memory crossing one particular level, and a bonus inside one level answers every level at
  once, so ma still learns Maps over Mail and nothing needs to know about word starts here.
- **The launcher's own sort, `_rankCatalog` scoring with `rank.score` and sorting remembered
  rows first.** 2026-10-17, removed with them. A list that sorts its own rows is a search that
  differs per list, which Milos ruled out, and it was the reason the presentation carried
  `matcher = false`. The memory is a `bonus` on each row and the stage ranks the list.

- **A typed size under the floor offering no row at all.** Until 2026-10-17, rejected that day
  by Milos because nothing conveyed why. Window Size answered nothing for a size with an edge
  under `smallestEdge`, on the reasoning that a typo which quietly acts is worse than one that
  quietly does not. The row simply vanished, so a person could not tell a refused size from a
  grammar the launcher does not know.

## Log

### 2026-09-21 20:40

Asked for the launcher to rank what it lists and to drop what no longer exists, with weighting
rather than counts, and with the explicit requirement that a thing picked a thousand times must
not need a thousand picks to displace. Survey of the existing code found one plain most recently
used list capped at fifty, no frequency anywhere, and the tie break at
`lib/chooser/providers/native.lua` that was meant to carry it and never fires.

### 2026-09-21 21:30

Design narrowed twice by the person. Recency stays as it is until something is typed, and the
ranking applies only among results, which rules out the global popularity score designed up to
that point. Then stated exactly, pick the third result and next time it leads, which is a memory
of query and row pairs rather than a score per row. That reframing removed the open question
about whether the store should learn from Cmd Tab and chorded launches, since an association
needs a query and a chord has none.

### 2026-09-22 00:10

Built on `olm/launcher-ranking`. `lib/queryassoc.lua`, its registration in `init.lua` and
`root/compose.lua`, the declaration and the three numbers in `host/launcher/manifest.lua`, and
`_rankCatalog`, `_noteAssociation` and `_pruneAssociations` in `host/launcher/init.lua`. Dry
gate identical to main, 0 findings and the same 4 unknowns, the launcher among them for the
pre-existing reason that the gate stubs `hs.processInfo.bundleID` as a table and the host
concatenates it at load. `check-dependencies.sh` clean.

### 2026-09-22 00:35

`test/ranking.lua` caught the one real defect in the design, which the plan had asserted was
impossible. An association reached through a prefix put Maps above Mail for the query `mail`,
because the prefix walk back is what makes the memory useful and Maps matches `mail` through the
scorer's typo tolerance. Measured, `mail` scores Mail 43.90 and Maps 12.56, against 21.86 and
21.72 for `ma`. Added `nearness`, a proportion of the best score rather than a distance in
points, since the score grows with every character typed. The three cases sit at 99.4%, 65% and
28.6% of their own best, so the default 0.9 has a wide margin on both sides. Both new checks
were mutation tested by setting the constant to zero and confirming they fail.

### 2026-10-17 12:04

The shared search now ranks a word found whole a tier above any scattered match, carried in the
score as a large step, `olm-unified-search.md`. A proportion of the whole score would read two
rows a tier apart as near, so nearness now admits a remembered row only from the best row's
tier and takes the proportion of the score inside that tier, which is the number the 99.4%, 65%
and 28.6% measurements were made on. Inside a tier the order is what it was, and a remembered row
can no longer lift a scattered match over a whole one. `_rankCatalog` scores and sorts through
`lib/chooser/rank.lua` behind the query memory instead of its own loop. Every expectation in
`test/ranking.lua` passed unchanged.

Corrected 2026-10-17 12:29, see below.

### 2026-10-17 12:29

The shared search now ranks four levels per word, word start, initials, inside a word and
scattered, `olm-unified-search.md`. A remembered row may lead unless the best row matches every
word at a word start and the remembered row does not. Inside that, nearness is the proportion of
the score inside the level, measured down from the best row's score by its size, so a best score
below zero, which a long inner gap between initials produces, admits its own pick rather than
inverting the proportion and dropping every pick.

This is not the rejected hard band. The gate is on the kind of match, a fact about what was typed
and where it sits in the row, which incidental text such as a subtitle's length never moves, so
it has no edge two near equal rows can drift across while typing. The proportion inside it is the
same proportion as before. Nor is it unconditional memory. The Mail and Maps case is exactly a best
row at a word start against a pick that is not, and the gate keeps Mail first however often Maps
was picked at ma.

Four cases in `test/ranking.lua` pin it, each proved by mutation. A pick at a lower level leads
when the best row is not a word start match, Axb over Crab for ab, which the phase one tier gate
fails. A pick that is not a word start match never leads over one that is, Alpha Bravo against a
row starting ab deep inside it, which removing the gate fails. Rows close only because of the
step, Mail and a row starting Map late, are not near, which a proportion of the whole score
fails. A pick near a best row scoring below zero still leads, which the plain proportion fails.
Every earlier expectation passed unchanged, 50 checks.

### 2026-10-17 12:55

The shared search now favours names, five levels per word, `olm-unified-search.md`, and the
launcher hands its catalog over as each row's name plus its declared terms, so a subtitle's
category, status and chord no longer decide anything. The gate reads as before, a remembered row
may lead unless the best row matches every word at the start of a word of its name and the pick
does not. The cases were rebuilt on the new levels and each still fails under the mutation it
guards against. Three older expectations changed by the new search rather than by this rule,
each with its reason beside it. mail no longer matches Maps at all, map no longer matches Mail,
and with nothing remembered Mail and Maps tie on ma, since the subtitle that used to separate
them is a status and no longer searched, so the resting order decides as the original complaint
asked.

### 2026-10-17 17:32

Not about ranking, logged here because this is the launcher's file. Choosing the Aliases row
closed the launcher and then seeded a field that was already gone. The row is a special row with
no owner and no tool, so the registry has no presentation for it and the row intercept declined
it. `registrar.aliasRowReplacement` now answers it, seeding the word `queryFor` gives through
the same path a directory row takes, and `special.aliasDirectory` stays as the fallback for a
click whose row could not be resolved. `enterPage` has no caller left. The notes that said the
Aliases row was hosted were wrong and are corrected in `AGENTS.md`. `test/cases/launcher-aliasrow.lua`
covers it.

Corrected 2026-10-17 17:51. The fallback described above was still broken. It seeded a field on
a stage that had already closed, which show then cleared, so an unresolved click opened nothing.
It was fixed in the review rework logged below, and the helper and the case named here no longer
exist.

### 2026-10-17 17:33

Not about ranking either. The emoji picker answers to em as well as e and emoji, since two letters
is what gets typed for it. Nothing else holds em. The word s and system were checked as a possible
collision between the System Settings plugin and the launcher's settings pane scope, and there is
none, because the plugin registers no scope and its aliases only word the launcher row's hint.

### 2026-10-17 17:33

Not about ranking. The Arithmetic and Convert result rows now carry the subtitle Copy the result
and nothing else, and the Converting placeholder has no subtitle. The category word and the echoed
expression are gone, since the field already holds the query. The category option had no other
reader, so it was removed from both plugins and from the Arithmetic manifest. Subtitles are not
searched, so nothing in ranking moves.

### 2026-10-17 17:37

Not about ranking. The Window Size row is titled `Resize` and the application the launcher is
covering, read through the root word `coveredApp` that menu search and text case already
declare, since the launcher gives focus back to that app before a window row runs and asking
macOS while the list is up answers the list itself. With no app known it reads `Resize window`.
The subtitle is the size that will land and nothing else, `1920 x 1080`, with `, display limit`
when the screen trims it. An edge under `smallestEdge`, still 200, is now raised to it and reads
`, size limit`, and the descriptor carries the raised size, since the floor depends on no screen,
while the display trim still runs against the real screen when the row is chosen. When both
apply the subtitle names the size limit, because it holds on every display while the display
limit is a guess about which screen is involved. The category option lost its reader and was
removed. `test/cases/windowsize-row.lua` covers it.

### 2026-10-17 17:51

Not about ranking. An adversarial review of the launcher polish branch found six things and all
six were fixed. The Aliases fallback in `special.aliasDirectory` seeded a hidden field that show
then cleared, so it now calls the alias directory scope's own run, which opens the launcher with
the word typed. The row replacement had been put in `lib/registrar.lua` as
`aliasRowReplacement`, which made the registrar know the row, so it was deleted and the root holds
one closure that both `rowIntercept` and the special fallback use, with the name and the row shape
written once. Its proof moved from a unit case that rebuilt the wiring by hand into the dry gate's
composition run, which asks the real configured launcher and reports `wiring FAIL` lines that the
rename proof turns into findings. A case that loaded a copy of the launcher could not have caught
the root wiring it was meant to guard. The Window Size title could name an app the resize would
not reach, so it names the covered app only when that app has a focused window and otherwise reads
`Resize window`, and the case now runs the window manager's real `exactSizePlan` over a fake screen.
VPN let No results replace a better status, since the CLI not found row was neither pinned nor
from the query. It is pinned, and a cold location cache now shows the pinned Reading the locations
row at the top level as the scope already did. Other lists on the shared matcher with status rows
that a typed query would drop were pinned the same way, audio, processes, text case and wifi.
`enterPage` and its prose, and the stale `hostedInPlace` and every tool row is hosted claims, were
removed or corrected. `test/cases/chooser-emptystate.lua` now covers the provider's `_rankedQuery`
across show, setQuery and refresh, including a field that runs ahead of the rows.

### 2026-10-17 21:45

Phase four of `docs/PLAN-UNIFIED-SEARCH.md`, on `olm/search-launcher`. Milos decided that the
launcher's learned query memory orders only rows that match equally well, exactly like recency in
every other list, so a better match always leads. ma still learns Maps over Mail, lose keeps
Local Servers above a remembered Loes, and the empty field keeps today's recency order.

The presentation dropped `matcher = false`. `_commandRows` hands the catalog over in its resting
order with each row's bonus from the new `_memoryBonus`, the place in `orderFor(query)` scaled
from one down to one over the count. `_rankCatalog`, the nearness rule and its default, the
atStart lock, the launcher's sort, the `nearness` number in the manifest, the `rank` root data
and the stored matcher are deleted, and so are the `within` and `atStart` fields of a scored
entry in `rank.lua`, which only the launcher read. `queryassoc`, the margin, the decay, the
prefixes, pruning and recording are unchanged, so the leader still changes on the fourth pick.

`test/ranking.lua`'s launcher half now drives the supplier through `rank.apply` with the shared
fuzzy matcher, as the stage does, 59 checks against 50. Kept as they were, ma learns Maps after
one pick, a longer pick orders the shorter query, mail spelled out stands alone, a remembered row
that does not match is not added, an empty query keeps recency, recording skips a computed row,
nothing is recorded on a hosted page, and the three prune cases. Changed to the new decision,
lose now keeps Local Servers above Loes after twenty picks, where it used to put Loes first. A
row starting a word deep in its name and Mail at the same level now order by the memory, where
nearness kept Mail first. Deleted, the case of a best row scoring below zero, since no
proportion is left to invert. Added, the fourth pick overturns a settled leader in the list as
well as in the store, a remembered row never passes a better level, the bonus is one for the
leader and one half for the last of two and nothing on an empty query, a calc row leads and is
never recorded, and a hosted page keeps its source's rows and order. Making the bonus nil failed
eight checks, making it a tier failed five and inverting it five.

