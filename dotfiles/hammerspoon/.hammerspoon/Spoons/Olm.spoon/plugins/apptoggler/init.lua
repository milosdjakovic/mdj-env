--- === AppToggler ===
---
--- Smart application toggle (show/hide)
---
--- This is the olm side copy of AppToggler, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from lived at
--- Spoons/AppToggler.spoon.
---
--- Placement and the show and hide toggle form both used to live in TerminalHandler.spoon,
--- a whole spoon kept outside Olm for the one behaviour the terminal wanted, hide when
--- frontmost instead of cycle, and land centered at a fixed size on whichever display it
--- was already on. Both turned out to be plain fields any appToggles entry can ask for,
--- `hides` and `placement`, rather than a tool of their own, so the spoon is gone and every
--- app this plugin already serves may now ask for the same thing.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "AppToggler"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("AppToggler", "info")

-- Configuration
obj._apps = nil
obj._hyperKey = nil
obj._appFocus = nil   -- lib/appfocus.lua, dot called, focus or cycle and toggle by url
obj._toggles = nil    -- the toggle list bindHotkeys bound from
obj._sheetItems = nil -- the modal toggles as cheat sheet rows, { key, name, bundleID, icon }
obj._appDetails = nil -- bundle id to what the launcher's row for that app shows, see launcherAppDetails

-- The literal combo an entry with no `modifiers` field falls back to when HyperKey is not
-- wired at all, so losing that spoon degrades the chord rather than the toggle itself.
-- Nobody has ever wanted a different combo here, the same reasoning the timing constants
-- below get, so it stays an internal constant rather than something config/keys.lua states
-- for every entry the way it used to.
local HYPER_FALLBACK = { "shift", "ctrl", "alt", "cmd" }

-- The async ready wait's own timing, ported unchanged from TerminalHandler, which is where
-- it was tuned. A window a fresh launch or a fresh focus produces is not necessarily ready
-- to be measured and moved the instant the call that asked for it returns, macOS hands the
-- app a main window before it has actually taken focus, so this waits a beat and then polls
-- until the app answers ready or the attempts run out. Nobody has ever tuned these numbers,
-- so they are internal rather than something config/settings.lua carries for a plugin whose
-- own defaults have never once needed changing.
local PLACEMENT_TIMING = {
  initialDelay = 0.1,
  checkInterval = 0.25,
  maxAttempts = 20,
}

--------------------------------------------------------------------------------
-- Placement geometry, plain functions with no state, since a box, an anchor, and a
-- clamp are all pure arithmetic on the numbers a screen and a window already hand over.
--------------------------------------------------------------------------------

-- padding insets a box on every side. A single number insets all four sides alike, a table
-- with x and y insets left/right by x and top/bottom by y, and a table with any of top,
-- right, bottom, left insets exactly the sides named, everything else staying zero. Absent
-- means no inset at all.
local function normalizePadding(padding)
  if padding == nil then
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end
  if type(padding) == "number" then
    return { top = padding, right = padding, bottom = padding, left = padding }
  end
  if padding.top or padding.right or padding.bottom or padding.left then
    return {
      top = padding.top or 0, right = padding.right or 0,
      bottom = padding.bottom or 0, left = padding.left or 0,
    }
  end
  local x = padding.x or 0
  local y = padding.y or 0
  return { top = y, right = x, bottom = y, left = x }
end

-- The screen's usable frame, screen:frame() rather than fullFrame(), so the box already
-- excludes the menu bar and the Dock the way a person actually sees the screen, inset by
-- whatever padding the entry declared.
local function placementBox(screen, padding)
  local p = normalizePadding(padding)
  local frame = screen:frame()
  return {
    x = frame.x + p.left,
    y = frame.y + p.top,
    w = frame.w - p.left - p.right,
    h = frame.h - p.top - p.bottom,
  }
end

-- A fractional anchor clamped to 0 through 1, half standing in for any axis the entry left
-- out, since half is center and center is the sane thing to want when nobody asked for an
-- edge. A value outside that range is a config mistake rather than a crash, so it is
-- clamped to whichever bound it overshot and named on the console, loudly enough that the
-- mistake is found rather than merely worked around forever.
local function clampAnchor(value, axis, appName)
  if value == nil then return 0.5 end
  if value < 0 or value > 1 then
    log.w(string.format(
      "AppToggler clamped %s's placement anchor.%s of %s to the 0 to 1 range it must stay in",
      tostring(appName), tostring(axis), tostring(value)))
    return value < 0 and 0 or 1
  end
  return value
end

-- The table form's own frame. Width and height are the desired size in pixels, each
-- clamped to the box so a number bigger than the screen never asks for more room than
-- exists, and an omitted dimension keeps the window's current size, itself clamped the
-- same way. at is the fractional anchor, position along an axis being the box's own edge
-- plus whatever room is left over times the anchor, so 0 sits flush against the near edge,
-- 1 flush against the far one, and 0.5 splits the room evenly.
local function tableFrame(entry, box, win, appName)
  local current = win:frame()
  local width = entry.width and math.min(entry.width, box.w) or math.min(current.w, box.w)
  local height = entry.height and math.min(entry.height, box.h) or math.min(current.h, box.h)
  local at = entry.at or {}
  local ax = clampAnchor(at.x, "x", appName)
  local ay = clampAnchor(at.y, "y", appName)
  return {
    x = box.x + (box.w - width) * ax,
    y = box.y + (box.h - height) * ay,
    w = width,
    h = height,
  }
end

-- The one safety net a function form entry answers through. A hand written frame can ask
-- for anything, including a size or a position off the screen entirely, so the engine
-- clamps whatever comes back against the screen's own frame before it is ever applied, the
-- raw frame rather than the padded box, since a function that wanted padding already read
-- it out of the box it was handed.
local function clampToScreen(frame, screenFrame)
  local w = math.min(frame.w, screenFrame.w)
  local h = math.min(frame.h, screenFrame.h)
  local x = math.max(screenFrame.x, math.min(frame.x, screenFrame.x + screenFrame.w - w))
  local y = math.max(screenFrame.y, math.min(frame.y, screenFrame.y + screenFrame.h - h))
  return { x = x, y = y, w = w, h = h }
end

--- AppToggler:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- AppToggler:configure(opts)
--- Method
--- Configure the spoon
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  -- When a HyperKey spoon is provided, an entry with no modifiers of its own binds into
  -- its modal (fired by holding the physical Hyper key) instead of a literal modifier
  -- combination.
  self._hyperKey = opts.hyperKey
  -- Focus or cycle and toggle by url, the core lib the manifest asks for through needs.lib.
  -- Both used to be methods here, and the launcher reached them as siblings on this plugin.
  -- Phase three of the core split moved them into lib/appfocus.lua so the launcher's app rows
  -- name no plugin, and this plugin calls the same module rather than keeping a copy.
  self._appFocus = opts.appFocus
  -- The leader default only routes which sheet receives the app sections, while the keys
  -- always bind through the app leader's hyperKey, so any other word would bind the keys on
  -- one leader and list them on another's sheet, or on none. It is refused here, loudly.
  if opts.leader ~= nil and opts.leader ~= "app" then
    error("AppToggler binds its keys on the app leader only, so leader must be \"app\" and not "
      .. tostring(opts.leader), 2)
  end
  return self
end

--- AppToggler:toggle(bundleID)
--- Method
--- Toggle an app (show if hidden/not frontmost, hide if frontmost). Answers what actually
--- happened, "hidden", "launched", or "focused", so a caller that also asked for placement
--- knows whether a window was really brought forward or merely sent away.
function obj:toggle(bundleID)
  local app = hs.application.get(bundleID)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    app:hide()
    return "hidden"
  end

  local wasRunning = app ~= nil
  hs.application.launchOrFocusByBundleID(bundleID)
  return wasRunning and "focused" or "launched"
end

--- AppToggler:launchOrFocus(bundleID)
--- Method
--- Launch or focus an app (for workspace engine)
function obj:launchOrFocus(bundleID)
  hs.application.launchOrFocusByBundleID(bundleID)
end

-- Whether the outcome a toggle answered is one placement is allowed to fire on. Showing,
-- launching, and focusing all qualify, a press that only cycled or only hid the app does
-- not, cycling because the window that ended up frontmost was already positioned by an
-- earlier press and moving it again would fight the person's own last placement, hiding
-- because there is no window left on screen to place.
local PLACING_OUTCOMES = { launched = true, focused = true }

--- AppToggler:_isAppReady(bundleID)
--- Method
--- Whether the app is ready to be measured and placed, meaning it has a main window and
--- that window is the one macOS has actually handed focus to. Ported unchanged from
--- TerminalHandler, which needed both, an app answers a main window before focus has truly
--- landed on it, and placing a window that only looks frontmost reads as the wrong window
--- moving on screen.
function obj:_isAppReady(bundleID)
  local app = hs.application.get(bundleID)
  if not app then return false end

  local win = app:mainWindow()
  if not win then return false end

  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow or focusedWindow:application():bundleID() ~= bundleID then
    return false
  end

  return true
end

--- AppToggler:_applyPlacement(bundleID, placement)
--- Method
--- Computes and applies one entry's placement, the single setFrame call this engine
--- owns in both the table and the function form. Operates on the display the window is
--- already on, win:screen(), and never chooses one. That used to be TerminalHandler's own
--- decision, this person's own of 2026-09-01, kept rather than revisited, the shared
--- overlay display policy resolves to the cursor's screen, right for a chooser or an
--- overlay that has to appear under the eye, wrong here, since it moved the window to a
--- different display on every summon, and a window that changes display every time it is
--- summoned loses the one thing a person relies on, knowing where it is without looking.
--- Choosing a display at all is the workspaces plugin's job, never this one's.
function obj:_applyPlacement(bundleID, placement)
  local app = hs.application.get(bundleID)
  if not app then return end
  local win = app:mainWindow() or hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local frame

  if type(placement) == "function" then
    -- A bare function carries no padding field of its own to declare, so the box handed to
    -- it is the screen's usable frame with nothing inset, and the engine still clamps
    -- whatever the function answers against the raw screen frame below, so a wild answer
    -- cannot push the window off screen even so.
    local answer = placement(placementBox(screen, nil), win)
    if type(answer) ~= "table" then
      log.w("AppToggler's placement function for '" .. tostring(bundleID) ..
            "' answered no frame table, so nothing was placed")
      return
    end
    frame = clampToScreen(answer, screen:frame())
  else
    local box = placementBox(screen, placement.padding)
    frame = tableFrame(placement, box, win, bundleID)
  end

  win:setFrame(hs.geometry.rect(frame.x, frame.y, frame.w, frame.h))
end

--- AppToggler:_setupPlacement(bundleID, placement)
--- Method
--- Set up async window placement after a toggle whose outcome earned it.
---
--- Both stages are held in fields on the spoon, ported unchanged from TerminalHandler. A
--- Hammerspoon timer is userdata whose finalizer stops it, so a pending one nothing refers
--- to can be collected before it fires, and the window would then never be placed with
--- nothing said about it. The two stages are strictly sequential so one field each is
--- enough, and a fresh placing press stops whichever stage is outstanding, since it is
--- waiting on a window an even newer press has superseded. Global rather than per app,
--- because only one press can actually be producing a window at a time in ordinary use,
--- the same scope TerminalHandler held when it was the only entry that ever asked for this.
function obj:_setupPlacement(bundleID, placement)
  local self_ref = self

  if self._placementDelay then self._placementDelay:stop() end
  if self._placementWait then self._placementWait:stop() end
  self._placementDelay = hs.timer.doAfter(PLACEMENT_TIMING.initialDelay, function()
    self_ref._placementWait = hs.timer.waitUntil(
      function() return self_ref:_isAppReady(bundleID) end,
      function()
        local app = hs.application.get(bundleID)
        if app then
          app:activate()
          self_ref:_applyPlacement(bundleID, placement)
        end
      end,
      PLACEMENT_TIMING.checkInterval,
      PLACEMENT_TIMING.maxAttempts
    )
  end)
end

--- AppToggler:_buildAction(toggle, bundleID)
--- Method
--- Builds one entry's key action, the show-and-hide or focus-or-cycle call its `hides`
--- field asks for (or the URL form when `url` is stated, untouched by either), then
--- placement when the entry declared one and the outcome was showing, launching, or
--- focusing rather than a plain cycle.
function obj:_buildAction(toggle, bundleID)
  local self_ref = self
  return function()
    local outcome
    if toggle.url then
      outcome = self_ref._appFocus.toggleURL(bundleID, toggle.url)
    elseif toggle.hides then
      outcome = self_ref:toggle(bundleID)
    else
      outcome = self_ref._appFocus.focusOrCycle(bundleID)
    end
    if toggle.placement and PLACING_OUTCOMES[outcome] then
      self_ref:_setupPlacement(bundleID, toggle.placement)
    end
  end
end

--- AppToggler:bindHotkeys(toggles)
--- Method
--- Bind app toggle hotkeys from config. An entry with no `modifiers` field binds into the
--- Hyper modal when HyperKey is wired, and falls back to the internal literal combo when it
--- is not, exactly as before. An entry that DOES state `modifiers` binds as a literal global
--- combo through hs.hotkey.bind outright, live all the time rather than only while Hyper is
--- held, regardless of whether HyperKey is wired, since stating a combo is asking to skip
--- the modal entirely rather than asking for a fallback from it. Every entry used to be
--- forced into the modal no matter what it declared, a defect this fixes.
function obj:bindHotkeys(toggles)
  -- Kept as given, the list this plugin bound from, so the key inventory reads the toggles where
  -- they are used rather than from a copy somewhere else.
  self._toggles = toggles
  local modal, bound = {}, {}
  self._sheetItems, self._appDetails = {}, {}
  for _, toggle in ipairs(toggles) do
    local ok, err = pcall(function()
      local bundleID = self._apps[toggle.app]
      if not bundleID then
        log.w("Unknown app '" .. tostring(toggle.app) .. "' in config")
        return
      end
      local action = self:_buildAction(toggle, bundleID)
      local inModal = false
      if toggle.modifiers then
        hs.hotkey.bind(toggle.modifiers, toggle.key, action)
      elseif self._hyperKey then
        -- Fires while the physical Hyper key is held (HyperKey.spoon eventtap)
        self._hyperKey:bind(toggle.key, action)
        inModal = true
      else
        -- Fallback when no HyperKey is wired: the literal modifier combo
        hs.hotkey.bind(HYPER_FALLBACK, toggle.key, action)
      end
      -- Only an entry that bound reaches the sheet and the launcher, and each is built here on
      -- its own, so a lookup that raises for one app costs that app's row and nothing else.
      local entry = { toggle = toggle, bundleID = bundleID }
      bound[#bound + 1] = entry
      if inModal then modal[#modal + 1] = entry end
    end)
    if not ok then
      log.w("Toggle for '" .. tostring(type(toggle) == "table" and toggle.app or toggle)
        .. "' failed to bind, " .. tostring(err))
    end
  end
  self._sheetItems = self:_sheetItemsFor(modal)
  self._appDetails = self:_appDetailsFor(bound)
  return self
end

--------------------------------------------------------------------------------
-- What the launcher's row for a bound app shows, supplied through provides.launcherAppDetails.
-- The launcher read the person's toggles and app registry itself until the core split finished,
-- the same leak phase four removed from the Hyper sheet, so a core host knew this plugin's data
-- and its shape. It is built here now, from exactly the entries bindHotkeys bound.
--------------------------------------------------------------------------------

--- AppToggler:_appDetailsFor(bound)
--- Method
--- One entry per bundle id. Two toggles may name the same app, one in the Hyper modal for the
--- ordinary focus and cycle and one stating its own modifiers for something like a placed
--- summon. The one with modifiers wins the chord the row shows, since a literal combo appears on
--- no cheat sheet and the row is the only place it can be found, while the modal entry keeps the
--- Hyper sheet as its own. A url from either belongs to the row whichever chord is shown, since
--- choosing the row always opens it. A modal entry names its leader by role, so the launcher
--- spells the leader's name and this plugin never writes the word Hyper. An entry bound on the
--- literal fallback combo because no HyperKey was wired is still a Hyper chord and reads as one.
function obj:_appDetailsFor(bound)
  local out = {}
  local function chordOf(toggle)
    if toggle.modifiers then return { key = toggle.key, mods = toggle.modifiers } end
    return { leader = "app", key = toggle.key }
  end
  for _, b in ipairs(bound) do
    local t = b.toggle
    local existing = out[b.bundleID]
    if not existing then
      out[b.bundleID] = { chord = chordOf(t), description = t.description, url = t.url }
    else
      if t.modifiers and not existing.chord.mods then
        existing.chord = chordOf(t)
        existing.description = t.description
      end
      existing.url = existing.url or t.url
    end
  end
  return out
end

--- AppToggler:launcherAppDetails()
--- Method
--- Bundle id to { chord, description, url } for every app this plugin bound, asked by the
--- launcher whenever it builds its app rows. chord is { leader, key } for a key on a leader, or
--- { key, mods } for a literal combo on no leader. Empty before bindHotkeys has run.
function obj:launcherAppDetails()
  return self._appDetails or {}
end

--------------------------------------------------------------------------------
-- The Hyper cheat sheet's app sections, supplied through provides.cheatSheetSections. They were
-- built by the sheet itself until phase four of the core split, from the same person data this
-- plugin binds, which made a core host know this plugin's data and its shape. They are built
-- here now, from exactly the entries bindHotkeys put into the Hyper modal, so the sheet cannot
-- list a toggle that was not bound there.
--------------------------------------------------------------------------------

-- Order by key, alphanumeric first (0 to 9, a to z), then symbols such as ` and / at the end,
-- ignoring case. The running and dormant split keeps this order, so each group ends up sorted
-- the same way.
local function keyRank(k)
  return k:match("^%w$") and 0 or 1
end

--- AppToggler:_sheetItemsFor(modal)
--- Method
--- Resolve each modal toggle's name and icon once, since both are disk work and the sheet is
--- shown on a key hold that must feel instant. An app that is not installed is dropped, so the
--- sheet never shows a row for something that is not on this machine. pathForBundleID answers
--- an empty string rather than nil for such an app, and an empty string is truthy in Lua, so
--- the test is for a non empty path.
function obj:_sheetItemsFor(modal)
  local items = {}
  for _, m in ipairs(modal) do
    -- Each lookup is guarded on its own, so one app whose name or icon raises is logged and
    -- skipped while every other row stays.
    local ok, err = pcall(function()
      local path = hs.application.pathForBundleID(m.bundleID)
      if path and path ~= "" then
        items[#items + 1] = {
          key = tostring(m.toggle.key),
          name = hs.application.nameForBundleID(m.bundleID) or m.toggle.app,
          bundleID = m.bundleID,
          icon = hs.image.imageFromAppBundle(m.bundleID),
        }
      end
    end)
    if not ok then
      log.w("Sheet row for '" .. tostring(m.toggle.app) .. "' failed, " .. tostring(err))
    end
  end
  table.sort(items, function(a, b)
    local ra, rb = keyRank(a.key), keyRank(b.key)
    if ra ~= rb then return ra < rb end
    return a.key:lower() < b.key:lower()
  end)
  return items
end

--- AppToggler:cheatSheetSections()
--- Method
--- The app toggles as two sheet sections, the apps running now and the ones that are not,
--- dormant ones faded with their title kept bright. Running apps are enumerated once, a single
--- NSWorkspace call, rather than asked per item, which cost about twenty milliseconds an app
--- and dominated the overlay's show latency. The badge is the toggle's key exactly as written.
function obj:cheatSheetSections()
  local running = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    local bid = app:bundleID()
    if bid then running[bid] = true end
  end
  local open, closed = {}, {}
  for _, item in ipairs(self._sheetItems or {}) do
    local row = { badge = item.key, label = item.name, icon = item.icon }
    if running[item.bundleID] then open[#open + 1] = row else closed[#closed + 1] = row end
  end
  return {
    { title = "RUNNING", icons = true, alpha = 1.0, rows = open },
    { title = "DORMANT", icons = true, alpha = 0.55, titleAlpha = 1.0, rows = closed },
  }
end

return obj
