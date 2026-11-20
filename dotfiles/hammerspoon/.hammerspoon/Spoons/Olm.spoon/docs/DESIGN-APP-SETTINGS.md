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
  typing goes into its search and its fields. Olm.app stays out of the Dock, `LSUIElement`.
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
| Window management | Move and resize steps, pressed and held | `windowSizing` | pixels | live |
| Window management | Smallest and largest window | `windowSizing` | pixels | live |
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

## Back out

The four plugins keep their lists, so their launcher rows come back by putting `row` back under
`registry` in each manifest. The store's values can be removed with `~/.olm/state/settings.json`, which puts
every setting back on its file.
