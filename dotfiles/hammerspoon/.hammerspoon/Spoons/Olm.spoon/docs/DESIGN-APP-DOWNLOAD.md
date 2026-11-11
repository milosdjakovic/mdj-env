# Download in the app, step 1.4i

A design note for step 1.4i of `docs/PLAN-STANDALONE.md`, written and agreed with Milos on
2026-11-11, Hyper and G and the list staying up, both as proposed. Since 1.4b the app's preview pane never reads a file iCloud
holds only as a placeholder, `dataless` in its stat flags, since reading it downloads it. The pane
draws the heading and the facts from the stat and says `in iCloud, not downloaded`. This step adds
a way to bring the file down from the list.

## What a person gets

1. **Download in the actions pane, on a placeholder only.** A verb named Download, with a shortcut
   of its own, listed only over a row iCloud has not downloaded, so it never sits in the pane over
   an ordinary file.
2. **The preview pane names the shortcut.** Beside `in iCloud, not downloaded` the pane says how
   to get it, Download and its key cap, so the way out is on the screen where the problem is.
3. **The list stays open and the preview lands.** Download asks iCloud for the file and the pane
   shows the spinner it shows for any preview on its way. When the file arrives the preview is
   drawn, the picture or the text head, where the person is looking. Moving the highlight away
   does not stop the download, only the wait for it, so coming back finds it drawn.
4. **It counts as a use**, like every other action on a row.

## How it works

- **The verb is declared once, in the Lua manifest**, beside Copy File, since the app's actions
  pane and its keys come from the share the root writes from that manifest, `filesearchkeys.json`.
  Its gate is `isPlaceholder`.
- **The Lua list never offers it.** Its preview reads the head of the highlighted file, which
  already downloads it, so it never holds a placeholder worth a verb, and its `isPlaceholder`
  answers false, with that reason beside it. Nothing about the Lua list changes, as the plan says.
- **The app's gate** is the stat flag 1.4b already reads, `Peek.attributes(path).dataless`.
- **The download** is `FileManager.startDownloadingUbiquitousItem(at:)`, the system's own request,
  which returns at once. Where it throws, a path no iCloud container claims, the pane says the file
  could not be downloaded rather than reading it.
- **The wait** is the loop the stage already runs for a picture on its way. The answer to the verb is `refreshPreview` alone, the list staying up, and the source marks the path as downloading, so the
  preview it is asked for next is pending with a `downloading` line. `previewLanded` then polls the
  stat flag, a few times a second and bounded, and once the flag clears it reads the file as any
  other preview. A stat costs microseconds, and the poll runs only while that row is highlighted.
- **A new effect, `refreshPreview`**, asks the stage to ask the highlighted row's preview again,
  since today the stage asks only when the highlight moves. Quick Look's effect does not need it,
  so nothing else changes.

## What Milos decided, 2026-11-11, both as proposed

1. **The key is Hyper and G**, for get. File search's list keys were c, d, f, h, i, j, k, l, o, q,
   u, x, y and `;` under Hyper, and `s` and `w` were the other free ones offered.
2. **The list stays up** while the file comes down, rather than closing as Copy Path does.

## Left out

- Downloading every placeholder in a folder, or evicting a file back to iCloud. Neither was asked.
- A progress figure. iCloud reports progress through a metadata query, which is a watcher of its
  own for one row, and the spinner already says it is on its way.

## How it is checked

- `olm-index-check` cases on a fake placeholder: the gate answering only for one, the verb marking
  the path and answering `refreshPreview`, the pending preview, and the preview drawn once the flag
  clears, with the download itself stood in for, since a check cannot make iCloud evict a file.
- A unit case that the Lua gate answers false.
- A hand trial in the app on a real placeholder in `~/Documents`, and in the Lua list to see
  nothing moved there.

Revised in the build, 2026-11-11. The two questions iCloud is asked are `CloudFiles` in
`app/Plugins/FileSearch/Cloud.swift`, closures a check stands in for. The pane's shortcut is a
field of the preview's body, `shortcut`, naming the verb, which the stage spells from the keys
share, its title and its chord's glyphs, and the pane painter lays out as a fact under the heading,
so the source never writes a key. A download iCloud refuses says `in iCloud, could not download`.
The unit case is `test/cases/filesearch-download.lua`.

