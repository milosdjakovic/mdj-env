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

hs.loadSpoon("StageManager")
hs.loadSpoon("WindowManager")
hs.loadSpoon("AppToggler")
hs.loadSpoon("WorkspaceEngine")
hs.loadSpoon("TerminalHandler")
hs.loadSpoon("DockMenuToggle")

--------------------------------------------------------------------------------
-- Initialize Spoons
--------------------------------------------------------------------------------

-- StageManager (no dependencies)
spoon.StageManager:init()
spoon.StageManager:bindHotkeys({ toggle = keys.toggleStageManager })

-- WindowManager (depends on StageManager)
spoon.WindowManager:init()
spoon.WindowManager:configure({
  stageManager = spoon.StageManager,
  settings = settings,
})
spoon.WindowManager:bindHotkeys(keys.windowManagement)

-- AppToggler (standalone, uses apps config)
spoon.AppToggler:init()
spoon.AppToggler:configure({
  apps = apps,
  hideOthersDefault = settings.features.hideOthersDefault,
})
spoon.AppToggler:bindHotkeys(keys.appToggles)
spoon.AppToggler:bindHideOthersToggle(keys.toggleHideOthers)

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
})
spoon.TerminalHandler:bindHotkeys({ terminal = keys.terminal })

-- DockMenuToggle (standalone)
spoon.DockMenuToggle:init()
spoon.DockMenuToggle:bindHotkeys({ toggle = keys.toggleDockMenu })

--------------------------------------------------------------------------------
-- Auto-reload and IPC
--------------------------------------------------------------------------------

-- Reload Hammerspoon configuration automatically when files change
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()

-- Enable IPC for command-line control
require("hs.ipc")
