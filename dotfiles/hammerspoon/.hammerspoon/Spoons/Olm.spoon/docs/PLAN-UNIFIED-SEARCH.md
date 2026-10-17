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

Contiguous first. A row whose field contains the typed text as a contiguous case insensitive
substring ranks above every row that only matches with gaps, and inside each tier the existing
scoring orders the rows. So typing se favours se over s then e.

Each word is scored separately. A query of several words requires every word to match and
sums their scores.

Fuzzy subsequence matching applies only to short fields. Long bodies, such as clipboard
contents and file paths, match by plain substring only. That keeps them fast and replaces the
separate words strategy rather than keeping a second algorithm beside it.

Typo tolerance and the relevance floor stay for the fuzzy part.

## The row vocabulary

Plugins declare these, and only core applies them.

1. Several searchable fields per row, with the best score kept, so a match cannot be assembled
   across a title and an address.
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

**Done.**

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
