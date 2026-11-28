-- Per plugin configuration, the person side mirror of the plugin manifests.
--
-- One entry per plugin, keyed by the plugin's own identity, the name its manifest declares and
-- every launcher row and log line uses. That is not always its directory, browsertabs is
-- browserTabs and eyedropper is colorPicker, and a key spelled the directory way matches nothing,
-- which Olm says out loud in the console rather than dropping in silence.
--
-- A plugin's defaults, its suggested keys, its aliases, its icon and its place on a sheet, live in
-- its own manifest. This file holds only what this person changes about a plugin other than how it
-- is reached, so a plugin with no entry here runs exactly as shipped and deleting an entry returns
-- that plugin to its defaults. An entry is one of two things.
--
--   false   the plugin is switched off. Its code never runs, it is taken out of every list and
--           claims no key, and a plugin that requires it goes off with it. Only a plugin under
--           plugins can be, a host written false is refused out loud. A plugin switched off
--           here shows as locked on the settings page, which saves its own switches in
--           hs.settings and cannot undo a line in this file.
--   table   any of the following, all optional.
--             override fields, merged over that plugin's manifest defaults the way Olm always
--                has, so naming one field leaves its siblings alone. A key, a list key or an
--                alias is never one of them. config/keymap.lua holds every key, list key and
--                alias a person sets, and key, mods, leader, bindings, surface and aliases
--                written here are each refused with a console line naming that file.
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
local toggles    = require("config.toggles")
local settings   = require("config.settings")
local displays   = require("config.displays")
local filesearch = require("config.filesearch")
local processes  = require("config.processes")

return {
  displayProfiles = {
    data = { profiles = displays.profiles, settleDelay = displays.settleDelay },
  },

  windowmanager = {
    -- The gap and the window sizes are Olm's settings, laid into settings before configure, and the
    -- margins follow the gap unless stated here.
    data = { settings = settings },
  },

  -- The app toggler's data, no keys. The catalog of bundle ids lives in config/apps.lua and how
  -- apps toggle in config/toggles.lua, and this entry points at both rather than copying them in.
  -- Every app in the catalog is an action, apptoggler.Safari, and which key reaches it is written
  -- in config/keymap.lua, the one place a person sets a key. The key is the plugin's identity,
  -- apptoggler, which is also its directory.
  apptoggler = {
    data = { apps = apps, styles = toggles.styles, toggles = toggles.apps },
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

  -- This machine's pieces, from config/machine.lua, which the bridge host reads to know whether
  -- Olm.app takes a key here, and the tools whose open key it takes where it does, Olm's
  -- docs/PLAN-STANDALONE.md from step 1.2. A tool joins this list in the step that serves it.
  -- shares is what the app reads of this config, written beside it where the piece is on.
  bridge = { data = {
    pieces = require("config.machine").pieces,
    -- File search is the app's since step 1.5's flip on 2026-11-12, every feature of the Lua list
    -- tried in it by hand, docs/PARITY-FILESEARCH.md, where the olmapp piece is on. Going back is
    -- that piece turned off and a reload, which opens the Lua list again with the app's uses merged
    -- into it. The launcher's slash scope stays on the Lua list until stage 3.
    -- Keep awake is the app's since step 4.4 on 2026-11-28, a core list in Swift whose rows are
    -- checked against plugins/caffeinate/rows.lua by test/fixtures/keepawake, and its session held by
    -- the app, which took over the one Hammerspoon kept. Taking it out is the way back, the app's
    -- session in ~/.olm/state/caffeinate then left for the app alone.
    serves = { "fileSearch", "caffeinate" },
    -- Whether the bridge connects to the app's socket, ~/.olm/run/bridge.sock, and serves the
    -- launcher read only, step 2.2 of the plan. On since step 2.3, where the olmapp piece is on,
    -- which is the only place the bridge acts, and turning it off again is the way back.
    socket = true,
    -- Whether Hyper and Space opens the app's launcher, step 3.5, while the app's socket is up,
    -- and the Lua launcher otherwise. Held off on 2026-11-17, since a row leading to a tool the
    -- app did not show yet, Clipboard History among them, did nothing there, and on again on
    -- 2026-11-18 once step 3.6 showed every such tool in the app. False is the way back.
    launcherFlip = true,
    -- Whether a tool's own key opens its list in the app while its socket is up, step 3.8, for
    -- every tool in hosts below, through the one door every tool shows its list by. False is the
    -- way back, and the launcher stays in the app.
    keysFlip = true,
    -- Whether the app's launcher builds its catalog itself and asks Hammerspoon only for the rows made
    -- from what was typed, step 6.1, on since 2026-11-20 once both catalogs listed the same rows in
    -- the same order on this machine. False is the way back, every row asked of Hammerspoon again.
    launcherCatalog = true,
    -- The leaders whose modifier combinations the app claims while its socket is up, step 5.3,
    -- docs/DESIGN-APP-KEYS.md, META since 2026-11-20, Hyper and plain, the rows with no leader, since 2026-11-23. Each one's held key and its sheet stay Hammerspoon's,
    -- and every row still runs here, asked by the app with runKey, except META's window rows, which the app
    -- runs itself since 6.3b, windowsInApp below. Hammerspoon takes the keys back the
    -- moment the socket goes. An empty list is the way back.
    appKeys = { "meta", "hyper", "plain" },
    -- Whether a leader's cheat sheet is drawn by the app, step 5.2, docs/DESIGN-APP-KEYS.md, on since
    -- 2026-11-20. Hammerspoon still decides when a sheet shows and lays it out, and draws it itself
    -- whenever the app's socket is down. False is the way back.
    sheetsInApp = true,
    -- Whether a press on an app, a Hyper app key or an app row in the launcher, is run by the app,
    -- step 6.2, docs/DESIGN-APP-APPS.md, on since 2026-11-20 with its shadow logging beside it. The
    -- app runs one only once it holds Accessibility and has said so, and Lua runs it otherwise. False
    -- is the way back, every press run in Hammerspoon again.
    appToggler = true,
    -- Whether META's window keys are run by the app itself, step 6.3b, docs/DESIGN-APP-WINDOWS.md, on
    -- since 2026-11-23 after the shadow logged no difference. The app reads the window, plans with
    -- Olm's own settings and sizes and writes the frame, Hide Others too, once it holds
    -- Accessibility, and hands the key to Hammerspoon otherwise. A launcher row still runs here.
    -- False is the way back.
    windowsInApp = true,
    -- Whether the app keeps the app catalog, step 6.2b, docs/DESIGN-APP-APPS.md: every app's key,
    -- mode and place in Olm's config, seeded once from what Hammerspoon binds and styles, each key
    -- claimed and run by the app, and a change on the Applications page applied at once with no
    -- reload. False is the way back, the keys, modes and places Hammerspoon's again.
    appCatalog = true,
    -- The tools whose own list the app shows inside its launcher, step 3.3, so the launcher's row
    -- for one replaces its rows in place in the app's window. A tool joins in the step that hosts
    -- it, and taking it out leaves its row put in the app's launcher, as before. Since step 3.6
    -- every tool a launcher row leads to, launcher naming Olm Keys, the page carrying its name.
    hosts = { "volume", "audio", "wifi", "inputsources", "tmuxSessions", "vpn", "emoji", "browserTabs", "speedtest",
      "clipboard", "displayProfiles", "obsidian", "textCase", "workspaces", "processes",
      "olmchooser", "olmplacement", "olmplugins", "olmtheme", "launcher" },
    -- The tools whose every settled answer the app answers again and compares, step 1.3e. File
    -- search's compares nothing while the app serves it and resumes by itself after a back out.
    -- The launcher's, step 2.3, goes over the socket, the app ranking the rows the bridge sends.
    shadows = { "fileSearch", "launcher" },
    shares = { filesearch = { types = filesearch.types, limits = filesearch.limits, preview = filesearch.preview,
      placeholder = filesearch.placeholder, roots = filesearch.roots, prune = filesearch.prune,
      pruneLocal = filesearch.pruneLocal, searchAlso = filesearch.searchAlso } },
  } },
}
