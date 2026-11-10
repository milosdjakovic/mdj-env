# Quick Look in the app's list, step 1.4c

A design note for step 1.4c of `docs/PLAN-STANDALONE.md`, written 2026-11-10, to be agreed with
Milos before any code. The app's file search gets the Quick Look the Lua file search has, looking
and behaving the same, under rule 9's no lost feature.

## What the Lua list does today

Quick Look is the verb `peekPreview`, on q under the list leader and as the Quick Look row of the
actions pane, which lists it only over a real file or folder, `applies = "isEntry"`.
`plugins/filesearch/viewers/quicklook.lua` runs a small Swift helper,
`viewers/quicklook.swift`, compiled once into a cache, and the helper opens the panel. What a
person sees:

1. A panel over the list, centred on the screen the list is on, at most 1100 by 820 points and
   70 by 80 percent of that screen, above the list and everything it draws around itself.
2. A header strip of its own, the file name centred and a grey close disc on the left, Finder's
   look rather than the system title bar, and the whole panel draggable.
3. The list stays up and keeps the caret. The panel never takes key and never activates.
4. Q on the file already shown closes the panel. Q on another file replaces it. Moving the
   highlight does not change what the panel shows.
5. Escape closes the panel only, and the list stays up. A second Escape closes the list.
6. The list closing takes the panel with it. The close disc closes the panel alone.
7. A video or a sound starts playing at once.

## The shape

The app is a real app, so it opens the same panel in its own process. No helper is compiled, and
no process starts per file.

1. **The source answers, the stage shows.** File search gains the action `peekPreview`, titled
   Quick Look, with `applies` as the Lua row has it. Choosing it answers a new effect,
   `quickLook(path)`, beside `openFile` and `revealFile`, and no `hide`, so the list stays up. A
   plugin puts no window on screen, so the panel belongs to the stage, as the info pane and the
   actions pane do.
2. **One panel, `OlmCore/QuickLook.swift`.** It is `viewers/quicklook.swift`'s panel moved in,
   the same `QLPreviewView`, the same header, close disc, size, level and nonactivating style, so
   the two lists look the same until the flip retires the helper.
3. **The keys come for free.** Q already reaches the app as the verb `peekPreview` since piece 1
   of 1.4f. The stage runs it because the manifest now names it. The actions pane lists the row
   by the same rule it uses for Copy Path.
4. **The stage keeps the rules above.** It remembers which path is shown, for the toggle and the
   replace. Escape over an open panel closes the panel first, as Escape over an open actions pane
   closes the pane first. `hide` closes the panel with the list. A press inside the panel is not a
   press outside the list, so it does not close the list.

## Left out, and where it goes

- The Lua viewer records a use for frecency when it opens a file. The app's frecency is 1.4d, so
  this use is recorded there.
- The Lua list offers Quick Look only where the root chose the Quick Look viewer, its
  `askedPreview` gate. The app always has the panel, so it always offers it.

## How it is checked

The fixtures gain a case for the source answering `quickLook` and no `hide` for a real file, and
no row for a status row. The rest is a hand trial against the Lua list, side by side, every point
of the list above.
