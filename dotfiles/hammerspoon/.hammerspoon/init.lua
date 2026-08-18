-- Hammerspoon configuration.
--
-- This file holds this person's own data, one call into Olm, and the one tool deliberately
-- kept outside it. It names no atom, no wiring order, and no plugin's collaborators. All of
-- that lives inside Olm.spoon now, in root/compose.lua, because Olm is portable and this file
-- is not, so anything a second person would also need belongs on that side of the line.
--
-- Everything below is either a value only this machine could know or a preference that
-- differs from what Olm ships. Delete any of it and Olm still comes up working.

local apps       = require("config.apps")
local keys       = require("config.keys")
local settings   = require("config.settings")
local displays   = require("config.displays")
local filesearch = require("config.filesearch")
local processes  = require("config.processes")

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

  -- Values about one plugin in particular, keyed by the name that plugin is known by
  -- everywhere outside its own folder, the same name config/keys.lua and every launcher row
  -- already use. Per plugin rather than shared because these field names are not unique across
  -- the set and two plugins wanting a bundleID or a settings block mean different things by it.
  --
  -- The name matters and used to be wrong here. Eight of these tools spell their folder one way,
  -- browsertabs, and themselves another, browserTabs, and a key spelled the folder way matched
  -- nothing and was dropped in silence. So Chrome had no bundle id, this machine's display
  -- arrangements never arrived, and file search ran with no policy, all three from one letter.
  -- Olm now names any key here that matches no plugin, so the next slip says so.
  data = {
    displaymemory   = { bundleID = apps[settings.terminal.preferredTerminal] },
    displayProfiles = { profiles = displays.profiles, settleDelay = displays.settleDelay },
    windowmanager   = { settings = settings, margins = margins },
    browserTabs     = { chromeBundleID = apps.GoogleChrome },
    clipboard       = { shortcut = keys.clipboardShortcut },
    -- Two whole policy files, each too large and too particular to this machine to live
    -- anywhere but its own file. File search's is the type words, the folder aliases and the
    -- prune list. Processes' is which command names count as a dev runtime and which
    -- directories mark a project. Both tools open and work without either, and recognise
    -- almost nothing, which is why their absence looked like nothing being wrong.
    fileSearch      = { policy = filesearch },
    processes       = { policy = processes },
    -- The screen capture chain, in priority order, by name. The plugin resolves each name
    -- against its own backends, so this stays a list of words and reordering it is one edit.
    capture         = { providers = settings.capture.providers },
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
  -- mirrored out for it. Nothing else in this config uses globals. Keyed by the plugin's own
  -- name for the same reason the data block above is, and spelled browsertabs it mirrored
  -- nothing at all, so the suite's own door was shut while everything else looked fine.
  globals = { browserTabs = "BrowserTabs" },
})

print(olm:report())

-- TerminalHandler stays outside Olm, this person's own decision of 2026-08-07. It reaches in
-- through the two escape hatches Olm exposes for exactly this, a plugin it does not manage
-- and the shared display policy, so its terminal lands on the same screen every managed
-- surface does rather than picking one of its own.
--
-- terminalBundleID rather than bundleID, which is the name this spoon actually reads. Written
-- as bundleID it arrived as nil, so the toggle had no application to look for and the key did
-- nothing on a spoon that was otherwise wired correctly.
--
-- And bindHotkeys is what gives it a key at all. Being outside Olm means nothing binds this
-- one for it, so leaving the call out left the whole tool reachable only from the console.
hs.loadSpoon("TerminalHandler")
spoon.TerminalHandler:configure({
  appToggler       = olm:module("apptoggler"),
  windowManager    = olm:module("windowmanager"),
  terminalBundleID = apps[settings.terminal.preferredTerminal],
  timing           = settings.terminal,
  size             = settings.terminal.size,
  minPadding       = settings.terminal.minPadding,
  targetScreen     = function() return olm:screen() end,
})
spoon.TerminalHandler:bindHotkeys({ terminal = keys.terminal })

require("hs.ipc")
