-- Hammerspoon Configuration
-- Orchestrates all Spoons and configuration

--------------------------------------------------------------------------------
-- Load Configuration
--------------------------------------------------------------------------------

local apps = require("config.apps")
local keys = require("config.keys")
local settings = require("config.settings")

-- Load workspace configurations
local devWorkspace = require("config.workspaces.dev")
local vicertWorkspace = require("config.workspaces.vicert")

--------------------------------------------------------------------------------
-- Load Spoons
--------------------------------------------------------------------------------

hs.loadSpoon("HyperKey")
hs.loadSpoon("HyperCheatSheet")
hs.loadSpoon("StageManager")
hs.loadSpoon("WindowManager")
hs.loadSpoon("AppToggler")
hs.loadSpoon("ClipboardHistory")
hs.loadSpoon("WorkspaceEngine")
hs.loadSpoon("TerminalHandler")
hs.loadSpoon("DockAutoHide")

--------------------------------------------------------------------------------
-- Initialize Spoons
--------------------------------------------------------------------------------

-- HyperCheatSheet: overlay of Hyper app bindings (open vs not running)
spoon.HyperCheatSheet:init()
spoon.HyperCheatSheet:configure({ apps = apps, toggles = keys.appToggles })

-- HyperKey: Caps Lock (remapped to F18 via hidutil) as a Hyper key.
-- Hold + letter = app toggles; quick tap = toggle real Caps Lock; hold 0.6s
-- with no key = show the cheat sheet. No extra process.
spoon.HyperKey:init()
spoon.HyperKey:configure({
  keyCode = 79, -- F18 (Caps Lock is remapped to F18 by src/setup-capslock-hyper.sh)
  tapThreshold = 0.2,
  onTap = function()
    hs.hid.capslock.toggle()
  end,
  holdDelay = 0.6,
  onHold = function()
    spoon.HyperCheatSheet:show()
  end,
  onHoldEnd = function()
    spoon.HyperCheatSheet:hide()
  end,
})
spoon.HyperKey:start()

-- StageManager (no dependencies, reads fresh on each check)
spoon.StageManager:init()

-- WindowManager (uses margin system for canvas calculation)
spoon.WindowManager:init()
spoon.WindowManager:configure({
  margins = {
    top = 4,
    right = 4,
    bottom = 4,
    left = function()
      local base = spoon.StageManager:isActive() and settings.stageManagerMargin or 0
      return base + 4
    end,
  },
  settings = settings,
})
spoon.WindowManager:bindHotkeys(keys.windowManagement)

-- AppToggler (uses apps config; toggles fire via the Right-Cmd Hyper modal)
spoon.AppToggler:init()
spoon.AppToggler:configure({ apps = apps, hyperKey = spoon.HyperKey })
spoon.AppToggler:bindHotkeys(keys.appToggles)

-- ClipboardHistory: reveal clipboard history on the Hyper key. The provider is
-- the macOS Tahoe Spotlight clipboard; swap it to change backends.
spoon.ClipboardHistory:init()
spoon.ClipboardHistory:configure({
  hyperKey = spoon.HyperKey,
  provider = spoon.ClipboardHistory.providers.spotlightTahoe,
})
spoon.ClipboardHistory:bindHotkeys({ open = keys.clipboardHistory })

-- WorkspaceEngine (depends on AppToggler, WindowManager)
spoon.WorkspaceEngine:init()
spoon.WorkspaceEngine:configure({
  appToggler = spoon.AppToggler,
  windowManager = spoon.WindowManager,
  apps = apps,
  settings = settings,
})
spoon.WorkspaceEngine:registerWorkspace(devWorkspace)
spoon.WorkspaceEngine:registerWorkspace(vicertWorkspace)
spoon.WorkspaceEngine:start()

-- TerminalHandler (depends on AppToggler, WindowManager)
spoon.TerminalHandler:init()
spoon.TerminalHandler:configure({
  appToggler = spoon.AppToggler,
  windowManager = spoon.WindowManager,
  terminalBundleID = apps[settings.terminal.preferredTerminal],
  timing = settings.terminal,
  size = settings.terminal.size,
  minPadding = settings.terminal.minPadding,
})
spoon.TerminalHandler:bindHotkeys({ terminal = keys.terminal })

-- DockAutoHide (standalone)
spoon.DockAutoHide:init()
spoon.DockAutoHide:bindHotkeys({ toggle = keys.toggleDock })

--------------------------------------------------------------------------------
-- Auto-reload and IPC
--------------------------------------------------------------------------------

-- Reload Hammerspoon configuration automatically when files change
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()

-- Enable IPC for command-line control
require("hs.ipc")
