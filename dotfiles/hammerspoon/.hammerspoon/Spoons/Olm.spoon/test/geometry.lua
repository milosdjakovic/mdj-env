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

-- The action bar. A footer height is taken from the rows a short screen can hold, sits under the
-- list across the canvas's full width, and is absent when the height is zero.
local short = { x = 0, y = 0, w = 1440, h = 600 }
local bare = geometry.resolve(short, layoutWith(9), nil)
check("a 600 point screen holds eight rows with no bar", bare.rowCount, 8)
check("and resolves no footer rect", bare.footer == nil and 1 or 0, 1)
local barred = layoutWith(9)
-- 35 is the shipped bar, the hint chip 23 with the small space 6 above and below.
barred.footerH = 35
local withBar = geometry.resolve(short, barred, nil)
check("a 35 point bar trims the same screen to seven rows", withBar.rowCount, 7)
check("the canvas grows by the bar", withBar.canvas.h,
  barred.marginY + barred.baseH + withBar.viewRows * barred.rowH + 35)
check("the footer is the bar's height", withBar.footer.h, 35)
-- The rows a screen holds turn on the bar's own height, seven at 565.1 points and six just below.
check("seven rows fit exactly where the bar leaves room for them", geometry.resolve({ x = 0, y = 0, w = 1440, h = 565.1 }, barred, nil).rowCount, 7)
check("and six one hair shorter", geometry.resolve({ x = 0, y = 0, w = 1440, h = 565 }, barred, nil).rowCount, 6)
check("the footer spans the canvas's width", withBar.footer.w, withBar.canvas.w)
check("the footer starts at the canvas's left edge", withBar.footer.x, withBar.canvas.x)
check("the footer sits on the canvas's bottom edge", withBar.footer.y + withBar.footer.h, withBar.canvas.y + withBar.canvas.h)
check("the list stops at the footer's top edge", withBar.list.y + withBar.list.h, withBar.footer.y)
local paned = geometry.resolve(screen, barred, true)
check("a companion keeps matching the canvas height with the bar", paned.companion.h, paned.canvas.h)

if failed then os.exit(1) end
