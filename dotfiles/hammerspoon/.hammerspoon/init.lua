-- Hammerspoon Configuration
-- Orchestrates all Spoons and configuration

--------------------------------------------------------------------------------
-- Load Configuration
--------------------------------------------------------------------------------

local apps = require("config.apps")
local keys = require("config.keys")
local settings = require("config.settings")
local displays = require("config.displays")
local settingsPanes = require("config.settingsPanes")

-- Load workspace configurations
local devWorkspace = require("config.workspaces.dev")
local vicertWorkspace = require("config.workspaces.vicert")

--------------------------------------------------------------------------------
-- Load Spoons
--------------------------------------------------------------------------------

hs.loadSpoon("KeyRemap")
hs.loadSpoon("ChordKey")
hs.loadSpoon("CheatSheet")
hs.loadSpoon("Chooser")
hs.loadSpoon("CanvasPanel")
hs.loadSpoon("HyperKey")
hs.loadSpoon("HyperCheatSheet")
hs.loadSpoon("StageManager")
hs.loadSpoon("WindowManager")
hs.loadSpoon("WindowLeader")
hs.loadSpoon("WindowCheatSheet")
hs.loadSpoon("AppToggler")
hs.loadSpoon("ClipboardHistory")
hs.loadSpoon("Caffeinate")
hs.loadSpoon("Vpn")
hs.loadSpoon("Capture")
hs.loadSpoon("Eyedropper")
hs.loadSpoon("WorkspaceEngine")
hs.loadSpoon("TerminalHandler")
hs.loadSpoon("DisplayMemory")
hs.loadSpoon("Launcher")
hs.loadSpoon("DockAutoHide")
hs.loadSpoon("DisplayProfiles")
hs.loadSpoon("SystemSettings")
hs.loadSpoon("Emoji")

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

-- Chooser is the picker facade behind every list tool below, the clipboard, the
-- VPN locations, keep awake, menu search, and the launcher. It wraps the native
-- hs.chooser. There was once a second webview backend built on a Surface spoon,
-- selectable per consumer, but every consumer settled on native so the web backend
-- and the Surface foundation were removed.
spoon.Chooser:init()

-- CheatSheet: the shared overlay behind both cheat sheets. Both builders below
-- draw through this one instance (only ever one overlay is up). It owns only the
-- grid layout and draws through the shared CanvasPanel atom, the same
-- surface as the docked shortcut hint bar; it is configured further down, once the
-- panel fill and border the hint bar uses are in scope, so the two share one look.
spoon.CheatSheet:init()

-- HyperCheatSheet: overlay of everything under Hyper. App toggles first (open vs
-- not running), then one ACTIONS group for the non-app commands. This is the one
-- place that names which non-app bindings surface on the overlay and in what
-- order, so the Capture, ClipboardHistory, and system configs stay pure binding
-- data. The order below is the on-screen order, filled row-major into the four
-- column grid: the colour picker leads, then the four capture actions (OCR,
-- screenshot copy, screenshot file, record), then menu search, keep awake, VPN,
-- clipboard, launcher, and finally lock and sleep.
local hyperActions = { keys.colorPicker }
for _, b in ipairs(keys.capture) do
  hyperActions[#hyperActions + 1] = b
end
hyperActions[#hyperActions + 1] = keys.menuSearch
hyperActions[#hyperActions + 1] = keys.emoji
hyperActions[#hyperActions + 1] = keys.caffeinate
hyperActions[#hyperActions + 1] = keys.vpn
hyperActions[#hyperActions + 1] = keys.clipboardHistory
hyperActions[#hyperActions + 1] = keys.launcher
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
-- defaults each key inherits unless it overrides them. passthrough = true leaks
-- any combo the domains do not claim downstream as leader+key (F18/F17/F16), so
-- other apps can bind combos we leave free; combos we do bind still run here and
-- never leak.
spoon.ChordKey:init()
spoon.ChordKey:configure({ holdDelay = 0.6, tapThreshold = 0.2, passthrough = true })

-- HyperKey: Caps Lock (remapped to F18 by KeyRemap) as a Hyper key.
-- Hold + letter = app toggles; quick tap = toggle real Caps Lock; hold 0.6s
-- with no key = show the cheat sheet. Registers into the shared ChordKey engine.
--
-- The hold reveals the ACTIVE layer's cheat sheet, not always the apps. The base
-- layer is the app overlay. A live modal context reveals its own shortcuts
-- instead. These two functions are forward declared here and assigned once the
-- context overlays and predicates exist below, so the hold wiring stays in one
-- place.
local revealHyperLayer, hideHyperLayer
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
    if revealHyperLayer then revealHyperLayer() end
  end,
  onHoldEnd = function()
    if hideHyperLayer then hideHyperLayer() end
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
-- arrow resizes, WASD moves, C centers, and , / . switch display. Any
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
--
-- Forward-declared so the predicate registry and the chooser navigation registry
-- can name menu search's navigation surface before it is built further below (it
-- needs this predicate table and hideShortcuts, which are defined here). The
-- launcher's surface is not forward-declared, it lives in Launcher.spoon, so its
-- predicate reads the spoon directly.
local menuSearchSurface
-- The overlay display picker's navigation surface, forward-declared so the predicate
-- below and the choosers registry can name it before it is built with the other
-- native-panel choosers further down.
local overlayDisplaySurface
local predicates = {
  multipleDisplays = function() return #hs.screen.allScreens() > 1 end,
  -- The launcher chooser is open. Gates the launcher Hyper context,
  -- so it gets the same j/k/i navigation and hold overlay the clipboard chooser has.
  launcherOpen = function()
    return spoon.Launcher:isShowing()
  end,
  -- The menu search chooser is open. Gates the menuSearch Hyper context.
  menuSearchOpen = function()
    return menuSearchSurface ~= nil and menuSearchSurface.isShowing()
  end,
  -- The Hammerspoon clipboard chooser is open. Gates the clipboard Hyper context.
  clipboardOpen = function()
    return spoon.ClipboardHistory ~= nil and spoon.ClipboardHistory.manager.isShowing()
  end,
  -- The keep awake chooser is open. Gates the caffeinate Hyper context.
  caffeinateOpen = function()
    return spoon.Caffeinate ~= nil and spoon.Caffeinate.isShowing()
  end,
  -- The VPN chooser is open. Gates the vpn Hyper context, so the navigation shortcuts
  -- route to it while it is up.
  vpnOpen = function()
    return spoon.Vpn ~= nil and spoon.Vpn.isShowing()
  end,
  -- The overlay display picker is open. Gates the overlayDisplay Hyper context, so it
  -- gets the same j/k/i/x navigation every other chooser has.
  overlayDisplayOpen = function()
    return overlayDisplaySurface ~= nil and overlayDisplaySurface.isShowing()
  end,
  -- The display profiles chooser is open. Gates the displayProfiles Hyper context.
  displayProfilesOpen = function()
    return spoon.DisplayProfiles ~= nil and spoon.DisplayProfiles.chooser.isShowing()
  end,
  -- The emoji picker chooser is open. Gates the emoji Hyper context, so it takes the
  -- shared j, k, i, and x navigation while it is up.
  emojiOpen = function()
    return spoon.Emoji:isShowing()
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

-- Clipboard shortcut overlay. Holding Hyper while the chooser is open reveals its
-- keys, drawn by the shared CheatSheet renderer from the same keys.hyperContexts
-- data, so the sheet never drifts from the real bindings. It lives here, not in
-- the manager, because it draws through CheatSheet, a root concern. Return,
-- Escape, and the arrows are not Hyper bindings, so they ride along as a second
-- "or" box on the Paste, Close, and move rows for a complete legend. hideShortcuts
-- is injected into the manager as its onClose below, so closing the clipboard also
-- clears the sheet, and it is called before each context action so any key
-- dismisses the sheet.
local shortcutsShown = false
-- Build the shortcut hint chips for a named Hyper context from that context's own
-- bindings, so the footer never drifts from the real keys. The context keys fire
-- on Hyper plus the key, so each chip spells the chord out, Hyper+J, which cannot
-- be misread as a plain key, paired with the plain key that does the same thing,
-- the arrows for move, Return for the primary action, Escape for close, so both
-- ways in are shown at once. These live in each picker's own footer now, drawn
-- persistently under the surface rather than peeked in a separate window on a
-- Hyper hold, so no second window competes for the frosted backdrop. Returned as a
-- list of { badges = {...}, label = ... }, the shape List:_footerHtml consumes.
local function footerFor(name)
  local hints = {}
  for _, ctx in ipairs(keys.hyperContexts or {}) do
    if ctx.name == name then
      for _, b in ipairs(ctx.bindings) do
        local chord = "Hyper+" .. spoon.CheatSheet.glyphFor(b.key, b.mods)
        local badges = { chord }
        if b.action == "insertSelected" or b.action == "enter" then
          badges = { chord, spoon.CheatSheet.glyphFor("return") }
        elseif b.action == "closeChooser" then
          badges = { chord, spoon.CheatSheet.glyphFor("escape") }
        elseif b.action == "selectNext" then
          badges = { chord, spoon.CheatSheet.glyphFor("down") }
        elseif b.action == "selectPrev" then
          badges = { chord, spoon.CheatSheet.glyphFor("up") }
        end
        hints[#hints + 1] = { badges = badges, label = b.description or b.action, action = b.action }
      end
    end
  end
  return hints
end
-- Every chooser runs on the native backend and docks the deferred CanvasPanel for
-- its shortcut hints. The footerFor hints above feed the panels directly.
local function hideShortcuts()
  if shortcutsShown then
    spoon.CheatSheet:hide()
    shortcutsShown = false
  end
end
-- Assign the Hyper hold reveal now that the predicates exist. A hold shows the app
-- cheat sheet when nothing modal is open. When a modal context is live (the
-- clipboard, the VPN locations, the launcher) the hold reveals nothing,
-- because each such surface already shows its shortcuts in its own footer, so a
-- peek window would be redundant and would fight the picker for the frosted
-- backdrop. contextOverlays is therefore empty; it stays as the seam so a context
-- that wants a real hold overlay again can register one here without touching the
-- reveal logic.
local contextOverlays = {}
local function activeContext()
  local best
  for _, ctx in ipairs(keys.hyperContexts or {}) do
    local live = (not ctx.when) or (predicates[ctx.when] and predicates[ctx.when]())
    if live and (not best or (ctx.priority or 0) > (best.priority or 0)) then
      best = ctx
    end
  end
  return best
end
local heldLayer = nil -- what the current hold revealed, context, apps, or none
revealHyperLayer = function()
  local ctx = activeContext()
  if ctx then
    local model = contextOverlays[ctx.name]
    if model then
      spoon.CheatSheet:show(model())
      shortcutsShown = true
      heldLayer = "context"
    else
      heldLayer = "none" -- a modal context with no overlay reveals nothing
    end
  else
    spoon.HyperCheatSheet:show()
    heldLayer = "apps"
  end
end
hideHyperLayer = function()
  if heldLayer == "context" then
    hideShortcuts()
  elseif heldLayer == "apps" then
    spoon.HyperCheatSheet:hide()
  end
  heldLayer = nil
end

-- ClipboardHistory: reveal clipboard history from the launcher and the
-- hammerspoon://clipboard URL, and Hyper+X. The native Hammerspoon manager (the
-- canvas chooser with its docked preview) is placed first and is always available,
-- so Hyper+X opens it. The external backends stay behind it as fallbacks: to hand
-- the hotkey to one, move it ahead of hammerspoon (the shortcut backend fires the
-- shared clipboardShortcut combo, optionally gated on an app). The chain logs each
-- skip, and availability is rechecked on every open.
spoon.ClipboardHistory:init()
-- The native manager's UI (its chooser, canvas preview, and docked shortcut panel)
-- is configured and started further down with the other native-panel choosers,
-- since it needs shortcutPanelFor, which is defined below. Only the reveal routing,
-- which tool opens on the hotkey, is wired here.
local clipShortcut = keys.clipboardShortcut
spoon.ClipboardHistory:configure({
  hyperKey = spoon.HyperKey,
  provider = spoon.ClipboardHistory.providers.firstAvailable({
    -- Native manager first: always available, so Hyper+X opens the canvas clipboard.
    spoon.ClipboardHistory.providers.hammerspoon,
    -- External fallbacks, unreached while the native manager is first. The shortcut
    -- backend fires clipShortcut's combo; give clipboardShortcut an `app` (resolved
    -- to a bundle id here, the one place concretions are named) to gate it on that
    -- app. Move one ahead of hammerspoon above to hand it the hotkey.
    spoon.ClipboardHistory.providers.shortcut({
      name = clipShortcut.app or "Shortcut",
      mods = clipShortcut.mods,
      key = clipShortcut.key,
      bundleID = clipShortcut.app and apps[clipShortcut.app] or nil,
    }),
    spoon.ClipboardHistory.providers.raycast,
    spoon.ClipboardHistory.providers.spotlightTahoe,
  }),
})
spoon.ClipboardHistory:bindHotkeys({ open = keys.clipboardHistory })

-- Caffeinate is wired further down, alongside menu search and VPN, since all three are
-- native choosers that dock the same deferred shortcut hint panel and share its factory,
-- which is defined below.

-- Launcher: the app switcher and command runner on Hyper+Space now lives in
-- Launcher.spoon, a coordinator. It is instantiated and wired below, alongside
-- menu search and VPN, where the shared shortcut panel factory it uses is defined.


-- The shared canvas surface. CanvasPanel owns the look (background, border, corner
-- radius, per light and dark), sourced once from settings.surface. Every surface it
-- draws, the docked hint bars, the cheat sheet, the colour toast, and the clipboard
-- preview pane, reads this one style and stays identical by construction. Edit the
-- values in config/settings.lua, once, and every canvas surface follows.
spoon.CanvasPanel.configure(settings.surface)

-- Overlay display policy, the one place that decides which display every transient
-- overlay appears on. This is Strategy wired through injection, the same shape as
-- TerminalHandler.targetScreen below: a small registry maps a mode name to a resolver
-- returning an hs.screen, config/settings.lua picks the mode, and the chosen resolver
-- is injected into the two atoms (the Chooser and the CanvasPanel). Neither atom names
-- the policy or the modes, so both the choosers (with their docked panels) and the
-- cheat sheets read one seam and agree on the display. Resolvers run at overlay-open
-- time, so they track live state and may safely forward-reference DisplayProfiles,
-- which is configured further down.
local function activeWindowScreen()
  local w = hs.window.focusedWindow()
  return (w and w:screen()) or hs.screen.mainScreen() or hs.screen.primaryScreen()
end
local function cursorScreen()
  return hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
end

-- The runtime policy store, layered over the config default. config/settings.lua's
-- overlayDisplay stays the documented seed; the launcher picker below writes the
-- live choice here, under one hs.settings key, so it survives a reload (frequent
-- here) and a reboot, the same persistence shape as the launcher MRU and
-- DisplayMemory. effectiveMode / effectiveFixed read the stored value first and
-- fall back to the config seed, and the resolvers below read only through them, so
-- a picker choice takes effect on the next overlay with no reload and an unset key
-- still honours the config default. The picker is the only writer; it lives further
-- down and is forward-declared here so the launcher can name it.
local OVERLAY_STORE_KEY = "overlayDisplayPolicy" -- { mode, fixed = { [profile] = serial } }
local OVERLAY_NAMES_KEY = "overlayDisplayNames"  -- remembered { [id] = friendly name }
local showOverlayDisplayPicker
local function overlayStore()
  return hs.settings.get(OVERLAY_STORE_KEY) or {}
end
local function effectiveMode()
  return overlayStore().mode or (settings.overlayDisplay or {}).mode
end
local function effectiveFixed(profile)
  if not profile then return nil end
  local s = overlayStore()
  local stored = s.fixed and s.fixed[profile]
  if stored then return stored end
  return ((settings.overlayDisplay or {}).fixed or {})[profile]
end

-- Fixed mode turns a displayplacer serial id (the portable id config/displays.lua
-- already uses) into a live hs.screen. hs.screen exposes no serial id, so we bridge
-- through `displayplacer list`, which prints, per screen, both its Serial screen id
-- and its Persistent screen id; the persistent id is the CoreGraphics display UUID,
-- the same value hs.screen:getUUID returns, so serial -> persistent -> getUUID resolves
-- exactly. The parse shells out, so the map is cached and cleared on a screen change
-- (the same event DisplayProfiles reacts to), making fixed mode free per open after the
-- first resolve on a given arrangement.
local serialToUUID = nil -- serial id -> persistent id (CoreGraphics UUID)
local uuidToSerial = nil  -- the reverse, so an attached screen resolves to its serial
local function refreshSerialMap()
  serialToUUID, uuidToSerial = {}, {}
  local out = hs.execute("displayplacer list", true) or ""
  local persistent, serial
  local function flush()
    if serial and persistent then
      serialToUUID[serial] = persistent
      uuidToSerial[persistent] = serial
    end
  end
  for line in (out .. "\n"):gmatch("(.-)\n") do
    local p = line:match("Persistent screen id:%s*(%S+)")
    local s = line:match("Serial screen id:%s*(%S+)")
    if p then
      flush() -- close the previous screen block before starting this one
      persistent, serial = p, nil
    elseif s then
      serial = s
    end
  end
  flush()
end
local function screenForSerial(serial)
  if not serial then return nil end
  if not serialToUUID then refreshSerialMap() end
  local uuid = serialToUUID[serial]
  if not uuid then return nil end
  for _, s in ipairs(hs.screen.allScreens()) do
    if s:getUUID() == uuid then return s end
  end
  return nil
end
-- Remembered display names, so the picker can label a display by its friendly name
-- even while it is unplugged, the whole point of managing every setup from one
-- place. hs.screen names a display only while it is attached, so we capture each
-- attached screen's name against its serial id whenever the display set changes,
-- persist it, and read it back for detached ids later. This is the same
-- observe-and-persist shape as DisplayMemory: seeing a monitor once is enough for
-- its name to show forever after.
local function rememberAttachedNames()
  if not uuidToSerial then refreshSerialMap() end
  local names = hs.settings.get(OVERLAY_NAMES_KEY) or {}
  local changed = false
  for _, s in ipairs(hs.screen.allScreens()) do
    local serial = uuidToSerial[s:getUUID() or ""]
    local nm = s:name()
    if serial and nm and names[serial] ~= nm then
      names[serial] = nm
      changed = true
    end
  end
  if changed then hs.settings.set(OVERLAY_NAMES_KEY, names) end
end
-- The friendly name for a display id (a serial), attached or not: the live
-- hs.screen name when it is plugged in, else the remembered name, else the raw id
-- so nothing ever shows blank.
local function displayName(id)
  local screen = screenForSerial(id)
  if screen then return screen:name() end
  local names = hs.settings.get(OVERLAY_NAMES_KEY) or {}
  return names[id] or id
end

-- Rebuild the serial map lazily after any display change, refresh the remembered
-- names while the new set is attached, and let the fixed-mode warning fire once per
-- arrangement rather than on every open. Kept module-local so the watcher is not
-- garbage collected.
local fixedWarned = false
local overlayScreenWatcher = hs.screen.watcher.new(function()
  serialToUUID, uuidToSerial = nil, nil
  fixedWarned = false
  rememberAttachedNames()
end)
overlayScreenWatcher:start()
rememberAttachedNames() -- seed from whatever is attached at load

local function fixedScreen()
  local profile = spoon.DisplayProfiles:current()
  local serial = effectiveFixed(profile)
  local screen = serial and screenForSerial(serial)
  if screen then return screen end
  if not fixedWarned then
    fixedWarned = true
    print(string.format(
      "overlayDisplay: fixed mode has no display for profile '%s' (serial '%s'), using active window",
      tostring(profile), tostring(serial)))
  end
  return activeWindowScreen()
end

-- Keyed by the same overlayModes constants config/settings.lua names, so the valid
-- mode names live in one place and the two sides cannot drift.
local overlayScreenStrategies = {
  [settings.overlayModes.activeWindow] = activeWindowScreen,
  [settings.overlayModes.cursor] = cursorScreen,
  [settings.overlayModes.fixed] = fixedScreen,
}
-- The injected contract. Reads the effective mode fresh each open (the persisted
-- picker choice, else the config seed), so a mode switch takes effect on the next
-- overlay with no reload. Unknown mode falls back to activeWindow, and a resolver
-- returning nil to the primary screen.
local function overlayScreen()
  local fn = overlayScreenStrategies[effectiveMode()] or activeWindowScreen
  return fn() or hs.screen.primaryScreen()
end
spoon.CanvasPanel.setScreenProvider(overlayScreen)
-- One matching policy for every chooser, decided here. Fuzzy subsequence ranking is the
-- default, so the launcher, VPN, and menu search filter alike and a future list chooser
-- gets it for free. The clipboard and caffeinate opt out at their own new() (matcher =
-- false) because their query is not a plain filter, the clipboard parsing a type prefix
-- and then reusing this same matcher for the free-text part, caffeinate parsing a time.
-- Swap to spoon.Chooser.matchers.substring here to return every list to the old behaviour.
spoon.Chooser.configure({ screen = overlayScreen, matcher = spoon.Chooser.matchers.fuzzy })

-- The overlay display picker is built below, alongside the other native-panel
-- choosers, since it docks the shared shortcut hint panel and follows the picker
-- checklist (its own control surface, `when` predicate, choosers-registry entry,
-- and hyperContexts block) so the Hyper j/k/i/x navigation works in it too. It
-- reads the store helpers (effectiveMode/effectiveFixed/displayName) defined above.

-- Finish wiring the cheat sheet. It draws its binding grid through the CanvasPanel
-- atom, centered on screen, inheriting the one shared surface, so no fill or border
-- is passed here. The cheatSheet settings block tunes only the content, font size,
-- padding, and badge radius.
local cheatOpts = { theme = settings.chooserTheme, canvasPanel = spoon.CanvasPanel }
for k, v in pairs(settings.cheatSheet or {}) do cheatOpts[k] = v end
spoon.CheatSheet:configure(cheatOpts)

-- Shortcut hints as a HelperPanel content renderer: the first PURPOSE of the panel.
-- It measures and draws the chord chips, wrapping them to the width the panel offers,
-- and knows nothing about placement or the panel's fill and border (the panel owns
-- those). Theme aware per draw, so the text tracks light and dark. Another purpose is
-- just another content object with the same preferredSize/draw contract. It draws in
-- the panel's content box, origin (0, 0); the panel offsets it by its own padding.
local function shortcutsContent(theme, hints)
  local chipGapX, rowGapY = 16, 8
  local hintGap = 6
  local badgeH, badgePadX, badgeR = 18, 6, 5
  local badgeSize, labelSize = 11, 12
  local font = ".AppleSystemUIFont"

  local function textW(str, size)
    local sz = hs.drawing.getTextDrawingSize(hs.styledtext.new(str, { font = { name = font, size = size } }))
    return math.ceil((sz and sz.w) or 0)
  end
  local function chipW(h)
    local w = textW(h.label or "", labelSize)
    for _, b in ipairs(h.badges or {}) do w = w + textW(b, badgeSize) + 2 * badgePadX end
    return w + hintGap * #(h.badges or {})
  end
  -- Wrap chips into rows that fit width w, recording each chip's x within its row.
  local function wrap(w)
    local rows, cur, curW = {}, {}, 0
    for _, h in ipairs(hints) do
      local cw = chipW(h)
      if #cur > 0 and curW + chipGapX + cw > w then rows[#rows + 1] = cur; cur, curW = {}, 0 end
      local startX = (#cur == 0) and 0 or (curW + chipGapX)
      cur[#cur + 1] = { h = h, x = startX }
      curW = startX + cw
    end
    if #cur > 0 then rows[#rows + 1] = cur end
    return rows
  end
  local function rowsHeight(rows)
    return #rows * badgeH + math.max(0, #rows - 1) * rowGapY
  end

  return {
    preferredSize = function(availW)
      local w = availW or 320
      return { w = w, h = rowsHeight(wrap(w)) }
    end,
    draw = function(w)
      local dark = hs.host.interfaceStyle() == "Dark"
      local side = (dark and theme.dark) or theme.light or theme.dark or {}
      local fg = side.titleColor or { white = dark and 0.92 or 0.15 }
      local meta = side.subColor or { white = dark and 0.55 or 0.42 }
      local badgeBg = { white = dark and 1 or 0, alpha = dark and 0.12 or 0.06 }
      local els, rows = {}, wrap(w)
      for ri, row in ipairs(rows) do
        local rowTop = (ri - 1) * (badgeH + rowGapY)
        for _, chip in ipairs(row) do
          local cx = chip.x
          for _, b in ipairs(chip.h.badges or {}) do
            local bw = textW(b, badgeSize) + 2 * badgePadX
            els[#els + 1] = { type = "rectangle", action = "fill", fillColor = badgeBg,
              roundedRectRadii = { xRadius = badgeR, yRadius = badgeR },
              frame = { x = cx, y = rowTop, w = bw, h = badgeH } }
            els[#els + 1] = { type = "text", text = b, textFont = font, textSize = badgeSize,
              textColor = fg, textAlignment = "center",
              frame = { x = cx, y = rowTop + (badgeH - badgeSize) / 2 - 1, w = bw, h = badgeSize + 4 } }
            cx = cx + bw + hintGap
          end
          local lw = textW(chip.h.label or "", labelSize)
          els[#els + 1] = { type = "text", text = chip.h.label or "", textFont = font,
            textSize = labelSize, textColor = meta, textAlignment = "left",
            frame = { x = cx, y = rowTop + (badgeH - labelSize) / 2, w = lw + 4, h = labelSize + 4 } }
        end
      end
      return els
    end,
  }
end

-- The deferred shortcut hint panel, shared by every native chooser that wants one
-- (the launcher, menu search, VPN). One factory builds a CanvasPanel docked below the
-- chooser, inheriting the shared surface so it matches the native picker, with that
-- context's footerFor hints as its content, and returns the three callbacks a native
-- chooser is wired with. arm on onPositioned starts the idle countdown (the panel stays
-- hidden until the user pauses), poke on onActivity resets it on each keypress, and hide
-- on onClose tears it down and clears any peeked overlay. The idle delay is the one
-- settings.shortcutsPanel.delayMs, so editing it there applies to every panel this
-- builds; nil or 0 there shows the panel instantly on open.
local function shortcutPanelFor(context)
  local panel = spoon.CanvasPanel.new({
    placement = "below",
    gap = 8,
    padX = 14, padY = 10,
    delay = settings.shortcutsPanel and settings.shortcutsPanel.delayMs,
    content = shortcutsContent(settings.chooserTheme, footerFor(context)),
  })
  return {
    onPositioned = function(frame) panel:arm(frame) end,
    onActivity = function() panel:poke() end,
    onClose = function()
      hideShortcuts()
      panel:hide()
    end,
  }
end

-- The overlay display picker, a launcher-only chooser that switches the policy at
-- runtime. It has no Hyper key by design (reached only through the launcher), but
-- it follows the picker checklist like every other list tool, so once open it gets
-- the shared Hyper j/k/i/x navigation and docks the same shortcut hint panel. Typing
-- filters the current view's rows, and arrows, Return, and Escape drive it too.
-- hs.chooser dismisses on every select, so a drill (into Configure, a profile, or
-- Back) records the target view and reopens on a short timer, the reopen idiom menu
-- search uses; a commit (a mode, or a display for a profile) writes the store and
-- either closes or returns to the profile list so several can be set in a row.
-- Wrapped in a do block so its helpers stay out of the root's local budget; only
-- showOverlayDisplayPicker and overlayDisplaySurface, forward-declared above, escape
-- for the launcher and the shared nav registry.
do
  local modes = settings.overlayModes
  local MODE_LABEL = {
    [modes.cursor] = "Follow mouse cursor",
    [modes.activeWindow] = "Follow active window",
    [modes.fixed] = "Pin to a display",
  }
  -- Row icons are emoji rendered to images in the left icon slot, matching the
  -- launcher's look rather than a glyph prefix in the title. A selected row (the
  -- active mode, the pinned display) shows the check; an unselected default row
  -- shows its category emoji.
  local MODE_ICON = {
    [modes.cursor] = "🖱️",
    [modes.activeWindow] = "🎯",
    [modes.fixed] = "📌",
  }
  local ICON_SELECTED, ICON_BACK, ICON_CONFIG, ICON_DISPLAY = "✅", "⬅️", "⚙️", "🖥️"
  -- Emoji -> image, once per emoji and cached, sized to line up with app icons, the
  -- same technique Launcher uses for its glyph rows since this Hammerspoon has no SF
  -- Symbol API.
  local iconCache = {}
  local function emojiIcon(glyph)
    if not glyph then return nil end
    if iconCache[glyph] == nil then
      local size = 72
      local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
      c[1] = { type = "text", text = glyph, textSize = 52, textAlignment = "center",
               frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
      iconCache[glyph] = c:imageFromCanvas() or false
      c:delete()
    end
    return iconCache[glyph] or nil
  end
  -- The current view: "root" (modes + the Configure door), "configure" (the
  -- profile list), or "profile" (one profile's displays). profile names the
  -- profile while in the profile view. Reset to root on each fresh open.
  local nav = { view = "root" }
  local picker

  -- The profile's ordered display ids, read live from DisplayProfiles.
  local function profileIds(name)
    for _, p in ipairs(spoon.DisplayProfiles:profiles()) do
      if p.name == name then return p.ids end
    end
    return {}
  end

  -- Build the current view's rows, then filter by the typed query (case-insensitive
  -- substring over title and subtitle), so the field filters like any chooser. The
  -- query resets to empty on each show, so it clears when drilling between views.
  local function buildRows(query)
    local out = {}
    if nav.view == "root" then
      local mode = effectiveMode()
      for _, m in ipairs({ modes.cursor, modes.activeWindow, modes.fixed }) do
        out[#out + 1] = {
          title = MODE_LABEL[m],
          image = emojiIcon(mode == m and ICON_SELECTED or MODE_ICON[m]),
          item = { commit = "mode", mode = m },
        }
      end
      out[#out + 1] = {
        title = "Configure displays…",
        subTitle = "Set which display each setup pins to",
        image = emojiIcon(ICON_CONFIG),
        item = { nav = "configure" },
      }
    elseif nav.view == "configure" then
      out[#out + 1] = { title = "Back", image = emojiIcon(ICON_BACK), item = { nav = "root" } }
      local current = spoon.DisplayProfiles:current()
      local profiles = spoon.DisplayProfiles:profiles()
      if #profiles == 0 then
        out[#out + 1] = { title = "No display setups defined", enabled = false,
          subTitle = "Add profiles in config/displays.lua" }
      end
      for _, p in ipairs(profiles) do
        local serial = effectiveFixed(p.name)
        local pinned = serial and displayName(serial) or "not set"
        local here = (p.name == current) and "   ● you are here" or ""
        out[#out + 1] = {
          title = p.name,
          subTitle = "Pins to: " .. pinned .. here,
          image = emojiIcon(ICON_DISPLAY),
          item = { nav = "profile", profile = p.name },
        }
      end
    elseif nav.view == "profile" then
      out[#out + 1] = { title = "Back", image = emojiIcon(ICON_BACK), item = { nav = "configure" } }
      local chosen = effectiveFixed(nav.profile)
      for _, id in ipairs(profileIds(nav.profile)) do
        out[#out + 1] = {
          title = displayName(id),
          subTitle = id,
          image = emojiIcon(chosen == id and ICON_SELECTED or ICON_DISPLAY),
          item = { commit = "pin", profile = nav.profile, serial = id },
        }
      end
    end
    local q = (query or ""):lower()
    if q == "" then return out end
    local filtered = {}
    for _, r in ipairs(out) do
      local hay = ((r.title or "") .. " " .. (r.subTitle or "")):lower()
      if hay:find(q, 1, true) then filtered[#filtered + 1] = r end
    end
    return filtered
  end

  local function reopen()
    hs.timer.doAfter(0.04, function() picker:show() end)
  end

  local function onSelect(item)
    if not item then return end
    if item.nav then
      nav = { view = item.nav, profile = item.profile }
      reopen()
    elseif item.commit == "mode" then
      local s = overlayStore()
      s.mode = item.mode
      hs.settings.set(OVERLAY_STORE_KEY, s)
      nav = { view = "root" } -- committed, chooser closes
    elseif item.commit == "pin" then
      -- Configuring a pin is configuration only. It records which display this
      -- profile pins to and never touches the active mode; pin mode is chosen
      -- separately from the root view, so setting up pins does not silently switch
      -- where overlays appear.
      local s = overlayStore()
      s.fixed = s.fixed or {}
      s.fixed[item.profile] = item.serial
      hs.settings.set(OVERLAY_STORE_KEY, s)
      nav = { view = "configure" } -- back to the list so another setup can be set
      reopen()
    end
  end

  -- Docks the same deferred hint panel the other choosers use, so its Hyper j/k/i/x
  -- hints spell out once the user pauses. The panel is closed on teardown (including
  -- between drills) and re-armed on the reopen, which is fine.
  local odPanel = shortcutPanelFor("overlayDisplay")
  picker = spoon.Chooser.new({
    theme = settings.chooserTheme,
    placeholder = "Overlay display",
    fieldMode = "filter", -- type to filter the current view's rows
    -- A drill-in menu whose supplier morphs its rows per view and does its own
    -- substring filter in buildRows, exactly the query-driven shape caffeinate and
    -- the DisplayProfiles chooser are, so it opts out of the atom's fuzzy matcher.
    -- Without this the atom would fuzzy-filter and reorder the morphing rows and hide
    -- the Back and commit rows.
    matcher = false,
    rows = buildRows,
    onSelect = onSelect,
    onPositioned = odPanel.onPositioned,
    onActivity = odPanel.onActivity,
    onClose = odPanel.onClose,
  })

  -- Dot-called navigation adapter over the colon-called Chooser instance, so the
  -- shared activeChooser / routeNav registry drives it like every other picker.
  overlayDisplaySurface = {
    isShowing = function() return picker:isShowing() end,
    selectNext = function() picker:selectNext() end,
    selectPrev = function() picker:selectPrev() end,
    insertSelected = function() picker:insertSelected() end,
    hide = function() picker:hide() end,
  }

  showOverlayDisplayPicker = function()
    nav = { view = "root" }
    picker:show()
  end
end

-- The row runs deferred, after the chooser has torn down and macOS has restored
-- focus to the app that was frontmost before the launcher opened. Window actions
-- act on hs.window.focusedWindow(), so they must run once that window is focused
-- again rather than while the chooser holds focus. Like menu search and VPN it docks
-- the same deferred shortcut panel through the three chooser callbacks, and its
-- onClose also clears any peeked overlay, matching the clipboard.
-- Launcher.spoon, the coordinator that owns the app switcher and command runner.
-- The root injects every collaborator, the Chooser factory, the pure keys and apps
-- data, the window actions, a chord glyph resolver, the System Settings pane
-- descriptors, the shared predicate registry, the docked shortcut panel, and the
-- leaf actions that name the domain spoons. So this is the one place that maps the
-- app list and the pure binding data onto the domain spoons, and the spoon stays
-- ignorant of what a row does, the Command pattern with the command encoded as data.
-- Its navigation surface is registered in `choosers` and its `launcherOpen`
-- predicate above, both where the shared registries live. The leaf action closures
-- are only called at runtime, so the domain spoons they name need only be configured
-- by the time a row is chosen, not now.
spoon.SystemSettings:configure({ panes = settingsPanes })
spoon.Launcher:init()
spoon.Launcher:configure({
  chooser = spoon.Chooser,
  theme = settings.chooserTheme,
  placeholder = "Search apps and commands",
  keys = keys,
  apps = apps,
  windowActions = spoon.WindowManager:actions(),
  windowLeaderName = "Meta", -- keys.windowLeader is META today; display name
  glyphFor = spoon.CheatSheet.glyphFor,
  settingsPanes = spoon.SystemSettings:rows(),
  predicates = predicates,
  shortcutPanel = shortcutPanelFor("launcher"),
  actions = {
    app = function(bundleID, url)
      if url then
        spoon.AppToggler:toggleURL(bundleID, url)
      else
        spoon.AppToggler:focusOrCycle(bundleID)
      end
    end,
    capture = function(name) spoon.Capture:capture(name) end,
    settingsPane = function(url) spoon.SystemSettings:open(url) end,
    special = {
      clipboard = function() spoon.ClipboardHistory:open() end,
      caffeinate = function() spoon.Caffeinate.show() end,
      vpn = function() spoon.Vpn.show() end,
      colorPicker = function() spoon.Eyedropper:pick() end,
      lock = function() hs.caffeinate.lockScreen() end,
      sleep = function() hs.caffeinate.systemSleep() end,
      searchSettings = function() spoon.SystemSettings:focusSearch() end,
      overlayDisplay = function() showOverlayDisplayPicker() end,
      displayProfiles = function() spoon.DisplayProfiles.chooser.show() end,
    },
  },
})
spoon.Launcher:start()
-- Open key: a base HyperKey binding, suppressed while a modal context owns Hyper.
-- Hyper+Space always opens the launcher. Same shape as the clipboard.
spoon.HyperKey:bind(keys.launcher.key, function() spoon.Launcher:show() end)

-- Menu search: Hyper+E lists every enabled menu bar item of the frontmost app and
-- runs the chosen one. Like the launcher this is pure composition-root
-- policy over the same Chooser atom, so it adds no spoon. macOS exposes each app's
-- menus through the Accessibility API, which hs.application:getMenuItems reads; the
-- callback form does the tree walk off the main thread, so a large menu never
-- blocks Hammerspoon. The app frontmost when Hyper+E fires is captured as the
-- target, since showing the chooser takes focus, and the chosen item is dispatched
-- back to that app once focus returns to it.
--
-- Each row carries only a serializable descriptor, its menu path as a list of
-- titles, never a function, the same reason the palette rows do: hs.chooser
-- serialises each row and would silently drop a function. selectMenuItem takes
-- that path. The menu tree is fetched per open (it changes with the app and its
-- state), so the rows supplier reads a module-local list the fetch fills, and the
-- chooser is shown only once the fetch has built the rows.

-- hs decodes AXMenuItemCmdModifiers into a list of modifier names (e.g. { "cmd" }
-- or { "cmd", "shift" }). Turn it plus the command char into a readable glyph for
-- the row subtitle, in the canonical ⌃⌥⇧⌘ order, or nil when the item has no
-- keyboard shortcut. Both alt/option and ctrl/control spellings are accepted.
local function menuShortcutGlyph(char, mods)
  if not char or char == "" then return nil end
  local has = {}
  for _, m in ipairs(mods or {}) do has[tostring(m):lower()] = true end
  local g = ""
  if has.ctrl or has.control then g = g .. "⌃" end
  if has.alt or has.option then g = g .. "⌥" end
  if has.shift then g = g .. "⇧" end
  if has.cmd or has.command then g = g .. "⌘" end
  return g .. char:upper()
end

-- Flatten the nested AX menu tree into leaf rows. An entry's submenu is its
-- AXChildren[1] (a list); an entry with one is a container we recurse into, an
-- entry without is a runnable leaf. Blank-title entries (separators) are skipped,
-- and disabled items are dropped so the list stays actionable. Each leaf keeps the
-- full title path for selectMenuItem, plus its parent path and shortcut for display.
local function flattenMenus(entries, path, out)
  for _, e in ipairs(entries) do
    local title = e.AXTitle
    if title and title ~= "" then
      local kids = e.AXChildren and e.AXChildren[1]
      local newPath = {}
      for i = 1, #path do newPath[i] = path[i] end
      newPath[#newPath + 1] = title
      if type(kids) == "table" and #kids > 0 then
        flattenMenus(kids, newPath, out)
      elseif e.AXEnabled ~= false then
        local parents = {}
        for i = 1, #newPath - 1 do parents[i] = newPath[i] end
        out[#out + 1] = {
          title = title,
          path = newPath,
          parents = table.concat(parents, " ▸ "),
          shortcut = menuShortcutGlyph(e.AXMenuItemCmdChar, e.AXMenuItemCmdModifiers),
        }
      end
    end
  end
end

local menuRows = {}   -- filled by the async fetch on each open
local menuTargetApp   -- the app frontmost when Hyper+E fired, the dispatch target
local menuAppIcon     -- the target app's icon, shown on every row (one app per open)
local menuAppKey      -- a stable icon key so that icon is encoded once, not per row

-- Rows supplier. Returns every menu item and lets the atom's shared matcher filter and
-- rank, so typing a parent menu name (File, Format) narrows too since the path rides in
-- filterText. The shortcut glyph rides in the subtitle after the path.
local function menuSearchRows(_)
  local out = {}
  for _, r in ipairs(menuRows) do
    local subtitle = r.parents
    if r.shortcut then
      subtitle = (subtitle ~= "" and (subtitle .. "   ") or "") .. r.shortcut
    end
    -- Every item belongs to the one captured app, so each row shows that app's
    -- icon. The stable key memoizes the encoded icon once rather than per row.
    out[#out + 1] = { title = r.title, subTitle = subtitle, image = menuAppIcon,
                      iconKey = menuAppKey, item = { path = r.path },
                      filterText = r.title .. " " .. r.parents }
  end
  return out
end

-- The chosen item runs deferred, after the chooser tears down and macOS restores
-- focus to the captured app, since a menu action acts on that app. The shortcut
-- panel is wired in through onPositioned/onActivity/onClose, so it complements the
-- native chooser without the chooser knowing about it.
local menuPanel = shortcutPanelFor("menuSearch")
local menuSearch = spoon.Chooser.new({
  theme = settings.chooserTheme,
  placeholder = "Search menu items",
  rows = menuSearchRows,
  onSelect = function(item)
    if item and item.path and menuTargetApp then
      local app = menuTargetApp
      hs.timer.doAfter(0.1, function() app:selectMenuItem(item.path) end)
    end
  end,
  onPositioned = menuPanel.onPositioned,
  onActivity = menuPanel.onActivity,
  onClose = menuPanel.onClose,
})
-- Dot-called navigation adapter over the Chooser instance, so the shared
-- activeChooser / routeNav registry drives it exactly like the other pickers.
menuSearchSurface = {
  isShowing = function() return menuSearch:isShowing() end,
  selectNext = function() menuSearch:selectNext() end,
  selectPrev = function() menuSearch:selectPrev() end,
  insertSelected = function() menuSearch:insertSelected() end,
  hide = function() menuSearch:hide() end,
}

-- Open the built-in menu search: capture the frontmost app, fetch its menus
-- asynchronously so a large tree never blocks, then show the chooser once the rows
-- are built. Does nothing if no app is frontmost, the app exposes no menus, or focus
-- moved before the fetch returned (so we never target the wrong app).
local function openBuiltinMenuSearch()
  local app = hs.application.frontmostApplication()
  if not app then return end
  menuTargetApp = app
  local bundleID = app:bundleID()
  menuAppIcon = bundleID and hs.image.imageFromAppBundle(bundleID) or nil
  menuAppKey = bundleID and ("menuapp:" .. bundleID) or nil
  app:getMenuItems(function(menus)
    if not menus then return end
    if hs.application.frontmostApplication() ~= app then return end
    menuRows = {}
    flattenMenus(menus, {}, menuRows)
    menuSearch:show()
  end)
end

-- External combo hand-off, kept but disabled. Uncomment this block and bind
-- fireMenuSearchCombo below (instead of openBuiltinMenuSearch) to make Hyper+E fire
-- menuSearchShortcut (⇧⌃⌥⌘J) so an external tool bound to that same combo anywhere
-- opens. Disabled because routing through an Alfred hotkey added noticeable latency
-- versus the built-in chooser, which binds directly with no synthesized combo and no
-- round-trip. The menuSearchShortcut data stays in config/keys.lua for re-enabling.
-- local menuShortcut = keys.menuSearchShortcut
-- local function fireMenuSearchCombo()
--   hs.eventtap.keyStroke(menuShortcut.mods, menuShortcut.key, 0)
-- end

-- Open key. Bound to the built-in chooser: fast, direct, shows the app icon. Swap to
-- fireMenuSearchCombo (uncomment above) to hand off to an external tool instead.
spoon.HyperKey:bind(keys.menuSearch.key, openBuiltinMenuSearch)

-- VPN controls: a native chooser on Hyper+Y that merges the controls and the locations
-- into one flat list, Connect or Disconnect on top and every city below. It is pinned to
-- the native backend inside the spoon, so it needs only the shared theme and the Chooser
-- factory injected here, plus the same deferred shortcut panel menu search uses, wired
-- through the three chooser callbacks. The vpn Hyper context (see config/keys.lua) drives
-- the j, k, i, and x shortcuts through the choosers registry below. When the Mullvad CLI
-- is missing the spoon logs to the console and stays inert, so this wiring is safe on any
-- machine. The open key is a base HyperKey binding, suppressed while a modal context owns
-- Hyper.
local vpnPanel = shortcutPanelFor("vpn")
spoon.Vpn.configure({
  theme = settings.chooserTheme,
  chooser = spoon.Chooser,
  onPositioned = vpnPanel.onPositioned,
  onActivity = vpnPanel.onActivity,
  onClose = vpnPanel.onClose,
})
spoon.Vpn.start()
spoon.HyperKey:bind(keys.vpn.key, function() spoon.Vpn.show() end)

-- Caffeinate: the keep awake chooser on Hyper+K. Its search field doubles as the value
-- entry, a clock like 15:55 or a duration like 1h30m, so it needs only the shared theme
-- and the Chooser factory injected here, plus the same deferred shortcut panel menu search
-- and VPN use, wired through the three chooser callbacks. The caffeinate Hyper context (see
-- config/keys.lua) drives the j, k, i, and x shortcuts through the choosers registry below.
-- The open key is a base HyperKey binding, suppressed while a modal context owns Hyper.
local caffeinatePanel = shortcutPanelFor("caffeinate")
spoon.Caffeinate.configure({
  theme = settings.chooserTheme,
  chooser = spoon.Chooser,
  onPositioned = caffeinatePanel.onPositioned,
  onActivity = caffeinatePanel.onActivity,
  onClose = caffeinatePanel.onClose,
})
spoon.Caffeinate.start()
spoon.HyperKey:bind(keys.caffeinate.key, function() spoon.Caffeinate.show() end)

-- Emoji picker: a native chooser on Hyper+J that lists every emoji and matches by
-- keyword, so a word finds a glyph without its exact name. It is a small coordinator
-- spoon over the same Chooser atom, so the root injects only the Chooser factory, the
-- shared theme, the same deferred shortcut panel the other choosers dock, and onInsert,
-- the effect of a pick. onInsert types the glyph into the field that was focused before
-- the picker opened, deferred a moment so it runs after the chooser tears down and macOS
-- restores that focus, the same defer the launcher uses. The emoji Hyper context (see
-- config/keys.lua) drives the j, k, i, and x shortcuts through the choosers registry
-- below. The open key is a base HyperKey binding, suppressed while a modal context owns
-- Hyper.
spoon.Emoji:init()
spoon.Emoji:configure({
  chooser = spoon.Chooser,
  theme = settings.chooserTheme,
  placeholder = "Search emoji by name or keyword",
  shortcutPanel = shortcutPanelFor("emoji"),
  onInsert = function(glyph)
    hs.timer.doAfter(0.1, function() hs.eventtap.keyStrokes(glyph) end)
  end,
})
spoon.HyperKey:bind(keys.emoji.key, function() spoon.Emoji:show() end)

-- Clipboard manager UI: the native chooser with its canvas preview docked in the
-- companion pane and the same deferred shortcut panel the other choosers use. The
-- panel spells the shortcuts out below the list. The manager owns onPositioned to place its preview, so the
-- panel's onPositioned is injected and composed inside the manager's (it forwards the
-- chooser frame back out), while onActivity and onClose pass straight through. The
-- theme comes from the one source in config/settings.lua so the preview follows the
-- system light and dark appearance. start() begins the background pasteboard poll and
-- builds the picker; the reveal routing (which tool opens on the hotkey) was wired
-- above. The clipboard Hyper context (config/keys.lua) drives its shortcuts through
-- the choosers registry below.
local clipPanel = shortcutPanelFor("clipboard")
spoon.ClipboardHistory.manager.configure({
  theme = settings.chooserTheme,
  chooser = spoon.Chooser,
  -- The clipboard parses a type prefix off its query ("img ...") so it owns filtering and
  -- opts out of the atom's matcher at its own new(). It reuses this same shared matcher for
  -- the free-text part, so the one matcher policy still reaches the clipboard. Swap this to
  -- spoon.Chooser.matchers.substring to give the clipboard plain substring search.
  matcher = spoon.Chooser.matchers.fuzzy,
  -- The preview pane paints its background and border through the shared surface, so
  -- it matches the docked hint panel and the cheat sheet and rounds the same way. The
  -- clipboard draws its own canvas (it scrolls and clips), so it gets the surface as
  -- elements to prepend rather than a CanvasPanel instance.
  surface = spoon.CanvasPanel.surfaceElements,
  onPositioned = clipPanel.onPositioned,
  onActivity = clipPanel.onActivity,
  onClose = clipPanel.onClose,
})
spoon.ClipboardHistory.manager.start()

-- Hyper context layers. Inject the shared predicate registry into HyperKey, then
-- expand each context in keys.hyperContexts into HyperKey bindings that carry the
-- context's `when` gate and `priority`. config/keys.lua stays pure data and the
-- tools never learn about Hyper. The paste keystroke is delivered even while Hyper
-- is held, because ChordKey ignores synthetic events, so no action waits for
-- release. Adding another switcher later touches only keys.hyperContexts, the
-- predicate registry above, and this action map.
--
-- The navigation actions are shared. Only one chooser is ever open, so they route
-- to the active one, resolved from a small registry by isShowing, and both the
-- clipboard and caffeinate contexts reference the same action names. Append is
-- clipboard only. Every action first dismisses the peeked shortcut overlay, so a
-- glance at the sheet plus any key clears it.
spoon.HyperKey:configure({ predicates = predicates })
local clipManager = spoon.ClipboardHistory.manager
local choosers = { clipManager, spoon.Caffeinate, spoon.Vpn, spoon.Launcher:surface(), menuSearchSurface, spoon.DisplayProfiles.chooser, spoon.Emoji:surface(), overlayDisplaySurface }
local function activeChooser()
  for _, c in ipairs(choosers) do
    if c.isShowing() then return c end
  end
  return nil
end
local function routeNav(method)
  return function()
    hideShortcuts()
    local c = activeChooser()
    if c and c[method] then c[method]() end
  end
end
local contextActions = {
  selectNext = routeNav("selectNext"),
  selectPrev = routeNav("selectPrev"),
  insertSelected = routeNav("insertSelected"),
  -- The display profiles menu confirms in place through its own enter, so a drill or a step
  -- back never closes and re-shows. Only that context binds it; on any other active chooser
  -- routeNav's method guard makes it a no op.
  enter = routeNav("enter"),
  closeChooser = routeNav("hide"),
  appendSelected = function() hideShortcuts() clipManager.appendSelected() end,
  -- Delete is clipboard only, like append, so it calls the manager directly rather
  -- than routing to whatever chooser is active.
  deleteSelected = function() hideShortcuts() clipManager.deleteSelected() end,
  -- Preview scroll routes like the other nav actions; only the clipboard surface
  -- answers scrollPreview, so on any other active chooser the routeNav method guard
  -- makes it a no op.
  scrollPreviewDown = routeNav("scrollPreviewDown"),
  scrollPreviewUp = routeNav("scrollPreviewUp"),
}
-- Nav actions that auto-repeat while the key is held, so holding Hyper+j/k in any
-- chooser scrolls like a held arrow key. The initial delay and repeat rate are the
-- OS autorepeat's own timing (System Settings > Keyboard), inherited for free.
-- Toggles are deliberately absent, so they still fire once per press.
local repeatableActions = {
  selectNext = true,
  selectPrev = true,
  scrollPreviewDown = true,
  scrollPreviewUp = true,
}
for _, ctx in ipairs(keys.hyperContexts or {}) do
  for _, b in ipairs(ctx.bindings) do
    local fn = contextActions[b.action]
    if fn then
      spoon.HyperKey:bind(b.key, fn, b.mods, {
        when = ctx.when,
        priority = ctx.priority,
        repeats = repeatableActions[b.action],
      })
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

-- Eyedropper: a screen colour sampler on Hyper+2. Unlike the choosers it is a lone
-- mechanism, not a list tool, so it needs no Hyper context, predicate, or choosers
-- entry. It is wired exactly like lock and sleep, a base HyperKey binding (bound
-- through bindHyper below), and it is also reachable as the color picker launcher
-- row through the special action dispatcher above. The click copies the pixel hex.
--
-- The copied confirmation is drawn on the shared CanvasPanel, the same
-- surface as the cheat sheet and the docked hint bars, so the feedback reads as one
-- UI rather than a stray hs.alert. It is a centered panel showing the picked colour
-- as a swatch beside its hex, shown on each pick and hidden shortly after by a timer.
-- The content reads a small mutable state the onPick updates, so one panel instance
-- is reused. This is the root owning the look while the spoon owns only the sampling.
local function colorToastContent(theme, state)
  local font = "Menlo"
  local hexSize, swatch, gap = 18, 26, 12
  local function textW(str)
    local sz = hs.drawing.getTextDrawingSize(hs.styledtext.new(str, { font = { name = font, size = hexSize } }))
    return math.ceil((sz and sz.w) or 0)
  end
  return {
    preferredSize = function()
      return { w = swatch + gap + textW(state.hex), h = swatch }
    end,
    draw = function(w, h)
      local dark = hs.host.interfaceStyle() == "Dark"
      local side = (dark and theme.dark) or theme.light or theme.dark or {}
      local fg = side.titleColor or { white = dark and 0.92 or 0.15 }
      local swStroke = { white = dark and 1 or 0, alpha = dark and 0.25 or 0.2 }
      return {
        { type = "rectangle", action = "strokeAndFill", fillColor = state.color,
          strokeColor = swStroke, strokeWidth = 1,
          roundedRectRadii = { xRadius = 5, yRadius = 5 },
          frame = { x = 0, y = (h - swatch) / 2, w = swatch, h = swatch } },
        { type = "text", text = state.hex, textFont = font, textSize = hexSize,
          textColor = fg, textAlignment = "left",
          frame = { x = swatch + gap, y = (h - hexSize) / 2 - 1, w = w - swatch - gap, h = hexSize + 6 } },
      }
    end,
  }
end
local function hexToColor(hex)
  local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255, blue = tonumber(b, 16) / 255, alpha = 1 }
end
local pickState = { hex = "#000000", color = { red = 0, green = 0, blue = 0, alpha = 1 } }
local colorToast = spoon.CanvasPanel.new({
  placement = "center",
  content = colorToastContent(settings.chooserTheme, pickState),
})
local colorToastTimer
spoon.Eyedropper:init()
spoon.Eyedropper:configure({
  onPick = function(hex)
    pickState.hex = hex
    pickState.color = hexToColor(hex)
    colorToast:show()
    if colorToastTimer then colorToastTimer:stop() end
    colorToastTimer = hs.timer.doAfter(1.1, function() colorToast:hide() end)
  end,
})

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
bindHyper(keys.colorPicker, function()
  spoon.Eyedropper:pick()
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

-- This machine's name, the one place the per host split is decided. Resolved
-- once here for DisplayProfiles (later); the terminal's per-location memory keys
-- on the attached-display fingerprint instead, so it needs no machine name.
local host = (hs.execute("scutil --get LocalHostName") or ""):gsub("%s+$", "")

-- Attached-display fingerprint. A stable id for which screens are connected right
-- now, the sorted UUIDs of the attached displays joined into one string. It is the
-- same notion of a location DisplayProfiles matches on, that is which displays are
-- plugged in, expressed as a single value so any per-location memory can key on it.
-- Kept reusable and separate on purpose, a future per-location app placement scopes
-- on this same helper with one line. hs.settings is per machine, so the built-in
-- panel's machine-specific UUID already keeps this distinct across Macs without
-- naming one.
local function displayFingerprint()
  local ids = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    ids[#ids + 1] = s:getUUID() or tostring(s:id())
  end
  table.sort(ids)
  return table.concat(ids, ",")
end

-- DisplayMemory: remember which display the terminal was last moved to, per
-- location. It is the reusable Observer only; it watches the terminal's windows
-- and persists the display under the current scope, and answers nil when nothing
-- is remembered for this location or the remembered display is gone, so the caller
-- layers its own default underneath. Scoping by displayFingerprint means the
-- office and home setups each keep their own terminal display and switch
-- automatically when displays are docked or undocked.
local terminalBundleID = apps[settings.terminal.preferredTerminal]
spoon.DisplayMemory:init()
spoon.DisplayMemory:configure({
  bundleID = terminalBundleID,
  settingsKey = "terminalDisplay",
  scope = displayFingerprint,
})
spoon.DisplayMemory:start()

-- The default display policy, the one place the "where by default" rule lives:
-- the built-in panel if there is one, else the first attached screen. That single
-- rule covers every machine, built-in on the MacBook and the iMac, first available
-- on the Mac mini which has none, so no per host table is needed.
local function defaultTerminalScreen()
  local screens = hs.screen.allScreens()
  for _, s in ipairs(screens) do
    if s:name():match("Built%-in") then return s end
  end
  return screens[1]
end

-- TerminalHandler (depends on AppToggler, WindowManager)
-- targetScreen chains the two: the remembered display wins while it is attached,
-- otherwise the default policy. The engine calls this contract and stays ignorant
-- of both, and dropping the DisplayMemory wiring above would leave it on the
-- default alone.
spoon.TerminalHandler:init()
spoon.TerminalHandler:configure({
  appToggler = spoon.AppToggler,
  windowManager = spoon.WindowManager,
  terminalBundleID = terminalBundleID,
  timing = settings.terminal,
  size = settings.terminal.size,
  minPadding = settings.terminal.minPadding,
  targetScreen = function()
    return spoon.DisplayMemory:rememberedScreen() or defaultTerminalScreen()
  end,
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
-- `host` is resolved once earlier, in the TerminalHandler block.
-- The curated reference profiles are read only from the tool. The captured ones live in a
-- git tracked JSON file the chooser writes, keyed by the same host, and its path is resolved
-- from the live config directory here, the one place the concrete file location is named.
local hostProfiles = displays.profiles[host] or {}
spoon.DisplayProfiles:init()
spoon.DisplayProfiles:configure({
  profiles = hostProfiles,
  settleDelay = displays.settleDelay,
  host = host,
  storePath = hs.configdir .. "/config/display-profiles.json",
})
spoon.DisplayProfiles:start()
-- The inspect and manage chooser. Its api comes from the spoon, injected in configure above,
-- so only the view deps are handed in here, the shared theme, the Chooser factory, and the
-- same deferred shortcut hint panel the other native choosers dock. It opens from the
-- launcher with no dedicated key, and its displayProfiles Hyper context (config/keys.lua)
-- drives the j, k, i, and x shortcuts through the choosers registry above.
local displayProfilesPanel = shortcutPanelFor("displayProfiles")
spoon.DisplayProfiles.chooser.configure({
  theme = settings.chooserTheme,
  chooser = spoon.Chooser,
  onPositioned = displayProfilesPanel.onPositioned,
  onActivity = displayProfilesPanel.onActivity,
  onClose = displayProfilesPanel.onClose,
})
spoon.DisplayProfiles.chooser.start()
if #hostProfiles == 0 then
  print("DisplayProfiles: no curated profiles for host '" .. host .. "', add one in config/displays.lua or capture from the chooser")
end

--------------------------------------------------------------------------------
-- Auto-reload and IPC
--------------------------------------------------------------------------------

-- Reload Hammerspoon configuration automatically when files change, except a write to the
-- captured display profiles JSON. That file is runtime data the DisplayProfiles chooser
-- writes, and it lives inside the watched tree, so reloading on it would restart Hammerspoon
-- mid capture. The chooser already rebuilds the engine in memory after a write, so the change
-- is live without a reload. A batch that touches anything else still reloads as before.
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(paths)
  for _, p in ipairs(paths or {}) do
    if not p:match("display%-profiles%.json$") then
      hs.reload()
      return
    end
  end
end):start()

-- Enable IPC for command-line control
require("hs.ipc")
