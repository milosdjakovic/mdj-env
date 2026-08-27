-- Unit case for the hold step in Olm.spoon/plugins/windowmanager/init.lua, how far one press
-- of a move or resize key travels. The timing of a hold belongs to the chord engine and is
-- covered by cases/chordkey-repeat.lua; this case is only the distance, which is this
-- plugin's own policy, plus the wiring that carries the hold depth into it, since an action
-- that quietly ignored the depth would still move a window and look right.
--
-- There are exactly two distances, a press and a held repeat, and the case is mostly about
-- proving there is nothing in between, since a distance that drifted while the key was down
-- would make where a window lands depend on the moment it was released.
--
-- Loaded into an environment of this case's own with a fake hs in it, so a real window is
-- never touched and the frame each press produces can be read exactly.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/plugins/windowmanager/init.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local SIZING = {
  movePixels = 20, movePixelsHeld = 40,
  resizePixels = 30, resizePixelsHeld = 50,
  holdGrace = 1,
  minWidth = 400, minHeight = 300,
}

-- Two canvases, the same shape turned both ways, since one of them alone would hide the whole
-- point of anchoring on the long edge rather than on the width. 2.5 to 1, so the short edge
-- takes two fifths of whatever the long edge is given.
local WIDE = { w = 4000, h = 1600 }
local TALL = { w = 1600, h = 4000 }
local SHARE = 0.4

-- A window in the middle of a large canvas, so nothing below is clamped by an edge and every
-- reading is the step itself rather than the room that was left.
local function freshModule(canvas)
  canvas = canvas or WIDE
  local frame = { x = 500, y = 400, w = 700, h = 500 }
  local screen = { frame = function() return { x = 0, y = 0, w = canvas.w, h = canvas.h } end }
  local win = {
    frame = function() return { x = frame.x, y = frame.y, w = frame.w, h = frame.h } end,
    screen = function() return screen end,
    setFrame = function(_, f) frame = { x = f.x, y = f.y, w = f.w, h = f.h } end,
  }
  local fakeHs = {
    logger = { new = function() return { w = function() end } end },
    window = { focusedWindow = function() return win end, animationDuration = 0 },
    geometry = { rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end },
    alert = { show = function() end },
  }
  local env = {
    hs = fakeHs, math = math, table = table, string = string,
    type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, print = print,
  }
  local chunk, err = loadfile(modulePath, "t", env)
  if not chunk then
    error("could not load plugins/windowmanager/init.lua, " .. tostring(err))
  end
  local wm = chunk()
  wm:init()
  wm:configure({ settings = { windowSizing = SIZING } })
  return wm, function() return frame end
end

-- A press on its own is the small precise amount, which is what placing a window by eye needs
-- and the one thing none of this may change. One number answers for moving and resizing both.
do
  local wm = freshModule()
  check("the move press travels the move press amount", wm:_moveStep(0) == 20,
    "got " .. tostring(wm:_moveStep(0)))
  check("a call with no depth at all travels the press amount", wm:_moveStep(nil) == 20,
    "got " .. tostring(wm:_moveStep(nil)))
  check("the resize press is its own, larger amount", wm:_resizeStep(0) == 30,
    "got " .. tostring(wm:_resizeStep(0)))
end

-- Every repeat is the held amount, the same held amount, however long the key stays down.
do
  local wm = freshModule()
  check("the very first repeat is already the held amount", wm:_moveStep(1) == 40,
    "got " .. tostring(wm:_moveStep(1)))
  local drifted = false
  for hold = 1, 200 do
    if wm:_moveStep(hold) ~= SIZING.movePixelsHeld then drifted = true end
    if wm:_resizeStep(hold) ~= SIZING.resizePixelsHeld then drifted = true end
  end
  check("two hundred repeats and not one of them travels a different distance", not drifted)
  check("resizing holds its own larger amount", wm:_resizeStep(50) == 50,
    "got " .. tostring(wm:_resizeStep(50)))
end

-- The grace is what decides when the held amount takes over, so raising it keeps more of a
-- short hold at the precise amount.
do
  local wm = freshModule()
  wm:configure({ settings = { windowSizing = {
    movePixels = 20, movePixelsHeld = 40, holdGrace = 3,
  } } })
  check("a grace of three keeps the first two repeats at the press amount",
    wm:_moveStep(1) == 20 and wm:_moveStep(2) == 20,
    "got " .. tostring(wm:_moveStep(1)) .. ", " .. tostring(wm:_moveStep(2)))
  check("and hands over on the one after", wm:_moveStep(3) == 40,
    "got " .. tostring(wm:_moveStep(3)))
end

-- Resizing spends its step across two axes in the proportions of the canvas, the long edge
-- taking the step whole and the short edge its share. On a 2.5 to 1 canvas a 30 pixel press
-- grows the long edge by 30 and the short one by 12.
local function pressGrowth(canvas)
  local wm, frameNow = freshModule(canvas)
  local before = { w = frameNow().w, h = frameNow().h }
  wm:actions().increaseSize(0)
  return frameNow().w - before.w, frameNow().h - before.h
end

do
  local grewW, grewH = pressGrowth(WIDE)
  check("on a landscape canvas the width takes the step whole",
    grewW == 30, "grew " .. tostring(grewW))
  check("and the height takes its share of it",
    grewH == 12, "grew " .. tostring(grewH) .. " against a share of " .. tostring(SHARE))
  check("so the short edge grows slower than the long one", grewH < grewW)
end

-- The same shape rotated. This is the case that decides the whole rule, since anchoring on
-- the width instead would make the step mean the long edge here and the short edge there, so
-- one key would cover very different ground either side of a rotation.
do
  local grewW, grewH = pressGrowth(TALL)
  check("on a portrait canvas the height takes the step whole",
    grewH == 30, "grew " .. tostring(grewH))
  check("and the width takes its share of it",
    grewW == 12, "grew " .. tostring(grewW))
  check("so a rotation leaves the long edge growing by exactly the same step",
    grewH == select(1, pressGrowth(WIDE)),
    "portrait long edge " .. tostring(grewH))
end

-- A square canvas is not a special case, it is where both shares are one.
do
  local grewW, grewH = pressGrowth({ w = 2000, h = 2000 })
  check("a square canvas grows both edges by the step",
    grewW == 30 and grewH == 30,
    "grew " .. tostring(grewW) .. " by " .. tostring(grewH))
end

-- Growing in the canvas proportion moves a window's shape TOWARD the screen's rather than
-- setting it, which is the honest claim and worth stating as one. Each press adds the ratio
-- itself, so the aspect approaches it and only reaches it in the limit, and a window that
-- started nothing like the screen still stops being a column instead of becoming more of one.
do
  local wm, frameNow = freshModule(WIDE)
  local actions = wm:actions()
  local canvasRatio = WIDE.h / WIDE.w
  -- Centered first, and deliberately so. Growth is split between the two opposing edges, so a
  -- window that has run out of room on one side gets only half its step on that axis and the
  -- shape stops tracking the canvas, which is the right behaviour at an edge and simply not
  -- what this block is about. The claim here is about a window with room around it.
  actions.center()
  local function drift()
    local f = frameNow()
    return math.abs((f.h / f.w) - canvasRatio)
  end

  local started = drift()
  local grewApart = false
  local previous = started
  for _ = 1, 30 do
    actions.increaseSize(9)
    local now = drift()
    if now > previous + 1e-9 then grewApart = true end
    previous = now
  end

  check("every held resize leaves the window closer to the canvas shape than the one before",
    not grewApart)
  check("thirty of them close most of the gap",
    previous < started / 2, "started " .. string.format("%.4f", started) ..
    " and ended " .. string.format("%.4f", previous))
  local f = frameNow()
  check("and it is approaching from the tall side rather than overshooting",
    (f.h / f.w) > canvasRatio, "window ratio " .. string.format("%.4f", f.h / f.w))
end

-- Every edge stays on a whole pixel, since a window edge on a half lines up with nothing
-- beside it, and the height share is the one number here that does not divide evenly.
do
  local wm, frameNow = freshModule()
  local actions = wm:actions()
  local fractional = false
  for _ = 1, 20 do
    actions.increaseSize(9)
    local f = frameNow()
    for _, v in ipairs({ f.x, f.y, f.w, f.h }) do
      if v ~= math.floor(v) then fractional = true end
    end
  end
  check("no press ever leaves an edge on a fraction", not fractional)
end

-- The wiring. An action that ignored the depth would still move a window and look right, so
-- what is checked here is that a repeat actually travels further than a press.
do
  local wm, frameNow = freshModule()
  local actions = wm:actions()
  local startX = frameNow().x
  actions.moveRight(0)
  local pressed = frameNow().x - startX
  local mid = frameNow().x
  actions.moveRight(9)
  local held = frameNow().x - mid
  check("the action map carries the depth into the step",
    pressed == 20 and held == SIZING.movePixelsHeld,
    "press " .. tostring(pressed) .. ", held " .. tostring(held))

  local before = frameNow().x
  actions.moveLeft(9)
  check("a move the other way travels the same held amount",
    before - frameNow().x == SIZING.movePixelsHeld,
    "moved " .. tostring(before - frameNow().x))

  local widthBefore = frameNow().w
  actions.increaseSize(9)
  check("the resize action carries the depth too, into its long edge",
    frameNow().w - widthBefore == SIZING.resizePixelsHeld,
    "grew " .. tostring(frameNow().w - widthBefore))
end

-- An action called with no depth, which is every way one is reached other than a held key,
-- has to keep behaving exactly as it did.
do
  local wm, frameNow = freshModule()
  local actions = wm:actions()
  local before = frameNow().y
  actions.moveDown()
  check("an action reached with no depth moves the press amount",
    frameNow().y - before == 20, "moved " .. tostring(frameNow().y - before))
end
