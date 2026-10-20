-- Per plugin configuration, the person side mirror of the plugin manifests.
--
-- One entry per plugin, keyed by the plugin's own identity, the name its manifest declares and
-- every launcher row and log line uses. That is not always its directory, browsertabs is
-- browserTabs and eyedropper is colorPicker, and a key spelled the directory way matches nothing,
-- which Olm says out loud in the console rather than dropping in silence.
--
-- A plugin's defaults, its key, its aliases, its icon and its place in a leader, live in its
-- own manifest. This file holds only what this person changes, so a plugin with no entry here
-- runs exactly as shipped and deleting an entry returns that plugin to its defaults. An entry is
-- one of two things.
--
--   false   the plugin is switched off. Its code never runs, it is taken out of every list and
--           claims no key, and a plugin that requires it goes off with it. Only a plugin under
--           plugins can be, a host written false is refused out loud. A plugin switched off
--           here shows as locked on the settings page, which saves its own switches in
--           hs.settings and cannot undo a line in this file.
--   table   any of the following, all optional.
--             override fields, merged over that plugin's manifest defaults the way Olm always
--                has, so naming one key leaves its siblings alone. A key or an alias is not
--                one of them any more, config/keymap.lua holds every key and alias a person
--                sets, and the key fields still read here retire in phase 7 of the keymap plan.
--             data    values only this machine knows, handed to the plugin as its own declared
--                needs, never merged into its defaults.
--             global  the name a spoon global mirrors the plugin onto, for a test suite that
--                reaches it that way. Nothing else here uses globals.
--
-- To rebind a key, write the chord in config/keymap.lua, for example
--   ["hyper+Q"] = "vpn.open",
-- and to switch a plugin off, write
--   tmuxSessions = false,
-- Olm hands this whole table to its composition root as cfg.plugins, and that root is the only
-- thing that merges it with the manifests.

local apps       = require("config.apps")
local settings   = require("config.settings")
local displays   = require("config.displays")
local filesearch = require("config.filesearch")
local processes  = require("config.processes")

local gap = settings.gap
local margins = { top = gap, right = gap, bottom = gap, left = gap }

return {
  displayProfiles = {
    data = { profiles = displays.profiles, settleDelay = displays.settleDelay },
  },

  windowmanager = {
    data = { settings = settings, margins = margins },
  },

  -- The app toggler's data, no keys. The catalog of bundle ids lives in config/apps.lua and this
  -- entry points at it rather than copying it in, and every app there is an action,
  -- apptoggler.Safari, focusing or cycling the app. An app that needs more is a named variant
  -- below, an action of its own, apptoggler.GhosttyPlaced. Which key reaches which action is
  -- written in config/keymap.lua, the one place a person sets a key. This is the plugin's own data
  -- and no other plugin asks for it, which is why it travels here. The key is the plugin's
  -- identity, apptoggler, which is also its directory.
  --
  -- A variant names its app from config/apps.lua. `hides` turns focus or cycle into show and
  -- hide, a second press on an app already in front hiding it instead of walking its windows.
  -- `placement` centers and sizes the window once showing, launching, or focusing is the actual
  -- outcome of the press, never when the press only cycled to another window of an app already in
  -- front. `description` labels the action wherever Olm lists it. Every field is read in full in
  -- that plugin's own README.
  apptoggler = {
    data = {
      apps = apps,
      variants = {
        -- The terminal's own placed summon, show and hide rather than cycle since a second press
        -- while it is in front should get it out of the way, and centered at a fixed size on
        -- whichever display it is already on. This is what TerminalHandler.spoon used to be,
        -- absorbed into the toggler as one variant rather than a whole spoon kept outside Olm.
        -- Its key, Option and backtick, is in config/keymap.lua, beside the plain Ghostty toggle.
        GhosttyPlaced = { app = "Ghostty", hides = true, description = "Terminal placed",
          placement = { width = 2400, height = 1350, padding = { x = 40, y = 20 } } },
      },
    },
  },

  browserTabs = {
    data = { chromeBundleID = apps.GoogleChrome },
    -- The BrowserTabs test suite reaches its plugin through a global, so that one name is
    -- mirrored out for it. Spelled browsertabs it mirrored nothing at all, so the suite's own
    -- door was shut while everything else looked fine.
    global = "BrowserTabs",
  },

  clipboard = {
    data = {
      -- External clipboard shortcut, for ClipboardHistory's generic `shortcut` provider.
      -- Hammerspoon fires this combo and whatever clipboard manager you bind the SAME combo
      -- to (Raycast, Alfred, or any other) reveals its history. It is purely shortcut based
      -- and names no app, so it always fires and the manager on the other end decides what
      -- happens. This is the one place the combo lives, keep it in step with the shortcut set
      -- inside that app. Add an optional `app` naming an entry in the apps registry to instead
      -- gate on it, firing only while it runs and letting the native Hammerspoon clipboard take
      -- over otherwise.
      shortcut = { mods = { "cmd", "alt", "ctrl", "shift" }, key = "c" },
    },
  },

  -- Two whole policy files, each too large and too particular to this machine to live
  -- anywhere but its own file. File search's is the type words, the folder aliases and the
  -- prune list. Processes' is which command names count as a dev runtime and which
  -- directories mark a project. Both tools open and work without either, and recognise
  -- almost nothing, which is why their absence looked like nothing being wrong.
  fileSearch = { data = { policy = filesearch } },
  processes  = { data = { policy = processes } },

  -- The screen capture chain, in priority order, by name. The plugin resolves each name
  -- against its own backends, so this stays a list of words and reordering it is one edit.
  capture = { data = { providers = settings.capture.providers } },
}
