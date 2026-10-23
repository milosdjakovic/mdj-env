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
--- was already on. Both turned out to be plain fields any app can ask for, `hides` and
--- `placement`, rather than a tool of their own, so the spoon is gone and every app this
--- plugin already serves may now ask for the same thing.
---
--- Since phase 6 of the keymap plan this plugin holds no key. It answers one action per app in
--- its apps catalog, apptoggler.Safari, which focuses or cycles. An app listed in its toggles
--- takes a named style instead, a behaviour described once in its styles and shared by every app
--- that names it, so the action keeps the app's own name and only what it does changes. Every
--- descriptor names its app and a group answering whether the app is running, and Olm binds,
--- lists and draws the rest, so a key moved in config/keymap.lua shows its new chord everywhere.

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
obj._appFocus = nil   -- lib/appfocus.lua, dot called, focus or cycle
obj._actions = nil    -- the descriptors this plugin answers through provides.actions, see actions

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
--- Configure the spoon. opts.apps is the bundle id catalog, opts.styles the named behaviours and
--- opts.toggles the list saying which app takes which style, all this plugin's own data, and the
--- descriptors are built from them here, once per load.
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  -- Focus or cycle, the core lib the manifest asks for through needs.lib. It used to be a
  -- method here, and the launcher reached it as a sibling on this plugin. Phase three of the
  -- core split moved it into lib/appfocus.lua so the launcher's app rows name no plugin, and
  -- this plugin calls the same module rather than keeping a copy.
  self._appFocus = opts.appFocus
  self:_build(self._apps, opts.styles or {}, opts.toggles or {})
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

--- AppToggler:_buildAction(spec, bundleID)
--- Method
--- Builds one styled app's run from its resolved spec, the show and hide or focus or cycle call
--- its `hides` field asks for, then placement when the spec carries one and the outcome was
--- showing, launching, or focusing rather than a plain cycle.
function obj:_buildAction(spec, bundleID)
  local self_ref = self
  return function()
    local outcome
    if spec.hides then
      outcome = self_ref:toggle(bundleID)
    else
      outcome = self_ref._appFocus.focusOrCycle(bundleID)
    end
    if spec.placement and PLACING_OUTCOMES[outcome] then
      self_ref:_setupPlacement(bundleID, spec.placement)
    end
  end
end

--------------------------------------------------------------------------------
-- Which apps are running, the group every descriptor answers at each show of a sheet.
--------------------------------------------------------------------------------

-- The two groups an app's row is filed under, the apps running now and the ones that are not,
-- the second drawn faded with its title kept bright. One table each, so every descriptor
-- answers the same two and the sheet gathers them into two sections.
local RUNNING = { title = "RUNNING" }
local DORMANT = { title = "DORMANT", faded = true }

-- How long one answer about which apps run is kept. A sheet asks every app's group in the same
-- show, and running apps are enumerated once, a single NSWorkspace call, rather than asked per
-- app, which cost about twenty milliseconds an app and dominated the overlay's show latency. A
-- quarter of a second covers one show and never a second one a person could make.
local RUNNING_TTL = 0.25

--- AppToggler:_isRunning(bundleID) -> boolean
--- Method
--- Whether an app is running now, read from one enumeration of every running app shared by every
--- question asked within RUNNING_TTL of it.
function obj:_isRunning(bundleID)
  local now = hs.timer.secondsSinceEpoch()
  local fresh = type(now) == "number" and type(self._runningAt) == "number"
    and now - self._runningAt < RUNNING_TTL
  if not fresh or not self._running then
    local running = {}
    for _, app in ipairs(hs.application.runningApplications()) do
      local bid = app:bundleID()
      if bid then running[bid] = true end
    end
    self._running, self._runningAt = running, now
  end
  return self._running[bundleID] == true
end

--------------------------------------------------------------------------------
-- The descriptors, one per app, styled where the toggles list says so
--------------------------------------------------------------------------------

-- The fields a style describes, and the fields a toggles entry may carry, which are those plus the
-- app it names, the style it takes and a description. A key or a modifiers field is the person's
-- key choice, which config/keymap.lua holds, and a url a pane's, which System Settings answers as
-- an action of its own, so each is named rather than ignored in silence. `variants` and named
-- variant actions were retired on 2026-10-24, since a style named once and an app taking it keeps
-- the action on the app's own name rather than minting a second one per behaviour.
local STYLE_FIELDS = { hides = true, placement = true }
local ENTRY_FIELDS = { app = true, style = true, hides = true, placement = true, description = true }
local MOVED = {
  key = "a key belongs in config/keymap.lua, naming the app as apptoggler.<app>",
  modifiers = "modifiers belong in config/keymap.lua, written into the chord",
  url = "a pane is opened by its System Settings action, systemsettings.<pane>, named in config/keymap.lua",
}

local function sortedNames(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- Names every field of a table the reader does not read, with where it belongs when it moved.
local function warnUnread(t, known, what, allowed)
  for _, field in ipairs(sortedNames(t)) do
    if not known[field] then
      log.w(what .. " field '" .. tostring(field) .. "' is not read, " .. (MOVED[field] or allowed))
    end
  end
end

-- An entry's fields laid over its style's. A plain field the entry states wins. Placement merges
-- one level deep when both sides are tables, so an entry naming only a width keeps the style's
-- height and padding, and a function on either side replaces the other whole, since a function
-- answers the frame outright and has no fields to merge into.
local function resolve(style, entry)
  local spec = {}
  for k, v in pairs(style or {}) do spec[k] = v end
  if entry.hides ~= nil then spec.hides = entry.hides end
  if entry.placement ~= nil then
    if type(entry.placement) == "table" and type(spec.placement) == "table" then
      local merged = {}
      for k, v in pairs(spec.placement) do merged[k] = v end
      for k, v in pairs(entry.placement) do merged[k] = v end
      spec.placement = merged
    else
      spec.placement = entry.placement
    end
  end
  return spec
end

--- AppToggler:_styled(apps, styles, toggles) -> { [appName] = { spec, description } }
--- Method
--- Reads the toggles list against the catalog and the styles, answering each listed app's resolved
--- spec by its catalog name. A style naming a field no style reads, an entry that is not a table,
--- names an app the catalog does not hold, names a style that does not exist or repeats an app
--- already listed is logged, and that entry is left out, so its app keeps the plain focus or cycle
--- and every other entry still applies.
function obj:_styled(apps, styles, toggles)
  for _, name in ipairs(sortedNames(styles)) do
    local style = styles[name]
    if type(style) ~= "table" then
      log.w("Style '" .. tostring(name) .. "' is not a table, so no app can take it")
    else
      warnUnread(style, STYLE_FIELDS, "Style '" .. tostring(name) .. "'", "a style takes hides and placement")
    end
  end
  local out = {}
  if type(toggles) ~= "table" then
    log.w("The toggles list is not a table, so every app keeps its plain focus or cycle")
    return out
  end
  for i, entry in ipairs(toggles) do
    local where = "Toggle " .. i
    if type(entry) ~= "table" then
      log.w(where .. " is not a table, so it is left out")
    else
      where = where .. ", " .. tostring(entry.app)
      warnUnread(entry, ENTRY_FIELDS, where, "an entry takes app, style, hides, placement and description")
      local style = entry.style ~= nil and styles[entry.style] or nil
      if not apps[entry.app] then
        log.w(where .. ", names an app config/apps.lua does not hold, so it is left out")
      elseif out[entry.app] then
        log.w(where .. ", lists an app already listed, so only the first entry applies")
      elseif entry.style ~= nil and type(style) ~= "table" then
        log.w(where .. ", names the style '" .. tostring(entry.style)
          .. "', which is not among the styles, so the app keeps its plain focus or cycle")
      else
        out[entry.app] = {
          spec = resolve(style, entry),
          description = type(entry.description) == "string" and entry.description or nil,
        }
      end
    end
  end
  return out
end

--- AppToggler:_build(apps, styles, toggles)
--- Method
--- One descriptor per app in the catalog, named by its catalog name, sorted by name so the order
--- is the same on every load. An app the toggles list styles runs its resolved spec, any other
--- focuses or cycles. Every descriptor carries the bundle id in app, so the launcher shows its
--- chord on that app's own row rather than listing it twice, and a group answering whether the
--- app runs, so the sheet splits the apps into running and not running.
function obj:_build(apps, styles, toggles)
  local self_ref = self
  local styled = self:_styled(apps, styles, toggles)
  local actions = {}
  for _, name in ipairs(sortedNames(apps)) do
    local bundleID = apps[name]
    if type(name) == "string" and type(bundleID) == "string" then
      local appFocus = self._appFocus
      local style = styled[name]
      actions[#actions + 1] = {
        name = name, app = bundleID, description = style and style.description or nil,
        group = function() return self_ref:_isRunning(bundleID) and RUNNING or DORMANT end,
        run = style and self:_buildAction(style.spec, bundleID)
          or function() appFocus.focusOrCycle(bundleID) end,
      }
    end
  end
  self._actions = actions
  return self
end

--- AppToggler:actions() -> descriptors
--- Method
--- The descriptors built in configure, declared as provides.actions. Empty before configure has
--- run.
function obj:actions()
  return self._actions or {}
end

return obj
