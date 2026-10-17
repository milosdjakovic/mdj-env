# Olm one search for every list

Status. Phase one is built on branch `olm/search-algorithm`, the algorithm in `match.lua` and one
rank engine with its four copies deleted, awaiting review and a live load. Phases two to four of
`Spoons/Olm.spoon/docs/PLAN-UNIFIED-SEARCH.md` are planned. The exact field names are left to
phase 2.

## Now

Search is one algorithm and one ranking engine, `lib/chooser/match.lua` and
`lib/chooser/rank.lua`, used by every chooser list. No plugin or host matches or ranks rows
itself, and a search that differs per list is a defect.

The algorithm puts contiguous first. A row whose field contains the typed text as a contiguous
case insensitive substring ranks above every row that only matches with gaps, and the existing
scoring orders rows inside each tier. Each word of a query is scored separately, every word is
required, and the scores are summed. Fuzzy subsequence matching applies only to short fields,
and long bodies such as clipboard contents and file paths match by plain substring. Typo
tolerance and the relevance floor stay for the fuzzy part.

Plugins declare a row vocabulary and only core applies it. Rows carry several searchable
fields and keep the best score. Pinned rows are never ranked or dropped. Query rows always
survive. Tiers order before score. A bounded bonus reorders equally good matches and never
lifts a worse match over a better one. A level may declare only that its field is not a search
at all.

## Rejected

- **Fixing the BrowserTabs Settings row with a keyword list that leads on a whole word.**
  2026-10-17. Built as commit 7fbf1e4 the same day. Milos rejected it because it is search
  special to one list, and the goal is that search never differs per list. It stays in the tree
  only until phase 2 deletes it, together with `SETTINGS_WORDS` and `settingsPlace`.
- **Raising the relevance floor only.** 2026-10-17. It drops the scattered matches that
  surfaced the four tabs, but it leaves no guarantee that a contiguous match beats a scattered
  one, and it would cut real typo matches along with them.

- **Finding a word in a long body through a Lua pattern with both cases per letter.**
  2026-10-17. Meant to avoid lowering the body at all. Lua's pattern matcher steps through the
  body a byte at a time in its own matcher, where a plain find is a C level scan, and over four
  kilobyte bodies it cost about 23 microseconds a body, against 6.5 for lowering on every call
  and 2 for the words strategy over a body its caller had lowered. Replaced by a bounded memo of
  lowered copies inside `match.lua`.
- **Lowering a long body on every call.** 2026-10-17. Correct and simple, and three times the
  cost of the words strategy, 6.5 microseconds a four kilobyte body against 2, which is the
  cost the words strategy was written to avoid.

## Log

### 2026-10-17 11:31, the measurement, the survey and the decision

Typing "settings" in BrowserTabs listed four Chrome tabs above the Settings row, and none of
them contained the word. The shared fuzzy matcher accepted the letters scattered along long
addresses, each landing on a word start after a separator and earning the boundary bonus. The
scores were 33 to 40 against a floor of 26.5, and "Settings" itself scored 88. The Settings
row was never scored, since the plugin appended it outside the ranking by a keyword list.

A survey the same day found eleven lists that match or rank on their own. They are the
launcher, browsertabs, filesearch, clipboard, emoji, obsidian, tmuxsessions, displayprofiles,
workspaces, processes, and the settings and vpn fixed menus. It also found four copies of the
rank loop, in host/queryscope, in the default list model which hard wires fuzzy, in
host/actionpanel and in the launcher's catalog ranking. Each had opted out because the shared
chooser lacked something it needed.

Milos and the main session decided that one algorithm and one ranking engine serve every list,
with the row vocabulary declared by plugins and applied only by core, in four phases. The
launcher's own ranking, the BrowserTabs opt out and the FileSearch, tmuxsessions and obsidian
opt outs are overruled, each to be recorded with its reason when its phase lands. The launcher
rejections about hard bands, bare comparisons and unconditional memory still bind the bounded
bonus.

### 2026-10-17 12:04, phase one built

Built on `olm/search-algorithm` from main at 58eec85. `lib/chooser/match.lua` keeps the name
`fuzzy` for the one search, so the root's choice and every manifest naming it are unchanged, and
three rules now sit on the old subsequence scorer.

Contiguous first is a tier. A word found whole in the haystack, ignoring case, adds one tier, and
the score is the tier times a step plus the sum of the ordinary scores. The step is derived from
the weights per query, the sum over the words of their length times the most one matched
character can earn, eleven, plus the near free gap a whole word can still pay over the long body
bound. That is the widest the ordinary scores can ever spread, so one more whole word always
wins and `rank.lua` still sorts one number. The tier counts per word rather than once for the
query, because a row holding both words whole answers a two word query better than one holding
one whole and the other scattered. A whole word skips the floor, since the floor exists to cut
scattered alignments.

Each word is matched separately, every word required, scores summed. A single word query scores
exactly as before inside its tier.

The long body bound is 256 bytes. Past it a word matches only whole. The subsequence scorer
measured 34 microseconds for an eight letter word over 64 bytes, 58 over 128 and 104 over 256,
and the longest launcher row adds up to under 200 bytes from the longest declared title,
subtitle and keyword bag, so no launcher row loses its typo tolerance. A long body is lowered
once and the copy kept in a memo bounded at four megabytes, and a word in it then costs about 2.5
microseconds a four kilobyte body against 2.3 for the words strategy, measured by
`Spoons/Olm.spoon/test/search-timing.lua`. The first search over a body costs about 11 while its
copy is made. File paths, 60 to 150 bytes, fall under the bound, so phase three has to decide how
FileSearch hands a path over rather than rely on the bound to make it a long body.

Scores for `settings`, old then new, with the tier. Settings 88.00 then 181.12, tier one. seven
little things 63.60 then 63.60, tier zero. The anthropic guide address 40.50 then 40.50, the short
canvasmedical address 37.44 then 37.44, the long one 36.62 then 36.62, all tier zero, and the loom
address no match before or after. For `se`, Settings 21.88 then 49.00 and Sending 21.90 then
49.02, both tier one, Base 11.96 then 39.08, tier one, while Some example stays 17.28, Safe 11.20
and Screen Time Sharing 10.90, all tier zero. So every row holding se ranks above every row
spelling it with a gap, and Sending still edges Settings on its shorter tail.

The boundary bonus after separators is why the four addresses clear the floor, each letter
opening a run on a word start for eight points and paying only the inner gaps. It was left
unchanged, since the tier alone puts them below any row holding the word, which is the condition
the phase set for touching the weights. Whether they should drop out entirely is phase two's
question, where Settings is scored like any row.

The four copies of the rank loop are deleted. `lib/chooser/rank.lua` gained `score`, the one
scoring loop answering entries with the tier and the score inside it, and `before`, the one tie
rule, and `apply` is built from both. host/queryscope's `_filter` and host/actionpanel's
`filterOwnRows` call `rank.apply`, the panel with `substring` chosen at the root so a level
whose list owns its filtering behaves as before. The default list model's `rankRows`, hard wired
to fuzzy, is gone, and `newState` and `setQuery` take the matcher as an argument. The launcher's
`_rankCatalog` scores through `rank.score` and sorts with `rank.before` behind its query memory,
which stays its own until phase four. Hosts load only their own siblings, so `rank` reaches the
three hosts as root data declared in each manifest and set in `root/compose.lua`.

One launcher change follows from the tier. The nearness rule compared a row's score to a
proportion of the best, and a tier step inside the score would read two rows a tier apart as
near. A remembered row now has to sit in the best row's tier, and the proportion is taken of the
score inside the tier, which is the number the nearness measurements were made on, so the order
inside a tier is exactly what it was. Recorded in `olm-launcher-ranking.md` too. Every
expectation in `test/ranking.lua` passed unchanged.

Gates. Dry gate 0 findings, 23 accepted, 0 unknown. `check-dependencies.sh` clean. Units 1411
assertions, all passing, with new cases in `test/cases/match.lua` and
`test/cases/searchengine.lua` and a parity check in `test/cases/actionpanel.lua`.
