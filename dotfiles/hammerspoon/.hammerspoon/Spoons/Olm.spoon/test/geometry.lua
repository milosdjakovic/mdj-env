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

-- The bottom bar. A bottom bar height is taken from the rows a short screen can hold, sits under the
-- list across the canvas's full width, and is absent when the height is zero.
local short = { x = 0, y = 0, w = 1440, h = 600 }
local bare = geometry.resolve(short, layoutWith(9), nil)
check("a 600 point screen holds eight rows with no bar", bare.rowCount, 8)
check("and resolves no bottom bar rect", bare.bottomBar == nil and 1 or 0, 1)
local barred = layoutWith(9)
-- 35 is the shipped bar, the hint chip 23 with the small space 6 above and below.
barred.bottomBarH = 35
local withBar = geometry.resolve(short, barred, nil)
check("a 35 point bar trims the same screen to seven rows", withBar.rowCount, 7)
check("the canvas grows by the bar", withBar.canvas.h,
  barred.marginY + barred.baseH + withBar.viewRows * barred.rowH + 35)
check("the bottom bar is the bar's height", withBar.bottomBar.h, 35)
-- The rows a screen holds turn on the bar's own height, seven at 565.1 points and six just below.
check("seven rows fit exactly where the bar leaves room for them", geometry.resolve({ x = 0, y = 0, w = 1440, h = 565.1 }, barred, nil).rowCount, 7)
check("and six one hair shorter", geometry.resolve({ x = 0, y = 0, w = 1440, h = 565 }, barred, nil).rowCount, 6)
check("the bottom bar spans the canvas's width", withBar.bottomBar.w, withBar.canvas.w)
check("the bottom bar starts at the canvas's left edge", withBar.bottomBar.x, withBar.canvas.x)
check("the bottom bar sits on the canvas's bottom edge", withBar.bottomBar.y + withBar.bottomBar.h, withBar.canvas.y + withBar.canvas.h)
check("the list stops at the bottom bar's top edge", withBar.list.y + withBar.list.h, withBar.bottomBar.y)
local paned = geometry.resolve(screen, barred, true)
check("a preview pane keeps matching the canvas height with the bar", paned.previewPane.h, paned.canvas.h)
check("and the bar stays under the canvas alone", paned.bottomBar.w, paned.canvas.w)
-- A view drawing one surface across both asks for bottomBarSpan, so the bar runs under the gap and
-- the preview pane, and the preview pane keeps the canvas's height with the bar's height as under.
local spanning = {}
for k, v in pairs(barred) do spanning[k] = v end
spanning.bottomBarSpan = true
local spanned = geometry.resolve(screen, spanning, true)
check("a spanning bar runs from the canvas to the preview pane's right edge", spanned.bottomBar.w,
  spanned.previewPane.x + spanned.previewPane.w - spanned.canvas.x)
check("and starts at the canvas's left edge", spanned.bottomBar.x, spanned.canvas.x)
check("the preview pane keeps the canvas's height", spanned.previewPane.h, spanned.canvas.h)
check("and says the bar covers its bottom", spanned.previewPane.under, spanned.bottomBar.h)
check("a preview pane with no spanning bar has nothing under it", paned.previewPane.under == nil and 1 or 0, 1)
check("the canvas keeps its height", spanned.canvas.h, paned.canvas.h)
check("without a preview pane a spanning bar is the canvas's width",
  geometry.resolve(screen, spanning, nil).bottomBar.w, withBar.canvas.w)

if failed then os.exit(1) end
