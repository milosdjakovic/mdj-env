# Olm icons

Status. A plugin never draws a row icon. It declares icons in its manifest, names one on a row,
and Olm draws it through one engine whose active icon set is one setting in
`config/icons.toml`.

## Now

A row carries `icon`, either a key into the owning plugin's manifest `icons` or a table spec
such as `{ emoji = "🇸🇪" }` for a glyph that is content. A row that already carries an `image`
keeps it, since a real picture such as an app or a file icon is not an icon key. Resolution
happens in one helper, `lib/icons/rows.lua`, which the stage runs on the rows of the current
presentation and the query scope runs on a launcher scope's rows, both handing it the owning
plugin's identity. An unknown key logs one warning per owner and key and the row shows no icon.

The engine in `lib/icons/init.lua` is a Strategy over sources that answer a small contract in
`lib/icons/contract.lua`, a name and a `draw(spec, points, color)`. It tries the active set and
then the fallback, takes the first source that has an entry in the spec and draws, and caches
by source, value, size and, for a source that takes a colour, the colour. `lib/icons/sources`
holds the two sources, emoji and sf. The emoji source keeps the numbers that looked right live,
a 72 point canvas with the glyph at 60, and holds one reused canvas. The sf source renders an SF
Symbol in process through the AppKit bridge of `hs.osascript.javascript` and places it centred
in a square keeping its aspect. The composition root names both and reads `config/icons.toml`,
shipped as `emoji` for the set and the fallback. The colour is the foreground role, the one a
row title is drawn in, read from the kit on every draw.

`lib/glyphicon.lua` is a thin facade over the engine at 72 points, so the launcher and the
action panel are unchanged, and the kit's `iconImage` takes the same engine through
`ui.configure`, so a pane and a row draw with one set of numbers. The dry gate refuses a file
under `plugins` that creates a canvas and snapshots it with `imageFromCanvas`, with the few
declared exceptions listed with a reason in `test/drygate-accepted.txt`.

## Rejected

- **Each plugin drawing its own icons.** 2026-10-15. Twelve plugins each carried an
  `emojiImage` helper over the shared drawer, and three drew canvases of their own with numbers
  that had drifted, the kit's layout at 52 points dropped 8 percent while its comment claimed
  the shared drawer's numbers. Nothing could switch the icon set without editing every plugin.
- **A check alone, without moving the drawing into Olm.** 2026-10-15. A gate that forbade a
  plugin's own canvas would have left every plugin passing a bare emoji string and still no way
  to change the set. The gate is kept, but only as the guard behind the move.
- **A compiled Swift helper for SF Symbols.** 2026-10-15. Verified the same day that the AppKit
  bridge of `hs.osascript.javascript` renders a symbol in process, about 100 ms for the first
  call on Hammerspoon 1.1.1, with no compiler and no helper binary to build, declare and keep
  alive. A helper would add a toolchain dependency for what the bridge already does.
- **Drawing the SF Symbol straight to a canvas.** 2026-10-15. This Hammerspoon has no SF Symbol
  api and the named system images it does expose are too sparse, which is why the bridge is used.

## Log

### 2026-10-15 10:42

Decided with the person and built on its own branch. The engine, the two sources, the
config file, the manifest `icons` field with its registrar check, the shared row resolver and
the guard in the dry gate landed together with the migration of every plugin that passed an
emoji through the glyph drawer. Caffeinate and vpn carry an SF Symbol beside every emoji, which
is what proves the second source, each name checked with `osascript -l JavaScript` and
`isNil` before it was written. The emoji picker's rows use `{ emoji = glyph }` and never a key,
and the vpn flags the same way, so changing the set never changes content. The clipboard colour
chip, the processes nerd font glyphs and textcase are the declared exceptions, textcase and
processes left alone on request.

The emoji picker's background prewarm went with its drawing, since a plugin cannot reach the
engine, so its first open now renders the visible rows on demand. Its measurements stay in
`plugins/emoji/AGENTS.md`. The kit's old glyph numbers, 52 points dropped 8 percent, were never
the shared drawer's despite what its comment said, and the one engine's 60 of 72 replaces them.
