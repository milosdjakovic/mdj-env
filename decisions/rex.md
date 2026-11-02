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
- 2026-11-02 14:10, painting palette slots 16 to 19 into each Rex pane with OSC 4 from the
  Ghostty theme, as a stand in for the slots the theme import drops. It works around Rex's defect
  from our side and keeps the colours of whichever half was active when the pane opened.

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
- 2026-11-02 14:05, `client.theme.import` keeps only the 16 ANSI colours of a Ghostty theme and drops
  `palette = 16` to `19`, which Ghostty's theme-map declares for fzf's bar, footer and gutter, so
  both imported themes carry empty `paletteOverrides` and a Rex pane answers those slots with the
  xterm cube, black and dark blues. Measured with the terminal's `format` method and
  `extra_palette`. A program can still set them in its own pane with OSC 4, which Rex honours.
- 2026-11-02 14:05, a floating pane's command runs through a non interactive login zsh, which
  never reads `.zshrc`, so `FZF_DEFAULT_OPTS_FILE` is unset there and the floats' fzf ignores fzfrc.
- 2026-11-02 14:10, the fzf options file is now exported from `dotfiles/zsh/.zshenv`, which every
  zsh reads, rather than from `.zshrc.custom`, so a floating pane's finder draws the shared fzfrc
  colours, read back as slots 2, 4, 8 and 16 to 18. The three slots the import drops stay for Rex
  to fix, and no OSC 4 painting from our side was added, since it would be a workaround for their
  defect that also goes stale when the appearance switches. The report to Rex is still to be sent.
