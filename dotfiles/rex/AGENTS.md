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
the herdr calls swapped for Rex ones, and the keys are herdr's too behind the same `alt+z` prefix.
`alt+z alt+g` lazygit, `alt+z f` the fuzzy search, `alt+z alt+f` lf, and `alt+z alt+z` sends the
prefix on to a tmux running inside a pane. Adding a tool is a script in `tools/` and one
`rex.bind` line.

What differs from herdr. The float starts in the calling pane's directory, read from that pane's
foreground process, so no script resolves a directory. `MDJ_REX_TARGET` names the calling pane,
since inside the float `REX_BLOCK` names the float itself. A notification is `osascript`, which is
what Rex's own docs use, since Rex has no notification call of its own. The finder decides a
pane is free when its foreground process is a shell with nothing between it and `login`, from
the terminal's `process` method, and otherwise opens the place as a new tab, the same rule
herdr's finder follows. Escape closes all three, lazygit through the same overlay herdr loads.

Rex does not watch the file. After an edit run `rex config reload` from a Rex terminal, and
`rex config check PATH` validates a draft. `rex keymap` lists what the server loaded and warns
about a key the app also binds, since a shortcut set in the app wins over this file.

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
