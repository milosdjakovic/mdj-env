# Olm one search for every list

Status. Planned. `Spoons/Olm.spoon/docs/PLAN-UNIFIED-SEARCH.md` holds the four phases and none
has landed. The algorithm and the row vocabulary are decided and the exact field names are left
to phase 2.

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
