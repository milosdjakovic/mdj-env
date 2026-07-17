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
hs.loadSpoon("Surface")
hs.loadSpoon("Chooser")
hs.loadSpoon("Panel")
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

-- Surface: the themed webview foundation behind the web picker backend and the
-- cheat sheet grids. Its icon cache persists encoded app icons across reloads.
-- Chooser is the picker facade with two swappable backends, native (hs.chooser)
-- and web (a Surface list). The default backend is settings.chooserProvider, and
-- the Surface spoon is injected so the web backend can build on it. Every chooser
-- consumer below goes through this one facade, so flipping settings.chooserProvider
-- swaps them all at once, while the native chooser stays available as a fallback.
spoon.Surface:init()
spoon.Surface:configure({ iconCacheDir = "~/.cache/hs-icons" })
spoon.Chooser:init()
spoon.Chooser:configure({ provider = settings.chooserProvider or "native", surface = spoon.Surface })

-- CheatSheet: the shared grid-overlay renderer behind both cheat sheets. Both
-- builders below draw through this one instance (only ever one overlay is up). It
-- now draws through the Surface grid, so the overlays wear the same frosted panel
-- and palette as the pickers. The cheatSheet block still tunes the content, font
-- size, padding, and badge radius, while the background and theme come from
-- chooserTheme through the grid.
spoon.CheatSheet:init()
local cheatOpts = { surface = spoon.Surface, theme = settings.chooserTheme }
for k, v in pairs(settings.cheatSheet or {}) do cheatOpts[k] = v end
spoon.CheatSheet:configure(cheatOpts)

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
hyperActions[#hyperActions + 1] = keys.caffeinate
hyperActions[#hyperActions + 1] = keys.vpn
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
-- can name the command palette's navigation surface before it is built further
-- below (it needs this predicate table and hideShortcuts, which are defined here).
local commandPaletteSurface
local predicates = {
  multipleDisplays = function() return #hs.screen.allScreens() > 1 end,
  -- The command palette chooser is open. Gates the commandPalette Hyper context,
  -- so it gets the same j/k/i navigation and hold overlay the clipboard chooser has.
  commandPaletteOpen = function()
    return commandPaletteSurface ~= nil and commandPaletteSurface.isShowing()
  end,
  -- The Hammerspoon clipboard chooser is open. Gates the clipboard Hyper context.
  clipboardOpen = function()
    return spoon.ClipboardHistory ~= nil and spoon.ClipboardHistory.manager.isShowing()
  end,
  -- The keep awake chooser is open. Gates the caffeinate Hyper context.
  caffeinateOpen = function()
    return spoon.Caffeinate ~= nil and spoon.Caffeinate.isShowing()
  end,
  -- The VPN control panel is open. Gates the vpn Hyper context.
  vpnOpen = function()
    return spoon.Vpn ~= nil and spoon.Vpn.isShowing()
  end,
  -- The VPN location picker is open. Gates the vpnLocations Hyper context, so it
  -- gets the same Hyper navigation and hold overlay the clipboard chooser has.
  vpnLocationsOpen = function()
    return spoon.Vpn ~= nil and spoon.Vpn.locations.isShowing()
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
-- Build a shortcut overlay model for a named Hyper context, drawn from that
-- context's own bindings so it never drifts from the real keys. The context keys
-- fire on Hyper plus the key, and this panel is revealed by a Hyper hold, so a
-- bare badge would read as a plain key. Spell the chord out, Hyper+J, so it cannot
-- be misread. Return, Escape, and the arrows are genuine plain keys of the
-- chooser, so they stay bare, which also shows the split between what needs Hyper
-- and what does not. Insert and Return are one commit, Close and Escape one
-- dismiss, and the two move rows pair with the down and up arrows, each drawn as a
-- second box joined by "or", so no separate legend row is needed.
local function contextShortcutModel(name, title)
  local rows = {}
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
        rows[#rows + 1] = { badges = badges, label = b.description or b.action }
      end
    end
  end
  return {
    columns = 1,
    colWidth = 320,
    sections = { { title = title, rows = rows } },
  }
end
local function clipboardShortcutModel() return contextShortcutModel("clipboard", "CLIPBOARD") end
local function hideShortcuts()
  if shortcutsShown then
    spoon.CheatSheet:hide()
    shortcutsShown = false
  end
end
-- Assign the Hyper hold reveal now that the overlay model and predicates exist.
-- A hold shows the active layer. The base app overlay when nothing is modal, a
-- live modal context's own shortcuts when it has an overlay (the clipboard), and
-- nothing when a modal context has no overlay (caffeinate, whose command legend is
-- already in the body). contextOverlays maps a context name to its model builder,
-- and the active context is the highest priority one whose predicate holds, read
-- from the same registry the bindings use, so the hold and the keys never
-- disagree. Setting shortcutsShown keeps the toggle state in sync, so a context
-- keypress clears the peeked sheet like a toggled one.
local function vpnLocationsShortcutModel() return contextShortcutModel("vpnLocations", "LOCATIONS") end
local function commandPaletteShortcutModel() return contextShortcutModel("commandPalette", "COMMANDS") end
local contextOverlays = {
  clipboard = clipboardShortcutModel,
  vpnLocations = vpnLocationsShortcutModel,
  commandPalette = commandPaletteShortcutModel,
}
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

-- ClipboardHistory: reveal clipboard history on the Hyper key. The Hammerspoon
-- manager is placed first, so it always wins; Raycast and the macOS Tahoe
-- Spotlight clipboard stay as fallbacks. The chain logs each skip, and
-- availability is rechecked on every open. Reorder the list to change
-- preference, or drop the hammerspoon line to fall back to Raycast.
spoon.ClipboardHistory:init()
-- Inject the overlay teardown as the manager's onClose before it starts, so it is
-- captured when the ui is wired. Closing the chooser then clears the shortcut
-- sheet. The chooser theme is injected here too, from the one source in
-- config/settings.lua, so the chooser and its preview follow the system light and
-- dark appearance. The Chooser atom (Chooser.spoon) is injected as the factory the
-- ui builds its picker from, the shared mechanism behind the chooser window.
spoon.ClipboardHistory.manager.configure({
  onClose = hideShortcuts,
  theme = settings.chooserTheme,
  chooser = spoon.Chooser,
})
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

-- Caffeinate: the keep awake panel on Hyper+K. It is a short navigable list, but it
-- does not use the Chooser atom, because it needs inline numeric fields that clamp to
-- hours and minutes, which a webview gives natively. It builds on the shared Panel
-- atom (Panel.spoon), injected here as its view factory, sharing the same theme so it
-- matches the chooser's light and dark look. The open key is a base HyperKey binding,
-- so it opens when nothing modal owns Hyper and is suppressed while a modal context is
-- live.
spoon.Caffeinate.configure({ theme = settings.chooserTheme, panel = spoon.Panel })
spoon.Caffeinate.start()
spoon.HyperKey:bind(keys.caffeinate.key, function() spoon.Caffeinate.show() end)

-- VPN controls: the control panel on Hyper+Y. It is the second consumer of the Panel
-- atom, sharing it with caffeinate for its short fixed action list, and it also uses
-- the Chooser atom for the location search, the same widget behind the clipboard. Both
-- are injected here from the one theme source. When the Mullvad CLI is missing the
-- spoon logs to the console and stays inert, so this wiring is safe on any machine. The
-- open key is a base HyperKey binding, suppressed while a modal context owns Hyper.
spoon.Vpn.configure({ theme = settings.chooserTheme, panel = spoon.Panel, chooser = spoon.Chooser, onLocationsClose = hideShortcuts })
spoon.Vpn.start()
spoon.HyperKey:bind(keys.vpn.key, function() spoon.Vpn.show() end)

-- Command palette / switcher: an app switcher and command runner on Hyper+Space.
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
-- data, so the palette still never learns what a row does.
--
-- Like the clipboard it is wired into the Hyper contexts (see the checklist in
-- CLAUDE.md): its navigation surface is registered in `choosers` below so the
-- shared j/k/i actions reach it, its `commandPaletteOpen` predicate gates the
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
  for _, c in ipairs(keys.capture) do
    add(c.description or humanize(c.action), "Capture · " .. chordLabel("Hyper", c.key, c.mods),
      { kind = "capture", name = c.action }, captureGlyphs[c.action] or "📸")
  end
  add(keys.clipboardHistory.description, "Clipboard · " .. chordLabel("Hyper", keys.clipboardHistory.key), { kind = "special", name = "clipboard" }, "📋")
  add(keys.caffeinate.description, "System · " .. chordLabel("Hyper", keys.caffeinate.key), { kind = "special", name = "caffeinate" }, "☕")
  add(keys.vpn.description, "Network · " .. chordLabel("Hyper", keys.vpn.key), { kind = "special", name = "vpn" }, "🌐")
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
-- background helpers. Recomputed per open since running state changes; the costly
-- disk scan is cached.
local function appRows()
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
      item = { kind = "app", bundleID = e.bundleID, url = cfg and cfg.url },
    }
  end
  return rows
end

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

-- The row runs deferred, after the chooser has torn down and macOS has restored
-- focus to the app that was frontmost before the palette opened. Window actions
-- act on hs.window.focusedWindow(), so they must run once that window is focused
-- again rather than while the chooser holds focus. onClose clears any peeked
-- shortcut overlay, matching the clipboard.
local commandPalette = spoon.Chooser.new({
  theme = settings.chooserTheme,
  placeholder = "Search apps and commands",
  rows = commandRows,
  onSelect = function(item)
    if item then hs.timer.doAfter(0.1, function() runItem(item) end) end
  end,
  onClose = hideShortcuts,
})
-- Dot-called navigation adapter over the Chooser instance (whose methods are
-- colon-called), so the shared activeChooser / routeNav registry drives it exactly
-- like the other pickers. This is step 1 of the "wire a picker into the Hyper
-- contexts" checklist, the same wrap Vpn.spoon does for its location picker.
commandPaletteSurface = {
  isShowing = function() return commandPalette:isShowing() end,
  selectNext = function() commandPalette:selectNext() end,
  selectPrev = function() commandPalette:selectPrev() end,
  insertSelected = function() commandPalette:insertSelected() end,
  hide = function() commandPalette:hide() end,
}
-- Open key: a base HyperKey binding, suppressed while a modal context owns Hyper.
spoon.HyperKey:bind(keys.commandPalette.key, function() commandPalette:show() end)

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
local choosers = { clipManager, spoon.Caffeinate, spoon.Vpn, spoon.Vpn.locations, commandPaletteSurface }
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
