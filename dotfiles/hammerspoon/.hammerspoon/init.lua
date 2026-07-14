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

hs.loadSpoon("ChordKey")
hs.loadSpoon("CheatSheet")
hs.loadSpoon("HyperKey")
hs.loadSpoon("HyperCheatSheet")
hs.loadSpoon("StageManager")
hs.loadSpoon("WindowManager")
hs.loadSpoon("WindowLeader")
hs.loadSpoon("WindowCheatSheet")
hs.loadSpoon("AppToggler")
hs.loadSpoon("ClipboardHistory")
hs.loadSpoon("Capture")
hs.loadSpoon("WorkspaceEngine")
hs.loadSpoon("TerminalHandler")
hs.loadSpoon("DockAutoHide")

--------------------------------------------------------------------------------
-- Initialize Spoons
--------------------------------------------------------------------------------

-- CheatSheet: the shared grid-overlay renderer behind both cheat sheets. Both
-- builders below draw through this one instance (only ever one overlay is up).
-- Appearance (opacity, colour, radius, font, padding) is set once here from
-- config/settings.lua and applies to every overlay.
spoon.CheatSheet:init()
spoon.CheatSheet:configure(settings.cheatSheet)

-- HyperCheatSheet: overlay of everything under Hyper. App toggles first (open vs
-- not running), then the static service sections. This is the one place that
-- names which non-app bindings surface on the overlay and in what order, so the
-- Capture and ClipboardHistory configs stay pure binding data.
spoon.HyperCheatSheet:init()
spoon.HyperCheatSheet:configure({
  apps = apps,
  toggles = keys.appToggles,
  cheatSheet = spoon.CheatSheet,
  sections = {
    { title = "CAPTURE", bindings = keys.capture },
    { title = "CLIPBOARD", bindings = { keys.clipboardHistory } },
  },
})

-- ChordKey: the shared hold/tap/chord engine behind all three function-key
-- leaders (HYPER=F18, SUPER=F17, META=F16). One event tap serves them all;
-- HyperKey and WindowLeader register their keys into it below. These are the
-- defaults each key inherits unless it overrides them.
spoon.ChordKey:init()
spoon.ChordKey:configure({ holdDelay = 0.6, tapThreshold = 0.2 })

-- HyperKey: Caps Lock (remapped to F18 via hidutil) as a Hyper key.
-- Hold + letter = app toggles; quick tap = toggle real Caps Lock; hold 0.6s
-- with no key = show the cheat sheet. Registers into the shared ChordKey engine.
spoon.HyperKey:init()
spoon.HyperKey:configure({
  chord = spoon.ChordKey,
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
    top = settings.gap,
    right = settings.gap,
    bottom = settings.gap,
    left = function()
      local base = spoon.StageManager:isActive() and settings.stageManagerMargin or 0
      return base + settings.gap
    end,
  },
  settings = settings,
})
-- WindowLeader: the SUPER and META leader keys for window management. Named for
-- the classic modifier hierarchy META < SUPER < HYPER, ascending with the Fn
-- number (META=F16, SUPER=F17, HYPER=F18=Caps Lock/apps). Right Option (F17) and
-- Right Command (F16) are remapped via src/setup-capslock-hyper.sh.
-- Hold SUPER + key to resize the window; hold META to move it (arrows nudge,
-- C centers, , / . switch display).
spoon.WindowLeader:init()
spoon.WindowLeader:addLeader(64)  -- SUPER = F17 = Right Option (resize)
spoon.WindowLeader:addLeader(106) -- META  = F16 = Right Command (move)

-- Predicates for conditional window bindings. A binding in keys.windowManagement
-- may name one via `when = "<name>"`. The binding is then live only while its
-- predicate returns true, and its cheat-sheet row is hidden otherwise. This one
-- registry is the only place the logic lives, injected into both the dispatch
-- gate (bindToLeader) and the overlay filter (WindowCheatSheet), so the key and
-- the overlay never disagree. Keep predicates cheap and free of side effects,
-- since they run on every dispatch and every overlay show.
local windowPredicates = {
  multipleDisplays = function() return #hs.screen.allScreens() > 1 end,
}
spoon.WindowManager:bindToLeader(spoon.WindowLeader, keys.windowManagement, windowPredicates)

-- WindowCheatSheet: hold a leader ~0.6s with no other key to reveal that
-- leader's window actions (same hold rule as Caps Lock -> HyperCheatSheet).
-- Labels are the action names humanized (nextDisplay -> "Next Display") unless
-- an entry sets an explicit `description`.
spoon.WindowCheatSheet:init()
spoon.WindowCheatSheet:configure({
  windowManagement = keys.windowManagement,
  leaders = { [64] = "SUPER", [106] = "META" },
  cheatSheet = spoon.CheatSheet,
  predicates = windowPredicates,
})
spoon.WindowLeader:configure({
  chord = spoon.ChordKey,
  holdDelay = 0.6,
  onHold = function(leaderKeyCode)
    spoon.WindowCheatSheet:show(leaderKeyCode)
  end,
  onHoldEnd = function()
    spoon.WindowCheatSheet:hide()
  end,
})

spoon.WindowLeader:start()

-- Every leader is now registered; start the one shared event tap that drives
-- HYPER, SUPER and META together.
spoon.ChordKey:start()

-- AppToggler (uses apps config; toggles fire via the Caps Lock/F18 Hyper modal)
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

-- Capture: screen capture / recording on the Hyper key, backed by an ordered
-- provider chain. Each action is handled by the first provider that is both
-- installed and supports it, so macshot (its macshot:// URL scheme) is used when
-- present and the native macOS shortcuts (Cmd+Shift+4 / Cmd+Shift+5) are the
-- always-available fallback. Reorder this list to change priority; drop macshot
-- to use only native (e.g. to sidestep macshot's own capture bugs).
spoon.Capture:init()
spoon.Capture:configure({
  hyperKey = spoon.HyperKey,
  providers = {
    spoon.Capture.providers.macshot,
    spoon.Capture.providers.native,
  },
})
spoon.Capture:bindHotkeys(keys.capture)

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
