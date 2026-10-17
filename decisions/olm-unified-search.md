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

Plugins declare a row vocabulary and only core applies it. Today that is `title`, `subTitle`,
`keywords` and `filterText`, stated at the head of `rank.lua`. Phase two adds several names per
row, pinned rows, query rows, tiers and a bounded bonus.

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

