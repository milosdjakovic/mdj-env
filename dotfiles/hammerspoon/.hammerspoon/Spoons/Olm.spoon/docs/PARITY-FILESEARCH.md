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

## Opening and the list

- [ ] Hyper and semicolon opens file search. built, 1.3e, while the piece serves.
- [ ] The launcher row, a Plugin row with the keywords find, folders, locate, finder search. Lua,
  stage 3.
- [ ] The slash and a space in the launcher scopes to file search, deleting it steps back. Lua,
  stage 3.
- [ ] Nothing typed shows the recent list, the 40 files changed in the last 7 days, the 8 used last
  leading it. built, 1.3, 1.4d.
- [ ] A search answers from the first letter. built, 1.4g.
- [ ] At most 200 rows, then a row of more. check.
- [ ] A title cut in the middle, so the extension stays. built, 1.3.
- [ ] The subtitle, the folder, fitted to the row by dropping whole folders from the middle,
  `util.elideDir`, so the head and the folder holding the file stay. **gap**, the app shows the
  whole folder cut at its tail. Closing it is a port of `elideDir` and the fit, measured with the
  list's own font.
- [ ] Every empty state a row with an icon, a title and a line saying what to do, `chooser.lua`'s
  `STATUS`, No matches with Try fewer words, or a bang for pruned folders, Empty folder, Timed out,
  Could not list that folder. **gap in part**, the app says No matches, Empty folder, Timed out, No
  such folder and Nothing can answer that as the list's plain status line, with no icon and no
  second line. Closing it is the statuses as rows with the Lua words and icons.

## The grammar

- [ ] Words match anywhere in the name, every word required. built, 1.3.
- [ ] A dot attached to a known type filters by it, `.pdf`, `.img`, `.js report`. built, 1.3.
- [ ] A type naming a bundle, `.app`, lists every app. built, 1.4h.
- [ ] A lone dot includes hidden files, and with nothing else typed asks for something to search,
  Search hidden files. check, the second half.
- [ ] A lone bang includes what the prune list and gitignore leave out. check.
- [ ] A folder alias and a slash scopes the search, `docs/report`, and with nothing after it
  browses, `dl/`. built, 1.4e.
- [ ] Every alias in `config/filesearch.lua`, dev, personal, hs, config, apps, root among them.
  built, 1.4e, from the share.
- [ ] A path typed whole, `~/Development/`, browses it. check.
- [ ] A scoped search leaves out the prune list and `pruneLocal`, Google Drive, DaVinci Resolve
  Media and Sync. **gap**, the share carries `prune` without `pruneLocal`, which the Lua side adds
  in `init.lua`, so a scoped walk in the app goes into those three. Closing it is the root writing
  the merged list.

## The index

- [ ] The search covers home, `/Applications` and `/System/Applications`, `searchAlso`. built, the
  app reads the index the Lua side builds.
- [ ] An open rebuilds an index older than five minutes in the background, and the list answers
  again when it lands, saying Updating index meanwhile, and Building index when there is none.
  **gap**, the app never builds the index, `Index.swift`'s header, and only the Lua list's open
  starts a rebuild, so once the app serves the index stops moving. This one blocks the flip.
  Closing it is the app warming the index on open the way `index.lua`'s `warm` does, the same
  helper, the same arguments and the same file, its roots and prune list from the share, with the
  two status rows, so the list that serves owns the index, as 1.4d gave frecency one owner.

## The row's actions

- [ ] Return opens. built, 1.3.
- [ ] Command and Return, and Hyper and F, reveal in Finder. built, 1.3, 1.4f.
- [ ] Hyper and Y copies the path. built, 1.4f.
- [ ] Hyper and C copies the file, Copy Folder over a folder. built, 1.4k.
- [ ] Hyper and L goes into a folder, Hyper and H up a level, and the `..` row. built, 1.4e.
- [ ] Hyper and Q, Quick Look, following the highlight. built, 1.4c.
- [ ] Hyper and G downloads a file iCloud holds. built, 1.4i.
- [ ] Reveal, Copy Path and Copy File close the list once they act. built, 1.4d's trial.
- [ ] Every action but the `..` row counts as a use. built, 1.4d.
- [ ] The actions pane lists them, each only where it applies, and the info pane the rest. built,
  1.4f.
- [ ] Command and a digit chooses that row. built, 1.4f.
- [ ] J and K move, X closes, under Hyper. built, 1.4f.

## The preview pane

- [ ] The name, the folder, then KIND, SIZE, CHANGED, ADDED and USED. built, 1.4a, 1.4d.
- [ ] A text file's head, up to 400 lines with the rest counted. built, 1.4a.
- [ ] A folder's first 100 entries. built, 1.4a.
- [ ] A picture, and a rendered preview of a pdf or a video, cached. built, 1.4b.
- [ ] A file iCloud holds is never read, and says so with Download's shortcut. built, 1.4b, 1.4i.
- [ ] Hyper and D or U scrolls it, and a trackpad over it. built, 1.4f.
- [ ] Highlight a file to preview it, with nothing highlighted. built, 1.4a.

## The app's own

These the Lua list has no line for and the flip keeps.
- Folder permissions asked once, up front, and asked again from the list, 1.4j.
- The download meter, 1.4i.

## Before the flip

- The shadow log, `~/.olm/log/shadow-filesearch.jsonl`, read on 2026-11-11, holds 106 lines and 9
  differences, every one from 2026-11-08 and 2026-11-09 and explained in 1.3f, and none since.
- The flip itself, the piece opening the app on Hyper and semicolon as the daily path, with going
  back still the piece, is the last line, after every line above is ticked.
