# Folder search in the app, step 1.4e

A design note for step 1.4e of `docs/PLAN-STANDALONE.md`, written and agreed with Milos on
2026-11-10, both questions below answered as proposed. Today the app answers every query naming a folder with "A folder search
comes with a later step". This step makes it answer the way the Lua list does, so no feature is
lost at the flip.

## What a person gets, the same as the Lua list

1. **A folder in the query.** A token holding a slash names a folder, split at its last slash.
   `downloads/` browses Downloads, `downloads/inv` searches beneath it, `~/x/`, `/Applications/`
   and a path under home all work, and the sigils and types in front still apply, `. ~/dev/ env`
   and `.pdf docs/ tax`.
2. **The folder aliases.** `dl/`, `docs/`, `dev/`, `apps/`, `root/` and the rest, the `roots`
   table of `config/filesearch.lua`, resolved first, then a literal path, then a path under home.
3. **A browse lists one level, newest first.** A folder first row reads `..`, subtitle "up to"
   and the parent, and choosing it goes up a level in place, the list staying open.
4. **A search beneath a folder** walks it, hidden files with the lone dot, pruned and gitignored
   folders with the bang, a type filtering by extension.
5. **Into Folder on l and Up a Level on h**, in the actions pane over a folder and while browsing,
   the two that are off the app's pane today. Each writes a query into the input field, the
   folder with a slash or the parent, so going anywhere is something a person could have typed.
6. **The empty states**, Empty folder, No such folder, Could not list that folder, Search failed
   and Timed out, worded as the Lua list words them.

## How it works

- **The same tools as the Lua side.** A browse runs `/bin/ls -1 -A -p -t`, which sorts by date
  itself, and a search runs `fd` with the very arguments `sources/walk.lua` builds, the first
  word as its pattern and every row handed to the shared search to rank. fd is what gives
  gitignore and the bang their meaning, which a walk of our own would have to rebuild, and using
  it keeps both lists finding the same files.
- **The resolution and the up query** are ported to Swift in `Folder.swift`, the resolver and
  `upQuery` from `engine.lua`. The grammar already reads a scope, so it is unchanged.
- **The query written into the field** is a new effect, `setQuery`, which the stage answers by
  putting the text in the field and asking again, the list staying up. Into Folder, Up a Level
  and the `..` row answer it.
- **The two gates go live.** `isFolder` answers from the row, `isBrowsing` from the query, so the
  actions pane lists Into Folder and Up a Level only where they do something.

## Two things Milos decided, 2026-11-10, both as proposed

1. **Where the app finds fd.** The app cannot ask Hammerspoon's dependency door, so something
   has to tell it the path. Proposed: the root adds the walker's resolved path to the file search
   share the bridge already writes, beside `roots` and `prune`, so fd is still declared once, in
   the plugin's manifest, and resolved once, by the door. Without it a folder search says Nothing
   can answer that, as the Lua list does without fd, and a browse still works, since `ls` is the
   system's. The other way, the app searching for fd on its own, would be a second resolver.
2. **The shadow of 1.3e.** fd answers in no fixed order and stops at its cap, so two runs of the
   same folder search can hold different files, and comparing them would log noise. Proposed: a
   browse is compared, since `ls` is ordered, and a folder search stays skipped with that reason.

## Left out, and where it goes

- A folder search's frecency, the row's bonus on the Lua side, is 1.4d with the rest of frecency.
- The subtitle fitted to the row's width, `fitDir`, stays the full folder in the app, as its
  search rows already are. The app's rows are cut by AppKit at the tail.

## How it is checked

- `olm-index-check` cases for the resolution and the up query over a stood in filesystem, the
  walker's arguments, and for a browse, a search beneath a folder, the `..` row, the effects of
  Into Folder and Up a Level, the two gates and each empty state.
- A hand trial in the app, then in the Lua native list to see nothing moved there.

Revised in the build, 2026-11-10. The note first had the resolution pinned by shared fixtures. The
Lua resolver asks the filesystem through `hs.fs`, which the fixture runner has no stand in for, so
the Swift port is pinned by the index check over a stood in filesystem instead, and the Lua one
stays covered as it was. A status beside the `..` row is a row of its own under it, as the Lua
list's status row is, since the app's list says a status only while it holds no row.
