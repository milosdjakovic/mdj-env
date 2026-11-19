# Rex

Rex is a terminal multiplexer app from superlogical.com, a beta installed by hand. This module
is optional, on where the `rex` piece is on. Rex keeps every setting in the defaults domain
`com.superlogical.rex` rather than in a file, so `src/setup-rex.sh` writes those. Keys and actions
are the one thing Rex reads from a file, `~/.config/rex/init.lua`, and that file and the tools it
runs are the only part of this package stow links. `decisions/rex.md` has what was measured and
what was turned down.

## Floating tools

`init.lua` defines one action, `float_tool`, which opens a centred floating pane over the current
tab running one script from `tools/`, started in the directory of the pane the key was pressed
in. The pane closes when the script exits, which is Rex's default for a terminal with a command,
and its layer closes with it. The tools are herdr's three, copied as they were on 2026-11-02 with
the herdr calls swapped for Rex ones. `cmd+shift+g` opens lazygit, `cmd+shift+e` lf and
`cmd+shift+f` the fuzzy search, the Herdr app's keys. Adding a tool is a script in `tools/` and
one `rex.bind` line.

## Keys

Rex keeps the Herdr app's keys, `dotfiles/herdr-app/.config/herdr-app/keys.json`, so the fingers
do not change between the two, and a key changed in one changes in both. Herdr's spaces are Rex's
sessions. `init.lua` binds the Herdr keys Rex does not ship, tabs on `cmd+shift` with hjkl and
the brackets, spaces on `cmd+shift+j` and `k`, panes on `cmd+alt` with hjkl, zoom on
`cmd+alt+enter`, the sidebar on `cmd+b`, tab numbers, renames on F2, and Rex's Go to Anything
on `cmd+p`, which searches the tabs and panes of every session, View Activity on `cmd+k`, and
Change Session, which lists only sessions, on `cmd+s`. The three open one window with Sessions,
Blocks and Activity sections, each on its own section, while `cmd+.`, Show Activity, is the
sidebar's view and not that window. Activity has `cmd+k`, taken from Change Session, because it
is the section used most. Go to Anything exists only while Rex's experimental New Quick Switcher is
on, `Workspace.experiments.usesNewQuickSwitcher` in `SETTINGS`, and without it `cmd+p` only
beeps, since the action is gone from the app and its menus. New session on `cmd+shift+n` and close window on `cmd+shift+w` are Rex's own, and Herdr
was moved to match. A few differ because only one app has the feature. Herdr's agents keys,
`cmd+]` and `ctrl+alt+j` among them, and its layout switch exist only there, and Rex's float and
activity keys only here. Herdr's `ctrl+1` to `9` for spaces is not carried, since Rex selects a
session by id and not by position.

A binding in `init.lua` stacks over the key the app ships with, and only a shortcut recorded in
Rex's own Settings window sits above this file. So taking an app key, as `cmd+shift+g` takes Go to
Directory and `cmd+alt+h` takes Hide Others, needs nothing more, and the action keeps its place in
the command palette. `rex keymap --help` states the order.

What differs from herdr. The float starts in the calling pane's directory, read from that pane's
foreground process, so no script resolves a directory. `MDJ_REX_TARGET` names the calling pane,
since inside the float `REX_BLOCK` names the float itself. A notification is `osascript`, which is
what Rex's own docs use, since Rex has no notification call of its own. The finder decides a
pane is free when its foreground process is a shell with nothing between it and `login`, from
the terminal's `process` method, and otherwise opens the place as a new tab, the same rule
herdr's finder follows. Escape closes all three, lazygit through the same overlay herdr loads.

Every tool also runs inside `tools/upper-slots`, which sets the float's own palette slots above
fifteen before the tool starts. Rex's theme import keeps only the sixteen ANSI colours, so
without it a pane answers slot 20, the selected row's tint in fzf and lf, with the xterm cube's
dark blue. The slots are read from Ghostty's theme file for the half macOS is on, which already
carries them from `theme/`, so Rex still has no theme map or emitter of its own. Only the floats
get them. A plain Rex pane still answers those slots with the cube, so fzf run by hand there
shows the blue row until Rex's import keeps the slots.

A float clears the calling pane's zoom, because Rex keeps a zoom only while the zoomed pane has
focus, and zooming again while the float is open pulls focus back out of it. So the action reads
whether the calling pane was zoomed and runs every tool inside `tools/keep-zoom`, which zooms
that pane again as the tool exits, unless focus has already left the float, as it does when the
finder opens a new tab. Behind an open float the layout shows unzoomed, and that cannot be
changed from here. A new tool needs nothing for this, the action wraps it.

Rex does not watch the file. After an edit run `rex config reload` from a Rex terminal, and
`rex config check PATH` validates a draft. `rex keymap` lists what the server loaded. A key
this file binds wins over the one the app ships with, and loses only to a shortcut recorded in
Rex's own Settings window.

## What the step does

`SETTINGS` is what Rex stores on the machine it was captured on, as `key | type | value`, and
the step writes each row only where a machine differs. Rex stores a setting only while it
differs from Rex's default and drops the key when it goes back, so the file is exactly what was
changed from the defaults. Never edit it by hand. Change a setting in Rex's Settings window, then
run `src/setup-rex.sh --capture`, which replaces the whole file, so a setting put back to its
default leaves it, and commit the result. On a machine where a setting was changed in Rex,
capture before running the step, never after, since the step writes the file's values back into
Rex and would undo the change. Window frames, the collapsed sidebar, the theme slots and Remote Control
are never captured.

The themes are Ghostty's generated pair, `dotfiles/ghostty/.config/ghostty/themes/mdj-light` and
`mdj-dark`, imported through Rex's own `client.theme.import` action. So Rex has no theme map or
emitter, and a colour change reaches it by running `src/check-theme.sh` and then this step,
which notices the changed files by their hash and imports them again. The hash lives in Rex's
own domain under `mdj-env.themesHash`.

## Gotchas

Rex reads its settings when it launches. A value written while it runs shows only after Cmd+Q
and reopening, and `Cmd+=` or `Cmd+-` before that restart saves the old in memory size over the
new one. The Rex server runs apart from the app, so a restart keeps every session.

An import needs the app running with Remote Control on, in Settings under Rex Server, and the
`rex` CLI, which Rex puts on PATH only in its own terminals. So run the step from a Rex terminal.
Without either the step leaves a closing note and still writes the settings.

An import reselects themes on its own, and once put the light slot back on Rex's stock theme
while importing the dark one. So the step always points both slots at the imported themes by
name afterwards. Importing a file already imported updates it in place and adds no copy.

The stored theme list is data under a key with dots in its name. `defaults read` cuts long data
short and `plutil` cannot address such a key, so the step reads it from an export with
PlistBuddy, and reads only each theme's name and id.

The sidebar text size is not a Rex setting. Rex follows the macOS one, System Settings,
Appearance, Sidebar icon size, `NSTableViewDefaultSizeMode` in the global domain, which also
sizes every other app's sidebar, so this module does not carry it.
