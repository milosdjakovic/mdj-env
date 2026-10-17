# Plan, one search for every list

Written 2026-10-17. The goal is the one Milos stated. Search is a global fix in the algorithm,
it must not differ per list, and the chooser must have it. There is one matching algorithm and
one ranking engine, in `lib/chooser/match.lua` and `lib/chooser/rank.lua`, used by every
chooser list. No plugin or host matches or ranks rows itself.

The facts below were measured and surveyed on 2026-10-17. Recheck any citation before acting
on it, since the spoon moves.

## Why

Typing "settings" in BrowserTabs listed four Chrome tabs above the Settings row. None of them
contained the word. The shared fuzzy matcher accepted the letters scattered along long
addresses, each letter landing on a word start after a separator and earning the boundary
bonus. Those tabs scored 33 to 40 against a floor of 26.5, while "Settings" itself scored 88.
The Settings row was never scored at all, because the plugin appended it outside the ranking
by a keyword list.

A survey on the same day found eleven lists that match or rank on their own. They are the
launcher, browsertabs, filesearch, clipboard, emoji, obsidian, tmuxsessions, displayprofiles,
workspaces, processes, and the settings and vpn fixed menus. It also found four copies of the
rank loop. They are `_filter` in host/queryscope, `rankRows` in
`lib/chooser/providers/default/list/model.lua` which hard wires fuzzy, `filterOwnRows` in
host/actionpanel, and the launcher's `_rankCatalog`. Each list opted out because the shared
chooser lacked something it needed. The fix is to give the chooser what they needed, not to
let each list keep its own.

## The algorithm

Settled on 2026-10-17 after Milos tested the first two builds live. A row has a primary field,
its name, and secondary fields, the subtitle it shows and the keywords it declares, and a word
never matches across fields. Each query word matches at the strongest of five levels.

1. In the name, at the start of a word. lose in Loser.
2. In the name, in pieces, each the start of one of a run of consecutive words in one phrase.
   lose in LOcal SErvers, os in OLM settings, initials being every piece one letter.
3. In the name, 1 with exactly one edit, from four letters on, never on the first letter and
   never a wrong or extra last letter. dokcer and docekr in Docker.
4. In the name, inside a word, from three letters on. do never finds Window.
5. In a secondary field, 1 or 2 only, below every name level.

There is no scattered match and no relevance floor. Every word is required, so google chrome
finds nothing in a row titled Chrome, and the words' scores add. Past 256 bytes a field matches a
word only at a word start or inside a word, which keeps long bodies fast and retires the words
strategy. A row listed only through a keyword it does not show adds the matched phrase to its
subtitle while a query is typed.

## The row vocabulary

Plugins declare these, and only core applies them.

1. Several searchable fields per row, so a match cannot be assembled across a title and an
   address. Phase one built the first of them, the name as `title` or `filterText`, the
   subtitle, and `keywords`, a string or a list with a comma between phrases, stated at the
   head of `lib/chooser/rank.lua`. A description sentence is never a search term, since prose
   matches words nobody meant, set listing Wi-Fi through "see the current network". A row with several names of equal weight, a tab's title, host
   and address, is phase two.
2. Pinned rows that are never ranked or dropped. These are Back, Settings, Capture current
   arrangement, New snapshot and create note.
3. Rows that are the query itself and always survive. These are the calculator, convert,
   window size and wifi.
4. Tiers that order before score, so emoji sit above symbols.
5. A bounded bonus that reorders between equally good matches and never lifts a worse match
   over a better one. The users are tab recency, file frecency and the launcher's learned
   query memory.

A level may still declare one thing, that its field is not a search at all. Volume, the
caffeinate durations, the speedtest naming page and the clipboard prune page are input, not
ranking. Exact field names are decided in phase 2, and structural values are preferred over
loose quoted words.

## Phases

Each phase lands on its own branch, with an Opus builder and one Opus adversarial review. The
gates are the dry gate, check-dependencies and the units. Each phase gets a live load before
merge.

### Phase 1, the algorithm and one engine

The algorithm goes into match.lua and one rank engine goes into rank.lua. The four copies are
deleted and routed to `rank.apply`. No list changes how it looks, only how its matches rank.

**Done.** Built 2026-10-17 on `olm/search-algorithm`, reworked twice the same day, after the
adversarial review and after Milos's live test, awaiting a live load. `match.fuzzy` matches each
word in the name at a word start, in pieces, with one edit from four letters, or inside a word
from three, and otherwise in a secondary field at a word start or in pieces, with a step between
level sums derived from the weights. There is no scattered match and no floor. `rank.lua` builds
the fields from `title`, `subTitle`, `keywords` and `filterText`, adds a hidden matched phrase to
the subtitle, and gained `score`, `before`, `fieldsOf` and `present`. The copies in
host/queryscope, host/actionpanel, the default list model and the launcher's scoring loop are
gone, with `rank` handed to the three hosts as root data. The launcher hands its catalog over as
the name plus declared terms, so category, status and chord are not searched, and its memory may
lead unless the best row matches at a name word start and the pick does not. Keyword bags in the
manifests became comma separated phrases. This phase changes what lists show, not only their
order, and every list ranked by the engine reads names first. File paths fall under the 256 byte
bound, which phase three has to answer. After the review of 6237367 a word with no letter or
digit is a plain substring, the one edit applies to a word start only and never to the first or a
wrong last letter, descriptions are not searched, menu parents and the VPN settings words are
declared keywords, and prepared fields keep every measured list well under main's cost.
`decisions/olm-unified-search.md` has the measurements and the launcher catalog comparison.

### Phase 2, the vocabulary and the simple lists

The row vocabulary goes into rank.lua. The simple lists move onto it, which are the fixed
menus, displayprofiles, workspaces, tmuxsessions and the query rows. The BrowserTabs Settings
door is scored like any row with its keyword list deleted, which means `SETTINGS_WORDS` and
`settingsPlace` go.

**Done.**

### Phase 3, the lists with real scoring

The lists with their own scoring move onto the engine. They are browsertabs tabs, obsidian,
emoji, clipboard, filesearch and processes.

**Done.**

### Phase 4, the launcher and the gate

The launcher moves onto the engine, with its query memory feeding the bounded bonus. Then a
dry gate check fails any plugin or host that declares matcher false for a search level, or
that calls a matcher or sorts rows by a query itself.

**Done.**

## Decisions this overrules

Each is recorded in `decisions/olm-unified-search.md` with its reason when its phase lands.

1. The launcher's own ranking, in `decisions/olm-launcher-ranking.md` under "Leaving the
   ordering to the chooser atom" and the ties that never fired. The bounded bonus answers it.
2. The BrowserTabs opt out, in `plugins/browsertabs/AGENTS.md`, three fields never one string.
   Several fields per row answer it.
3. The FileSearch, tmuxsessions and obsidian opt outs. Pinned rows, the per word rule and the
   long body rule answer them.

The launcher rejections about hard bands, bare comparisons and unconditional memory stay. They
still bind the design of the bounded bonus.
