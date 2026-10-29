# Olm icons

Status. A plugin never draws an icon. It declares icons in its manifest, names one on a row, a
binding or its own `defaults.icon`, and Olm draws it through one engine whose active icon set is
one setting in `config/icons.toml`. Every spec carries an `sf` entry beside its `emoji` except
content.

## Now

A row carries `icon`, either a key into the owning plugin's manifest `icons` or a table spec
such as `{ emoji = "🇸🇪" }` for a glyph that is content. A row that already carries an `image`
keeps it, since a real picture such as an app or a file icon is not an icon key. A row never
holds a picture of an icon. Whoever knows the owner stamps `iconOwner` on the row, the stage
with the presenting plugin, the query scope with the scope, the launcher with the row's owner,
the action panel with the verb's owner, through `stamp` and `stampAll` in `lib/icons/rows.lua`.
The chooser then draws the icon each time it paints. The default provider's list render asks
`elements(spec, owner, frame)` in that file through an `iconElements` function the root injects,
and the legacy provider asks `image(spec, owner)` through an `icon` function as it converts a row
for `hs.chooser`, which takes only a picture. A source may answer elements, canvas elements drawn
straight into a frame, and the emoji source does, as one text element, so on the default chooser
an emoji is never a picture and never cached. A source without elements answers its cached
picture placed as an image element. An unknown key logs one warning per owner and key and the
row shows no icon.

The engine in `lib/icons/init.lua` is a Strategy over sources that answer a small contract in
`lib/icons/contract.lua`, a name and a `draw(spec, points, color)`. It tries the active set and
then the fallback, takes the first source that has an entry in the spec and draws, and caches
by source, value, size and, for a source that takes a colour, the colour. `lib/icons/sources`
holds the two sources, emoji and sf. The emoji source keeps the numbers that looked right live,
a 72 point canvas with the glyph at 60, and holds one reused canvas. The sf source never renders
in Hammerspoon's process. It keeps each SF Symbol as a PNG in the storage cache directory for
icons, named for the symbol, the side, the scale and the colour, and a separate `osascript -l
JavaScript` process started through `hs.task` renders the missing ones in batches, centred in a
square keeping their aspect, painted with a palette of one colour so every layer is at full
strength. A picture not on disk yet answers nil and pending, the engine keeps no answer for it,
and when a run finishes the root asks every chooser provider to repaint the lists it shows. At
load the root hands the source every symbol the manifests declare, so a fresh machine renders
the declared set in one run. The swift chooser's view resolves icons only for the rows near the
viewport, a page past each edge. The composition root names both sources and reads `config/icons.toml`,
shipped as `emoji` for the set and the fallback. The colour is the foreground role, the one a
row title is drawn in, read from the kit on every draw.

`lib/glyphicon.lua` is a thin facade over the engine at 72 points, kept as the door a plugin may
draw through at its own draw time though no host uses it for a row any more, and the kit's `iconImage` takes the same engine through
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
- **Rendering SF Symbols in Hammerspoon's process through `hs.osascript.javascript`.**
  2026-10-28. Every call builds a JavaScriptCore context group that bridges AppKit's metadata into
  strings and dictionaries and is never released, so Hammerspoon grows by every symbol drawn, to
  564 MB after one launcher open and 1.23 GB in another process. It was accepted on 2026-10-15
  for needing no helper, and that still holds for the out of process render, which runs the same
  JXA in an `osascript` process that exits and takes the leak with it.
- **Any other caller of `hs.osascript.javascript` in Olm.** 2026-10-29. The clipboard's file
  reader resolved each Finder reference url through it and leaked the same context group per
  copied file, 130 of them and about a gigabyte by an evening, after the icon fix had landed. The
  path was already on the pasteboard, as the url's `filePath` and in `NSFilenamesPboardType`, so
  the reader now reads it there, and the dry gate refuses a call of `hs.osascript.javascript` or
  `hs.osascript._osascript` anywhere in the spoon, see `test/drygate-jxa.lua`.
- **A memory tripwire in Olm's core.** 2026-10-29. A timer reading Hammerspoon's own footprint
  and showing a toast past a threshold was proposed after the second leak, and Milos declined it.
  Both causes are fixed, the dry gate refuses in process JavaScript, and he watches the usage
  himself, so it would be one more always running piece in the layer that runs everything else.
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

- **An appearance watcher that flushes row caches.** 2026-10-15. It would repair the launcher's
  two caches when the system switches halves, but every cache of rows added later would have to
  join the watcher or go stale in the same way, and the fault would reappear silently each time.
  Resolving at paint has no list to forget.
- **Per plugin colour choices.** 2026-10-15. A plugin picking a colour or a weight for its icons
  would be a plugin thinking about contrast, which it must never do, and it would drift from the
  active half and from every other plugin. Colour and contrast are built into Olm.
- **Keeping the hierarchical colour configuration for symbols.** 2026-10-15. It draws secondary
  layers at reduced opacity, so a multi layer symbol such as `face.smiling` or `globe` looked dim
  beside a single layer one such as `circle.fill`. A palette of one colour gives every layer the
  same strength and was verified to render so.

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

### 2026-10-15 20:35

Two defects were found live with the SF set and fixed inside Olm, with no plugin file touched.

The first was contrast. The sf source built `configurationWithHierarchicalColor`, which draws a
symbol's secondary layers at reduced opacity, so a multi layer symbol came out dim beside a single
layer one. It now builds `configurationWithPaletteColors` with the one colour, so every layer is
drawn at full strength, and the label colour is still the fallback for no colour. Verified with
`osascript` that every layer renders at full colour.

The second was staleness. The stage, the query scope and the launcher resolved a row's `icon`
into `row.image` when the row was built, and the launcher keeps its rows across shows in
`_orderedRowsCache` and `_appRowsCache`, so an icon drawn in one half's foreground kept that
colour after the system switched halves. Icons are now resolved at paint. A row keeps `icon` and
`iconOwner` and never holds a picture of an icon. The default provider's list render and the
legacy provider both ask the one injected `icon` function, which is `image(spec, owner)` in
`lib/icons/rows.lua`, and the colour is read on every call, so a switch redraws on the next paint.
`resolve` and `resolveAll` became `stamp` and `stampAll`, which set the owner and draw nothing, and
the launcher's `_icon` and the `glyphIcon` dependency of the launcher and the action panel were
removed. A scope row that names an icon the engine cannot draw no longer falls back to the scope's
identity icon, since the fallback is chosen from data and not from whether a picture came back.
Rejected here, an appearance watcher that flushes the row caches and per plugin colour choices,
both listed above with the reasons.

### 2026-10-24 00:55

The emoji source draws a row icon as text on the default chooser. Its picture path made a 72
point canvas snapshot per glyph, about 92KB that the process never gives back, kept in the
engine's cache and keyed by colour as well, so a light and dark switch drew every symbol again.
That cost was forced by `hs.chooser`, which takes only an image, and the emoji picker can surface
thousands of glyphs. The default chooser paints its own canvas, so the glyph can be a text element
in the row's icon box. The contract gained an optional `elements(spec, frame, color)`, the engine
an `elements` walk in the same order as `image`, and the resolver an `elements` beside `image`.
The text keeps the picture's 60 of 72 proportion of the frame, so it lands where the picture did
by construction, which the live look confirms rather than replaces. The picture path stays for
the legacy chooser and for anything else that wants an image.

### 2026-10-28 14:55

SF Symbol icons looked soft under both choosers. The sf source rendered the symbol to a bitmap of
one pixel per point, then snapshotted it through a 72 point canvas, so on a Retina screen the
image held half the pixels drawn. The native chooser already draws images on whole pixel frames,
see `decisions/olm-swift-chooser.md`, which left this source bitmap as the cause. The script now
draws the symbol itself into a bitmap of 72 times the scale pixels on a side with a size of 72
points, centred at 60 of 72 as before, and the canvas step is gone. Run from the shell, the script
gave 72 by 72 pixels at scale 1 and 144 by 144 at scale 2, both at 72 points, so every layout and
golden is unchanged.

The scale is the largest `scale` of `currentMode()` over `hs.screen.allScreens()`, bounded to 1
through 4. The source gained an optional `variant()` in the icon contract and the engine adds it
to its in memory cache key, so a draw at one scale is not served at another. No cache of images
exists on disk, the storage cache directory holds only the scratch PNG that is deleted after
loading, so no old entry needed handling. The emoji source was left alone, the default chooser
draws it as text and the legacy picture path is a canvas snapshot that is not the reported defect.
Not yet confirmed live, the soft edge going away on a Retina screen is the remaining check.

### 2026-10-28 15:05

Live under a manual hold on top of the Retina fix in the native list, 15c1541b, Milos looked at
the SF Symbols on the built in Retina display and on the external one and said they look good
everywhere. Merged to main.

### 2026-10-28 16:11

Measured live. A freshly started Hammerspoon with Olm and the swift chooser had a 61 MB footprint
and an 11 to 14 MB Lua heap. Three minutes later, after opening the launcher once, it was 564 MB,
and an earlier process reached 1.23 GB. `heap -s` showed 2.7 million CFString and 3.8 million
NSDictionary, about 350 MB together, 419 thousand non object blocks, 66 OpaqueJSContextGroup and
28 thousand JSC NativeJITCode, with SVGAttribute and SVGPathCommand from CoreSVG. Lua's own heap
stayed small.

The cause was the sf source. It rendered every symbol in process through `hs.osascript.javascript`,
and each run left a JavaScriptCore context group behind holding the AppKit metadata the bridge had
built. The canvas chooser resolved icons only for the rows it painted, so it leaked slowly. The
swift chooser's Lua view resolved every row's icon whenever rows were sent, so opening the launcher
rendered the whole catalog of symbols at once.

Two changes. The sf source now keeps pictures as PNG files in the storage cache directory for
icons, named `sf-<symbol>-72pt-<scale>x-<rrggbbaa>.png`, with an empty `.none` marker for a symbol
AppKit does not know. A missing picture answers nil and a second value for pending, a new optional
part of the contract, which the engine does not cache, so the next source draws meanwhile. The
missing ones are queued, and one turn later a single `osascript -l JavaScript` run started through
`hs.task` renders the whole queue, the tool declared in `root/manifest.lua` and resolved through
the door. A finished run fires a callback the root wires to `iconsChanged` on every chooser
provider, which repaints what is on screen. At load the root hands the source every declared
symbol at the current colour, and a miss at a new colour queues every known symbol at that colour,
so a switch of halves is one run. The swift view now resolves icons only for the rows from a page
above the viewport to a page below it, computed from the list model the engine already moves on a
native scroll, and resolves more as a scroll brings them near. No Swift changed.

From the shell, one run rendered `cup.and.saucer.fill` and `globe` at scale 2 into 144 by 144
pixel PNGs at 144 dpi, 72 points, in about 0.1 s, and reported `nope.nope` as unknown. The emoji
source was left as it is. It draws through `hs.canvas` and no JavaScript, and the default chooser
paints it as text, so it does not share this defect. Not yet measured live, the footprint after
opening the launcher is the remaining check.

### 2026-10-28 16:24

Measured live under a manual hold on this branch, Hammerspoon started fresh at 61 MB with the
swift chooser serving and no JavaScriptCore memory at all, and the background run had drawn 126
symbol pictures to disk. After Milos opened nearly every plugin it stood at 219 MB, the heap then
holding 29 thousand CFString rather than 2.7 million and no JS context group, the rest being Lua's
heap at 95 MB, of which a full collection freed 45 MB, plus clipboard images and file search's
Spotlight results. A few minutes later macOS had taken back the freed pages and it sat at 141 MB,
the plugins' own data rather than a leak. Milos found every icon present, full size and sharp.
Merged to main.

### 2026-10-29 09:20

Hammerspoon was back at 1007 MB the next morning with 130 JavaScriptCore context groups, the
same signature, and the count did not move over sixteen hours of idle. After a restart at 51 MB a
wrapper around `hs.osascript.javascript` logged a Lua traceback per call while a sampler read the
footprint and the context count every half minute. Milos copied a few files in Finder, and the
count went from 0 to 30 and the footprint to about 260 MB, with 29 logged calls, every one from
the clipboard monitor's capture through the file reader's `matches` into `resolveReferenceURL`,
one per copied file. Reading the pasteboard after that copy showed the real path already there,
the url's `filePath` from `hs.pasteboard.readURL` and the same path in `NSFilenamesPboardType`,
while `realpath`, `hs.fs.pathToAbsolute` and the `/.vol` device and inode path all fail on a
reference url. The resolver is deleted and the dry gate refuses in process JavaScript anywhere in
the spoon. The sampler's `heap` pauses the process while it walks memory, which may account for
some of the lag Milos saw during the measurement. The fix is not yet measured live.

### 2026-10-29 10:53

The copies in that test also spiked the footprint to about 500 MB for a few seconds, all of it
Malloc Large, with 11 MB of Lua heap after a forced collection. The clipboard's preview chain drew
a pdf or an icns in process through `hs.image.imageFromPath` and an `img:copy()`, which holds the
whole document twice in native memory that Lua's collector cannot see. Loading the 62 MB book
Milos had copied that way took Hammerspoon from 114 MB to 255 MB, back to 118 MB only after a
collection, and the call did not return within 15 seconds. `sips` drew the same first page at 512
pixels in 0.07 s and 24 MB in its own process, `qlmanage -t` took 0.24 s and 67 MB and then hung
on an epub, so the sips generator now takes pdf and icns beside the rasters and the hs.image
generator is deleted. The sips path was checked on an icns too.

