# Olm icons

Status. A plugin never draws an icon. It declares icons in its manifest, names one on a row, a
binding or its own `defaults.icon`, and Olm draws it through one engine whose active icon set is
one setting in `config/icons.toml`. Every spec carries an `sf` entry beside its `emoji` except
content.

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

A plugin's identity icon is `defaults.icon`, a key into its own `icons` named for the plugin, or
a table spec, and `defaults.glyph` no longer exists anywhere. The launcher row, the action panel,
the scoped list and a computed row source all read it through the one function
`image(spec, owner)` in `lib/icons/rows.lua`, which the `lib/glyphicon.lua` door wraps for the
two hosts that draw rows of their own. A binding, a registry row and a catalog scope name an icon
the same way and are read against the plugin that owns them. A string a person writes over a
default that is not an identifier, an emoji, reads as `{ emoji = string }`. The registrar refuses
a `defaults.icon` key the manifest does not declare, naming the plugin. The dry gate prints one
coverage line per source, warns for each plugin and key with no entry for it, and refuses a
literal `icon = "key"` in a plugin's Lua that its manifest does not declare.

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

- **Keeping `defaults.glyph` as a bare emoji beside `icons`.** 2026-10-15. A bare emoji cannot
  follow the active set, so the launcher row and the action panel stayed emoji while the plugin's
  own rows switched, which the first live run with the SF set showed. A translation table from
  emoji to symbol was the same split with a second place to forget, and a dual path where either
  field is read would have meant two answers for one fact.
- **Treating every undeclared string as an emoji.** 2026-10-15. A typo in a row's key would then
  draw its own letters as a glyph and say nothing. Only a string that is not a plain identifier
  is the emoji shorthand, and an identifier nobody declared still warns once and draws nothing.

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

### 2026-10-15 11:06

The identity icon moved from `defaults.glyph` to `defaults.icon`, and every other `glyph` field
went with it, bindings, registry rows, the launcher's special rows and catalog scopes, the
System Settings panes and the action panel's Back row. The reason was seen live. With the set at
`sf` the keep awake and vpn rows switched correctly, but the launcher row, the action panel and
the scoped list kept their bare emoji, because a bare emoji has no way to name a symbol. Each
plugin now declares an identity icon in its `icons`, named for the plugin, and points
`defaults.icon` at it, so one declaration serves the launcher row and the plugin's own rows. The
resolution is one function, `image(spec, owner)` in `lib/icons/rows.lua`, and the launcher, the
query scope, the action panel and the alias directory all call it, each handing the owner the key
belongs to, taken from the registry listing for a tool or a command, from the context owner for a
verb and from the launcher's own identity for the rows it states itself. The registrar refuses a
`defaults.icon` that names an undeclared key. A computed row source such as arithmetic is
wrapped by the root so its rows are drawn against its own manifest.

Every spec in every manifest and host now has an `sf` entry, each name checked with
`osascript -l JavaScript` and `isNil` before it was written, and the content glyphs stay emoji
only by design, the emoji picker's rows and the vpn country flags. The dry gate prints the
coverage of each source and warns for any gap, and it refuses a literal row key the manifest does
not declare. `config/settingsPanes.lua` was deleted, since nothing loaded it and the same list
lives in the System Settings manifest. `config/icons.toml` still ships `set = "emoji"`.
