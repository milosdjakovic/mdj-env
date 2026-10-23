# macOS shortcuts

Status. `src/setup-macos-shortcuts.sh` turns off the macOS keyboard shortcuts that take a chord this
repository uses, today symbolic hotkey 98, Show Help menu, so Olm's key panel can sit on Command
and ?.

## Now

macOS answers some chords itself before any application or event tap sees the key, so a chord Olm
binds is dead wherever the system holds it. One kind can be switched off, the symbolic hotkeys in
the `com.apple.symbolichotkeys` domain, and the setup step does that for the ones Olm needs. It
runs where the hammerspoon piece is on. It exports the domain as the running session holds it,
changes only the enabled flag of each entry with `plutil`, keeping whatever chord the entry holds,
writes a missing entry with the system's default chord switched off, imports the domain back and
applies it with `activateSettings -u`, so no logout is needed. A machine where the shortcut is
already off is told so and nothing is written.

The one entry today is 98, Show Help menu, on Command, Shift and slash, which is Command and ?, the
key Olm's key panel answers inside every list, `olm-chooser-keys.md`.

The other kind cannot be switched off. With Hyper as the four real modifiers, Hyper and slash
never reaches any tap, Hyper and period is the system's sysdiagnose shortcut, and Hyper and Escape
holds Command, Option and Escape, which is Force Quit. None of them is a symbolic hotkey a setting
frees. Those chords are avoided rather than reclaimed.

## Rejected

- **Freeing Hyper and slash with a setting.** 2026-10-23. Nothing was found that frees it, it is
  taken below the symbolic hotkeys, so Olm moved off it, file search to Hyper and semicolon and the
  key panel to Command and ?.
- **Writing the whole symbolic hotkey entry with `defaults write -dict-add`.** 2026-10-23. It is
  how the shortcut was first turned off by hand, but it replaces the entry, so a chord a person
  moved would be reset to the default. Changing only the enabled flag keeps their chord.

## Log

### 2026-10-23 16:49

Measured live on macOS 27 with kanata, where Hyper arrives as control, option, shift and command.
Hyper and slash never reaches a Hammerspoon tap or hotkey, Hyper and period is sysdiagnose, Hyper
and semicolon and Hyper and J arrive. Command, Shift and slash arrives once symbolic hotkey 98 is
off, done by hand with `defaults write com.apple.symbolichotkeys` and `activateSettings -u`. The
setup step was written to do the same on every machine where Olm runs, changing only the flag.
Written offline and not yet run, Milos runs it first.

### 2026-10-23 23:55

Hyper and Escape, the sleep key, measured dead on macOS 27 with kanata. A passive keyDown tap in
the live Hammerspoon saw all four modifiers go down twice and no Escape either time, while a plain
Escape arrived. The chord carries Command, Option and Escape, the Force Quit shortcut, which the
system takes before any tap. Sleep now ships with no key and runs from its launcher row, the
person's choice, since Olm already reaches it.

The same session found the lock key, Hyper and §, unbound. Hammerspoon resolves a key by its
character against the layout active when the config loads, and the Serbian Latin layout has no §,
so the chord was never bound. Switching to ABC and reloading bound it. A layout switch after a load
rebinds nothing, so a key missing after a switch wants a reload before any other diagnosis.

