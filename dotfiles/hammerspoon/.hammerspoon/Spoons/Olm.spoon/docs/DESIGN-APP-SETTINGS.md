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

## Back out

The four plugins keep their logic as providers, so their launcher rows come back by registering
their tools again. The store's values can be removed with `~/.olm/state/settings.json`, which puts
every setting back on its file.
