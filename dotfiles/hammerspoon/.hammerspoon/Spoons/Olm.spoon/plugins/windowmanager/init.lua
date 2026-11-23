--- === WindowManager ===
---
--- Window positioning and sizing operations
---
--- This is the olm side copy of WindowManager, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from lived at
--- Spoons/WindowManager.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowManager"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("WindowManager", "info")

-- Where every action puts the window, one pure function, step 6.3, loaded beside this file since
-- a plugin's directory is not on the module path.
local Plan = assert(loadfile(debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "plan.lua"))()

-- Dependencies (injected via configure)
obj._margins = {}
obj._settings = nil

-- The round trip memory for a move between screens, plan.lua's place, declared here as well as reset in init, since
-- init runs inside loader.lua's own pcall and a failure anywhere else inside it would
-- otherwise leave this field nil, turning the next display switch into a crash rather than
-- only a lost memory.
obj._lastFrames = {}

--- WindowManager:init()
--- Method
--- Initialize the spoon
function obj:init()
  -- The round trip memory lives only in this table, plain, with no timer and no watcher,
  -- since its whole job is answering the one place that reads and writes it, and it starts
  -- over on every reload the same way every other field on this object does.
  self._lastFrames = {}
  return self
end

--- WindowManager:configure(opts)
--- Method
--- Configure the spoon with dependencies
function obj:configure(opts)
  opts = opts or {}
  self._margins = opts.margins or {}
  self._settings = opts.settings or {}
  self._notify = opts.notify
  hs.window.animationDuration = self._settings.windowAnimationDuration or 0
  return self
end

--- WindowManager:_resolveMargin(value)
--- Method
--- Resolve a margin value (number or function returning number)
function obj:_resolveMargin(value)
  if type(value) == "function" then
    return value() or 0
  end
  return value or 0
end

--- WindowManager:_gap()
--- Method
--- The configured window gap in pixels (0 when disabled). The same value insets
--- the canvas (via the margins in init.lua) and forms the gutter between tiled
--- windows, so outer and inner spacing stay uniform.
function obj:_gap()
  return (self._settings and self._settings.gap) or 0
end

--- WindowManager:getScreenFrame(screen)
--- Method
--- Get screen frame adjusted for margins (canvas)
function obj:getScreenFrame(screen)
  screen = screen or (hs.window.focusedWindow() and hs.window.focusedWindow():screen()) or hs.screen.mainScreen()
  return Plan.canvas(screen:frame(), self:_resolvedMargins())
end

-- The margins as numbers, each one a number or a function answering one, and the gap on every side
-- where none is stated, so one gap insets the canvas and parts tiled windows.
function obj:_resolvedMargins()
  local stated = false
  for _ in pairs(self._margins or {}) do stated = true break end
  if not stated then
    local gap = self:_gap()
    return { top = gap, right = gap, bottom = gap, left = gap }
  end
  return {
    top = self:_resolveMargin(self._margins.top), right = self:_resolveMargin(self._margins.right),
    bottom = self:_resolveMargin(self._margins.bottom), left = self:_resolveMargin(self._margins.left),
  }
end

local function rectOf(f) return { x = f.x, y = f.y, w = f.w, h = f.h } end
local function uuidOf(screen) return screen:getUUID() or tostring(screen:id()) end

--- WindowManager:planInput(win, extra) -> table
--- Method
--- What plan.lua reads for a window, its frame, its screen, every screen, the memory and the
--- settings, with extra's depth, size or target laid over it.
function obj:planInput(win, extra)
  local screens = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    -- The Mac's own panel, which a named size may ask for, macOS naming it Built-in.
    screens[#screens + 1] = { uuid = uuidOf(screen), frame = rectOf(screen:frame()),
      builtin = (screen:name() or ""):find("Built%-in") ~= nil or nil }
  end
  local id = win:id()
  local screen = win:screen()
  local pointer = hs.mouse.absolutePosition()
  local s = {
    window = rectOf(win:frame()), id = id, screen = screen and uuidOf(screen), screens = screens,
    pointer = pointer and { x = pointer.x, y = pointer.y } or nil,
    margins = self:_resolvedMargins(), gap = self:_gap(), sizing = (self._settings or {}).windowSizing or {},
    memory = id and self._lastFrames[id] or nil,
  }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

--- WindowManager:_do(action, extra) -> result or nil
--- Method
--- Runs one action on the focused window, the frame plan.lua answers written, through _applyFrame
--- where the plan asks for a read back, and the frame a window leaves a screen with remembered.
function obj:_do(action, extra)
  local win = hs.window.focusedWindow()
  if not win then return nil end
  local input = self:planInput(win, extra)
  local result = Plan.plan(action, input)
  -- What this press read and planned, which the action's run hands back for Olm.app's shadow, step
  -- 6.3b, docs/DESIGN-APP-WINDOWS.md. Read before anything is written.
  self._report = { action = action, input = input, result = result }
  if not result then return nil end
  local id = win:id()
  if result.remember and id then
    self._lastFrames[id] = self._lastFrames[id] or {}
    self._lastFrames[id][result.remember.screen] = result.remember.frame
    self:_pruneLastFrames()
  end
  if result.verify then self:_applyFrame(win, result.frame) else win:setFrame(result.frame) end
  return result
end

--- WindowManager:maximize()
--- Method
--- Maximize the focused window
function obj:maximize() self:_do("maximize") end

--- WindowManager:center()
--- Method
--- Center the focused window on screen
function obj:center() self:_do("center") end

--- WindowManager:fullHeightReasonableWidth()
--- Method
--- Make window full height with reasonable width
function obj:fullHeightReasonableWidth() self:_do("fullHeightReasonableWidth") end

--- WindowManager:fullHeight()
--- Method
--- Expand the focused window to full height, leaving its width and x untouched
function obj:fullHeight() self:_do("fullHeight") end

--- WindowManager:resizeDefault()
--- Method
--- Resize window to default size, the reasonable size
function obj:resizeDefault() self:_do("reasonableSize") end

--- WindowManager:leftHalf()
--- Method
--- Move window to left half of screen
function obj:leftHalf() self:_do("leftHalf") end

--- WindowManager:rightHalf()
--- Method
--- Move window to right half of screen
function obj:rightHalf() self:_do("rightHalf") end

--- WindowManager:_applyFrame(win, rect)
--- Method
--- Writes a frame to a window, escalating to hs.window's own workaround only when a plain
--- write did not actually land. setFrame with the default setFrameCorrectness writes the
--- frame in one call, hs/window.lua:360, and macOS evaluates that write against whatever
--- screen the window is still considered to be on at the instant it arrives, so growing a
--- window while it crosses from a small screen to a large one gets its size clamped to the
--- screen it is leaving rather than the one it is headed to. A round trip from an ultrawide
--- to the built in panel and back once restored a width of about 1985 rather than the
--- remembered 2400, and the arithmetic named the cause, the remembered x of negative 471 plus
--- the observed 1985 lands at 1514, which is the built in panel's own right edge at 1512, the
--- size cut exactly at the boundary of the screen being left.
---
--- hs.window's own setFrameWithWorkarounds answers this, hs/window.lua:343, its zero duration
--- path writing the size, then the top left, then the size again, and it is that second size
--- write, landing once the window is already considered to be on the target screen, that
--- escapes the clamp. It is not used for every placement, because it parks the window inside
--- the screen it starts on to learn what size that screen will actually allow, which shows up
--- as a visible wiggle on every single display switch, and the plain write already lands
--- exactly whenever a window is shrinking rather than growing across the boundary. So the
--- plain write runs first and the workaround only follows once a readback shows it did not
--- take.
---
--- The tolerance below is not a fitted number. A terminal such as Ghostty only resizes in
--- whole rows and columns, hs/window.lua:388, so an exact match can never be expected of one,
--- and the allowance is roughly one cell on each axis with room to spare, while the failure
--- this escalation exists to catch was four hundred points out on one axis. Neither number is
--- delicate against the other.
function obj:_applyFrame(win, rect)
  local escalateTolerance = 20

  win:setFrame(rect)

  local landed = win:frame()
  local offW = math.abs(landed.w - rect.w)
  local offH = math.abs(landed.h - rect.h)
  if offW <= escalateTolerance and offH <= escalateTolerance then
    return
  end

  win:setFrameWithWorkarounds(rect, 0)
end

--- WindowManager:_pruneLastFrames()
--- Method
--- Drops a stored window id once its window is gone, so the round trip memory cannot grow
--- without bound across a long session. Walking the whole table costs a pass over every
--- entry, so it only runs once there is enough in it for that pass to be worth it rather than
--- on every placement.
---
--- The window enumeration happens exactly once here, through hs.window.allWindows(), and every
--- stored id is then only tested against the set that call produced. hs.window.get(id) looks
--- like the cheap way to ask about one id, and is not, since it is window.find(hint, true),
--- and window.find runs wins = wins or window.allWindows() whenever it has no list of its own
--- to search, so a per id call to hs.window.get repeats that same full accessibility
--- enumeration of every running application's windows once per stored id, forty of them on a
--- single keypress, on the main thread. Building the live set once and testing membership in
--- it is what keeps this an occasional single enumeration rather than dozens of them.
---
--- window.lua's own comment near its id accessor notes that a minimized window can also
--- report no id, so this prune can occasionally forget a window that only stepped out of view
--- rather than closing. That cost is acceptable here, since the whole table starts over on
--- every config reload regardless of anything a prune did or did not catch.
function obj:_pruneLastFrames()
  local count = 0
  for _ in pairs(self._lastFrames) do
    count = count + 1
  end
  if count <= 40 then return end

  local live = {}
  for _, w in ipairs(hs.window.allWindows()) do
    local id = w:id()
    if id then
      live[id] = true
    end
  end

  for windowId in pairs(self._lastFrames) do
    if not live[windowId] then
      self._lastFrames[windowId] = nil
    end
  end
end

--- WindowManager:moveToDisplay(direction)
--- Method
--- Move window to next or previous display, keeping its size and its place, and onto the frame it
--- had there when it has been there before, plan.lua's place
function obj:moveToDisplay(direction)
  self:_do(direction == "next" and "nextDisplay" or "previousDisplay")
end

--- WindowManager:moveToScreen(screen)
--- Method
--- Move focused window to specific screen
function obj:moveToScreen(screen)
  if screen then self:_do("toScreen", { target = uuidOf(screen) }) end
end

--- WindowManager:increaseSize(hold)
--- Method
--- Increase window size, by the held amount while the key is held
function obj:increaseSize(hold) self:_sized("increaseSize", hold) end

--- WindowManager:decreaseSize(hold)
--- Method
--- Decrease window size, by the held amount while the key is held
function obj:decreaseSize(hold) self:_sized("decreaseSize", hold) end

function obj:_sized(action, hold)
  if not hs.window.focusedWindow() then
    if self._notify then self._notify("No focused window") end
    return
  end
  self:_do(action, { depth = hold })
end

--- WindowManager:hideAllExceptFocused()
--- Method
--- Hide every app in the Dock except the one whose window has focus, as Hide Others does
function obj:hideAllExceptFocused()
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then return end
  local keep = focusedWindow:application():pid()
  local hidden = {}
  self._report = { hidden = hidden }
  -- The apps a person switches to, the ones in the Dock, as macOS's own Hide Others hides them, read
  -- from the running applications rather than from every window of every app. Walking the windows
  -- took over a second and a half with a dozen apps open, and hid the menu bar agent and Notification
  -- Center's interface too, which own windows of their own, found on 2026-11-20.
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 and app:pid() ~= keep and not app:isHidden() then
      hidden[#hidden + 1] = app:bundleID()
      app:hide()
    end
  end
end

--- WindowManager:_moveStep(hold) and WindowManager:_resizeStep(hold)
--- Method
--- How far one press travels, the press amount or the held one, plan.lua's own steps.
function obj:_moveStep(hold) return Plan.moveStep((self._settings or {}).windowSizing or {}, hold) end
function obj:_resizeStep(hold) return Plan.resizeStep((self._settings or {}).windowSizing or {}, hold) end

--- WindowManager:sizes() -> list
--- Method
--- The named sizes, Olm's setting windowSizes, each { id, name, width, height, unit, anchor,
--- display }. Small and Recording ship, each an action of the name it had before it was a size,
--- smallSize and screenRecording, and every other is size and its id.
function obj:sizes()
  return type((self._settings or {}).windowSizes) == "table" and self._settings.windowSizes or {}
end

local SIZE_ACTIONS = { small = "smallSize", recording = "screenRecording" }
function obj.sizeAction(id) return SIZE_ACTIONS[id] or ("size" .. id:sub(1, 1):upper() .. id:sub(2)) end

--- WindowManager:namedSize(id)
--- Method
--- Sizes and places the focused window as the named size id says, nothing when there is none.
function obj:namedSize(id)
  for _, z in ipairs(self:sizes()) do
    if z.id == id then return self:_do("namedSize", { named = z }) end
  end
end

function obj:screenRecording() self:namedSize("recording") end

--- WindowManager:exactSizePlan(width, height, screen)
--- Method
--- What an exact size request WOULD do, without doing any of it, so a surface can say so
--- before a person commits to it. Answers the size that would land plus whether anything was
--- taken off it, and nothing else, since a caller wording a row needs those two facts and no
--- geometry. Nil for a request that is not two usable numbers.
---
--- The ceiling is the screen's visible frame, which is the same frame exactSize applies
--- against, so the answer and the action agree by reading one thing. A request taller than the
--- space under the menu bar is therefore reported as trimmed rather than quietly placing a
--- window edge behind it, which is the honest answer even though a person asking for a round
--- number rarely expects the menu bar to come out of it.
---
--- The screen is resolved the way every other method here resolves it, the focused window's
--- own and the main screen otherwise. A LIST ASKING THIS WHILE IT IS SHOWING has no ordinary
--- focused window, so it reads the main screen, while the resize that follows runs once focus
--- is back and reads the real one. The two disagree only on a multiple display desk whose
--- screens are different sizes, where a row's trim wording can name a ceiling the action does
--- not use, which is why the caller is expected to hand the action the size as it was asked
--- for and let it trim against the screen it actually finds.
function obj:exactSizePlan(width, height, screen)
  local w, h = tonumber(width), tonumber(height)
  if not w or not h or w <= 0 or h <= 0 then return nil end

  screen = screen or (hs.window.focusedWindow() and hs.window.focusedWindow():screen()) or hs.screen.mainScreen()
  if not screen then return nil end
  local f = screen:frame()

  -- To whole pixels, since a window edge on a half pixel lines up with nothing beside it and a
  -- size read off a row should be a number a person recognises.
  local fitW = math.floor(math.min(w, f.w))
  local fitH = math.floor(math.min(h, f.h))
  return { width = fitW, height = fitH, clamped = fitW < w or fitH < h }
end

--- WindowManager:smallSize()
--- Method
--- Resize window to small size, centred on the canvas
function obj:smallSize() self:namedSize("small") end

-- camelCase action name to a Title Case label, the words every surface shows for an action,
-- the launcher row, the window sheet and the actions pane alike.
local function humanize(name)
  local s = tostring(name):gsub("(%l)(%u)", "%1 %2")
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- The actions in the order their launcher rows take, the order the bindings were authored in,
-- which matches the window sheet grid. Each names the facts every surface reads. repeats marks a
-- step worth repeating while its key is held, and when gates the key, the sheet row and the
-- launcher row together, the two display switches being pointless on one display. The last two
-- are unlisted, since neither has a key, and a row for exactSize could carry no size.
local ORDER = {
  { name = "previousDisplay", when = "multipleDisplays" },
  { name = "nextDisplay", when = "multipleDisplays" },
  { name = "leftHalf" }, { name = "rightHalf" }, { name = "fullHeight" },
  { name = "reasonableSize" }, { name = "maximize" },
  { name = "increaseSize", repeats = true }, { name = "decreaseSize", repeats = true },
  { name = "moveLeft", repeats = true }, { name = "moveRight", repeats = true },
  { name = "moveUp", repeats = true }, { name = "moveDown", repeats = true },
  { name = "center" }, { name = "hideAllExceptFocused" },
  { name = "exactSize", listed = false },
  -- The layouts a press steps through, round robin, plan.lua's LAYOUTS, with no key of their own,
  -- found in the launcher by name, Milos's ask of 2026-11-23. A person gives one a key in
  -- config/keymap.lua like any action.
  { name = "cycleHalves", description = "Halves, Left and Right" },
  { name = "cycleHalvesStacked", description = "Halves, Top and Bottom" },
  { name = "cycleThirds", description = "Thirds" },
  { name = "cycleTwoThirds", description = "Two Thirds" },
  { name = "cycleFourths", description = "Fourths" },
  { name = "cycleQuarters", description = "Quarters" },
}

--- WindowManager:actions() -> list of descriptors
--- Method
--- One action descriptor per window action, declared as provides.actions, in the order above.
--- Olm binds every key the bindings name to the descriptor's run and hands it the hold depth, 0
--- on the press, and lists every listed action in the launcher's catalog, so this plugin binds
--- nothing and builds no row. The kind is the word the launcher remembered these rows by before
--- they were descriptors, window and the action name, which the launcher's window scope also
--- narrows by. windowsize reads the same list as a sibling and calls exactSize's run with a size.
function obj:actions()
  local handlers = self:_handlers()
  local out = {}
  -- Every named size an action of its own after the fixed ones, Small's keeping its key.
  local order = {}
  for _, a in ipairs(ORDER) do order[#order + 1] = a end
  for _, z in ipairs(self:sizes()) do
    local name, id = obj.sizeAction(z.id), z.id
    handlers[name] = function() self:namedSize(id) end
    order[#order + 1] = { name = name, description = z.name, size = id }
  end
  for _, a in ipairs(order) do
    local handler = handlers[a.name]
    out[#out + 1] = {
      -- The run answers what the press read and planned, { window = report }, for Olm.app's shadow,
      -- step 6.3b. A caller that only runs the action ignores it.
      name = a.name, run = function(...)
        self._report = nil
        handler(...)
        local report = self._report
        self._report = nil
        return report and { window = report } or nil
      end, description = a.description or humanize(a.name),
      icon = "windows", kind = "window",
      when = a.when, repeats = a.repeats, listed = a.listed,
    }
  end
  return out
end

-- Which part of Olm Settings' Window Management page lists an action, by its name.
local GROUPS = {
  previousDisplay = "display", nextDisplay = "display",
  increaseSize = "step", decreaseSize = "step",
  moveLeft = "step", moveRight = "step", moveUp = "step", moveDown = "step",
  hideAllExceptFocused = "other",
}

--- WindowManager:catalog() -> list
--- Method
--- Every action the launcher lists, { action, title, group, size }, for the Window Management page,
--- which a setting's extra hands the share: a layout, a display move, a step, a named size by its
--- id, or other. The page never learns how an action works, only its name and where it belongs.
function obj:catalog()
  local out = {}
  for _, a in ipairs(ORDER) do
    if a.listed ~= false then
      out[#out + 1] = { action = a.name, title = a.description or humanize(a.name), group = GROUPS[a.name] or "layout" }
    end
  end
  for _, z in ipairs(self:sizes()) do
    out[#out + 1] = { action = obj.sizeAction(z.id), title = z.name, group = "size", size = z.id }
  end
  return out
end

-- The handler for each action, keyed by name. A repeating action reads the hold depth it is
-- called with, every other ignores the argument.
function obj:_handlers()
  return {
    maximize =             function() self:maximize() end,
    center =               function() self:center() end,
    fullHeight =           function() self:fullHeight() end,
    leftHalf =             function() self:leftHalf() end,
    rightHalf =            function() self:rightHalf() end,
    reasonableSize =       function() self:resizeDefault() end,
    increaseSize =         function(hold) self:increaseSize(hold) end,
    decreaseSize =         function(hold) self:decreaseSize(hold) end,
    nextDisplay =          function() self:moveToDisplay("next") end,
    previousDisplay =      function() self:moveToDisplay("previous") end,
    hideAllExceptFocused = function() self:hideAllExceptFocused() end,
    -- An exact size a surface parsed, sizing the window to it and centring it. The argument
    -- is a table and never the hold depth the repeating actions below take, so a non table is
    -- refused rather than read as a width. Nothing binds a key to this, since a size has to
    -- come from somewhere and a key carries none, and a person who bound one anyway would be
    -- handing it that depth, which is exactly the case the guard exists for.
    --
    -- The size arrives as it was ASKED FOR rather than already trimmed, so the trim happens
    -- against the screen the window is actually on at the moment of the press. exactSizePlan
    -- is the same answer computed ahead of time for a row to read, and it says why the two
    -- can differ.
    exactSize =            function(size)
      if type(size) ~= "table" then return end
      local w, h = tonumber(size.width), tonumber(size.height)
      if not w or not h then return end
      -- The one hard failure worth a message, the same shape a resize with nothing focused uses. A chosen
      -- row that silently does nothing reads as a broken feature, and the ordinary way to get
      -- here with nothing focused is a desktop with no window on it.
      if not hs.window.focusedWindow() then
        if self._notify then self._notify("No focused window") end
        return
      end
      self:_do("exactSize", { size = { width = w, height = h } })
    end,
    -- The four moves and the two resizes above take the hold depth the leader calls a
    -- repeating action with, and read their step off it, the press amount or the held one.
    -- Every other action here ignores the argument, since none of them repeats and a
    -- placement is the same wherever in a hold it is asked for.
    cycleHalves =          function() self:_do("cycleHalves") end,
    cycleHalvesStacked =   function() self:_do("cycleHalvesStacked") end,
    cycleThirds =          function() self:_do("cycleThirds") end,
    cycleTwoThirds =       function() self:_do("cycleTwoThirds") end,
    cycleFourths =         function() self:_do("cycleFourths") end,
    cycleQuarters =        function() self:_do("cycleQuarters") end,
    moveLeft =             function(hold) self:_do("moveLeft", { depth = hold }) end,
    moveRight =            function(hold) self:_do("moveRight", { depth = hold }) end,
    moveUp =               function(hold) self:_do("moveUp", { depth = hold }) end,
    moveDown =             function(hold) self:_do("moveDown", { depth = hold }) end,
  }
end

return obj
