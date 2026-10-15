-- The canvas viewport's row arithmetic, in plain Lua.
--
-- A viewport of one row takes no peek, since a tool that shows one row never has a list that
-- continues, and a viewport of several rows keeps the peek that says the list goes on. Pure
-- arithmetic, so it needs no Hammerspoon and no lock.
--
-- Run it.
--   lua test/geometry.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local geometry = dofile(here .. "../lib/chooser/providers/default/geometry.lua")

local screen = { x = 0, y = 0, w = 1920, h = 1080 }
local failed = false

local function check(name, got, want)
  if math.abs(got - want) > 1e-9 then
    failed = true
    print(("FAIL %s, wanted %s, got %s"):format(name, want, got))
  else
    print(("ok   %s"):format(name))
  end
end

local function layoutWith(rowCount)
  local layout = {}
  for k, v in pairs(geometry.DEFAULT_LAYOUT) do layout[k] = v end
  layout.rowCount = rowCount
  return layout
end

check("one row has viewRows 1", geometry.resolve(screen, layoutWith(1), nil).viewRows, 1)
check("nine rows keep viewRows 9.3", geometry.resolve(screen, layoutWith(9), nil).viewRows, 9.3)

if failed then os.exit(1) end
