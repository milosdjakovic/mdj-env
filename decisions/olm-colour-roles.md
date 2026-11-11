# Olm colour roles

Status. Olm draws with exactly eight colour roles and nothing else. A plugin, a pane, a host or
a component names one of them, and a theme file answers exactly those eight.

## Now

The roles are foreground, subtext, background, border, highlight, primary, secondary and
tertiary. foreground is text you read, subtext is text you glance at, background fills every
panel, border is an outline, a divider and a graph baseline, and highlight is the bar under the
list cursor and the tint behind selected text in the field. A key chip, on a cheat sheet as in
the bottom bar and its panes, is the foreground at the keycap alpha, one rule for every chip. The three
accents are ranks, so a graph takes its series in that order, and they carry no meaning such as
success or error. A faded look is an alpha laid over a role, never a ninth colour.

The kit in `lib/ui/style.lua` resolves those eight and refuses any other colour name at build
time, so a retired word fails where it was written. A theme file under `config/themes` holds
the eight keys under `[dark]` and `[light]`. The Aura one is generated from the repository
palette, through `dotfiles/hammerspoon/theme-map`, which points each key at a role from
`theme/VOCABULARY`, border at dim and the three accents at primary, secondary and tertiary. The
default theme is hand written, its three accents a hand chosen purple, green and orange that
read on their own half's page. `.hammerspoon/AGENTS.md` carries the rule beside the one for
typography.

The merge from the fourteen names before it was path and meta into subtext, dim, overlay and the
faint baseline into border, surface into background, selection and badge into highlight, accent
into foreground, outline into border since it only draws the edge of the colour toast's swatch,
and note into an accent by rank or into subtext when it was text.

Which colours are live belongs to the chooser that serves. Each provider declares an
`appearance`, and `lib/ui/appearance.lua` is its one reader. The canvas declares themes, every file
under `config/themes`. The glass declares a highlight, its own palette in
`lib/chooser/providers/swift/palette/glass.toml` with only the highlight role chosen, its own wash
or the accent colour set in System Settings at alpha 59, reapplied when that accent changes. The
eight roles are the same eight either way.

What stands on a solid highlight is drawn in the lit ink, `Ink` in the swift chooser's
`native/Model.swift`, and every surface that lights draws through `Style.ink(lit:)`, the list's
rows, the actions pane's highlighted line, a bar group lit whole and the bar item under the
pointer. Its text is `alternateSelectedControlTextColor`, the colour AppKit draws a selected row's
text in, and every other role, the subtitle, a dimmed word, a row number, the alternative word
between chords and the key chip, is that colour at the strength the role has against the
foreground on the glass. So a key chip there is the lit text at the keycap's strength, the key cap
rule applied to the lit foreground, and a one colour icon, an SF Symbol, is redrawn in the lit text.
On a translucent highlight, and on anything not lit, the ink is the palette's own.

## Rejected

- **The highlight as the fill of a key chip.** 2026-11-02 19:40, reported by Milos once the solid
  macOS highlight painted every cheat sheet chip blue. A chip is a key, the same thing the bottom
  bar, the info pane and the actions pane draw, and those already drew it as the foreground at the
  keycap alpha. The kit's badge was the one chip on the highlight, so the two rules had diverged.
- **Finder's sidebar selection colour for the macOS highlight.** 2026-11-02 19:30.
  `selectedContentBackgroundColor` read as a darker blue than a menu's selected item, which is
  what Milos compared it with. The accent itself, `controlAccentColor`, is what a menu fills.
- **The macOS highlight as a wash of the accent at alpha 59.** 2026-11-02 19:25. Built first and
  read as transparent. Milos wanted it solid, as macOS draws a selection, and the lit row's text
  turns white on it as AppKit's does.

- **One theme list for both choosers, glass among the themes.** 2026-11-02 19:05. A painted
  theme over glass covers the glass, and the glass palette offered beside Aura on the canvas was a
  theme made for a surface the canvas does not have. Each chooser now offers its own.
- **A ninth role for the system accent.** 2026-11-02 19:05. The accent answers the highlight role
  on the glass and nothing else, so it is a value of a role and not a new name every theme must
  answer.
- **A larger set mirroring the whole repository vocabulary.** 2026-10-14. Carrying all sixteen
  roles of `theme/VOCABULARY` into Olm would give more names than Olm has uses for, and every
  name needs an answer in every theme and a decision from every plugin author about which one
  fits. Eight covers every surface Olm draws today.
- **Separate path, dim, surface and selection roles.** 2026-10-14. They were distinctions nobody
  could see. A path is read like any other glanced text, a dim rule and a divider are both a
  faint line, a surface was the background in every theme that shipped, and a selection tint and
  the cursor bar are never on screen in the same place at once.
- **Semantic accents such as success and error.** 2026-10-14. The palette never promised them,
  and `theme/VOCABULARY` already chose rank words for that reason. A role that means error has
  to be an answer in every palette, and Aura has no such colour to give.
- **All six Aura accents.** 2026-10-14. Rejected until a fourth has a use. Nothing in Olm draws
  more than three series, and an unused role is a name a theme must still answer.

## Log

### 2026-10-14 18:31

Decided with the person and built. The fourteen colour names the kit
carried were cut to the eight above, the theme files were rewritten to those keys, and every
reader moved. The two derived views for readers outside the kit, the chooser shaped one and
the surface shaped one, are kept and rebuilt from the eight roles, since the native provider,
the panel and speedtest's pane still read them. Speedtest's pane keeps its own four keys
inside the chooser shaped view until it is migrated to the kit. The Local Servers graph now
draws its CPU line in primary, its memory line in secondary and its baseline in border.

### 2026-10-14 19:41

Speedtest's pane was moved onto the kit, and with it the last reader of the chooser shaped
view's preview table went, so the table was deleted from `root/uispec.lua`. The four keys it
held, fg, meta, path and note, are not roles and nothing reads them. The pane's download curve
and bars are primary, its upload secondary, its latency and responsiveness strip tertiary and
every baseline border, so a series is the same colour in every view. The figures are
foreground, both of them. The old pairing drew the upload figure in the note colour to match its
curve, but a figure sits directly over its own curve under its own unit, and an accent carries
a rank and no meaning, so a coloured figure would have said nothing the position did not. The
native provider still carries a preview colour set in its own fallback theme. Nothing reads it
either, `activeTheme` has no caller, and it goes with the native provider's own step.

### 2026-10-29 15:07

A third theme, `glass.toml`, was added beside default and Aura for the swift chooser's glass,
after Milos found the default highlight too grey and too opaque there. It is hand written from
the semantic colours AppKit answers on macOS 26, read off NSColor in sRGB under darkAqua and
aqua rather than from memory. Text, highlight and border are translucent the way Apple's are,
white over the dark half and black over the light half at a fixed alpha, so the glass shows
through, and highlight is systemFill at ten percent where the default theme's was an opaque
grey. The accents are the system purple, green and orange. background stays opaque, the window
background colour, because the canvas chooser fills its whole panel with it and has no blur, so
a translucent fill showed the desktop sharp through the list. On glass it fills only the key
panel. A first version had it at sixty percent and was changed the same session for that
reason. The default theme was left as it is, since it also paints the canvas surfaces.

### 2026-11-02 19:05

Milos asked for the look to belong to the chooser, the canvas fully themed and the glass choosing
only its highlight, Olm's own or the one macOS has, with a setting to switch between the two
choosers. Built on the olm-chosen-appearance branch. `glass.toml` moved from `config/themes` into
the swift provider. The store in `lib/ui/themes.lua` takes its own default name and settings key
so it can serve that one file. The Olm Theme list reads the chooser in use through four root
words and names what it offers in its field, and the new Olm Chooser list picks the provider,
persisted under `olmChooser` and applied by one reload. A stored `olmTheme` of glass is forgotten
once at load, since the canvas no longer offers it. `AppleColorPreferencesChangedNotification`
reapplies the macOS highlight when the accent changes, through one watcher kept for the life of
the config.

### 2026-11-02 19:40

Live on the test lock with Milos. The macOS highlight is the accent, solid, and the glass list
draws the lit row's text in `alternateSelectedControlTextColor` whenever its highlight is solid,
decided in Swift from the colour's alpha so no colour literal reaches Lua. The kit's badge, the
cheat sheet's key chip, moved off the highlight onto the key cap rule the bar already used, so the
highlight role is now the cursor bar and the field's selection tint and nothing else. The first
wash and the sidebar colour are in Rejected.

### 2026-11-02 19:50

Milos asked for the key cap rule to be deterministic in code rather than three copies that agree.
`keycapColor` in `lib/ui/style.lua` is now the one fill of a key chip, exposed as `ui.keycapColor`,
and the canvas bottom bar, the glass view and the kit's badge all call it. The dry gate refuses a
read of `alpha.keycap` outside `lib/ui`, proven by planting one in `bottombar.lua`, and a unit
case in `test/cases/uikit.lua` holds that a badge does not change with the highlight.

### 2026-11-03 10:44

Under the solid macOS highlight only the list's lit row turned white. The actions pane's
highlighted line kept the palette's dark label, its symbol and its key chip, the chip being the
foreground at the keycap alpha, a faint dark box on the accent that Milos could barely see, and a
lit bar group and the bar item under the pointer did the same. Milos asked for all of it to turn
white, and for the chip to read, as a proper rule rather than a patch per surface. The lit colours
had been one line in the list's cell, the title at the selection text colour and the subtitle and
number at a written 0.8. They are now one `Ink`, built by `Style.ink(lit:)` from the palette the
Lua view sent, each role keeping its alpha ratio to the foreground, so no strength is written in
Swift and the chip follows `ui.keycapColor`'s rule on the lit foreground. The list's lit subtitle
moves from 0.8 to the glass subtext's own ratio, about 0.65. A key cap takes an ink and repaints in
place when its item lights, and the actions pane's lines and the bar's keys picture carry the
one colour flag the rows already did. `test/swiftpane.swift` pins the rule, `test/swiftview.lua`
the flags.

### 2026-11-11 15:14

A meter, `kit.meter`, how far something has come, asked for by Milos in the 1.4i trial when the
app's download showed only a spinner. It takes no ninth role. Its track is `border` and its fill
`foreground`, a light grey under black on our own colours, and the fill is `highlight` when the
look's highlight follows the macOS accent, Milos's words being "when using mac highlight as theme
use that color". Which one is a fact only `lib/ui/appearance.lua` knows, so its `colors()` says
`followsAccent` beside the halves, `root/uispec.lua` turns that into the spec's `meter.fill`, and
`lib/ui/style.lua` resolves `T.meter`, refusing any word that is not a role. The swift pane is
handed the same block in the pane tokens, so both sides draw it from one rule.
