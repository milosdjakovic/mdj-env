# Olm launcher ranking

Status. Once something is typed the launcher orders its own list, putting what this query has
been used to pick before above the rest, and only among rows that matched about as well. The
resting list on an empty field is unchanged and still the plain recency timeline.

## Now

Two memories, answering two questions. `_mru` under `launcherRecency` says what was picked last
and is what an untouched list opens on. `lib/queryassoc.lua` under `launcherQueryAssoc` says
what a query has come to mean and is what orders the list once a character is typed. Both are
keyed by the same `recencyKey`, so they can never disagree about what a row is.

A pick records the query in the field together with the row chosen, and every prefix of that
query two characters or longer, so shorter searches improve on the way to longer ones. A single
character is recorded only when it was the whole query. Strength is one decaying number per
pair on an event clock counted per query, so a score converges on a ceiling and the picks
needed to overturn a settled favourite are the same handful whatever its history. The leader is
sticky by a margin. A remembered pick decides only among rows scoring close to the best match,
as a proportion of it. The three numbers are `ranking` in `host/launcher/manifest.lua`.

The launcher scores and sorts its own rows now, through `matcher = false` on its presentation
and the shared strategy it already received and never read. `test/ranking.lua` proves the whole
of it in plain Lua, which matters because this host is the dry gate's permanent unknown.

`host/launcher/CLAUDE.md` carries the working detail and the measurements.

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
