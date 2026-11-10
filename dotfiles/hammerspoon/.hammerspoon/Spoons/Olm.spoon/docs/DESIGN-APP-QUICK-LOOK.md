# Quick Look, a core surface, step 1.4c

A design note for step 1.4c of `docs/PLAN-STANDALONE.md`. The first version, agreed 2026-11-10,
moved the Lua helper's panel into the app as it was. Its trial the same day asked for more, and
this version replaces it, to be agreed with Milos before the rest is built.

## What Milos asked, 2026-11-10

1. Quick Look is one Olm glass pane, following Olm's own corner radius, paddings, fonts and
   colours rather than copying macOS's panel.
2. Its top line holds a close disc, the file's name, and on the right one button naming the
   application that opens the file, Open in Visual Studio Code, with its key cap.
3. Below it, the file's content sits in an inset of its own, with rounded corners.
4. It belongs to the core, so any plugin can ask for it, and both lists use it now.

## What a person sees

```
╭──────────────────────────────────────────────╮
│ ⊗  app.log                 Open in VS Code ⏎ │
│ ╭──────────────────────────────────────────╮ │
│ │ 2026-11-10T00:00:12 INFO  [app.main] ... │ │
│ │ ...                                      │ │
│ ╰──────────────────────────────────────────╯ │
╰──────────────────────────────────────────────╯
```

- The glass is the list's own surface, `Surface.swift`, at the list's corner radius.
- The header line is a list row's height, with the name in the row title's font and colour. The
  close disc stands where a row's icon starts, and the button on the right is a bar item, its
  words and key cap drawn as the bottom bar draws one.
- The content's inset stands the kit's outer padding in from the glass on all sides. Its corners
  are the glass's radius less that padding, the rule every chip inside a panel already follows.
- It opens and closes the way every Olm surface does, the motion in `config/settings.lua`.
- Its size and its place stay as today, centred on the list's screen, at most 1100 by 820 points.

## How it behaves

Unchanged from today:

- The list stays up and keeps the caret. The pane never takes key.
- Q on the file shown closes it. Escape closes the pane alone, and a second Escape closes the list.
- The list closing takes the pane with it. A press on the pane is not a press outside the list.
- A video or a sound plays at once.

New, and proposed for Milos to decide:

- **The pane follows the highlight.** Finder's Quick Look does, and the Lua list's did not only
  because a helper process per arrow key was too slow, `viewers/quicklook.lua`'s header. In
  process it costs nothing. It also keeps the key cap honest, since Return then opens the very
  file the pane shows.
- **Return opens the file shown,** the list's own Return on the highlighted row, so the use is
  noted for frecency the way every open is. A press on the button does the same.

## Where it lives

1. **`native/QuickLook.swift`**, in the swift chooser's shared library, built into both
   Hammerspoon's library and Olm.app. The panel, `Panel.swift`, owns one and hands it the style
   it already has, so the pane needs no setting of its own. The panel also keeps its rules,
   Escape, closing with the list and a press on the pane, so both lists get them from one place.
2. **Olm.app.** The stage answers the source's `quickLook` effect by asking its panel, as built
   now, less the panel this branch added to `OlmCore`.
3. **Hammerspoon.** The core gains one word plugins can declare under `needs.data`,
   `quickLook(path)`, which shows the path or closes the pane when it already shows it, and
   `quickLook(path, true)`, which takes the path into a pane already up, following the highlight.
   While the native list serves, the word asks its panel through the stage and the engine. While
   the canvas list serves, before the native library is first built or when a person chose the
   canvas, no native panel exists and the word answers false.
4. **File search** declares the word. Its `peekPreview` asks it first, and only where it answers
   false runs its own peek viewer, today's helper, so the canvas list loses nothing. Its
   highlight handler asks it to follow. The helper and its viewer seat go at the flip with the
   canvas list.

Revised in the build, 2026-11-10. The note first had the helper move into the core as the word's
fallback. Leaving it in file search as that plugin's own fallback, where the word answers false,
keeps the same behaviour with no dependency moved, so the core word stays one thing.

## Left out, and where it goes

- The button names the application macOS opens the file with. Choosing another application is
  not part of this step.
- The app's frecency is 1.4d. Until then the app's Return notes no use, as today.

## How it is checked

- The swift pane cases gain the pane's layout, the inset at the padding and its radius, the
  header's height and the button's place.
- The index check keeps its three cases for the source's `quickLook` answer.
- Root mechanism checks for the word, the native panel asked while it serves and the helper while
  the canvas list does.
- A hand trial in both lists, every point above.
