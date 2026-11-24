# Olm Settings, a window of the app's own

Written on 2026-11-19, asked for by Milos. This is the step after 3.9 in
`docs/PLAN-STANDALONE.md`, taken while the timings of the resting point's second condition record.
It waits on Milos's go and on his trim of the list under What it holds.

## What he asked for

- One entry, **Olm Settings**, in place of the four launcher rows Olm Chooser, Olm Placement, Olm
  Theme and Olm Plugins, which go.
- **⌘, opens it from any Olm window**, the launcher or any list, and it opens a real window, not a
  list. A sidebar with a search field on the left, the settings of the chosen section on the right,
  drawn with the system's own controls, a popup, a switch, a slider, as System Settings draws them.
- A change is **saved on this Mac over the files**. The config files stay the defaults, so a new
  machine starts from them, and a value set in the window wins on this one, the way Olm Placement's
  choice already wins over `overlayDisplay.mode`.
- Inside it the four pages as they are now, the look, the behaviour, and any setting he names.

## Why one entry is not the split undone

`decisions/olm-manifest-header.md` records the Olm Settings plugin split into separate plugins on
2026-10-27, because a launcher row a plugin contributes opened its list as a second window rather
than in place. That was a fault of a list. Olm Settings is a window, opened as a window, so the
rule it broke does not apply. `decisions/olm-keymap.md` moved Olm Keys out of the settings on
2026-10-21, because nobody looks for their keys under a preferences tool. Olm Keys stays where it
is, its own launcher row, and the keymap stays a file.

## Who owns what

The split this session settled holds. Olm.app draws, Hammerspoon decides.

```
 Hammerspoon                                   Olm.app
 ───────────                                   ───────
 lib/settings.lua declares every setting  ──►  ~/.olm/run/settings.json  ──►  Settings window
   id, section, title, keywords, kind,          (written at every load,         sidebar, search,
   choices or range, default from the           schema and current values)      native controls
   config files, live or reload                                                      │
                                                                                     │ a change
 checks the value, saves it, applies it   ◄──  bridge request  setting {id, value}  ◄─┘
   live, or reloads once the window             (the socket every list uses)
   says it is done
 ~/.olm/state/settings.json, this Mac's values, the one store
```

**The declarations are Lua's,** because what a setting means and how it is applied lives there:
the theme, the chooser, the plugin switches, the kit's tokens. Each is declared once in
`lib/settings.lua`, and the four plugins answer their own as providers, the themes the chooser in
use offers, the plugins that can be switched off. The window draws whatever the share lists, so a
setting added later is a declaration and nothing in Swift.

**One store on this Mac,** `~/.olm/state/settings.json`, beside the rest of Olm's state. The four
keys in Hammerspoon's own settings, `olmChooser`, `olmTheme`, the placement's and the disabled
plugins, move into it once on the first load that finds them, and are removed there, so there is
never a second answer. Every reader asks one accessor, the saved value first and the config file
after, as `effectiveMode` asks today.

**A change goes over the bridge,** not into the file directly, so Hammerspoon checks it against the
declaration, refuses one that is not allowed with the reason, and applies it. A setting declares
whether it applies at once, a theme or a row limit, or needs a reload, the chooser or a plugin
switched off. A reload is not run under the window on every click. The window says "applies on
reload" beside such a setting and reloads once when it closes, or on a button.

**With the app quit,** Settings needs the app. ⌘, and the Olm Settings row start it and open the
window. Every list keeps working from Hammerspoon as before.

## The window

- A normal macOS window titled Olm Settings, opened over the app in front and made key, since
  typing goes into its search and its fields. Olm.app stays out of the Dock by its activation policy, set to accessory before it runs, and
  not by `LSUIElement`, which kept it out of the app order macOS keeps, so the switcher listed
  the open window last.
- A sidebar of sections with a search field at the top. Typing filters the settings of every section
  by title and keywords, as System Settings does, and a match opens its section with the setting lit.
- The right pane is a grouped form. A choice is a popup or a radio group, on and off is a switch, a
  number a slider with its value or a stepper, a font a popup of installed fonts. Each row has a
  reset to the file's default when it differs.
- Its look is the system's, as System Settings', not the chooser's. Rule 9's one look covers what
  Olm draws over other apps. This is an ordinary app window, and the controls are AppKit's own.

**⌘, from any Olm window.** In Olm.app the panel claims ⌘, while a list is up, closes the list and
opens the window. In Hammerspoon's fallback list the field key ⌘, does the same through
`olm://settings`. It is reserved: the keymap refuses ⌘, in the `lists` section and in a manifest
with a problem line naming Olm Settings, so no list can take it. Outside Olm, ⌘, stays every app's
own settings.

## Layout

Stated by Milos on 2026-11-20. Every gap in the window is one of the tokens in `Space`, in
`app/Sources/OlmSettings/SettingsWindow.swift`, and a change to the window keeps to them rather than
adding a number of its own.

| Token | Points | Where |
|---|---|---|
| edge | 24 | from the pane's edge to its page, on all four sides |
| group | 20 | between groups, the header and the card, the search and the sections, the sections and the app's row |
| pad | 12 | inside a card or a sidebar row, and between a picture and its text |
| related | 6 | between related elements, a title and the line under it |
| row | 2 | between the rows of one list |

The sidebar's edge is where the window's close button starts, read off the window, so the buttons,
the search and every row's highlight share one left edge, and the same gap is kept on the right and
at the foot. The search's magnifier, the sections' symbols and the app's icon share one column.

**No layout shift.** Nothing a person does moves anything they did not touch.

- What comes and goes keeps its place while hidden, the reset button and the search's clear button.
  The line saying a change applies on close or was refused sits at the header's right, whose height
  is fixed, and is left out rather than made transparent when there is nothing to say, since Liquid
  Glass draws its capsule whatever the opacity.
- The search sits a group's gap under the window's buttons, measured from the window, not from
  under the title bar.
- A control sits in a column of fixed width, so a popup's width changing with its choice moves
  nothing, and a number is shown in a fixed width, as wide as it can get, with figures of one width.
- The sidebar's highlight is a fill behind the row and changes no weight and no size.
- The pane is the window's own background. The accent wash behind it is gone, Milos never asked for a
  blue pane.

## Parts, and keeping the window uniform

Stated by Milos on 2026-11-24. Olm Settings is built from a small set of parts in
`app/Sources/OlmSettings/Components.swift`, and every page uses them, so a thing done in one place
looks and behaves the same in every other. These are rules, and a change that breaks one is a
defect, not a choice.

1. **One part per job.** Undo is `UndoButton`, a row's own page is `PageButton`, the gear, the way
   back is `BackButton`, and a page's top is `PageHeader`. A page never draws its own copy of one.
   A need none of them meets adds a part to `Components.swift` and a line to this list, never a one
   off in the page's file.
2. **A row's right group is undo, gear, control, in that order.** Undo first, the gear after it when
   the row has a page of its own, the control last at the right edge. Each keeps its column while
   hidden, so a row with no undo showing or no gear lines its control up with the rest.
3. **A row's details open as a page in the window, never a sheet or a window of its own.** The gear opens it,
   `BackButton` at its top left, a glass button, names the page it returns to, and leaving it, by Back or any other
   way, keeps what it holds. What cannot be kept stays on the page with the reason in its header. A
   plugin's settings and an application's mode and place both work this way.
4. **What is set is drawn in the accent.** A value moved off the config files, and a gear whose page
   holds one, wear the tint, and the rest is muted, so a scroll down a list catches what is set.
5. **Words say only what is true now.** A row says it applies on reload only once its value has moved
   off the one running, and its line is kept while hidden, so nothing moves.
6. **The controls are the system's, at the size System Settings uses.** A switch is the mini one. A
   setting's kind decides its control, `SettingRow` draws every kind, and a page never draws a kind
   itself.
7. **Spacing is `Space`, and nothing moves that was not touched,** the Layout section above.

## What it holds, for Milos to trim

Sections and the settings in each. Live means applied at once, reload means once the window closes.

| Section | Setting | Today in | Kind | Applies |
|---|---|---|---|---|
| General | Chooser, glass or canvas | Olm Chooser, `chooser.provider` | choice | reload |
| General | Placement, under the cursor or with the active window | Olm Placement, `overlayDisplay.mode` | choice | live |
| General | Rows per list | `chooser.rowLimit` | number 10 to 500 | live |
| Appearance | Theme, or the highlight on the glass | Olm Theme | choice | live |
| Appearance | Interface font, code font | `typography.toml` fonts | font | live |
| Appearance | Text sizes, title, body, caption, section, code | `typography.toml` sizes | number 14 to 32 | live |
| Appearance | Icon set and its fallback, SF Symbols or emoji | `icons.toml` | choice | live |
| Appearance | Corner radius | `surface.cornerRadius` | number 0 to 24 | live |
| Appearance | Border width | `surface.borderWidth` | number 0 to 3 | live |
| Appearance | Outer, inner and bar padding | `spacing` | number | live |
| Motion | Show and hide, reshape | `motion.show`, `motion.reshape` | seconds 0 to 0.5 | live |
| Motion | Rise and scale | `motion.rise`, `motion.scale` | number | live |
| Behaviour | The fn cycle's wait | the Lua stage's `CYCLE_IDLE` | seconds 0.3 to 2 | live |
| Behaviour | Cheat sheet reveal delay | `cheatSheet` | seconds | live |
| Window management | Move and resize steps, pressed and held, and the repeats before the held one | the window manager's manifest, Olm's own since 2026-11-23 | pixels | live |
| Window management | The gap, the smallest, default, full height, small and screen recording sizes | the window manager's manifest, Olm's own since 2026-11-23 | pixels | live |
| Plugins | Each plugin on or off, with its description | Olm Plugins | switch | reload |

Left out on purpose. The keys, `config/keymap.lua`, which Olm Keys lists. This machine's Hyper apps
and display profiles, which are files under `machines/`. Paths, `capture.providers` and anything a
person would only set once with a text editor. Each can join later as one declaration.

## Steps

1. **The store and the declarations,** nothing on screen changes. `lib/settings.lua`, the one store,
   the move of the four saved keys, every reader in the table asking the accessor, and the share
   written at load. `test/settings.lua` pins precedence, the move, refusals and the share.
2. **The window, read only.** `olm://settings` and the Olm Settings launcher row open it. The
   sidebar, the search and every control drawn from the share. `olm-bridge-check` reads a share.
3. **Changing a setting.** The bridge request `setting`, checked, saved, applied live or on close
   with one reload. The checks pin a refusal and both kinds of apply.
4. **⌘, and one way in.** ⌘, in the app's panel and in Hammerspoon's field keys, reserved by the
   keymap, and the four launcher rows removed, their plugins left as providers. That last part
   changes four plugins, so it goes through the `olm-plugin` skill.

Each step ends with Milos's trial, as 3.8 and 3.9 did.

## Open questions

1. The trim of the table above, and any setting to add.
2. Whether a reload setting reloads when the window closes, as written, or only on a button.

## As built

**S.1, 2026-11-20.** Milos said go with no trim, so the table stands, and a reload setting applies
when the window closes, as written. `lib/settings.lua` declares the settings and keeps the store.
The root opens it first thing in `obj.run`, moves the five old keys of Hammerspoon's own settings,
`olmChooser`, `olmTheme`, `olmGlassHighlight`, `overlayDisplayPolicy` and `Olm.disabledPlugins`,
into it once, and lays every saved value over the table it belongs to as each is loaded, the
policy, the typography, the icons and the Lua stage's `CYCLE_IDLE`. So every reader of those values
reads the setting with no word of its own, and a saved value the declaration does not allow is said
once and leaves the file's. The chooser, the theme, the highlight, the placement and the plugin
switches read and write the store, and nothing calls `hs.settings` for any of them now. The share
`~/.olm/run/settings.json` is written at load, the sections in order, each setting with its kind,
its range or choices, how it applies, its default and its value, and every plugin a person can
switch off as one switch.

Two changes to the table. Window Management's steps and sizes are not declared yet. They reach the
window manager as its own data, and only a plugin may name itself, which the dry gate holds, so the
window manager declares them through its manifest in S.4 with the `olm-plugin` skill, and the
section stays empty until then. The icon set's choices are the icon sources themselves, each with a
title of its own, and the fonts' and sizes' defaults for a key the typography file leaves out are
the kit's, `ui.shippedTypography()`, so no font name or source name is written outside its owner.

**S.1 tried** on Milos's go for S.2, 2026-11-20.

**S.2, 2026-11-20 01:17.** The window, read only. A new module of the app, `OlmSettings`, holds the share's
model, `SettingsShare`, with its search, and the window, `SettingsWindow`, SwiftUI hosted in an
NSWindow: a `NavigationSplitView` whose sidebar lists the sections under a search field, and a
grouped form of the chosen section on the right, a popup for a choice, a switch, a slider with its
value for a number, a font shown in itself. Each says when it applies on reload, a plugin its
description and a locked one why. Every control is drawn disabled until S.3. The search keeps only
the sections holding a setting every typed word finds, in its title, detail, keywords or section
title, and only those settings in it. `olm://settings` shows it, reading the share afresh each time,
and the Olm Settings launcher row is the bridge host's third action, `bridge.settings`, a row where
the app is built, telling a running app and starting one that is not.

The window's state is an `ObservableObject` the window owns rather than `@State`, because the
command line tools the app builds with ship no SwiftUI macros and `@State` is one in macOS 27's SDK.
The build said so the first time.

**S.2 trial, 2026-11-20 09:14.** Milos found three things. The window was drawn in the look from
before Liquid Glass, it did not come forward, and the app was not in Command Tab. All three are fixed:

- **The look.** The app's binary recorded SDK 14.0, its deployment target, as the SDK it was built
  against, since the build named no SDK, and macOS draws an app linked against an SDK older than 26
  in the old look. `build.sh` and the three check builds now pass `SDKROOT`, so the app records
  SDK 27, as Hammerspoon records 26. The window is then built on glass: the system's floating glass
  sidebar, and on the right a header with the section's picture in a glass circle, a glass capsule
  for the note, and the settings on one glass card, all in one `GlassEffectContainer` over a wash of
  the accent colour carried under the sidebar. Before macOS 26 each glass falls back to the
  regular material.
- **Coming forward.** A running app told by the notification may only ask to come forward, since
  macOS 14's activation is cooperative, and the app in front declined. `openSettings` now always
  hands `olm://settings` to `open` in the foreground, running or not, since LaunchServices brings
  the app that opens a URL forward.
- **Command Tab.** While the window is open the app is an ordinary one, in the Dock and in Command
  Tab, with a menu bar of its own, Olm, Edit and Window, so Command W closes the window and the
  search field takes Command C and V. When the window closes the app goes back to an accessory and
  hands the keyboard back to the app before it.

**Layout, 2026-11-20 10:02,** on Milos's look at the glass window, with System Settings as the
model. The window opens at 1000 by 700 and the sidebar at 270 points, the frame saved under a new
name so the old size is not restored. The toolbar is compact, with no background and no line, so
the search sits just under the window's buttons and the pane's wash runs to the top. Under the
search, where System Settings shows the account, the sidebar shows Olm and its version from the
bundle, in a glass circle.

**S.2 tried** on Milos's go for S.3, 2026-11-20.

**S.3, 2026-11-20 10:34.** Changing a setting. Every control in the window is live, and a change goes to
Hammerspoon as the bridge request `setting {id, value, reset}`, which `lib/settings.lua`'s
`change` checks against the declaration and saves, a value equal to the file's or a reset removing
the saved one, a plugin's switch kept in the list of plugins switched off, and a hidden, absent or
locked setting refused with why. The answer carries the share as it now stands, which the window
draws, so it never shows a value Hammerspoon did not take, and a refusal is said in a line over the
card. Each row whose value differs from the file's has a reset button.

What applies at once is narrower than the table above said, and the declarations now say so. Only
the placement, the theme and the highlight have a word that applies them live, `overlay.setMode`
and `appearance.set`, which `settingsService` in `root/compose.lua` calls. Every other value is
copied as Olm loads, the row limit into each list's config, the fonts, sizes, corners, paddings and
motion into the look and the Swift style, the hold delay into each leader and the fn cycle's wait
into the app's serve, so each declares reload, and the window sends `settingsDone` as it closes,
which reloads once when anything waiting for a reload changed. A font is a popup of the system's
two fonts and every installed family.

The window also opens centred on the screen under the pointer, its sidebar starts at 320 points, and
Olm.app has an icon, `app/Olm.icns`, drawn by `app/icon/make-icon.sh` and shown in the Dock, Command
Tab and the sidebar's Olm row.

**S.4, 2026-11-20 13:58.** ⌘, and one way in.

- **⌘, from any list.** It is a list key of Olm's own all layer, `openSettings` in
  `lib/keymap.lua`'s `listDefaults`, built into every list by `lib/surface.lua` beside the info
  pane's, so the info pane of every list names it. A list Olm.app draws hears it in its own field,
  closes, and shows the window. A Lua list closes through its own close and the bridge opens the
  window. The keymap refuses ⌘, in the `lists` section unless it names `openSettings`, and a
  manifest's `surface.extra` row on it refuses that surface, both naming Olm Settings.
- **The four launcher rows are gone.** Olm Chooser, Olm Placement, Olm Theme and Olm Plugins keep
  their lists and their `registry.open`, so `olmtheme.open` and the rest can still be given a key in
  `config/keymap.lua`, which is how a machine without Olm.app changes these.
- **Window Management.** A manifest may now declare `settings`, the contract's section of that
  name. The window manager declares its move and resize steps, pressed and held, its smallest
  width and height, and its default width and height, each a path into its own data, and the root
  lays a saved value over that data before `configure`, so the plugin reads it with no word of its
  own. All apply on reload.
- **The sidebar.** Olm's icon, name and version sit at the foot of the sidebar, under the sections.

**Permissions, 2026-11-20.** Asked for by Milos once Accessibility was given for step 6.2. A page
after every section the share lists, drawn by the app and not from the share, since only the app can
ask macOS what it is allowed: Accessibility, Input Monitoring, and the Desktop, Documents and
Downloads folders file search reads. Each row says Allowed or Not allowed, read again every second
while the page is up, and its button opens the list in System Settings where the switch is, asking
macOS first where the permission was never asked for, which is what puts Olm in that list. An app
cannot switch its own permission, so the switch itself stays in System Settings. A folder is probed
only once file search has asked about it, since probing one never answered raises macOS's prompt,
and the probe opens it without listing it. The list is the composition root's,
`AppDelegate.permissions()`, so a part that comes to need a permission adds its row there.

**Applications, 2026-11-23.** Asked for by Milos, a page listing every application an app key can
reach, what Olm does with each, and a mode of its own. It is one setting of the app toggler's,
`apptoggler.apps`, a table of applications by bundle id, each with its mode, cycle or hides, and the
name and path of one added from outside the catalog, checked by `lib/settings.lua` as the kind
`apps`. An application's own mode wins over its style's, so Herdr's popup keeps its placement and
may still cycle, and the style's wins over App Keys, the global mode in Behaviour. An application
the table names and the catalog lacks gets an action of its own, `apptoggler.<its letters>`, so it
has a launcher row and a key a person may give it in this machine's file.

The page draws with the toggler's catalog, the setting's `extra`, a member of the plugin the
manifest names and the root answers as the share is written, so the plugin never learns the window
exists. The applications installed are the app's to find, read at the top of `/Applications`,
`/System/Applications` and `~/Applications` and never inside a folder there, so a suite's helpers
and an app's bundled utilities stay out, and one with `LSUIElement` or `LSBackgroundOnly` is left
out as an agent. Add Application is a file picker, the chosen bundle registered with LaunchServices
so it opens by its bundle id wherever it is kept. The catalog and every application given something
of its own are listed first, under Configured, the rest under Other Applications, each with its
icon, its key in words, its style and whether it is placed, and its mode, whose default names what
it follows. A change sends the whole table and applies on the reload the window's close runs.

**Applications, the second round, 2026-11-23.** Milos found the page stuttering as it scrolled,
missed the global mode on it, and could not tell an override from a default at a glance, and asked
for each app's shortcut on its row, the shortcut at the far right and the override before it.

- **Scrolling.** Each row asked macOS for its icon as it scrolled into view and every list sat on
  one glass card, whose blur is redrawn under each row on every frame. The icons are drawn once off
  the main thread into a 28 point bitmap, and the lists sit on a plain fill.
- **The global mode,** App Keys, is the page's first card, moved from Behaviour.
- **What is overridden** has a card of its own, Overridden, each row's mode marked in the accent
  with the word and a reset, and the rest under Following the Default, each saying what it follows,
  App Keys or its style.
- **Shortcuts** are Olm's own setting, `keys`, an action id to its chord or false for none, laid over
  `config/keymap.lua` and this machine's app keys by `savedKeys` in `root/compose.lua` before the
  keymap is read, every chord the keymap gives that action dropped first. A chord another action
  holds is refused on the page and again with a console line at load. The recorder takes one key,
  Hyper implied, since Olm.app holds Hyper's combinations and pressing one would run it, Delete for
  none and Escape to leave it.

**Applications, the third round, 2026-11-23.** From Milos's look at it. A row's mode reads Default,
Cycle windows or Show and hide and nothing more, its Overridden card saying the rest, so the word on
the row went. An application the catalog names and this Mac lacks wears the generic picture faded and
says Not installed. The list and its icons are read as the window is prepared at launch, every row is
made at once rather than as it scrolls into view, and an application that arrives later has its icon
drawn when the page opens.

**Applications, the fourth round, 2026-11-23.** Still not smooth to Milos. A row's mode and key are
drawn by SwiftUI rather than as a pop-up button and a push button, a press on the mode opening the
same menu from the pointer, so the page holds no AppKit control per row. The name takes the room the
row has, the mode and the key stand at the right, and the key is flush with the row's right edge.
Escape closes the window once the search is empty, and the window is activated a turn after the app
becomes an ordinary one, so Command Tab orders it like any app.

**Applications, the fifth round, 2026-11-23.** Milos asked for no separate Overridden card, the
override seen inline instead. The applications Olm knows are one card, Olm's Applications, beside
Other Applications. A mode of the row's own and a key that is set are drawn in the accent on a light
tint with an outline, and Default and None are muted, so a scroll catches what is set. This replaces
the Overridden and Following the Default cards of the second round.

**Applications, the sixth round, 2026-11-23.** Milos asked for no Olm's Applications at all. The
page is one list, Applications, of what the scan finds and what is added. What the app toggler in
Hammerspoon does with an app, its style and so its action and key, comes from the catalog of
config/apps.lua over the bridge and is laid over that list by `HammerspoonCatalog` in
`Applications.swift`, only for an app this Mac has, so Zed, Yomu and the rest of the catalog other
machines use are not listed here. That one enum is temporary and is removed whole when the app
switcher moves into Olm.app. An app saved with a mode of its own and since gone stays listed, Not
installed, so its mode can be reset. This replaces the cards of the fifth round.

**Applications, the seventh round, deferred until the app switcher is in Olm.app, 2026-11-23.**
Milos's order: the focus now is moving what Hammerspoon does into Olm.app, so the page stays as the
sixth round left it, a key only for an application Hammerspoon knows. Once the catalog, the actions
and the keys of app switching live in the app, 6.2 in `docs/PLAN-STANDALONE.md`, every listed
application takes a mode and a shortcut, and the recorder grows past Hyper and one key:

- a leader of the person's choosing, Hyper, META or SUPER, or none;
- any set of modifiers beside it;
- a leader that arrives as a function key, F13 to F20, which is how Caps Lock, Right Option and Right
  Command become leaders and how a pedal or a macro pad becomes one.

Each choice says its caveat where it is made. The ones known now: a held leader is a function key
read by an event tap, so it is deaf while an application holds secure input and macOS's own shortcut
fields cannot record it; Hyper as four real modifiers collides with any app's menu shortcut on them;
a plain combination with Command is likely an app's menu item; macOS keeps some combinations before
any app sees them, Hyper and slash among them; and a remapped key loses its own meaning in every
app. The full list is written when the recorder is designed.

**Applications, Customize, 2026-11-23.** Milos asked for one button per application in place of the
mode menu, opening a sheet. The row keeps its shortcut at the far right and gains Customize, which
reads what is set in the accent, Show and hide · Pointer · Centered · 2400 × 1350, or Customize in
the muted face. The sheet holds the mode, then the display, where it was, active or under the
pointer, then the position, kept or centred, and the size, kept or set in points or a percent with a
least, a most and the padding, and lists what that comes to on each display connected now. Reset
puts both back, Done saves. `docs/DESIGN-APP-APPS.md` has how the app places the window.

**Window Management, a page of its own, 2026-11-23.** Milos asked where his layouts, his named
sizes and their keys are. The section is drawn by `Windows.swift` as the Applications page is by its
own: every window action the launcher lists, read from the window manager's `catalog()` through the
sizes setting's `extra`, in cards, Layouts, Displays, Sizes, Moving and Resizing, Other, each with a
shortcut recorder at the right, META implied, Delete for none, Escape to leave it, and the steps and
sizes as numbers last. A named size is the setting `windowmanager.sizes`, kind `sizes`, a list of
`{ id, name, width, height, unit, anchor, display }`: points or a percent of the screen, one of nine
anchors picked on a three by three grid, and where it is, the built in display, the first external
or the one under the pointer. Small and Recording ship, can be changed and not removed, and keep
their actions, smallSize and screenRecording, so META and Z still reaches Small; a size added is the
action size and its id. Adding, changing or removing one applies on the reload the window's close
runs, so a new size takes a key once the window has closed once.

**Export and import, 2026-11-23.** Milos's aim is one Olm config, exported and imported, that makes
another Mac's Olm the same, with Hammerspoon still behind the bridge until its behaviour moves. The
store is that config. Export writes its values under the kind `olm.config` to a file the person
picks, and Import hands a file's values to Hammerspoon as `settingsImport`, where `settings.import`
passes each through the window's own change and resets every saved value the file leaves out, so
the config is the file's, then one reload. Both sit in a menu beside Olm's name at the foot of the
sidebar. Keys being in the config is why the shortcuts are Olm's setting rather than lines in this
machine's file, which Milos chose over editing that file once the aim was said.

## Back out

The four plugins keep their lists, so their launcher rows come back by putting `row` back under
`registry` in each manifest. The store's values can be removed with `~/.olm/state/settings.json`, which puts
every setting back on its file.
