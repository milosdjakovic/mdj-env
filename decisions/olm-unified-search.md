# Olm one search for every list

Status. Phase one is built on branch `olm/search-algorithm`, settled after Milos's live test on
names first, five levels per word and no scattered match, with one rank engine and its four copies
deleted, awaiting a live load. Phases two to four of `Spoons/Olm.spoon/docs/PLAN-UNIFIED-SEARCH.md`
are planned.

## Now

Search is one algorithm and one ranking engine, `lib/chooser/match.lua` and
`lib/chooser/rank.lua`, used by every chooser list. No plugin or host matches or ranks rows
itself, and a search that differs per list is a defect.

A row has a primary field, its name, and secondary fields, the subtitle it shows and the keywords
it declares, and a word never matches across fields. Each query word matches at the strongest of
five levels. In the name at the start of a word. In the name in pieces, each the start of one of
a run of consecutive words in one phrase, initials being every piece one letter. In the name at
a word start with one edit, from four letters on, never on the first letter or a wrong last one. In the name inside a word, from three letters on. And in a
secondary field only where one of its words starts with the query word, below every name level. There is no scattered
match and no relevance floor. A word with no letter or digit is a plain substring and adds no
level. Every word is required and the scores add. A row shows the subtitle its supplier gave.
Every query and every field is folded before it is lowered, Latin letters with diacritics to
their base letters, so resume finds Résumé, Milos's decision of 2026-10-17. At one level a word
found in the name leads the same level found only in a further name, unless it spells that name
whole, and at a level the name reaches a further name lends the row nothing, so where the word
sits in the name ranks the row.

Plugins declare a row vocabulary and only core applies it. Today that is `title`, `subTitle`,
`keywords`, `filterText`, `names`, `pinned`, `fromQuery`, `tier` and `bonus` on a row, and
`searchText` and `rowLimit` on a presentation or a scope, stated at the head of `rank.lua`.

## Rejected

- **Fixing the BrowserTabs Settings row with a keyword list that leads on a whole word.**
  2026-10-17. Built as commit 7fbf1e4 the same day. Milos rejected it because it is search
  special to one list, and the goal is that search never differs per list. It stayed in the tree
  only until phase 2 deleted it, together with `SETTINGS_WORDS` and `settingsPlace`, on
  2026-10-17 15:16. The Settings row is now scored through the injected matcher against its own
  title.
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

- **A scattered level, letters matched with gaps anywhere in a field.** 2026-10-17, built in
  both earlier phase one builds and removed after Milos's live test. It is what lets do find
  Local Servers through a d and an o picked out of its subtitle prose, and what the floor existed
  to hold back, and a floor tuned to keep typos cannot also cut scattered noise. Milos asked for
  tighter matching, one mistyped character or the start of words.
- **Searching the subtitle and every declared word as one string with the name.** 2026-10-17.
  The launcher glued title, subtitle, category, status, chord text, description and keyword bag
  into one filterText. Typing do on main listed 47 of the 232 launcher rows, every window command
  through do inside the category word Window, Wi-Fi through the initials of "disconnect, or join"
  in its description, and Local Servers through letters scattered in its prose. Fields are now
  searched apart, the name first, and a launcher subtitle is not searched at all.

- **Searching a launcher tool's description sentence as a declared term.** 2026-10-17, built at
  6237367 and found by the review. Prose matches words nobody meant. set listed Wi-Fi through
  "see the current network" and the listed six tools. Only the name, the declared keywords and
  the alias words are searched now.
- **An edit on the first letter, on the last letter, or inside pieces.** 2026-10-17, built at
  6237367 and found by the review. An inserted first letter let lose find Closet and Lock Screen
  by an edit, a wrong or extra last letter is only a shorter prefix, note finding Notifications
  and show finding Shortcuts, and an edit inside pieces let focs find Local Servers. One edit now
  applies to a word start match only, strictly after the first letter, never making the last
  letter wrong or extra.

- **Showing the matched hidden keyword in a row's subtitle.** 2026-10-17, built at 6237367 and
  removed by Milos after trying d41d57d live. He wants the subtitle to stay exactly as the
  supplier wrote it, typed query or not.
- **Matching a secondary field in pieces.** 2026-10-17, removed with it. A subtitle or a keyword
  is what a row also answers to, never a second name to spell out by initials, so dnd no longer
  matches Focus through do not disturb, only through the keyword dnd itself.

- **One field for both kinds of always shown row.** 2026-10-17, built at b9b187e as `pinned`,
  leading when the supplier gave it first and trailing otherwise. Rejected because the first row
  takes the highlight and Enter under a typed query, so a leading pinned door took Enter from the
  match. Typing work in Workspaces and pressing Enter opened New snapshot, and typing clip on the
  settings Plugins page popped Back. Replaced by `pinned`, which trails under a typed query, and
  `fromQuery`, which leads.

- **A lowered memo bounded at eight megabytes of bodies and copies.** 2026-10-17, built in phase
  one and replaced in phase three packet one. A clipboard history of a thousand bodies with a
  long tail came to fourteen megabytes, twice the budget with the copies, so the memo started
  over inside every keystroke and lowered the whole history again, 21 to 27 milliseconds a
  keystroke against 1.4 to 7.3 for the words strategy. Replaced by two generations bounded by
  entries.
- **Two generations bounded by count alone.** 2026-10-17, built in phase three packet one and
  replaced the same day after the review. Four thousand bodies a generation fixed the thrash and
  kept every body alive until four thousand distinct ones arrived, so an append accumulator
  growing one entry to 5.6 megabytes left 540 megabytes held after the entry was gone. A byte
  bound of 48 megabytes a generation was added beside the count.
- **Trying every occurrence of a word in a long field for a word start.** 2026-10-17, replaced
  after the review. ng over twenty bodies of a megabyte of words like running cost 405 to 455
  milliseconds a keystroke. An exact answer for a word shorter than three letters past the bound
  needs the whole body read per keystroke, and the cheapest exact form, a frontier pattern,
  measured 11.8 milliseconds a megabyte. Bounded at 256 occurrences instead.
- **Hiding held FileSearch rows whenever the query does not narrow the held one.** 2026-10-17,
  weighed for the review's fifth finding and not built. query.narrows fails on a backspace or an
  edit, so the list would blank to Searching on every backspace although the held rows are files
  of the same population matching what is typed. Hidden only when query.sameShape fails.
- **Restricting fzf to the file name with a slash delimiter and the last field.** 2026-10-17,
  tried in a shell. A directory line ends in a slash, so its last field is empty and every
  directory dropped. `--exact --scheme=path` instead.
- **Capping a long list in its supplier.** 2026-10-17. The emoji supplier keeps 100 rows before
  any ranking the shared search could do, so the cap decides which rows can be found first. A
  list of thousands hands the engine every row and declares `rowLimit`, which cuts after ranking.

- **The clipboard keeping its own words matcher behind `matcher = false`.** 2026-10-17, removed in
  phase three packet two B. It was right for the old fuzzy, whose cost ran query length times body
  length, and wrong once Milos decided search never differs per list. It kept a row when every
  word was a substring anywhere in a lowered haystack of title, preview and body, so it matched
  letters inside any word, and the preview made chars match every text entry, and it ranked
  nothing, so the newest match led however weak it was. The rows now name their body and paths,
  the newer leads only among equal matches, and the type prefix reaches the engine through
  `searchText`.
- **FileSearch ordering and narrowing its own rows.** 2026-10-17, removed in phase three packet
  two B. Its engine filtered the held rows between round trips by the injected words matcher over
  each row's folded full path, ordered a search by its own score, the text whole in the name, every
  word in it, a shorter path, with frecency under the gaps, and cut the list to two hundred before
  any of it reached the chooser behind `matcher = false`. The path made typing on keep rows a round
  trip for the same text never returns, since Spotlight matches names only, and the cap cut before
  ranking. The engine now hands every held row over, the shared search ranks them by the text
  `searchText` answers, frecency is the bonus and `rowLimit` cuts after ranking.

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

### 2026-10-17 12:55, names first, five levels, no scattered match

Milos tested the four level build live. Typing do listed every window command, since their
subtitle category Window holds do inside a word, Wi-Fi by initials across "disconnect, or join"
in its description, and Local Servers and others by d and o scattered through subtitle prose. He
asked for tighter matching, one mistyped character or the start of words, lose finding Local
Servers, an exact match at a word start first, Loser above Local Servers, and the main name
favoured over anything else, with the reason for a row visible somehow.

The main session set the design and it is built. A row has a primary field, the name, and
secondary fields, its subtitle and its declared keywords, and a word never matches across them.
Each query word matches at the strongest of five levels, worth 4 to 0. A, a name word starts
with it. B, it splits into pieces that start a run of consecutive words of the name in one
phrase, the best split kept. C, A or B with one edit, a substitution, an insertion, a deletion or
two neighbours swapped, from four letters on. D, inside a word of the name, from three letters
on. E, a secondary field at A or B only. Inside a level the position bonuses order, an earlier
word, a shorter name and fewer pieces winning. The scattered level and the floor are gone, since
the floor's only job was cutting scattered matches and every level left is a deliberate way of
naming a row.

Three choices inside the design. A camel hump offers a piece start without demanding one, so
DaVinci Control Panels answers dcp, which the strict reading made unreachable, and YouTube Music
answers ym, the case the four level build lost. Clause punctuation, a comma, a semicolon, a
question or exclamation mark, ends a phrase, so pieces never span "disconnect, or" and a keyword
string holds several phrases. A standalone symbol such as an ampersand is no word, so ps finds
Printers & Scanners.

The step. A word of n letters matched by any variant scores at most n plus one times eleven, the
one being an inserted letter, and more than minus 256 times 0.02, the near free gap before and
after it, which a short field pays at most its length of and a long one has capped. So rows at
one level sum differ by less than the sum over the words of that spread, the step is that sum,
and a higher level sum always scores higher.

Fields in core. `rank.lua` builds them. title is the name, subTitle is searched beside it, and
keywords, a string or a list, is declared and not shown, a comma ending a phrase. filterText,
when set, replaces the name and turns the subtitle off, which keeps menu search's parents
searchable and computed rows matching their query, and is how the launcher says its subtitle is
a category, a status and a chord. The launcher hands each catalog row over as its name plus a list
of terms, the keyword bag, a tool's description and its alias words. Every keyword bag in the
manifests became comma separated phrases, focus, do not disturb, dnd for one, which is the only
plugin change. A row listed only through a hidden phrase gets the phrase added to its subtitle,
in `rank.present`, while a query is typed, a copy so the supplier's row is never changed.

Results over the real catalog, 232 rows dumped through a temporary unit case then deleted. do
lists 9 rows where main listed 47, Dock, Docker, Docker Desktop, Move Down, Google Docs, Desktop &
Dock, Focus showing do not disturb, Local Servers showing docker, and Screen Time showing
downtime. Every window command and Wi-Fi are gone. Local Servers stays, at level E, because its
declared keywords hold docker, and dropping it would take Screen Time with it since downtime is
the same kind of match. That conflicts with the list the live test asked for and is left for
Milos. lose lists Local Servers by pieces and then four rows by one edit. One letter queries now
match only word starts, e 8 against 10 on main, i 19 against 20, o 15 against 42, a 38 against
40, s 70 against 94, d 33 against 35. Of 660 queries of two to four letters, 71 change their top
result against main. Most are two names matching at the same level now ordered by the shorter
name or the earlier word where main ordered them by incidental subtitle text, do giving Dock
before Docker, dd Desktop & Dock before Docker Desktop, sy System Settings before System
Information. The rest are real changes, md giving Move Down by pieces where main gave Device
Management, met Digital Color Meter where main matched Center on its chord text Meta. The full
list is in the commit report.

Cost. A typo query over launcher sized names measured about 37 microseconds a row and a two
letter query about 5, against about 34 for main's scorer on a 64 byte field. One edit over a
256 byte name is the dearest path, about 340 microseconds, which only a long title with a typo
reaches. Long bodies are unchanged, about 2.3 microseconds for settings against 1.9 for words.

Launcher memory. The gate reads the same, a remembered row may lead unless the best row matches
every word at a name word start and the pick does not. Its cases were rebuilt on the new levels,
Closet by one edit over Local Servers by pieces for lose, and the guard against a best score below
zero now uses a stand in matcher, since the new weights cannot produce one. Mutation, the phase
one tier gate fails the lower level and negative cases, removing the gate fails the word start
case, a proportion of the whole score fails the lower level and step cases, and the plain
proportion fails the negative case. Three older launcher expectations changed by the new rule
and say so where they sit. mail no longer lists Maps, map no longer lists Mail, and with nothing
remembered Mail and Maps tie on ma and keep their resting order.

Other order changes in existing cases. `test/cases/launcher-contributions.lua` reads a row's
keywords as a list whose first entry is the manifest's phrases.

Gates. Dry gate 0 findings, 23 accepted, 0 unknown. `check-dependencies.sh` clean. Units 1434
assertions all passing, and `test/ranking.lua` 50 checks.

Corrected 2026-10-17 13:15, see below.

### 2026-10-17 13:15, the review of 6237367

The cost paragraph above is wrong. It compared single calls on launcher sized names and called
them comparable to main, while whole lists measured far slower. The review measured 1500 menu
rows at 172 milliseconds against 55 on main for settings and 153 against 51 for inspect, 300 tab
titles at 61 against 16, and 200 names made of one letter words at 16 seconds for a 20 letter
query. The entry also listed the description sentence among the searched terms, which this
review removed.

Fixed in one commit, decided by the main session with Milos's intent, tight, one mistyped
character in between, word starts first, name first.

Symbols. A query word with no letter or digit, an ampersand, a plus, a minus, a percent sign,
matched nothing, so date & time, desktop & dock, touch id & password and every computed row whose
name is the query, 2 + 3, 100 - 20, 10 % of 50, dropped. Such a word is now a plain substring
anywhere in the row and adds no level and no score, and a word starting with symbols, $5, -5, #1,
matches on its word part with the symbols somewhere in the row. Every byte that is no letter,
digit or non ASCII letter now ends a word, and the middle dot, the triangle and their usual
neighbours count as separators and as phrase breaks.

The typo is tighter, see Rejected. lose now lists Loser, Local Servers, and Closet only because
lose sits inside its word, level D, which the design keeps for three letters and more. The
review's list asked that Closet not be listed at all, which conflicts with level D as decided, so
it is left at D for the main session.

Presentation. Two words in one hidden phrase show it once, a pieces match shows the phrase its
pieces started in, a long field the occurrence that matched, the phrase a row shows splits on the
same breaks the matching respects, and a phrase is left out of the subtitle only when the
subtitle holds it as whole words, so time is shown beside Sometimes.

Rows. VPN's settings row keeps its name and declares providers, backend, settings and config as
keywords instead of replacing its name. A menu item is named by its title and declares its
parents as keywords, so pieces never run from the title into a parent.

Cost. Every short field is now read once into its lowered text, its words, its words by first
letter and the phrase breaks between them, kept in a memo bounded at 20000 entries. A, B and C
all begin at a word whose first letter is the query's, so a name with none skips them. Pieces are
a memo over the query position and the word, bounded by the query length times the words times
the longest word. Measured on synthetic lists of the same shapes, every keystroke after the
first, main against the reviewed build against now. 1500 menu rows for settings, 30 against 69
against 3.6 milliseconds, and the first keystroke 18 while the memo fills. The same for inspect,
29 against 50 against 2.3. 300 tab titles for settings, 10 against 23 against 0.8. 200 names of
one letter words for a 20 letter query, 17 against 104 against 0.5, and names of a b c repeated,
the worst shape found here, 28 against 34 against 16. The reviewed build's 16 seconds did not
reproduce on these lists, its shape is unknown here.

The launcher comparison was rerun on the live catalog through a temporary unit case, deleted
after. do lists the same 9 rows, Local Servers still among them through its keyword docker. lose
lists Local Servers alone, the catalog having no Loser. One letter queries match e 8, i 16, o 10,
a 33, s 70, d 33 rows against 10, 20, 42, 40, 94, 35 on main. Of 660 queries of two to four
letters, 71 change their top result against main, the same list as before.

The launcher's lower level pick case is now Loes by two swapped letters over Local Servers by
pieces for lose, since Closet no longer matches lose by an edit. Mutation results are unchanged.

Gates are in the commit report.

### 2026-10-17 13:34, no shown keywords, secondary fields at a word start only

Milos tried d41d57d live and asked for two changes, both built. A row matched through a hidden
keyword no longer gets the phrase added to its subtitle, so every row shows exactly the subtitle
its supplier gave, typed query or not, and `rank.present`, the matcher's list of shown phrases
and the cases describing them are gone. And a secondary field, a subtitle, a keyword or an alias
word, now matches a query word only where one of its words starts with it, with no pieces, no
edit and nothing inside a word. Name levels A to D are unchanged.

On the live catalog, dumped again through a temporary unit case and deleted after, do lists the
same 9 rows, Dock, Docker, Docker Desktop, Move Down, Google Docs, Desktop & Dock, Focus through
do not disturb, Local Servers through docker, and Screen Time through downtime, each now showing
only its own subtitle. dnd still finds Focus through the keyword dnd itself, no longer through the
initials of do not disturb. 71 of 660 two to four letter queries change their top result against
main, as before.

### 2026-10-17 13:50, run together phrases, the phrase bonus and the keyword rules

Milos asked for four things and three are built. A declared keyword or alias phrase also matches
a query word that is a prefix of the whole phrase with its spaces taken out, counted from the
phrase's start, so nomore and nomo find "no more" and donotd finds "do not disturb", while ore and
otdisturb find nothing and nothing runs across a comma. It is the same level as any secondary
match, applies to declared keywords and alias words only and not to the subtitle a row shows, and
reads phrases from the prepared field memo, so it costs one prefix compare per phrase.

The phrase bonus. A query of two or more words whose words all start words of one secondary
phrase, in order, ranks above rows whose words are spread across phrases or fields at the same
level sum. The scores inside a level sum spread less than one spread, the sum over the words of
the word length times eleven plus 256 times 0.02. The bonus is one spread and the step between
level sums is now two spreads, so a row with the bonus leads every row at its level sum and never
reaches the next one. Words still match on their own, focus disturb finds Focus with focus in its
name and disturb in a keyword. A case proves the bonus decides, the spread row scoring higher
without it, and fails when the bonus is switched off.

The rules for keywords are now in the olm-plugin skill, PLUGIN-AUTHORING.md and
PLUGIN-CONTRACT.md. The fourth item, an audit of every declared keyword list, was written as a
proposal outside the repository and nothing in the manifests was changed by it. Over 54 lists in
14 manifests it proposes removing 150 phrases and adding 79, most removals being title words,
plurals and generic words, and it moves the search words of nine descriptions into keywords. It
proposes taking docker out of Local Servers, which is why do lists that row beside Docker.


### 2026-10-17 14:03, the keywords audit applied

The keywords audit was applied on Milos's approval, with one exception. Docker stays on Local
Servers, so do still lists that row beside Docker, and the row now reads dev server, port, kill
process, node, docker, container. Every other proposed value went in as written. Over 54 lists in
14 manifests, 54 keyword values were changed, 12 tool rows, 39 settings panes and 3 clipboard
commands, and no description or detail was touched. The one test that asserted an old value, the
Wi-Fi pane keywords in launcher-contributions, was updated to the new list, since the audit
plainly removed internet and network there. The inventory golden was not rerun and carries no
keyword lines.


### 2026-10-17 15:06, phase two packet one, pinned, tier and bonus

`rank.lua` now applies three row fields. pinned true keeps a row out of scoring and never drops
it, leading when the supplier gives it before every unpinned row and trailing otherwise, so a row
that is the query itself is pinned by its supplier rather than given filterText equal to the
query. tier, a number, orders before how well a row matched. bonus, clamped to zero to one, orders
only rows the search calls equally good, the same tier, level sum and phrase bonus, ahead of where
a word landed. It is a structural group from the matcher and not a distance between scores, so
it is not the hard band `decisions/olm-launcher-ranking.md` rejects.

`M.before` is the one comparison, tier, then level sum, then phrase, then bonus, then score, then
index. The phrase bonus is folded into within, so fuzzy now answers it as a fifth value rather
than rank reading one spread back out of the score. A matcher answering only a score gives no
level, and for its rows only an equal score is equally good, so its score decides before a bonus.
The score steps two spreads per level sum and one for the phrase, so ordering by level and phrase
first is what the score already did, and a case over fourteen rows, ten queries and three matchers
proves rows setting none of the fields keep the old order exactly. Every case in
`test/cases/rankvocabulary.lua` failed under a mutation switching off the feature it proves.

### 2026-10-17 15:16, phase two, the simple lists on the vocabulary

The settings page, the VPN provider page, DisplayProfiles, Workspaces, TmuxSessions, the query
rows and the BrowserTabs Settings row moved onto `pinned`. A level whose field is a search
dropped matcher false and its hand filter, and its supplier now returns every row. Back, the
capture and new snapshot rows, the waiting placeholders and the answer rows of Arithmetic,
Convert, WindowSize and Wifi are pinned instead of faking a match through `filterText` or
`filterText = ""`. Rename, capture, new snapshot, delete confirms and the Workspaces app level
keep matcher false, since their field is input or a confirm.

The query scope rewrapped every row with `filterText` set to the query, and read why, its only
purpose was to keep rows the scope had already filtered from being scored a second time against a
query carrying the alias. That is exactly what pinned says, so the rewrap and the two error rows
beside it are pinned now. The launcher's own copy of query rows is pinned the same way and no
longer copies a row's filterText.

BrowserTabs deleted `SETTINGS_WORDS` and `settingsPlace`. On an empty query the Settings row
trails the tabs as before. Once something is typed it is one more candidate in the tab scoring,
through the same injected matcher against its own title, with no recency, merged by score and
dropped when it does not match, so a tie leaves it after a tab. The tabs keep their field by
field scoring until phase three.

Two behaviour changes follow and are meant. A Back row that used to vanish while typing, through
an empty filterText, now stays, and Workspaces never shows an empty list since New snapshot is
pinned, so the No layout matches row is gone. TmuxSessions lost its hand written word match and
the settings level lost its opt out, since the shared search reads the window name first and the
session second.

### 2026-10-17 15:49, two kinds of always shown row, and a comparator that cannot cycle

An adversarial review of b9b187e and 39ccf34 found four things. A pinned row that led the list
took the highlight under a typed query, since the list model puts it on row one, so Enter in
Workspaces on work opened New snapshot and on the settings Plugins page clip popped Back.
`M.before` was not a strict weak ordering once graded and ungraded entries met, a and b graded
at one level with a carrying the bonus and the lower score, c ungraded between their scores,
giving a before b, b before c and c before a. Status and prose subtitles were searched in the
lists that moved, so apps or studio matched every layout through "Applies here, 3 apps, taken on
Studio". And several docs still described filterText set to the query.

Milos decided two kinds. `pinned` keeps its meaning of never scored and never dropped, keeps the
supplier's place on an empty query, so Back still leads a fresh page, and under a typed query
trails every ranked row in supplier order wherever it was given. `fromQuery` is a row made from
what was typed, never scored or dropped, and under a typed query it leads in supplier order. A
row setting both is fromQuery. The calculator, Convert, WindowSize, the launcher's query rows,
the query scope's rewrap and the VPN waiting row are fromQuery. The scope's No match row names
the typed rest, so it is fromQuery, and the row for a scope that raised names only the scope, so
it is pinned. The Wifi rows the review named stay pinned, because none of them is built from the
typed rest, and Not connected sits above the networks, where leading would take Enter from the
network that matched. DisplayProfiles Profile is gone is pinned to match Layout is gone.

The comparator maps every entry to one fixed tuple and compares it lexicographically, tier
ascending, a match key descending, the phrase descending, bonus descending, score descending and
index ascending. The match key is the level sum for a graded entry and the score for an ungraded
one, which never has the phrase. A fixed tuple per entry cannot cycle. An ungraded list still
orders by score before bonus, and rows setting no field still rank as score then index did, which
the fourteen row case keeps proving. A case with the cycle above and a randomized mixed list of
thirty six entries checked over every triple fail under the old comparator.

Workspaces, DisplayProfiles, the settings top level, the VPN provider page and the TmuxSessions
settings door and providers now search the title alone. The settings row constructor had lost its
filterText parameter to pinned in 39ccf34, so the Plugins page searched the state words under
each plugin, and it carries filterText again with pinned set by a small helper. A tmux window's
session subtitle stays searchable, since it is what the row is.

### 2026-10-17 18:33, phase three packet one, names, searchText, rowLimit and the memo

Milos decided three things for phase three before it started. Recency and use history only
order matches of the same level, so the clipboard's newest first and Obsidian's remembered
notes first are overruled and both feed the bounded bonus. Processes rank by match first, and
the group only orders equal matches. The phase is one branch, `olm/search-lists`, with one live
round.

Packet one builds what the six lists need, on `olm/search-lists` from main at 3c9b629.

`names`, a row field, a list of strings never shown. Each is matched at name levels A to D
exactly like the title, or like filterText when the row sets it, since names add to the primary.
Each query word takes its best level across the primary and the names and, at that level, its
best score, then the words add as before. So github pull finds a tab titled Pull request whose
host is github.com, while one word never spans two names and pieces stay inside one. The combine
rule is the maximum per word and never a sum, so an extra name that matches no better changes
nothing and a row never scores higher for having more names than an equal row with fewer. Every
name is bounded exactly as the title is, a long one by the 256 byte rule, so the spread the step
is derived from holds whatever the number of names. The phrase bonus is unchanged. A one string
strategy, words or substring, never sees names, since joining a body of megabytes into one
string on every key is the cost the shared search exists to avoid.

`searchText`, a presentation field, a member spec resolving to a function from the raw field
text to the text the engine ranks by. A scope declares it the same way under `registry.scope`.
An empty answer, or one of spaces only, keeps the supplier's order, the same as an empty query,
and an answer that raises or is not a string does the same with a console line. The supplier
still gets the raw text. The registrar refuses anything but a member spec resolving to a
function, through the same loop every presentation member goes through, and host/queryscope
refuses a scope's that is not a function.

`rowLimit`, a presentation and scope field, a positive whole number, the most rows shown that
are neither pinned nor fromQuery, cut after `rank.apply` places the kept rows, never cutting a
pinned or fromQuery row, on an empty query too. It was needed. The default provider's list
model and its render are bounded to the visible window, `visibleRows` answers ten rows and an
icon is resolved only at paint, but `_rebuildList` styles every ranked row through
`hs.styledtext.new`, title and subtitle, and the legacy provider draws an icon for every row. A
plain Lua build of the 5648 emoji rows through rank, the style step with a stand in and the
model measured the Lua side at 0.06 milliseconds to rank an empty query, 10 to 15 for a typed
one, 2.7 to copy every row and 0.04 for the model. `hs.styledtext.new` measured 16.8
microseconds a call over 2000 calls inside the running Hammerspoon, so an empty emoji query
would cost about 190 milliseconds of styling a keystroke and s, matching 2759 rows, about 93.

Both travel beside the matcher. The stage hands them to `setMatcher` as a second argument before
every show, so a presentation declaring neither clears them, and `matcher()` answers them as a
second value. The default and legacy providers rank with them, the stage's highlight hold ranks
with them on an empty field too so it never finds a row the limit cut, and the query scope ranks
a scope's rows with the scope's own. The action panel ranks only its own rows and takes the
search off the instance while it is open, since its verbs do not speak a tool's grammar, and
hands it back as it leaves. The picker contract keeps its names and arities.

The memo. The eight megabyte budget thrashed, see Rejected. The memo is now two generations of
at most 4096 lowered bodies each, a body found in the older one moving back to the current, so
the live set is never lowered again after the first keystroke and a body no list asks is gone
after two turns. A word with no word start in a long body tries every occurrence, and that loop
now answers the common ASCII case inline. Measured by `Spoons/Olm.spoon/test/search-timing.lua`
over a thousand bodies, 89 percent of 80 to 980 bytes, 10 percent of 4 to 64 kilobytes and 1
percent of about a megabyte, 14 megabytes in all, a keystroke after the first, in milliseconds.

| query | words | fuzzy, old memo | fuzzy, now |
|---|---|---|---|
| c | 1.5 | 21.9 | 3.1 |
| cho | 1.4 | 21.6 | 3.9 |
| chooser | 1.5 | 23.1 | 3.2 |
| settings | 7.0 | 27.0 | 8.3 |
| hello there | 6.4 | 26.5 | 8.1 |
| zebra | 1.8 | 21.0 | 2.9 |
| quick fox | 1.6 | 21.8 | 4.2 |
| ump | 1.5 | 46.7 | 20.0 |

The old column was measured with each body as the row's name, the same path a name takes. Every
query but one is within about twice to under three times the words strategy. ump is the one
outlier, a word that sits only inside words, so every occurrence is tried for a word start
before the first is kept, the best occurrence rule phase one decided, which this synthetic text
makes dense since jumps is one word in twenty. The first keystroke over the history costs 48
milliseconds while every body is lowered and every short one prepared, where the clipboard's own
lowering of the same bodies took 20. No body is truncated.

Cases in `test/cases/searchfields.lua`, `test/cases/stage-search.lua` and a block in
`test/cases/actionpanel.lua`. Every mutation tried failed at least one case. Summing names
instead of taking the best failed 2, ignoring names 10, joining names into one 2, dropping names
under filterText 2, not applying searchText 1, ranking an empty answer 4, the registrar taking
any searchText 4 and any rowLimit 4, the limit cutting kept rows 2, the limit not applied after
ranking 2, the stage passing no search 7, the hold ignoring it 2, the provider ignoring it 5, the
scope ignoring it 1, the scope admitting any searchText 1, the panel leaving the search on 1 and
never restoring it 1. A default limit for rows setting nothing failed the unchanged order case in
`test/cases/rankvocabulary.lua`, which with a new case over an empty search proves rows and
searches setting none of the new fields rank exactly as before.

### 2026-10-17 18:52, phase three packet two A, BrowserTabs, emoji, Obsidian and Processes

Four lists moved onto the engine on `olm/search-lists`, one commit each. Each supplier now hands
every row over in its resting order and reads no query, each deleted its own matching and
ranking, and each presentation and scope dropped its matcher, so all four inherit the shared
search. Every recency or group order became a `bonus` scaled into zero to one, the first place at
one and the last at one over the count, never a tier, since Milos decided recency and use history
only order matches of the same level and Processes rank by match first.

BrowserTabs. A tab filters on its title, since its subtitle is a status like line of browser,
Arc's group and host, names its host and full address, and declares its browser as a keyword. The
bonus is the tab's place among the tabs this tool opened that are in the listing, counted over
the whole listing, a tab never opened here earning nothing. `matchedTabs`, `searchFields`,
`bestFieldScore`, `namesBrowser`, `recencyBonus` and its two constants are deleted. The browser
name rule could not survive as it was, because it read the query and a row is built before the
query is known. It became a keyword, which needs no query. A keyword matches only at a word
start, so far still finds no Safari tab, which is what the gate was for, and it ranks below every
name, so a page named after a browser still outranks that browser's tabs. What is lost is the two
letter minimum, one letter matching a browser like any keyword. The rows explaining an empty list
are pinned, and with no tabs the Settings row after them is pinned too, since they point at it,
so the empty states read as they did. `tabRows` ignores its query, so the integration harness's
`rows` command in `test/agent.lua` now answers the resting order rather than a ranking. `run.sh`
reads it as the precondition of every round that types a query, so every case but `no_query`
and the cases that never open a tab will report that the intended tab was not the top row, and
`existing_user_tab` asks it for exactly one row and will always skip. The tool itself is not
what changed for them, the harness reads a ranking the supplier no longer makes, and it was left
untouched as instructed until its `topRows` ranks through the shared engine.

Emoji. The tags and the category are not stored apart in `data.lua`, only folded into `k` with the
name and aliases, so nothing was regenerated and the row build reads the words back out of `k`
after the name, each its own comma separated phrase with an ampersand joining its neighbours, so
smileys & emotion stays one phrase. An emoji is tier zero and a symbol tier one. The rows are built
once per load. `MAX_RESULTS` left the supplier for `rowLimit` 100 on the presentation and the
scope, cut after ranking. A typed query over the 5648 rows measured 9 to 15 milliseconds in plain
Lua. An exact alias no longer jumps to the top and a token inside a word no longer counts, which is
the shared rule.

Obsidian. A note row is titled by its name with its folder, or its vault, as the subtitle, an
excluded note is tier one and a note opened here carries its recency bonus. New note and Search
notes are pinned, and so is the row saying no vault is known. The word filter, the subsequence
gate, the incremental narrowing and the 300 passer cheap rank are deleted, since nothing else
needed them. The resting rows are built once per scan and again after a pick. A folder word now
matches at the start of a word of the folder and no longer as letters in order through the path.

Processes. A row filters on its title, the name with its ports after a colon, so a port matches at
a word start there and needs no names. Its keywords are the framework label, the runtime, the
command, the working directory's folder name and a container's name, never a live figure. The pid
and the status are no longer searched. The bonus is the row's place in the scan's order, recorded
when the scan lands, so a heat sort changes what an empty field shows and not what a typed query
prefers. Keep it running and Stop anyway are pinned.

Cases in `test/cases/browsertabs-settings.lua` and the new `test/cases/searchlists.lua`. Every
mutation tried failed at least one case. For BrowserTabs no bonus failed 3, an inverted bonus 3,
no filterText 2, no names 3, no keyword 2, the empty rows unpinned 2, the door unpinned in the
empty state 1, the door pinned beside tabs 3 and the door without filterText 2. For emoji no tier
2, no keywords 3, no ampersand join 1, no recents 5, recents twice 2, a supplier cap 5, no row
cache 1, matcher false 1 and no scope limit 1. For Obsidian no tier 2, no bonus 2, an inverted
bonus 1, either action row unpinned 3 and 4, the no vault row unpinned 1, no recency order 2, no
resting sort 1 and matcher false 1. For Processes no bonus 2, the group as a tier 2, the bonus from
the order in hand 1, filterText off 2, no keywords 4, the full path as a keyword 2, no container
1, the confirm unpinned 2 and words back 1.

### 2026-10-17 19:14, phase three packet two B, the clipboard, FileSearch and two corrections

The last two lists with their own scoring moved onto the engine on `olm/search-lists`, with an
emoji correction and the BrowserTabs harness, one commit each.

Clipboard. A history row filters on its one line title, since its subtitle is a kind, an age and a
count, names its full text body and every file path, and carries its place in the store as a
bonus, newest one and oldest one over the count, so the newer leads only among equal matches. A
first line match therefore leads a newer entry that matches only inside a word of its body, while
a body word at a word start matches at the same level as the title and the newer leads there. The
preview line is not searched, since it reads 1200 chars or URL and made chars match every text
entry. The type prefix stays the clipboard's grammar, the supplier still reads it to keep only that
kind, and the presentation's `searchText` answers the rest. The manage history page shares the
presentation and swaps inside it, so the matcher the stage writes before a show cannot follow it,
and `searchText` answers nothing on that page, which keeps its rows in prune.lua's order whatever
is typed, what matcher false did. `haystack`, `hayCache`, the words matcher, matcher false and the
cache drop in `UI.entryChanged` are deleted. An appended entry is searched by its new text with
nothing dropped, since the row names its body afresh and the memo is keyed by the string the
append replaced. Measured by `Spoons/Olm.spoon/test/search-timing.lua` over the same thousand
bodies and fourteen megabytes, building the rows as the supplier does minus the icons and ranking
them, a keystroke after the first cost 3 to 11 milliseconds, against 1.4 to 7 for the words
strategy over lowered bodies, and 20 for ump, a word found only inside words.

FileSearch. The sources still fetch by the whole parse and the engine still decides recent, keep
typing, browse or search and dispatches round trips, but it hands every held row over, up to the
retain cap of 2000, unfiltered and in the order its source gave. `_filter`, `_order`, `allWordsIn`,
the injected matcher, `displayCap`, `frecencyWeight`, the folded `lower` path field and matcher
false are deleted. The shared search ranks the held rows by the free text `searchText` answers from
the engine's own parse, so `.js ~/dev/ foo` ranks by foo and a browse or a bare type keeps the
source's order. Narrowing between round trips is now that ranking over the held rows. Whether a
round trip is needed is still decided by shape alone, `query.narrows`, the truncation flag and the
narrowable flag, never by matching a row, so no yes or no matching step was needed. A file row
filters on its file name and carries frecency, used over used plus two, as its bonus. `rowLimit`
200 on the presentation and the scope replaces the display cap, after ranking.

The full path is not a name and not a keyword. The old narrow searched the folded full path while
Spotlight, which answers every unscoped query, matches names only, so typing on kept rows a round
trip for the same text never returned, and a folder word as a name would tie with a file actually
called that. A row fzf or the walker found through its folders, or fzf by scattered letters, is
now dropped by the shared search, the rule every list has.

Status, help and up rows are pinned. A status row also trails the files whenever the engine
reports one, not only when it holds none, and the engine reports searching as soon as it arms the
debounce. Without that, the held rows from the last query ranked by the new text often kept none,
so every round trip would have said no results until the answer landed, and a one or two letter
query matching no recent file would have said no results rather than keep typing. That is a
visible change, a Searching or Keep typing row trailing the files that do match while it applies.
Building the rows for 2000 held paths and ranking them measured 5 to 9 milliseconds a keystroke in
plain Lua. Fitting each new folder to the row is measured against the live instance and is not in
that number, so the budget is now taken once per list rather than once per row, and a new folder
is fitted once per open and cached as before.

Emoji, a correction. Packet two A read an emoji's shortcode aliases as keywords, below any name
match, so grin listed grinning face above the beaming face whose shortcode it is. Milos corrected
that aliases are names, what a person types as the emoji's name. Each alias is now a name, tags and
category stay keywords, and grin leads with the beaming face, its alias matched whole scoring
above grinning face, whose name only starts with it. A symbol's a field is a synonym line or its
category, so a symbol declares no names.

BrowserTabs harness. `test/agent.lua` ranks the presentation's own rows, the settings door
included, through rank.apply with the shared fuzzy matcher and the presentation's search, loading
`rank.lua`, `match.lua` and the manifest from the spoon. No case's expectation changed, since
every typed round types a token unique to its own tab and `no_query` reads the resting order. The
harness was not run.

`words` stays in `match.lua`. No list or manifest names it, and `test/search-timing.lua` measures
the shared search against it and `test/cases/match.lua` covers it while it is exported.

Cases in `test/cases/clipboard-search.lua`, `test/cases/filesearch-search.lua` and
`test/cases/searchlists.lua`. Every mutation tried failed at least one case. For the clipboard no
bonus failed 2, an inverted bonus 2, no filterText 1, the preview as a name 4, the prune page
ranked 1, the prefix left in the search text 3, the supplier filtering by the query 5 and no names
6. For FileSearch no filterText 3, no bonus 3, frecency as a tier 4, a status only when no file is
held 4, the status row unpinned 5, the up row unpinned 1, the help rows unpinned 1, searchText
answering the raw query 6, no searching status while the debounce waits 2, the display cap back
in the engine 1, the engine filtering by path 3 and no preference 2. For emoji no names 3, a
symbol's synonyms as names 1, the aliases left among the keywords 1 and the aliases joined as one
name 1.

### 2026-10-17 20:00, phase three reworked after the adversarial review

Every finding of the review of e3989a6 was answered on `olm/search-lists`, in four commits.

The memo. The long field memo keeps its two generations of 4096 bodies and now also turns a
generation once its bytes pass 48 megabytes, counting the body, any folded text and the lowered
copy, since the memo is what keeps a body alive once no row holds it. The review's probe, an
append accumulator growing one entry to 5.6 megabytes with a search between appends, held 540
megabytes after the entry was dropped and now holds 31.7, and 32 at 400 appends, so it no longer
grows with them. The measured history, fourteen megabytes and twenty eight counted, fits in one
generation, so the thrash numbers of 18:33 hold, 2.2 to 8.9 milliseconds a keystroke after the
first for every query of that table.

The occurrences. A long field tries a word at 256 places at most. Past them with no word start
the word is read as found inside a word at its first place, which keeps the row for a word of
three letters or more in a name, at the inside level, and does not match a shorter word or a
secondary field. So which rows match is unchanged whenever a word start lies within the first 256
places, and a word start later lands at the inside level. The review's probe, ng and ing over
twenty bodies of a megabyte, went from 405 to 455 milliseconds to 1.0 after the first keystroke,
and ump over the fourteen megabyte history from 20 to 7.

Accents, Milos's decision of today. The matcher folds Latin-1 and Latin Extended-A letters and
the Romanian comma letters to their base letters, upper case to upper case so a camel hump
survives, ß to ss, and drops combining marks, the decomposed form macOS gives file names, for the
query and every field, before lowering. Only a text holding one of six lead bytes is folded,
found by plain byte scans, since a pattern for any byte above 127 measured near six milliseconds
a megabyte. The query is parsed once per distinct query rather than once per row.

Titles before further names. At one level a word found in the title or filterText leads the same
level found only in a further name. fuzzy answers a sixth value, how many words came only from
further names, rank.lua compares it after the phrase and before the row's bonus, so a recent tab
never lifts over one whose title holds the word, and the score folds it in, one spread a word,
with the phrase bonus inside the score widened to the words plus one spreads and the step to
twice that. within still carries the phrase as one spread, so a row with no names answers the
within it always did and the launcher's nearness reads the same proportion. face now lists person
facepalming before oncoming fist, flag lists the flags before carp streamer, github pull lists
Pull request github before the tab on github.com. A further name the word spells whole counts as
the name, which this entry adds to the review's rule so Milos's emoji correction of 19:14 still
holds, grin listing the beaming face whose shortcode is grin before grinning face. Milos should
confirm that refinement.

The ampersand. The run together key of a phrase drops a token that is only ampersands, and the
key with it is kept beside it when they differ, so smileysemo and smileys&emo both find smileys &
emotion. A consequence worth knowing, foodd now finds every food & drink emoji, as fooddrink
typed run together.

FileSearch. The root hands the engine keeps, from the shared matcher every surfaced plugin is
handed and the surface's new searchName, and the engine fills the retain cap with rows the search
keeps first, each part in the source's order, and reports nothing found when a round trip brought
back rows the search keeps none of, so the list says No matches rather than nothing. The root asks
the matcher how many letters a word needs to be kept inside a word, three, rather than restating
it, and hands that to Spotlight and the walker. Spotlight asks a shorter word with LIKE[cdw] "w*",
word based, measured through NSMetadataQuery over one folder at 28 names for ab against 660
anywhere and 6 for ng against 4326. The walker hands a short first word to fd as a word start
pattern with its case stated inside it and matches later words on the file name, not the path.
fzf is asked --exact --scheme=path, each word whole and the file name ranked first. While a round
trip for another population is pending, a scope, a type or a sigil changed, only the pinned
searching status shows, and over the same population the held rows stay, see Rejected for why
not query.narrows.

Clipboard and Obsidian. Both presentations declare rowLimit 200, and Obsidian's scope too, so an
empty field now shows the newest two hundred entries or notes. The clipboard caches each entry's
row, weak keyed, rebuilt on UI.entryChanged, on every open and when media lands, since an icon or
a badge may then differ, when its batch position moves, and when its age text would read
differently, at the time the new util.relTimeChanges answers, so the subtitle is always what a
fresh build would say. Only the bonus is written per keystroke. In plain Lua the ranking dominates
and a keystroke measured about the same, 2.4 to 9.2 milliseconds, the saving being the provider's
styling of eight hundred fewer rows.

Docs. docs/PLUGIN-CONTRACT.md no longer uses the words matcher as its example or says three
plugins want it.

Cases in test/cases/match.lua, searchfields.lua, filesearch-search.lua, the new
filesearch-sources.lua, clipboard-search.lua and searchlists.lua. Every mutation tried failed at
least one case. No fold failed 10, the query unfolded 2, the ampersand kept 3, no occurrence bound
3, no byte bound 2, no further name count 3, rank ignoring it 1, no whole name refinement 3, the
score keeping the old step 1, no kept first 2, no nothing found 1, held rows never hidden 1,
narrows in place of sameShape 1, Spotlight asking anywhere 1, fzf scattered 1, the walker fixed 1,
entryChanged keeping the row 3, an age that never refreshes 1, an open keeping rows 1, a stale
bonus 1 and no cache 4.

### 2026-10-17 20:19, a copied file answers only to its file name

Milos's decision. A clipboard file entry named its full text body and every file path, so the
words of the folders a file sits in matched it, and support listed eight screenshots saved under
Application Support. A file entry now names only the last part of each path, its file name, and
never its folders or its body. A text or url entry still names its whole body. The case in
test/cases/clipboard-search.lua adds a file entry under Library and Application Support whose
body also names those folders, and support, library and the shared folder find nothing while a
file name and a part of one still find it. Naming the paths again fails four of its checks.

### 2026-10-17 20:20, a further name lends nothing at a level the name reaches

The 20:00 rework said face listed person facepalming before oncoming fist, and its case passed,
yet on the live emoji data face put person facepalming first, ahead of face with tongue, face
exhaling and face vomiting. The case was built by hand with the facepalm row alone against the
fist, never against a row whose name starts with face, so it could not see the cause. Ranking the
real rows the provider builds from data.lua showed every one of them at level four with no
further name word counted, the title reaching the start level in each, and the facepalm row ahead
by a tenth of a point. Its score came from its shortcode, not its name. matchNames took the best
score at the row's level across the name and every further name, and face starts facepalm, a
field of eight letters where the word fills the start and leaves little trailing gap, which beat
face at the start of the longer face with tongue. So the rule that a title leads a further name
held for the level and leaked through the score. The same leak put grinning face before grinning
cat for grin, its shortcode grinning lending it a shorter field.

The fix is in matchNames. The name and any further name the word spells whole form one group,
every other further name the second, and the second answers only when it reaches a level the
first does not, at the cost of one further name word as before. At a level the name reaches, the
name's own score answers. Rows without names take the path they always did. On the real rows
face now lists face exhaling, face vomiting, face in clouds and face with tongue, with person
facepalming after every name starting with face, flag lists the country flags with carp streamer
after every name holding flag, and grin lists the beaming face, grinning cat and grinning face.
The hand built rows in test/cases/searchfields.lua are replaced by the real rows, built through
the provider over a stand in hs, and searchlists.lua now expects grinning cat second. Reverting
the fix fails five checks.
