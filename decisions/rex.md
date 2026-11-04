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
- 2026-11-02 14:20, Rex's docs say nothing about theme files. The app describes its import as "a
  Ghostty or iTerm theme file", and its stored theme holds 16 ANSI colours plus `paletteBase`,
  `paletteGenerate`, `paletteHarmonious` and `paletteOverrides`, so the model carries per slot
  overrides above 15 and only the Ghostty importer leaves them empty. iTerm's format has no slots
  above 15, so importing that instead cannot help.
- 2026-11-03 10:00, `rex.agents.names-sessions` was written true on 2026-10-30 and was found
  rewritten by the step again today, so Rex removes or resets that key itself. Its row was
  dropped from `SETTINGS`, since a row Rex undoes never settles. Nine settings changed in Rex's
  window since the first pass were added, and the step was run twice with nothing to write.
- 2026-11-04 09:00, `SETTINGS` keeps only general choices a fresh machine should start with.
  The sidebar width, dragged to fit one screen, and the cursor blink interval, inert while the
  custom interval is off, were dropped. Neither is removed from this machine, the step only stops
  carrying them. Corrected 2026-11-04, see below.
- 2026-11-04 09:30, the entry above misread the request. What is wanted is every choice made in
  Rex's Settings window, the colour scheme, the glass interface, the tab sidebar on the left and
  its width, three tab icons and the rest, so the sidebar width and the cursor blink rows are back.
  Only runtime state, Remote Control and the key Rex resets itself stay out.
- 2026-11-04 10:15, settled on carrying only what was changed from Rex's defaults, which is what
  the domain holds. Every Settings page was read through Hammerspoon's accessibility API to
  compare. Pressing an option already selected makes Rex store its value, which is how a default
  could be captured, but defaults need no row on a fresh machine, so it was not used, and the one
  key that test stored, `Workspace.appearance = system`, was deleted again. The cursor blink pair
  holds Rex's default and was dropped. The Integrations page shows agent session naming off while
  `rex.agents.names-sessions` reads true, so that checkbox is not that key. Corrected 2026-11-04, see below.
- 2026-11-04 10:40, captured again. `rex.agents.names-sessions` now reads false, matching the
  Integrations checkbox, so it is that key after all, and the row that kept being rewritten on
  2026-11-03 was this checkbox being changed between runs, not Rex resetting it. It is carried as
  false. Pane headers off and matching program backgrounds on were stored since and are carried.
