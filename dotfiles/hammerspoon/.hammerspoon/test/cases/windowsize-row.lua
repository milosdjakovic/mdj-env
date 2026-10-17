-- Unit case for Olm.spoon/plugins/windowsize/init.lua, the query row source that turns a typed
-- size into one launcher row. The runner reaches this file with a dofile call carrying an
-- absolute path, so this file locates itself through debug.getinfo and derives the module path
-- from there, the same way cases/arithmetic.lua does. No absolute path is written down here.
--
-- The plugin reaches nothing of Hammerspoon's own, since the window manager's plan and the
-- launcher's covered app both arrive through configure. The covered app is a stand in that
-- answers a name and whether it has a focused window. The plan is the window manager's real
-- exactSizePlan, loaded from this checkout over a small hs stand in and handed a fake screen,
-- so the trim arithmetic is the one the action uses and is not copied here.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/plugins/windowsize/init.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(opts)
  local chunk, err = loadfile(modulePath)
  if not chunk then
    print("FAIL load Olm.spoon/plugins/windowsize/init.lua, " .. tostring(err))
    return nil
  end
  local module = chunk()
  local instance = setmetatable({}, module)
  instance:init()
  instance:configure(opts)
  return instance
end

-- The window manager's own module, which reads hs only while loading, for a logger.
local realHs = hs
hs = {
  logger = { new = function()
    return setmetatable({}, { __index = function() return function() end end })
  end },
}
local wmChunk, wmErr = loadfile(caseDir .. "/../../Spoons/Olm.spoon/plugins/windowmanager/init.lua")
local windowManager = wmChunk and wmChunk()
hs = realHs
if not windowManager then print("FAIL load the window manager, " .. tostring(wmErr)) end

local function planOn(width, height)
  local screen = { frame = function() return { x = 0, y = 0, w = width, h = height } end }
  return function(w, h)
    if not windowManager then return nil end
    return windowManager.exactSizePlan(windowManager, w, h, screen)
  end
end

-- A display large enough for anything typed below, so nothing is trimmed.
local roomy = planOn(100000, 100000)

-- A display 1728 by 1080.
local laptop = planOn(1728, 1080)

local function app(name, windowless)
  return {
    name = function() return name end,
    focusedWindow = function() if not windowless then return {} end end,
  }
end

local function only(instance, query)
  local rows = instance:rows(query)
  return rows[1], #rows
end

-- The title names the application the launcher is covering.
do
  local ws = fresh({ plan = roomy, coveredApp = function() return app("Safari"), 3 end })
  local row = only(ws, "1920x1080")
  check("the title names the covered application", row and row.title == "Resize Safari",
    row and row.title)
end

-- A covered app with no focused window cannot receive the resize, so the title does not name it.
do
  local ws = fresh({ plan = roomy, coveredApp = function() return app("Finder", true), 3 end })
  local row = only(ws, "1920x1080")
  check("an app with no focused window reads Resize window",
    row and row.title == "Resize window", row and row.title)

  local asked = false
  ws = fresh({ plan = roomy, coveredApp = function()
    return { name = function() return "Safari" end, focusedWindow = function() asked = true return {} end }
  end })
  only(ws, "not a size")
  check("an ordinary query never asks the app for its window", asked == false)

  ws = fresh({ plan = roomy, coveredApp = function()
    return { name = function() return "Safari" end, focusedWindow = function() error("the app quit") end }
  end })
  row = only(ws, "1920x1080")
  check("an app that cannot answer its window reads Resize window",
    row and row.title == "Resize window", row and row.title)
end

-- No covered app, or no root word at all, reads as a window.
do
  local ws = fresh({ plan = roomy, coveredApp = function() return nil, 1 end })
  local row = only(ws, "1920x1080")
  check("an unknown application reads Resize window", row and row.title == "Resize window",
    row and row.title)

  ws = fresh({ plan = roomy })
  row = only(ws, "1920x1080")
  check("no coveredApp word at all reads Resize window", row and row.title == "Resize window",
    row and row.title)

  ws = fresh({ plan = roomy, coveredApp = function()
    return { name = function() error("the app quit") end }
  end })
  row = only(ws, "1920x1080")
  check("an app that cannot answer its name reads Resize window",
    row and row.title == "Resize window", row and row.title)
end

-- The plain subtitle is the size that will land and nothing else.
do
  local ws = fresh({ plan = roomy })
  local row = only(ws, "1920x1080")
  check("the plain subtitle is the size alone", row and row.subTitle == "1920 x 1080",
    row and row.subTitle)
  local size = row and row.item and row.item.size or {}
  check("the plain descriptor carries the size as typed",
    size.width == 1920 and size.height == 1080)
end

-- A size the display cannot hold says so, and the descriptor keeps the size before the trim,
-- since the action trims against the screen it finds rather than this moment's guess.
do
  local ws = fresh({ plan = laptop })
  local row = only(ws, "2560x1440")
  check("a trimmed size reads display limit", row and row.subTitle == "1728 x 1080, display limit",
    row and row.subTitle)
  local size = row and row.item and row.item.size or {}
  check("the display trim stays out of the descriptor",
    size.width == 2560 and size.height == 1440)
end

-- An edge under the floor is raised to it, offered, and carried raised.
do
  local ws = fresh({ plan = roomy })
  local row, count = only(ws, "19x400")
  check("a size under the floor still offers its row", count == 1, tostring(count))
  check("a floored size reads size limit", row and row.subTitle == "200 x 400, size limit",
    row and row.subTitle)
  local size = row and row.item and row.item.size or {}
  check("the floored descriptor carries the raised size",
    size.width == 200 and size.height == 400,
    tostring(size.width) .. " x " .. tostring(size.height))
end

-- The plan is asked about the floored size, not the one typed.
do
  local asked
  local ws = fresh({ plan = function(w, h) asked = { w, h }; return roomy(w, h) end })
  only(ws, "19x400")
  check("the plan is asked about the floored size",
    asked and asked[1] == 200 and asked[2] == 400)
end

-- An edge exactly on the floor is not a limit.
do
  local ws = fresh({ plan = roomy })
  local row = only(ws, "200x400")
  check("an edge on the floor reads plain", row and row.subTitle == "200 x 400",
    row and row.subTitle)
end

-- Both limits at once name the size limit, since it holds on every display.
do
  local ws = fresh({ plan = laptop })
  local row = only(ws, "19x5000")
  check("both limits read size limit", row and row.subTitle == "200 x 1080, size limit",
    row and row.subTitle)
  local size = row and row.item and row.item.size or {}
  check("both limits carry the floored size before the display trim",
    size.width == 200 and size.height == 5000)
end

-- A smaller floor from configuration moves the line.
do
  local ws = fresh({ plan = roomy, smallestEdge = 50 })
  local row = only(ws, "100x400")
  check("a configured floor of 50 leaves 100 alone", row and row.subTitle == "100 x 400",
    row and row.subTitle)
end

-- Anything that is not a size still answers nothing.
do
  local ws = fresh({ plan = roomy })
  local _, count = only(ws, "safari 1920x1080")
  check("a size inside a longer query offers no row", count == 0, tostring(count))
end
