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
hs.loadSpoon("Chooser")
hs.loadSpoon("HelperPanel")
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

-- Chooser is the picker facade behind every list tool below, the clipboard, the
-- VPN locations, keep awake, menu search, and the launcher. It wraps the native
-- hs.chooser. There was once a second webview backend built on a Surface spoon,
-- selectable per consumer, but every consumer settled on native so the web backend
-- and the Surface foundation were removed.
spoon.Chooser:init()

-- CheatSheet: the shared overlay behind both cheat sheets. Both builders below
-- draw through this one instance (only ever one overlay is up). It owns only the
-- grid layout and draws through the shared HelperPanel canvas atom, the same
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
--
-- Forward-declared so the predicate registry and the chooser navigation registry
-- can name the launcher's navigation surface before it is built further
-- below (it needs this predicate table and hideShortcuts, which are defined here).
local launcherSurface
local menuSearchSurface
local predicates = {
  multipleDisplays = function() return #hs.screen.allScreens() > 1 end,
  -- The launcher chooser is open. Gates the launcher Hyper context,
  -- so it gets the same j/k/i navigation and hold overlay the clipboard chooser has.
  launcherOpen = function()
    return launcherSurface ~= nil and launcherSurface.isShowing()
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
        if b.action == "insertSelected" then
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
-- Every chooser runs on the native backend and docks the deferred HelperPanel for
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

-- Launcher: an app switcher and command runner on Hyper+Space.
-- It lists every installed application (open ones first, then not running), and
-- below them the Hyper and window-leader actions. An app that has a Hyper toggle
-- shows its shortcut; the rest are launchable by name. Type to filter, Return or
-- Hyper+i runs the highlighted row.
--
-- This is pure composition-root policy. The reusable mechanism is the Chooser
-- atom (the same widget behind the clipboard and the VPN locations), so no new
-- spoon is needed, and this is the one place that maps the app list and the pure
-- binding data in config/keys.lua onto the domain spoons.
--
-- A chosen row carries only a small serializable descriptor, its kind plus a
-- name or bundle id, never a function, because the Chooser hands each row to
-- hs.chooser which serialises it to a native object (a function there is what
-- made the list come up empty). A single dispatcher turns that descriptor back
-- into the right call. This is the Command pattern with the command encoded as
-- data, so the launcher still never learns what a row does.
--
-- Like the clipboard it is wired into the Hyper contexts (see the checklist in
-- CLAUDE.md): its navigation surface is registered in `choosers` below so the
-- shared j/k/i actions reach it, its `launcherOpen` predicate gates the
-- context, and its hold overlay is registered in contextOverlays above. Native
-- arrows, typing, Return, and Escape work whenever Hyper is released.

-- camelCase action name -> "Title Case" label, the same rule WindowCheatSheet
-- uses, applied when a binding sets no explicit description.
local function humanize(name)
  local s = tostring(name):gsub("(%l)(%u)", "%1 %2")
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- Render a chord as readable row text: the leader name plus the key glyph
-- (CheatSheet.glyphFor turns "left" / {"shift"} into "⇧←"). Kept as words
-- ("Hyper", "Meta") rather than badges, since a chooser row is plain text.
local function chordLabel(leader, key, mods)
  return leader .. " " .. spoon.CheatSheet.glyphFor(key, mods)
end

local windowActions = spoon.WindowManager:actions()
local windowLeaderName = "Meta" -- keys.windowLeader is META today; display name

-- The one dispatcher. Each palette row's `item` is a plain descriptor; this maps
-- it back to a call, reusing the action functions the domain spoons already
-- expose (AppToggler, WindowManager:actions(), Capture:capture, and the same show
-- functions the base Hyper bindings call). Nothing here is serialised, so it may
-- hold closures freely.
local specialActions = {
  clipboard = function() spoon.ClipboardHistory:open() end,
  caffeinate = function() spoon.Caffeinate.show() end,
  vpn = function() spoon.Vpn.show() end,
  colorPicker = function() spoon.Eyedropper:pick() end,
  lock = function() hs.caffeinate.lockScreen() end,
  sleep = function() hs.caffeinate.systemSleep() end,
}
local function runItem(it)
  if not it then return end
  if it.kind == "app" then
    if it.url then
      spoon.AppToggler:toggleURL(it.bundleID, it.url)
    else
      spoon.AppToggler:focusOrCycle(it.bundleID)
    end
  elseif it.kind == "window" then
    local fn = windowActions[it.name]
    if fn then fn() end
  elseif it.kind == "capture" then
    spoon.Capture:capture(it.name)
  elseif it.kind == "special" then
    local fn = specialActions[it.name]
    if fn then fn() end
  end
end

-- Action rows have no app icon of their own, so we give each a generic one. This
-- Hammerspoon (1.1.1) has no SF Symbol API and the named system images are too
-- sparse, so the icon is drawn from a glyph, once per glyph and cached, and lines
-- up in the row with the real app icons above it. A nil glyph yields no icon.
local glyphIconCache = {}
local function glyphIcon(glyph)
  if not glyph then return nil end
  if glyphIconCache[glyph] == nil then
    local size = 72
    local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
    c[1] = { type = "text", text = glyph, textSize = 52, textAlignment = "center",
             frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
    glyphIconCache[glyph] = c:imageFromCanvas() or false -- false marks "tried, none"
    c:delete()
  end
  return glyphIconCache[glyph] or nil
end

-- The static action rows, built once. Each row is
-- { title, subTitle, image, item, when? } where item is a serializable descriptor
-- for the dispatcher above. Apps are added live per open (their running state
-- changes), so they are not here.
local function buildActionRows()
  local rows = {}
  local function add(title, subTitle, item, glyph, when)
    rows[#rows + 1] = { title = title, subTitle = subTitle, image = glyphIcon(glyph), item = item, when = when }
  end
  -- Category glyphs. Window actions all share one, since the chord in the subtitle
  -- already tells them apart; capture and the system actions get a per-action one.
  local captureGlyphs = { ocrArea = "🔤", captureArea = "📸", captureAreaClipboard = "📸", recordArea = "🎥" }
  add(keys.colorPicker.description, "Tools · " .. chordLabel("Hyper", keys.colorPicker.key), { kind = "special", name = "colorPicker" }, "🎨")
  for _, c in ipairs(keys.capture) do
    add(c.description or humanize(c.action), "Capture · " .. chordLabel("Hyper", c.key, c.mods),
      { kind = "capture", name = c.action }, captureGlyphs[c.action] or "📸")
  end
  add(keys.caffeinate.description, "System · " .. chordLabel("Hyper", keys.caffeinate.key), { kind = "special", name = "caffeinate" }, "☕")
  add(keys.vpn.description, "Network · " .. chordLabel("Hyper", keys.vpn.key), { kind = "special", name = "vpn" }, "🌐")
  add(keys.clipboardHistory.description, "Clipboard · " .. chordLabel("Hyper", keys.clipboardHistory.key), { kind = "special", name = "clipboard" }, "📋")
  add(keys.lock.description, "System · " .. chordLabel("Hyper", keys.lock.key), { kind = "special", name = "lock" }, "🔒")
  add(keys.sleep.description, "System · " .. chordLabel("Hyper", keys.sleep.key), { kind = "special", name = "sleep" }, "🌙")
  for _, b in ipairs(keys.windowManagement) do
    if windowActions[b.action] then
      add(b.description or humanize(b.action), "Window · " .. chordLabel(windowLeaderName, b.key, b.mods),
        { kind = "window", name = b.action }, "🪟", b.when)
    end
  end
  return rows
end
local actionRows = buildActionRows()

-- The configured Hyper toggle for each app, keyed by bundle id, so an app row can
-- show its shortcut (and reuse its url-pane behavior). Built from the same pure
-- appToggles data the AppToggler binds.
local configuredApps = {}
for _, t in ipairs(keys.appToggles) do
  local bundleID = apps[t.app]
  if bundleID then configuredApps[bundleID] = { key = t.key, url = t.url } end
end

-- Enumerate installed applications once, lazily on first open, so config load
-- stays fast. Scans the standard app directories for .app bundles and resolves
-- each bundle id, name, and icon, deduped by bundle id. Cached; a newly installed
-- app appears after the next Hammerspoon reload, which is automatic on file change.
local APP_DIRS = {
  "/Applications",
  "/Applications/Utilities",
  "/System/Applications",
  "/System/Applications/Utilities",
  os.getenv("HOME") .. "/Applications",
}
local installedApps
local function scanInstalledApps()
  local byId = {}
  for _, dir in ipairs(APP_DIRS) do
    if hs.fs.attributes(dir, "mode") == "directory" then
      for file in hs.fs.dir(dir) do
        if file:sub(-4) == ".app" then
          local path = dir .. "/" .. file
          local info = hs.application.infoForBundlePath(path)
          local bundleID = info and info.CFBundleIdentifier
          if bundleID and not byId[bundleID] then
            byId[bundleID] = {
              name = hs.application.nameForBundleID(bundleID) or file:sub(1, -5),
              bundleID = bundleID,
              icon = hs.image.imageFromAppBundle(bundleID),
            }
          end
        end
      end
    end
  end
  return byId
end

-- The live app rows: every installed app plus any running app not on disk in the
-- scanned dirs, marked open when running so open apps sort first. A running app
-- outside the scan is included only when it has a dock presence (kind 1), to skip
-- background helpers. The disk scan is cached, and the assembled rows are cached
-- too, rebuilt only when the running set changes (see the watcher below) rather
-- than rescanned and resorted on every open, so opening the palette just filters.
local appRowsCache
local function appRows()
  if appRowsCache then return appRowsCache end
  installedApps = installedApps or scanInstalledApps()
  local byId = {}
  for bundleID, a in pairs(installedApps) do
    byId[bundleID] = { name = a.name, bundleID = bundleID, icon = a.icon, running = false }
  end
  for _, app in ipairs(hs.application.runningApplications()) do
    local bundleID = app:bundleID()
    if bundleID then
      local e = byId[bundleID]
      if e then
        e.running = true
      elseif app:kind() == 1 then
        byId[bundleID] = { name = app:name() or bundleID, bundleID = bundleID, icon = hs.image.imageFromAppBundle(bundleID), running = true }
      end
    end
  end
  local list = {}
  for _, e in pairs(byId) do list[#list + 1] = e end
  table.sort(list, function(x, y)
    if x.running ~= y.running then return x.running end -- open apps first
    return (x.name or ""):lower() < (y.name or ""):lower()
  end)

  local rows = {}
  for _, e in ipairs(list) do
    local cfg = configuredApps[e.bundleID]
    local status = e.running and "Open" or "Not running"
    local subTitle = cfg and (status .. " · Hyper " .. cfg.key) or status
    rows[#rows + 1] = {
      title = e.name,
      subTitle = subTitle,
      image = e.icon,
      -- A stable key so the atom encodes each app icon once and reuses it across
      -- opens, even when the bundle image is rebuilt for an unscanned running app.
      iconKey = "app:" .. e.bundleID,
      item = { kind = "app", bundleID = e.bundleID, url = cfg and cfg.url },
    }
  end
  appRowsCache = rows
  return rows
end

-- Invalidate the cached app rows when the running set changes, so open apps still
-- sort first and the Open / Not running status stays accurate without rescanning on
-- every open. Kept in a module local so the watcher is not garbage collected, and
-- started once at load.
local appRowsWatcher = hs.application.watcher.new(function(_, event)
  if event == hs.application.watcher.launched or event == hs.application.watcher.terminated then
    appRowsCache = nil
  end
end)
appRowsWatcher:start()

-- The row supplier. Apps first (open, then not running), then the action rows.
-- Case-insensitive substring match over the visible text, so typing filters by
-- name or shortcut. Gated action rows (the display switches) drop out live through
-- the same predicate registry the window bindings use, so the palette and the
-- cheat sheet agree on what is available.
local function commandRows(query)
  local q = (query or ""):lower()
  local out = {}
  local function consider(row)
    if row.when and not (predicates[row.when] and predicates[row.when]()) then return end
    if q == "" or (row.title .. " " .. row.subTitle):lower():find(q, 1, true) then
      out[#out + 1] = { title = row.title, subTitle = row.subTitle, image = row.image, item = row.item }
    end
  end
  for _, row in ipairs(appRows()) do consider(row) end
  for _, row in ipairs(actionRows) do consider(row) end
  return out
end

-- Panel colours plucked from the live native chooser with Digital Color Meter, so
-- the helper panel matches its solid fill and 1px border. Light is measured; dark is
-- a placeholder until the dark picker is sampled.
local PANEL_BG = { light = "#E5E1E3", dark = "#2A2A2E" }
local PANEL_BORDER = { light = "#A09F9F", dark = "#000000" }
local function panelHexColor(hex)
  local r, g, b = hex:match("#?(%x%x)(%x%x)(%x%x)")
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1.0 }
end

-- The panel fill and border, resolved per show so they track light and dark. One
-- pair, handed to both the docked shortcut hint bar and the cheat sheet overlay,
-- so the two canvases share one surface look.
local function panelFill()
  return (hs.host.interfaceStyle() == "Dark") and panelHexColor(PANEL_BG.dark) or panelHexColor(PANEL_BG.light)
end
local function panelBorder()
  return { width = 1, color = function()
    return (hs.host.interfaceStyle() == "Dark") and panelHexColor(PANEL_BORDER.dark) or panelHexColor(PANEL_BORDER.light)
  end }
end

-- Now that the shared surface is in scope, finish wiring the cheat sheet. It draws
-- its binding grid through the HelperPanel atom with the same fill and border as
-- the hint bar, centered on screen. The cheatSheet settings block tunes only the
-- content, font size, padding, and badge radius; the surface comes from here.
local cheatOpts = { theme = settings.chooserTheme, helperPanel = spoon.HelperPanel,
                    fill = panelFill, border = panelBorder() }
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
-- (the launcher, menu search, VPN). One factory builds a HelperPanel docked below the chooser, filled
-- and bordered to match the native picker, with that context's footerFor hints as its
-- content, and returns the three callbacks a native chooser is wired with. arm on
-- onPositioned starts the idle countdown (the panel stays hidden until the user pauses),
-- poke on onActivity resets it on each keypress, and hide on onClose tears it down and
-- clears any peeked overlay. The idle delay is the one settings.shortcutsPanel.delayMs,
-- so editing it there applies to every panel this builds; nil or 0 there shows the panel
-- instantly on open. fill and border are functions so they re-resolve light/dark on
-- every show.
local function shortcutPanelFor(context)
  local panel = spoon.HelperPanel.new({
    placement = "below",
    gap = 8,
    padX = 14, padY = 10,
    delay = settings.shortcutsPanel and settings.shortcutsPanel.delayMs,
    fill = function()
      return (hs.host.interfaceStyle() == "Dark") and panelHexColor(PANEL_BG.dark) or panelHexColor(PANEL_BG.light)
    end,
    border = {
      width = 1,
      color = function()
        return (hs.host.interfaceStyle() == "Dark") and panelHexColor(PANEL_BORDER.dark) or panelHexColor(PANEL_BORDER.light)
      end,
    },
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

-- The row runs deferred, after the chooser has torn down and macOS has restored
-- focus to the app that was frontmost before the launcher opened. Window actions
-- act on hs.window.focusedWindow(), so they must run once that window is focused
-- again rather than while the chooser holds focus. Like menu search and VPN it docks
-- the same deferred shortcut panel through the three chooser callbacks, and its
-- onClose also clears any peeked overlay, matching the clipboard.
local launcherPanel = shortcutPanelFor("launcher")
local launcher = spoon.Chooser.new({
  theme = settings.chooserTheme,
  placeholder = "Search apps and commands",
  rows = commandRows,
  onSelect = function(item)
    if item then hs.timer.doAfter(0.1, function() runItem(item) end) end
  end,
  onPositioned = launcherPanel.onPositioned,
  onActivity = launcherPanel.onActivity,
  onClose = launcherPanel.onClose,
})
-- Dot-called navigation adapter over the Chooser instance (whose methods are
-- colon-called), so the shared activeChooser / routeNav registry drives it exactly
-- like the other pickers. This is step 1 of the "wire a picker into the Hyper
-- contexts" checklist, the same wrap Vpn.spoon does for its location picker.
launcherSurface = {
  isShowing = function() return launcher:isShowing() end,
  selectNext = function() launcher:selectNext() end,
  selectPrev = function() launcher:selectPrev() end,
  insertSelected = function() launcher:insertSelected() end,
  hide = function() launcher:hide() end,
}
-- Open key: a base HyperKey binding, suppressed while a modal context owns Hyper.
-- Hyper+Space always opens this built-in launcher. Same shape as the clipboard.
spoon.HyperKey:bind(keys.launcher.key, function() launcher:show() end)

-- Menu search: Hyper+J lists every enabled menu bar item of the frontmost app and
-- runs the chosen one. Like the launcher this is pure composition-root
-- policy over the same Chooser atom, so it adds no spoon. macOS exposes each app's
-- menus through the Accessibility API, which hs.application:getMenuItems reads; the
-- callback form does the tree walk off the main thread, so a large menu never
-- blocks Hammerspoon. The app frontmost when Hyper+J fires is captured as the
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
local menuTargetApp   -- the app frontmost when Hyper+J fired, the dispatch target
local menuAppIcon     -- the target app's icon, shown on every row (one app per open)
local menuAppKey      -- a stable icon key so that icon is encoded once, not per row

-- Rows supplier: case-insensitive substring over the item title and its menu path,
-- so typing a parent menu name (File, Format) narrows too. The shortcut glyph rides
-- in the subtitle after the path.
local function menuSearchRows(query)
  local q = (query or ""):lower()
  local out = {}
  for _, r in ipairs(menuRows) do
    if q == "" or (r.title .. " " .. r.parents):lower():find(q, 1, true) then
      local subtitle = r.parents
      if r.shortcut then
        subtitle = (subtitle ~= "" and (subtitle .. "   ") or "") .. r.shortcut
      end
      -- Every item belongs to the one captured app, so each row shows that app's
      -- icon. The stable key memoizes the encoded icon once rather than per row.
      out[#out + 1] = { title = r.title, subTitle = subtitle, image = menuAppIcon,
                        iconKey = menuAppKey, item = { path = r.path } }
    end
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
-- fireMenuSearchCombo below (instead of openBuiltinMenuSearch) to make Hyper+J fire
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
local choosers = { clipManager, spoon.Caffeinate, spoon.Vpn, launcherSurface, menuSearchSurface }
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

-- Eyedropper: a screen colour sampler on Hyper+2. Unlike the choosers it is a lone
-- mechanism, not a list tool, so it needs no Hyper context, predicate, or choosers
-- entry. It is wired exactly like lock and sleep, a base HyperKey binding (bound
-- through bindHyper below), and it is also reachable as the color picker launcher
-- row through the special action dispatcher above. The click copies the pixel hex.
--
-- The copied confirmation is drawn on the shared HelperPanel canvas, the same
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
local colorToast = spoon.HelperPanel.new({
  placement = "center",
  fill = panelFill,
  border = panelBorder(),
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
