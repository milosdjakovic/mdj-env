# Olm one search for every list

Status. Phase one is built on branch `olm/search-algorithm` with the four levels Milos decided
after review, word start, initials, inside a word and scattered, and one rank engine with its
four copies deleted, awaiting a live load. Phases two to four of
`Spoons/Olm.spoon/docs/PLAN-UNIFIED-SEARCH.md` are planned. The exact field names are left to
phase 2.

## Now

Search is one algorithm and one ranking engine, `lib/chooser/match.lua` and
`lib/chooser/rank.lua`, used by every chooser list. No plugin or host matches or ranks rows
itself, and a search that differs per list is a defect.

The algorithm ranks four levels per word, strongest first. The word at a word start, the word
spelled by the initials of consecutive words, the word inside a word, and a scattered match with
gaps or typos. A stronger level always outranks any score at the levels below it, and the
existing scoring orders rows inside a level. Each word of a query is scored separately, every word is
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

- **Two tiers, contiguous or not, the first phase one build.** 2026-10-17. Built at 6539235
  and rejected by Milos after the adversarial review. A whole word skipped the floor wherever it
  sat, so one typed letter listed nearly every row, e from 10 to 185 of the 232 launcher rows, i
  from 20 to 209 and o from 42 to 223. It ranked Base above Some example for se, where a name
  spelled by initials is what a person means. And the launcher's tier gate locked learned picks
  out, so Docker Desktop for dd could never be relearned against Hidden Bar. Replaced by four
  levels.

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

Corrected 2026-10-17 12:29, see below.

### 2026-10-17 12:29, phase one reworked to four levels

The adversarial review of 6539235 found the two tiers wrong in three ways, all listed under
Rejected, and two statements in the entry above untrue. A single word query did not score as
before, since a whole word skipped the floor and that changed which rows a list shows, not only
their order. And lists do change what they show, not only how matches rank, which the plan's own
phase one line also claimed.

Milos decided four levels per word, strongest first. A word start, the word whole at the start of
the row, after a separator or at a camel hump, se in Settings. Initials, the word's letters as
the first letters of consecutive words, os in OLM settings, dd in Docker Desktop, ps in Printers &
Scanners. Inside a word, contiguous anywhere else, se in Base. Scattered, the old alignment with
gaps or typos. He accepted that se now ranks Some example above Base. A word starts where the
scorer's own bonus says one does, so the levels and the scoring agree, and only a letter, a digit
or a non ASCII byte begins a word for initials, so a standalone ampersand is skipped. Nobody types
the ampersand when spelling a name by its initials. Only a word start and initials skip the floor.
Past the 256 byte bound only a word start and inside a word exist, and the best occurrence wins, a
word start anywhere in the body over the first hit.

A row's level is the sum over its words, worth 3, 2, 1 and 0. The step per level is the sum over
the words of the word length times eleven, the most one matched character earns, plus 256 times
the 0.4 inner gap. Every matching word scores at most its length times eleven and more than minus
256 times 0.4, since an accepted alignment pays at most its haystack length in gaps and the
inner gap is the dearest, a short haystack is at most 256 bytes, and a long one is scored by a run
whose gap is capped at 256 times 0.02. So two rows at one level sum differ by less than the step,
and a row one level higher scores more than the step minus that spread, which is above zero.

Levels for the examples. se gives Settings and Sending a word start, Some example initials, Base
inside and Safe scattered, so the order is Settings, Some example, Base, Safe. os puts OLM
settings at initials above Photos inside, dd Docker Desktop at initials above Hidden Bar inside,
ps Printers & Scanners at initials, and mb Menu Bar at initials above Numbers inside. settings puts
Settings at a word start and the four addresses and seven little things scattered, 40.50, 37.44,
36.62, no match and 63.60, all below. dspl puts Displays scattered, so a bag whose words spell
dspl by initials, Downloads System Preferences Look, now leads it. Two existing cases used that
bag as their scattered example, `test/cases/match.lua` and `test/cases/canvaslist.lua`, and both
now use Device Management sync profile lock, with a comment saying why. That is the one existing
order that changed, and it changed by the decided rule.

Over the real launcher catalog, 232 rows dumped through a temporary unit case that was then
deleted, one letter queries return to the counts on main, e 10, i 20, o 42, a 40, s 94. Of 660
queries of two to four letters, every prefix and every run of initials of the titles, 7 change
their top result against main, where phase one's two tiers changed 36. ais, General to Apple
Intelligence & Siri. brs and brst, Browser tabs to Blackmagic RAW Speed Test. rst, Raycast to
Blackmagic RAW Speed Test. mch, Monarch to Manage clipboard history. ss, Sleep to Wi-Fi, whose
keywords hold ssid. And ym, YouTube Music to RubyMine, since the camel hump makes YouTube two
words, so ym is not its initials, while RubyMine holds ym inside a word. That last one is the
camel rule doing what it says and is left for Milos to judge.

Choosing the best occurrence costs most when a word sits only inside words, every occurrence
tried. ump over the four kilobyte timing bodies measured 6.1 microseconds a body against 0.3 for
the words strategy, and the other queries stayed near the words strategy, 2.4 against 2.3 for
settings.

The memo comment said Lua interns long strings, which it does not. It computes a long string's
hash once and keeps it in the string. The memo also held each body as its key without counting
it, so it now counts body and copy together against a budget of eight megabytes, which is the
real bound.

The launcher rule changed with it, recorded in `olm-launcher-ranking.md`.

Gates. Dry gate 0 findings, 23 accepted, 0 unknown. `check-dependencies.sh` clean. Units 1425
assertions all passing, and `test/ranking.lua` 50 checks.
