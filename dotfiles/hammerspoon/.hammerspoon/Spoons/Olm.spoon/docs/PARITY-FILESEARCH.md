# File search parity, step 1.5

The written list step 1.5 of `docs/PLAN-STANDALONE.md` asks for, every feature of the Lua file
search, read from `plugins/filesearch/manifest.lua`, its `README.md`, its `AGENTS.md`,
`chooser.lua`'s status rows and `config/filesearch.lua`, on 2026-11-11. Each line says where the app
stands. A line is ticked only once it is tried in the app by hand, and the piece opens the app as
the daily path only when every line is ticked, rule 9. The launcher's slash scope stays on the Lua
file search until stage 3, as 1.2 says, so it is listed and left out of the flip.

Where the app stands, read from the code on 2026-11-11.
- **built**, the step that brought it, so its hand trial is the step's and this list tries it again.
- **gap**, the app does not do it yet, with what would close it.
- **check**, the code says it should hold and nothing has tried it yet.

Ticked on 2026-11-12, from Milos's three rounds of hand checks in Olm.app on step 1.5's branch.

## Opening and the list

- [x] Hyper and semicolon opens file search. built, 1.3e, while the piece serves.
- [ ] The launcher row, a Plugin row with the keywords find, folders, locate, finder search. Lua,
  stage 3.
- [ ] The slash and a space in the launcher scopes to file search, deleting it steps back. Lua,
  stage 3.
- [x] Nothing typed shows the recent list, the 40 files changed in the last 7 days, the 8 used last
  leading it. built, 1.3, 1.4d.
- [x] A search answers from the first letter. built, 1.4g.
- [x] At most 200 rows, then a row of more. check.
- [x] A title cut in the middle, so the extension stays. built, 1.3.
- [x] The subtitle, the folder, fitted to the row by dropping whole folders from the middle,
  `util.elideDir`, so the head and the folder holding the file stay. built, 1.5, `PathFit` in
  `app/Sources/OlmLook/PathFit.swift` over the row's room, geometry.lua's `textBudget`, measured a
  character at a time in the subtitle's font as the Lua list measures, the `..` row's `up to` too.
- [x] Every empty state a row with an icon, a title and a line saying what to do, `chooser.lua`'s
  `STATUS`, No matches with Try fewer words, or a bang for pruned folders, Empty folder, Timed out,
  Could not list that folder. built, 1.5, the manifest's `statuses`, each a `StatusLook` the stage
  draws as an inert row, never chosen, previewed or acted on, with the Lua fallback, Nothing to show.
- [x] A question mark alone shows the grammar, nine inert lines, `chooser.lua`'s `HELP`. built, 1.5,
  found while closing the line above.

## The grammar

- [x] Words match anywhere in the name, every word required. built, 1.3.
- [x] A dot attached to a known type filters by it, `.pdf`, `.img`, `.js report`. built, 1.3.
- [x] A type naming a bundle, `.app`, lists every app. built, 1.4h.
- [x] A lone dot includes hidden files, and with nothing else typed asks for something to search,
  Search hidden files. built, the second half in 1.5.
- [x] A lone bang includes what the prune list and gitignore leave out. check.
- [x] A folder alias and a slash scopes the search, `docs/report`, and with nothing after it
  browses, `dl/`. built, 1.4e.
- [x] Every alias in `config/filesearch.lua`, dev, personal, hs, config, apps, root among them.
  built, 1.4e, from the share.
- [x] A path typed whole, `~/Development/`, browses it. check.
- [x] A scoped search leaves out the prune list and `pruneLocal`, Google Drive, DaVinci Resolve
  Media and Sync. built, 1.5, the share carrying `pruneLocal` beside `prune` and the app joining
  them as `init.lua` does.

## The index

- [x] The search covers home, `/Applications` and `/System/Applications`, `searchAlso`. built, the
  app reads the index the Lua side builds.
- [x] An open rebuilds an index older than five minutes in the background, and the list answers
  again when it lands, saying Updating index meanwhile, and Building index when there is none.
  built, 1.5, Milos choosing on 2026-11-11 that the list that serves owns the index.
  `IndexBuild.swift` warms it on an open as `index.lua`'s `warm` does, the same helper, arguments
  and file, home and `searchAlso` from the share, and an answer while it runs is pending, which the
  stage asks `rowsLanded` for, drawing the new rows with the highlight held on its row. The helper
  writes a temporary file of each run's own, so a Lua build from the launcher's slash scope at the
  same moment never mixes with it.

## The row's actions

- [x] Return opens. built, 1.3.
- [x] Command and Return, and Hyper and F, reveal in Finder. built, 1.3, 1.4f.
- [x] Hyper and Y copies the path. built, 1.4f.
- [x] Hyper and C copies the file, Copy Folder over a folder. built, 1.4k.
- [x] Hyper and L goes into a folder, Hyper and H up a level, and the `..` row. built, 1.4e.
- [x] Hyper and Q, Quick Look, following the highlight. built, 1.4c.
- [x] Hyper and G downloads a file iCloud holds. built, 1.4i.
- [x] Reveal, Copy Path and Copy File close the list once they act. built, 1.4d's trial.
- [x] Every action but the `..` row counts as a use. built, 1.4d.
- [x] The actions pane lists them, each only where it applies, and the info pane the rest. built,
  1.4f.
- [x] Command and a digit chooses that row. built, 1.4f.
- [x] J and K move, X closes, under Hyper. built, 1.4f.

## The preview pane

- [x] The name, the folder, then KIND, SIZE, CHANGED, ADDED and USED. built, 1.4a, 1.4d.
- [x] A text file's head, up to 400 lines with the rest counted. built, 1.4a.
- [x] A folder's first 100 entries. built, 1.4a.
- [x] A picture, and a rendered preview of a pdf or a video, cached. built, 1.4b.
- [x] A file iCloud holds is never read, and says so with Download's shortcut. built, 1.4b, 1.4i.
- [x] Hyper and D or U scrolls it, and a trackpad over it. built, 1.4f.
- [x] Highlight a file to preview it, with nothing highlighted. built, 1.4a.

## The app's own

These the Lua list has no line for and the flip keeps.
- Folder permissions asked once, up front, and asked again from the list, 1.4j.
- The download meter, 1.4i.

## Before the flip

- The shadow log, `~/.olm/log/shadow-filesearch.jsonl`, read on 2026-11-11, holds 106 lines and 9
  differences, every one from 2026-11-08 and 2026-11-09 and explained in 1.3f, and none since.
- The flip itself, the piece opening the app on Hyper and semicolon as the daily path, with going
  back still the piece, is the last line, after every line above is ticked.
- [x] The flip, on 2026-11-12, and going back tried the same day, the piece off opening the Lua list
  with the app's uses merged in, and on again the app with the Lua list's.
