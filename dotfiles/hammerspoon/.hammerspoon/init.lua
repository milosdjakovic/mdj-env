-- Hammerspoon Configuration
-- Orchestrates all Spoons and configuration

--------------------------------------------------------------------------------
-- Load Configuration
--------------------------------------------------------------------------------

local apps = require("config.apps")
local keys = require("config.keys")
local settings = require("config.settings")
local displays = require("config.displays")

-- Load workspace configurations
local devWorkspace = require("config.workspaces.dev")
local vicertWorkspace = require("config.workspaces.vicert")

--------------------------------------------------------------------------------
-- Load Spoons
--------------------------------------------------------------------------------

hs.loadSpoon("KeyRemap")
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
hs.loadSpoon("DisplayProfiles")

--------------------------------------------------------------------------------
-- Initialize Spoons
--------------------------------------------------------------------------------

-- Leader key remap. The catalog in config/keys.lua lists which physical key maps
-- to which unused function key; KeyRemap applies that at the HID level. A leader
-- is "active" only by being referenced, so we apply exactly the ones the domains
-- name, HYPER for apps and the window leader, and every other catalog key stays a
-- normal key. Keycodes are resolved here from each entry's fkey, so no raw
-- function-key numbers live anywhere else, and the catalog stays ignorant of what
-- consumes it.
local catalog = keys.leaderKeys
local function leaderCode(name)
  return hs.keycodes.map[catalog[name].fkey]
end
spoon.KeyRemap:init()
spoon.KeyRemap:apply(catalog, { keys.appLeader, keys.windowLeader })

-- CheatSheet: the shared grid-overlay renderer behind both cheat sheets. Both
-- builders below draw through this one instance (only ever one overlay is up).
-- Appearance (opacity, colour, radius, font, padding) is set once here from
-- config/settings.lua and applies to every overlay.
spoon.CheatSheet:init()
spoon.CheatSheet:configure(settings.cheatSheet)

-- HyperCheatSheet: overlay of everything under Hyper. App toggles first (open vs
-- not running), then one ACTIONS group for the non-app commands. This is the one
-- place that names which non-app bindings surface on the overlay and in what
-- order, so the Capture, ClipboardHistory, and system configs stay pure binding
-- data. The order below is the on-screen order: the four capture actions fill the
-- first row (the grid is four columns) and clipboard, lock, and sleep fall to the
-- second, since the renderer fills row-major.
local hyperActions = {}
for _, b in ipairs(keys.capture) do
  hyperActions[#hyperActions + 1] = b
end
hyperActions[#hyperActions + 1] = keys.clipboardHistory
hyperActions[#hyperActions + 1] = keys.lock
hyperActions[#hyperActions + 1] = keys.sleep

spoon.HyperCheatSheet:init()
spoon.HyperCheatSheet:configure({
  apps = apps,
  toggles = keys.appToggles,
  cheatSheet = spoon.CheatSheet,
  sections = {
    { title = "ACTIONS", bindings = hyperActions },
  },
})

-- ChordKey: the shared hold/tap/chord engine behind the function-key leaders
-- (HYPER for apps, plus the active window leader). One event tap serves them all;
-- HyperKey and WindowLeader register their keys into it below. These are the
-- defaults each key inherits unless it overrides them.
spoon.ChordKey:init()
spoon.ChordKey:configure({ holdDelay = 0.6, tapThreshold = 0.2 })

-- HyperKey: Caps Lock (remapped to F18 by KeyRemap) as a Hyper key.
-- Hold + letter = app toggles; quick tap = toggle real Caps Lock; hold 0.6s
-- with no key = show the cheat sheet. Registers into the shared ChordKey engine.
spoon.HyperKey:init()
spoon.HyperKey:configure({
  chord = spoon.ChordKey,
  keyCode = leaderCode(keys.appLeader), -- resolved from the catalog (HYPER -> F18)
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
-- WindowLeader: the window leader key. It is whichever catalog key config names
-- as `windowLeader` (META today, Right Option). Hold it and press a key, a bare
-- arrow resizes, Shift+arrow moves, C centers, and , / . switch display. Any
-- other catalog key stays a normal key until some domain references it, so
-- swapping the window leader is a one-word change in config/keys.lua.
spoon.WindowLeader:init()
spoon.WindowLeader:addLeader(leaderCode(keys.windowLeader))

-- Live-state predicates, one shared registry. A binding names one via
-- `when = "<name>"` and is active only while that predicate returns true. Window
-- bindings use it to hide the display-switch keys on a lone screen, and Hyper
-- context layers use it to gate a context (like clipboard navigation) on that UI
-- being open. The single registry is injected into every consumer (WindowManager,
-- the window cheat sheet, and HyperKey), so a key and its overlay never disagree.
-- Keep predicates cheap and free of side effects, since they run on every
-- dispatch and every overlay show.
local predicates = {
  multipleDisplays = function() return #hs.screen.allScreens() > 1 end,
  -- The Hammerspoon clipboard chooser is open. Gates the clipboard Hyper context.
  clipboardOpen = function()
    return spoon.ClipboardHistory ~= nil and spoon.ClipboardHistory.manager.isShowing()
  end,
}
-- The window bindings carry no leader (see config/keys.lua). Stamp the resolved
-- window leader onto each here, in the composition root, so WindowManager and
-- WindowCheatSheet keep working from a single leader without either learning the
-- catalog. This resolve-and-inject is exactly the wiring the root exists for.
local windowLeaderCode = leaderCode(keys.windowLeader)
local windowBindings = {}
for i, binding in ipairs(keys.windowManagement) do
  local copy = {}
  for k, v in pairs(binding) do copy[k] = v end
  copy.leader = windowLeaderCode
  windowBindings[i] = copy
end
spoon.WindowManager:bindToLeader(spoon.WindowLeader, windowBindings, predicates)

-- WindowCheatSheet: hold a leader ~0.6s with no other key to reveal that
-- leader's window actions (same hold rule as Caps Lock -> HyperCheatSheet).
-- Labels are the action names humanized (nextDisplay -> "Next Display") unless
-- an entry sets an explicit `description`.
spoon.WindowCheatSheet:init()
spoon.WindowCheatSheet:configure({
  windowManagement = windowBindings,
  -- The overlay section title. This is the leader's display name, shown as the
  -- heading over its window actions, so it reads like the CAPTURE / CLIPBOARD
  -- headings on the Hyper overlay rather than the raw leader name (META).
  leaders = { [windowLeaderCode] = "WINDOW MANAGEMENT" },
  cheatSheet = spoon.CheatSheet,
  predicates = predicates,
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

-- Every active leader is now registered; start the one shared event tap that
-- drives HYPER and the window leader together. Catalog keys nobody references
-- are neither remapped nor tapped, so they stay normal keys.
spoon.ChordKey:start()

-- AppToggler (uses apps config; toggles fire via the Caps Lock/F18 Hyper modal)
spoon.AppToggler:init()
spoon.AppToggler:configure({ apps = apps, hyperKey = spoon.HyperKey })
spoon.AppToggler:bindHotkeys(keys.appToggles)

-- ClipboardHistory: reveal clipboard history on the Hyper key. The Hammerspoon
-- manager is placed first, so it always wins; Raycast and the macOS Tahoe
-- Spotlight clipboard stay as fallbacks. The chain logs each skip, and
-- availability is rechecked on every open. Reorder the list to change
-- preference, or drop the hammerspoon line to fall back to Raycast.
spoon.ClipboardHistory:init()
spoon.ClipboardHistory.manager.start() -- begin the background pasteboard poll
spoon.ClipboardHistory:configure({
  hyperKey = spoon.HyperKey,
  provider = spoon.ClipboardHistory.providers.firstAvailable({
    spoon.ClipboardHistory.providers.hammerspoon,
    spoon.ClipboardHistory.providers.raycast,
    spoon.ClipboardHistory.providers.spotlightTahoe,
  }),
})
spoon.ClipboardHistory:bindHotkeys({ open = keys.clipboardHistory })

-- Hyper context layers. Inject the shared predicate registry into HyperKey, then
-- expand each context in keys.hyperContexts into HyperKey bindings that carry the
-- context's `when` gate and `priority`. Action names resolve here against the
-- manager methods, the one place that knows both the keys and the clipboard, so
-- config/keys.lua stays pure data and the manager never learns about Hyper. The
-- paste keystroke is delivered even while Hyper is held, because ChordKey ignores
-- synthetic events, so no action needs to wait for release. Adding another
-- switcher later touches only keys.hyperContexts, the predicate registry above,
-- and this action map.
spoon.HyperKey:configure({ predicates = predicates })
local clipManager = spoon.ClipboardHistory.manager
local contextActions = {
  selectNext = function() clipManager.selectNext() end,
  selectPrev = function() clipManager.selectPrev() end,
  insertSelected = function() clipManager.insertSelected() end,
}
for _, ctx in ipairs(keys.hyperContexts or {}) do
  for _, b in ipairs(ctx.bindings) do
    local fn = contextActions[b.action]
    if fn then
      spoon.HyperKey:bind(b.key, fn, b.mods, { when = ctx.when, priority = ctx.priority })
    else
      print("hyperContexts: unknown action '" .. tostring(b.action) .. "'")
    end
  end
end

-- Script / URL trigger: hammerspoon://clipboard opens the popup through the same
-- provider chain, so Raycast, skhd, a shell script, or  hs -c "..."  can summon
-- it without touching the hotkey binding.
hs.urlevent.bind("clipboard", function()
  spoon.ClipboardHistory:open()
end)

-- Capture: screen capture / recording / OCR on the Hyper key, backed by an
-- ordered provider chain. Each action is handled by the first provider that is
-- both installed and supports it, so macshot (its macshot:// URL scheme) is used
-- for screenshots when present and the native macOS shortcuts (Cmd+Shift+4 /
-- Cmd+Shift+5) are the always-available fallback. macocr (schappim's `ocr` CLI)
-- is the sole backend for the OCR action, so it just sits last. Reorder this list
-- to change screenshot priority; drop macshot to use only native (e.g. to
-- sidestep macshot's own capture bugs).
spoon.Capture:init()
spoon.Capture:configure({
  hyperKey = spoon.HyperKey,
  providers = {
    spoon.Capture.providers.macshot,
    spoon.Capture.providers.native,
    spoon.Capture.providers.macocr,
  },
})
spoon.Capture:bindHotkeys(keys.capture)

-- Sleep the Mac on Hyper+Esc and lock the screen on Hyper+§. These are lone
-- system actions, not whole domains, so they are bound directly here in the
-- composition root rather than given a spoon of their own. Each binds into the
-- Hyper modal when HyperKey is wired, otherwise the literal HYPER combo, matching
-- how the other Hyper consumers degrade.
local function bindHyper(binding, fn)
  if spoon.HyperKey then
    spoon.HyperKey:bind(binding.key, fn, binding.mods)
  else
    hs.hotkey.bind(binding.modifiers, binding.key, fn)
  end
end
bindHyper(keys.lock, function()
  hs.caffeinate.lockScreen()
end)
bindHyper(keys.sleep, function()
  hs.caffeinate.systemSleep()
end)

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

-- DisplayProfiles: reapply the saved display arrangement that fits whatever
-- screens are attached, so a dock waking monitors in the wrong order does not
-- leave the wrong main display or scaling. This is the composition root's job
-- and only this. It resolves the machine name, the one place the per host split
-- is decided, and injects that machine's profiles from config/displays.lua. The
-- spoon stays ignorant of hostnames and of the catalog. A machine with no entry
-- gets an empty list and simply does nothing, logged so the reason is visible.
local host = (hs.execute("scutil --get LocalHostName") or ""):gsub("%s+$", "")
local hostProfiles = displays.profiles[host] or {}
spoon.DisplayProfiles:init()
spoon.DisplayProfiles:configure({
  profiles = hostProfiles,
  settleDelay = displays.settleDelay,
})
spoon.DisplayProfiles:start()
if #hostProfiles == 0 then
  print("DisplayProfiles: no profiles for host '" .. host .. "', add one in config/displays.lua")
end

--------------------------------------------------------------------------------
-- Auto-reload and IPC
--------------------------------------------------------------------------------

-- Reload Hammerspoon configuration automatically when files change
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()

-- Enable IPC for command-line control
require("hs.ipc")
