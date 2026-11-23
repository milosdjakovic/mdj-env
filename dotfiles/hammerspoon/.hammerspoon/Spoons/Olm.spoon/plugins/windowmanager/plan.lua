-- Where a window action puts the focused window, as one pure function, step 6.3 of
-- docs/PLAN-STANDALONE.md. init.lua gathers what an action reads, the window's frame, its screen,
-- every screen and what the window remembers of each, hands it here and writes the frame this
-- answers, so the geometry has one statement that test/fixtures/windows/plan.json pins and Olm.app's
-- WindowPlan.swift answers the same way. Nothing here touches hs, so the fixtures run it in plain Lua.
--
-- M.plan(action, s) -> result or nil
--
--   action      a window action's name, the names init.lua's ORDER lists, plus fullHeightReasonableWidth
--               and toScreen, the two the plugin's own methods reach with no key
--   s.window    the focused window's frame, { x, y, w, h }, nil when nothing has focus
--   s.id        its window id, nil when it has none
--   s.screen    the uuid of the screen it is on
--   s.screens   every screen, in hs.screen.allScreens's order, each { uuid, frame }, the frame being
--               the screen's visible frame, below the menu bar and beside the Dock
--   s.margins   { top, right, bottom, left }, numbers
--   s.gap       the gutter between tiled halves
--   s.sizing    config/settings.lua's windowSizing block
--   s.depth     how deep into a held key a repeating action is, 0 on the press
--   s.size      { width, height }, the size exactSize asks for
--   s.target    the uuid toScreen moves to
--   s.memory    what the window remembers, the frame it last had on each screen by uuid
--
-- result.frame     the frame to write
-- result.screen    the uuid of the screen it lands on, given for a move between screens
-- result.remember  { screen, frame }, the frame the window leaves a screen with, for the memory
-- result.verify    true when the write is read back and retried through hs.window's workarounds on a
--                  miss, which only a move between screens needs, see init.lua's _applyFrame
--
-- nil means the action does nothing now, no window, no screen to move to, or a shrink at its floor.

local M = {}

-- Hold a value inside a travel range, whichever way round the two bounds arrive. A window
-- wider than the canvas inverts the range, since its left edge can then only sit at or left
-- of the canvas edge, and ordering the pair keeps that case a real range to slide along,
-- flush left through flush right, rather than an empty one that would pin the window where
-- it stands.
local function clampBetween(value, a, b)
  local low, high = math.min(a, b), math.max(a, b)
  if value < low then return low end
  if value > high then return high end
  return value
end
M.clampBetween = clampBetween

local function rect(f) return { x = f.x, y = f.y, w = f.w, h = f.h } end

-- A screen by its uuid, and its place in the list.
local function find(screens, uuid)
  for i, screen in ipairs(screens or {}) do
    if screen.uuid == uuid then return screen, i end
  end
  return nil
end

-- The canvas a screen offers, its visible frame less the margins.
function M.canvas(frame, margins)
  margins = margins or {}
  local top, right = margins.top or 0, margins.right or 0
  local bottom, left = margins.bottom or 0, margins.left or 0
  return { x = frame.x + left, y = frame.y + top, w = frame.w - left - right, h = frame.h - top - bottom }
end

-- How far one press travels, which is one of two amounts and never anything in between. A key
-- pressed on its own moves press, small enough to place a window by eye, and a key being held
-- moves held, far enough that crossing a screen is a hold rather than an errand. The first
-- holdGrace repeats count as the press. Two amounts rather than a ramp, since a distance that keeps
-- growing under a held finger is a distance nobody can aim with.
local function holdStep(sizing, press, held, depth)
  if (depth or 0) < (sizing.holdGrace or 1) then return press end
  return held
end

function M.moveStep(sizing, depth)
  local press = sizing.movePixels or 20
  return holdStep(sizing, press, sizing.movePixelsHeld or (press * 2), depth)
end

-- Its own pair and a larger one, since a resize moves an edge across two axes where a move slides
-- the whole window one distance.
function M.resizeStep(sizing, depth)
  local press = sizing.resizePixels or 30
  return holdStep(sizing, press, sizing.resizePixelsHeld or (press + 20), depth)
end

-- To whole pixels, and by an even number, since half of a step goes to each of two opposing edges
-- and a half pixel edge lines up with nothing beside it.
local function wholePair(value)
  local half = value / 2
  local rounded = half >= 0 and math.floor(half + 0.5) or -math.floor(-half + 0.5)
  return rounded * 2
end

-- amount is what the canvas's LONG edge grows by, the short edge taking its proportional share,
-- so a window grows in the shape of the screen it grows inside and one press moves the long edge
-- the same whichever way the screen is turned. Growing stops at the canvas and shrinking at a
-- floor per axis, since a held key would otherwise walk a window down to a sliver with no key to
-- bring it back.
local function adjust(frame, canvas, sizing, amount)
  local longest = math.max(canvas.w, canvas.h)
  local shareW = longest > 0 and (canvas.w / longest) or 1
  local shareH = longest > 0 and (canvas.h / longest) or 1
  local amountW, amountH = wholePair(amount * shareW), wholePair(amount * shareH)
  if amount < 0 then
    amountW = -math.min(-amountW, math.max(0, frame.w - (sizing.minWidth or 400)))
    amountH = -math.min(-amountH, math.max(0, frame.h - (sizing.minHeight or 300)))
    if amountW == 0 and amountH == 0 then return nil end
  end

  local roomLeft = math.max(0, frame.x - canvas.x)
  local roomRight = math.max(0, (canvas.x + canvas.w) - (frame.x + frame.w))
  local roomTop = math.max(0, frame.y - canvas.y)
  local roomBottom = math.max(0, (canvas.y + canvas.h) - (frame.y + frame.h))

  local increaseLeft = math.min(amountW / 2, roomLeft)
  local increaseRight = math.min(amountW / 2, roomRight)
  local increaseTop = math.min(amountH / 2, roomTop)
  local increaseBottom = math.min(amountH / 2, roomBottom)

  local newLeft = frame.x - increaseLeft
  if newLeft < canvas.x then
    increaseRight = increaseRight + (canvas.x - newLeft)
    increaseLeft = frame.x - canvas.x
  end
  local newTop = frame.y - increaseTop
  if newTop < canvas.y then
    increaseBottom = increaseBottom + (canvas.y - newTop)
    increaseTop = frame.y - canvas.y
  end

  return {
    x = frame.x - increaseLeft,
    y = frame.y - increaseTop,
    w = frame.w + increaseLeft + increaseRight,
    h = frame.h + increaseTop + increaseBottom,
  }
end

-- Only the axis the key moved is clamped, stopping flush against the canvas maximize uses, so a
-- held key never walks a window off the display, and a press to the right never pulls it down.
local function move(frame, canvas, direction, pixels)
  local f = rect(frame)
  if direction == "left" or direction == "right" then
    f.x = f.x + (direction == "right" and pixels or -pixels)
    f.x = clampBetween(f.x, canvas.x, canvas.x + canvas.w - f.w)
  elseif direction == "up" or direction == "down" then
    f.y = f.y + (direction == "down" and pixels or -pixels)
    f.y = clampBetween(f.y, canvas.y, canvas.y + canvas.h - f.h)
  end
  return f
end

-- A size centred on a screen's visible frame, each side no larger than the frame.
local function sized(frame, width, height)
  local w = math.min(width or frame.w, frame.w)
  local h = math.min(height or frame.h, frame.h)
  return { x = frame.x + (frame.w - w) / 2, y = frame.y + (frame.h - h) / 2, w = w, h = h }
end

-- A window moved onto another screen keeping its size and its place. Each side is clamped to the
-- target canvas only where it does not fit, and the centre is carried over as a fraction of the
-- source canvas, so a window a third of the way across a small screen lands a third of the way
-- across the large one. A window returning to a screen it has visited lands on the frame it had
-- there, while all four of that frame's edges still lie inside the canvas, since the frame is
-- absolute and a screen's origin moves when the displays are arranged again.
local function place(s, frame, source, target)
  local remember = s.id ~= nil and source and { screen = source.uuid, frame = rect(frame) } or nil
  local targetCanvas = M.canvas(target.frame, s.margins)
  local remembered = s.id ~= nil and s.memory and s.memory[target.uuid]
  if remembered
    and remembered.x >= targetCanvas.x
    and remembered.y >= targetCanvas.y
    and remembered.x + remembered.w <= targetCanvas.x + targetCanvas.w
    and remembered.y + remembered.h <= targetCanvas.y + targetCanvas.h then
    return {
      frame = { x = math.floor(remembered.x), y = math.floor(remembered.y),
                w = math.floor(remembered.w), h = math.floor(remembered.h) },
      screen = target.uuid, remember = remember, verify = true,
    }
  end

  local sourceCanvas = M.canvas(source.frame, s.margins)
  local newW = math.min(frame.w, targetCanvas.w)
  local newH = math.min(frame.h, targetCanvas.h)
  local cx, cy = 0.5, 0.5
  if sourceCanvas.w > 0 then cx = (frame.x + frame.w / 2 - sourceCanvas.x) / sourceCanvas.w end
  if sourceCanvas.h > 0 then cy = (frame.y + frame.h / 2 - sourceCanvas.y) / sourceCanvas.h end
  local newX = targetCanvas.x + cx * targetCanvas.w - newW / 2
  local newY = targetCanvas.y + cy * targetCanvas.h - newH / 2
  newX = clampBetween(newX, targetCanvas.x, targetCanvas.x + targetCanvas.w - newW)
  newY = clampBetween(newY, targetCanvas.y, targetCanvas.y + targetCanvas.h - newH)
  return {
    frame = { x = math.floor(newX), y = math.floor(newY), w = math.floor(newW), h = math.floor(newH) },
    screen = target.uuid, remember = remember, verify = true,
  }
end

local MOVES = { moveLeft = "left", moveRight = "right", moveUp = "up", moveDown = "down" }

function M.plan(action, s)
  s = s or {}
  local window = s.window
  if not window then return nil end
  local screen, index = find(s.screens, s.screen)
  if not screen then return nil end
  local sizing = s.sizing or {}
  local gap = s.gap or 0
  local canvas = M.canvas(screen.frame, s.margins)
  local f = rect(window)

  if action == "maximize" then
    return { frame = rect(canvas) }
  elseif action == "center" then
    f.x = canvas.x + (canvas.w - f.w) / 2
    f.y = canvas.y + (canvas.h - f.h) / 2
    return { frame = f }
  elseif action == "fullHeightReasonableWidth" then
    f.h = canvas.h
    f.w = math.min(canvas.w - 140, sizing.fullHeightMaxWidth or 2400)
    f.x = canvas.x + (canvas.w - f.w) / 2
    f.y = canvas.y
    return { frame = f }
  elseif action == "fullHeight" then
    f.h = canvas.h
    f.y = canvas.y
    return { frame = f }
  elseif action == "reasonableSize" then
    local w = math.min(sizing.maxWidth or 1800, canvas.w - 80)
    local h = math.min(sizing.maxHeight or 1200, canvas.h - 80)
    return { frame = { x = canvas.x + (canvas.w - w) / 2, y = canvas.y + (canvas.h - h) / 2, w = w, h = h } }
  elseif action == "leftHalf" then
    return { frame = { x = canvas.x, y = canvas.y, w = (canvas.w - gap) / 2, h = canvas.h } }
  elseif action == "rightHalf" then
    return { frame = { x = canvas.x + (canvas.w + gap) / 2, y = canvas.y, w = (canvas.w - gap) / 2, h = canvas.h } }
  elseif action == "increaseSize" or action == "decreaseSize" then
    local step = M.resizeStep(sizing, s.depth)
    local next = adjust(f, canvas, sizing, action == "increaseSize" and step or -step)
    return next and { frame = next } or nil
  elseif MOVES[action] then
    return { frame = move(f, canvas, MOVES[action], M.moveStep(sizing, s.depth)) }
  elseif action == "smallSize" then
    -- Sized on the visible frame, then centred on the canvas, the two steps the action takes.
    local small = sizing.smallSize or { width = 700, height = 800 }
    local w = sized(screen.frame, small.width, small.height)
    return { frame = { x = canvas.x + (canvas.w - w.w) / 2, y = canvas.y + (canvas.h - w.h) / 2, w = w.w, h = w.h } }
  elseif action == "exactSize" then
    local size = s.size
    if type(size) ~= "table" then return nil end
    local w, h = tonumber(size.width), tonumber(size.height)
    if not w or not h then return nil end
    return { frame = sized(screen.frame, w, h) }
  elseif action == "nextDisplay" or action == "previousDisplay" then
    -- hs.screen's next and previous, wrapping, so a single screen places the window back onto
    -- itself, inside its canvas.
    local n = #s.screens
    local to = action == "nextDisplay" and (index % n) + 1 or ((index - 2) % n) + 1
    return place(s, f, screen, s.screens[to])
  elseif action == "toScreen" then
    local target = find(s.screens, s.target)
    if not target then return nil end
    return place(s, f, screen, target)
  elseif action == "screenRecording" then
    -- Onto the second screen, or the first where there is one, then sized there.
    local target = s.screens[2] or s.screens[1]
    local moved = place(s, f, screen, target)
    local sizes = sizing.screenRecording or { width = 2400, height = 1350 }
    moved.frame = sized(target.frame, sizes.width, sizes.height)
    -- Read back only where it crossed to another screen, the case a plain write can land short.
    moved.verify = target.uuid ~= screen.uuid or nil
    return moved
  end
  return nil
end

return M
