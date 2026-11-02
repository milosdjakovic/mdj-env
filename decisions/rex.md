# Rex

Status. An optional module that writes Rex's settings into its defaults domain and imports the Ghostty theme pair through Rex's own action.

## Now

Rex keeps its settings in `com.superlogical.rex` and has no config file for them, its `init.lua`
holds only keys and actions. `dotfiles/rex/SETTINGS` lists the carried preferences and
`src/setup-rex.sh` writes the ones that differ. The themes are Ghostty's generated files,
imported with `client.theme.import`, and both theme slots are then set by name. The `rex` piece
is off by default and on for Miloss-MacBook-Pro-Vicert.

`dotfiles/rex/.config/rex/init.lua` is stowed and binds herdr's three tools, lazygit, the fuzzy
search and lf, to the same `alt+z` keys, each opened by one action in a floating pane over the
current tab. The tools are copies of herdr's for now.

## Rejected

- 2026-10-30 14:50, writing `Workspace.customThemes` directly from the Ghostty files. The stored
  form is Rex's internal JSON with a palette per slot and a source record, in a beta that can
  change it in any release. The import action is the published interface and does the same job.
- 2026-10-30 14:50, a theme map and emitter for Rex under `theme/`. Rex reads Ghostty's theme
  format itself, so a second generated pair would only duplicate Ghostty's.
- 2026-10-30 14:50, carrying the sidebar text size. It is the macOS Sidebar icon size, global to
  every app, so it is not Rex's to set.
- 2026-10-30 14:50, carrying Remote Control as a setting. It lets local programs drive the app,
  which is the person's call per machine, so the step only says when it is off.

## Log

- 2026-10-30 14:10, the Rex docs at superlogical.com/rex/docs cover only keys, actions and the
  CLI. The appearance keys were found in the app binary, `Workspace.*` in `com.superlogical.rex`,
  and the sidebar typography observes `NSTableViewDefaultSizeMode`.
- 2026-10-30 14:20, the font was written to the domain while Rex ran and did not show until a
  restart. Rex reads these at launch.
- 2026-10-30 14:40, importing `mdj-dark` a second time kept one theme with the same id, and
  importing a changed copy updated that theme in place. The same imports moved the theme slots,
  once leaving the light slot on `merino-light`, so the step sets both slots after importing.
- 2026-11-02 12:25, Rex has floating panes. The server's `session.new_layer` creates blocks in a
  floating layer at fractional bounds over a window, and a terminal block with a command closes
  when the command exits, which closes a layer holding nothing else. An action in `init.lua` can
  call it through `rex.session.new_layer`, so a key can open a tool the way a herdr popup does.
- 2026-11-02 12:32, the three herdr tools were copied into this module rather than shared,
  as asked, with herdr's pane calls swapped for `rex api call`, `rex send` and `rex window new`.
  Validated with `rex config check`, not yet pressed, since the app was not running.
