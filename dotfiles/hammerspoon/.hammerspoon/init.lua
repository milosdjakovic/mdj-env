-- Hammerspoon configuration.
--
-- This file holds this person's own data, one call into Olm, and the one tool deliberately
-- kept outside it. It names no atom, no wiring order, and no plugin's collaborators. All of
-- that lives inside Olm.spoon now, in root/compose.lua, because Olm is portable and this file
-- is not, so anything a second person would also need belongs on that side of the line.
--
-- Everything below is either a value only this machine could know or a preference that
-- differs from what Olm ships. Delete any of it and Olm still comes up working.

local apps     = require("config.apps")
local keys     = require("config.keys")
local settings = require("config.settings")
local displays = require("config.displays")

local gap = settings.gap
local margins = { top = gap, right = gap, bottom = gap, left = gap }

hs.loadSpoon("Olm")

local olm = spoon.Olm:start({
  -- Values wanted by more than one plugin, matched by FIELD NAME rather than by plugin, so
  -- one application catalog serves the app toggles, the Hyper cheat sheet and the launcher
  -- without any of the three being named here. A plugin that stops needing one of these
  -- simply stops receiving it, with nothing to remove. Only genuinely shared values belong
  -- here, anything one plugin alone wants goes below where it is easier to follow.
  shared = {
    apps    = apps,
    toggles = keys.appToggles,
  },

  -- Values about one plugin in particular, keyed by its directory. Per plugin rather than
  -- shared because these field names are not unique across the set and two plugins wanting a
  -- bundleID or a settings block mean different things by it.
  data = {
    displaymemory   = { bundleID = apps[settings.terminal.preferredTerminal] },
    displayprofiles = { profiles = displays.profiles },
    windowmanager   = { settings = settings, margins = margins },
    browsertabs     = { chromeBundleID = apps.GoogleChrome },
    clipboard       = { shortcut = keys.clipboardShortcut },
  },

  -- Which physical key drives each domain. The only two facts about this keyboard that Olm
  -- cannot guess, and moving either one moves everything on it.
  leaders = { app = keys.appLeader, window = keys.windowLeader },

  -- Global policy that differs from what Olm ships. Absent means Olm's own default stands.
  policy = {
    surface        = settings.surface,
    chooserTheme   = settings.chooserTheme,
    cheatSheet     = settings.cheatSheet,
    overlayDisplay = settings.overlayDisplay,
    hyperTrigger   = settings.hyperTrigger,
    storage        = { cacheRoot = settings.paths.cacheRoot, olmRoot = settings.paths.olmRoot },
  },

  -- The BrowserTabs test suite reaches its plugin through a global, so that one name is
  -- mirrored out for it. Nothing else in this config uses globals.
  globals = { browsertabs = "BrowserTabs" },
})

print(olm:report())

-- TerminalHandler stays outside Olm, this person's own decision of 2026-08-07. It reaches in
-- through the two escape hatches Olm exposes for exactly this, a plugin it does not manage
-- and the shared display policy, so its terminal lands on the same screen every managed
-- surface does rather than picking one of its own.
hs.loadSpoon("TerminalHandler")
spoon.TerminalHandler:configure({
  appToggler    = olm:module("apptoggler"),
  windowManager = olm:module("windowmanager"),
  bundleID      = apps[settings.terminal.preferredTerminal],
  size          = settings.terminal.size,
  minPadding    = settings.terminal.minPadding,
  targetScreen  = function() return olm:screen() end,
})

require("hs.ipc")
