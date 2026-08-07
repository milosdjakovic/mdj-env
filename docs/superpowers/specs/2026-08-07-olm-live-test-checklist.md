# Olm live test checklist, every migrated tool one by one

Written 2026-08-07, after phase 6 landed at merge `92f4dc6`. Every tool below runs on its olm
copy on the live config, the originals untouched behind the toggles. Test top to bottom, tick
a box when its tool behaves, report anything off and we fix as we go. The instant fallback for
any tool is one edit, flip its boolean to false at the named line of
`dotfiles/hammerspoon/.hammerspoon/init.lua` and reload, and the original takes over unchanged.

Three toggles are cross cutting and have no row of their own. `ATOMS_ON_OLM` at line 80 covers
the six shared atoms, Dependencies, ChordKey, CheatSheet, Chooser, CanvasPanel, and HyperKey,
and every chooser, cheat sheet, and chord below exercises them. `CLIPBOARD_ON_OLM` at line 164
and `VPN_ON_OLM` at line 186 landed in earlier phases and get short confirmation rows at the
end.

- [x] WindowManager, `WINDOWMANAGER_ON_OLM` line 112. Hold META, the right option key, then
  arrows resize, `W` `A` `S` `D` move, `C` centers, `,` and `.` switch display, `Z` `=` `-`
  are size presets, `H` hides all but the focused window. Exercise a few moves and resizes,
  the display switch on your monitor setup, and one placement with Stage Manager on, the left
  margin should widen by the configured 66 points.

- [ ] WindowLeader, `WINDOWLEADER_ON_OLM` line 122. The META hold itself. Hold META alone
  about half a second and the window cheat sheet reveals, release early and nothing shows. A
  bound key while held fires and is swallowed by the leader, and unbound combos still pass
  through to the app.

- [ ] WindowCheatSheet, `WINDOWCHEATSHEET_ON_OLM` line 132. No key of its own, it is the
  overlay the META hold reveals. Labels and order match the window bindings, the display
  switch row hides on a single monitor, and pressing any bound key dismisses it.

- [ ] AppToggler, `APPTOGGLER_ON_OLM` line 142. Hyper, the held caps lock, plus your app
  letters. Toggle a frontmost app to hide it, toggle a closed one to launch it, and `HYPER+,`
  should open System Settings straight to the General pane rather than a plain focus.

- [ ] FileSearch, `FILESEARCH_ON_OLM` line 330, on `HYPER+/`. Search a file, `q` opens the
  QuickLook preview, `l` and `h` step into and out of a folder, `o` reveals in Finder, `y`
  copies the path. Files you acted on before the migration should still rank near the top,
  the usage recency persisted.

- [ ] BrowserTabs, `BROWSERTABS_ON_OLM` line 310, on `HYPER+W`. The list should lead with the
  tabs you touched most recently, the remembered order survived the migration since both
  sides share one settings key. Picking a tab raises the right window and tab. Enter on the
  settings row steps into the browser toggles without the chooser closing.

- [ ] Caffeinate, `CAFFEINATE_ON_OLM` line 174, on `HYPER+K`. Type a clock time like `15:55`
  or a duration like `1h30m`, confirm with `i`, the machine stays awake for that period, and
  `x` closes the panel.

- [ ] Capture, `CAPTURE_ON_OLM` line 196. `HYPER+3` drags a region and copies the recognized
  text, paste it somewhere to prove it. `HYPER+4` screenshots to the clipboard and
  `HYPER+Shift+4` to a file, the shift sub modifier splitting two actions on one key is worth
  proving on its own. `HYPER+5` records the screen.

- [ ] Emoji, `EMOJI_ON_OLM` line 289, on `HYPER+J`. Search by name or shortcode, pick a
  glyph, it pastes in place without landing in clipboard history. Try it once in a terminal,
  astral glyphs should render since the paste carries them rather than keystrokes.

- [ ] MenuSearch, `MENUSEARCH_ON_OLM` line 1702, on `HYPER+E`, with the launcher aliases `m`
  and `menu` scoping the covered app's menus inside the launcher. Open it over an app with
  real menus and run an item, the item fires on that app after focus returns. Type `m` and a
  space in the launcher, the covered app's menus list in place with a reading row while the
  tree loads, and the docked shortcut hints appear under the chooser after a pause.

- [ ] Processes, `PROCESSES_ON_OLM` line 320, the launcher row named Local Servers. `s` sorts
  by live load, `r` rescans in place, `f` force stops. Stop a dev server and confirm the
  whole process group dies rather than one leaf process.

- [ ] DisplayProfiles, `DISPLAYPROFILES_ON_OLM` line 267, the launcher row named Display
  Profiles plus a background screen watcher. Unplug and replug a monitor, the saved
  arrangement reapplies with no key pressed. In the chooser, capture and rename a profile,
  curated ones stay read only, and pins write to the git tracked
  `config/display-profiles.json`.

- [ ] Eyedropper, `EYEDROPPER_ON_OLM` line 206, on `HYPER+2`. The loupe appears, a click
  copies the sampled hex with the swatch toast, escape cancels cleanly.

- [ ] TextCase, `TEXTCASE_ON_OLM` line 299, the launcher row named Text Case. Select text in
  another app first, the rows preview your selection recased, and picking one replaces the
  selection in place with clipboard history untouched.

- [ ] SystemSettings, `SYSTEMSETTINGS_ON_OLM` line 277, launcher rows under the `s` or
  `system` scope. Picking a pane opens System Settings directly to it. This tool had a rework
  fix for its init call, so the full pane list appearing at all is part of the proof.

- [ ] TerminalHandler, `TERMINALHANDLER_ON_OLM` line 226, on `Option+` backtick. Toggles the
  terminal, placed on the display last remembered for the current monitor arrangement, and
  toggling again hides it.

- [ ] Arithmetic, `ARITHMETIC_ON_OLM` line 340, no key. Type `2+2` into the open launcher, a
  computed row leads the list, selecting it copies the value.

- [ ] Convert, `CONVERT_ON_OLM` line 350, no key. Type `10 usd to eur` into the launcher, a
  row appears once the calculator answers, it is asynchronous so give it a beat. This tool
  had the other init rework fix, a row appearing proves it ran.

- [ ] WorkspaceEngine, `WORKSPACEENGINE_ON_OLM` line 216. `Shift+Alt+D` fires the dev
  workspace and `Shift+Alt+V` the vicert one. The app set launches and arranges in the
  declared order, with apps landing on the right display when a second one is attached.

- [ ] DockAutoHide, `DOCKAUTOHIDE_ON_OLM` line 257, on `Ctrl+Alt+D`. Toggles the real Dock
  auto hide, twice returns to where you started, and it must not collide with the
  `Shift+Alt+D` workspace key.

- [ ] DisplayMemory, `DISPLAYMEMORY_ON_OLM` line 236, background only. Move the terminal to
  another display, hide it, retoggle it with the terminal key, it returns to the display you
  left it on for this monitor arrangement, and that memory survives a reload.

- [ ] WindowMemory, `WINDOWMEMORY_ON_OLM` line 246, background only. Move and resize a
  window, unplug or replug a display, and once things settle the frame restores by itself for
  that arrangement.

- [ ] StageManager, `STAGEMANAGER_ON_OLM` line 102, no surface of its own. Toggle macOS Stage
  Manager and watch a WindowManager placement, the left margin grows by the configured amount
  while it is on and drops back when it is off.

- [ ] KeyRemap, `KEYREMAP_ON_OLM` line 54, the ground under everything. If caps lock drives
  Hyper, a quick tap still toggles real caps lock, a hold reveals the Hyper cheat sheet, and
  right option drives the window leader, then it works, every row above silently proved it.

- [ ] Host, the three spoons that sat outside the bundling pass, `HYPERCHEATSHEET_ON_OLM` line
  101, `LAUNCHER_ON_OLM` line 265, and `QUERYSCOPE_ON_OLM` line 380. Hold Hyper for the cheat
  sheet overlay and check that the app list still splits into open and not running. Open the
  launcher with `HYPER+Space` and run an app row and a command row. Apps you open often should
  still lead the list, the `launcherRecency` order persists across the flip. Type an alias like
  `k` and a space to prove the scope grammar still hands the whole list to one tool.

- [ ] ClipboardHistory, `CLIPBOARD_ON_OLM` line 164, on `HYPER+X` with append copy on
  `Ctrl+Alt+C` and the paste walk on `Ctrl+Alt+V`. Landed in phase 3 with a programmatic live
  pass, so a quick human confirmation of copy, search, paste, and one paste walk closes it.

- [ ] Vpn, `VPN_ON_OLM` line 186, on `HYPER+P` or the `vpn` launcher scope. Landed earlier,
  connect and disconnect once.
