-- Hammerspoon configuration.
--
-- This file holds this person's own data and one call into Olm. It names no atom, no
-- wiring order, and no plugin's collaborators. All of that lives inside Olm.spoon now, in
-- root/compose.lua, because Olm is portable and this file is not, so anything a second
-- person would also need belongs on that side of the line. TerminalHandler.spoon used to
-- be the one tool kept outside that line, its own placement mechanism reaching in through
-- Olm's escape hatches, and it is gone now, absorbed into AppToggler as a plain per entry
-- field any toggle may declare, so this file has nothing left to load outside Olm at all.
--
-- Everything below is either a value only this machine could know or a preference that
-- differs from what Olm ships. Delete any of it and Olm still comes up working.

local settings   = require("config.settings")

hs.loadSpoon("Olm")

local olm = spoon.Olm:start({
  -- Values matched by FIELD NAME rather than by plugin, for a value several plugins ask for
  -- under one name. Empty today. The application catalog and the app toggles used to travel
  -- here, but only the app toggler reads either one now, so both moved to its own entry in
  -- config/plugins.lua. A value belongs here only when two plugins genuinely want the same
  -- thing, anything one plugin alone wants goes below where it is easier to follow.
  shared = {},

  -- Everything about one plugin in particular, keyed by the name that plugin is known by
  -- everywhere outside its own folder. Its overrides of its own defaults, the values only this
  -- machine knows, the spoon global it is mirrored onto, or false to switch it off, all in
  -- config/plugins.lua, which is also where the app catalog and the app toggles reach the app
  -- toggler. Per plugin rather than shared because these field names are not unique
  -- across the set and two plugins wanting a bundleID or a settings block mean different things
  -- by it. Olm names any key there that matches no plugin, so a slip in a name says so.
  plugins = require("config.plugins"),

  -- Every key choice this person makes, the one file Olm owns. A chord to an action or false,
  -- a set of modifiers named as a leader, a role moved to another held leader, and the words
  -- that scope the launcher to a plugin, all in config/keymap.lua. Olm reads it and no plugin
  -- does, and an empty file is the keys Olm and its plugins ship.
  keymap = require("config.keymap"),

  -- Global policy that differs from what Olm ships. Absent means Olm's own default stands.
  policy = {
    -- The window leader's repeat timing, empty unless this machine wants to differ from its
    -- own keyboard settings. Merged per key, so the hold delay, the tap threshold and
    -- passthrough all keep whatever Olm ships.
    chord          = { repeatTiming = settings.keyRepeat },
    surface        = settings.surface,
    -- Absent from this table until 2026-09-01, which is why the shortcuts panel's own idle
    -- delay never reached Olm and every docked bar drew instantly. Olm ships 800 ms
    -- now, so this line matters only on a machine that wants to differ.
    shortcutsPanel = settings.shortcutsPanel,
    chooserProvider = settings.chooser.provider,
    cheatSheet     = settings.cheatSheet,
    overlayDisplay = settings.overlayDisplay,
    storage        = { cacheRoot = settings.paths.cacheRoot, olmRoot = settings.paths.olmRoot },
    -- The colour theme files, one per theme, which hold every colour the surfaces draw with.
    themes         = { dir = settings.paths.themes },
    typography     = { file = settings.paths.typography },
    -- The active icon set and its fallback, one small file beside the typography.
    icons          = { file = settings.paths.icons },
  },
})

print(olm:report())

require("hs.ipc")
