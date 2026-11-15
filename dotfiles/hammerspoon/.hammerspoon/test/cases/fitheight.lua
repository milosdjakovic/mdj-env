-- Unit case for a list as tall as its rows, docs/DESIGN-FIT-HEIGHT.md in Olm.spoon, decided by
-- Milos on 2026-11-15. The real check in lib/registrar.lua, which takes fit as a real boolean,
-- refuses rowCount by name and refuses fit beside a preview pane, and the real geometry, which
-- keeps the top edge and cuts the window at the rows. The rectangles themselves are pinned in
-- test/fixtures/chooser/geometry.json for both ports. The runner reaches this file with a dofile
-- call carrying an absolute path, so this file locates itself through debug.getinfo.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olmDir = caseDir .. "/../../Spoons/Olm.spoon/"

local function load(path)
  local chunk, err = loadfile(olmDir .. path)
  if not chunk then
    print("FAIL load Olm.spoon/" .. path .. ", " .. tostring(err))
    return nil
  end
  return chunk()
end
local registrar = load("lib/registrar.lua")
local geometry = load("lib/chooser/providers/default/geometry.lua")
if not registrar or not geometry then return end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local module = { rows = function() return {} end, select = function() end, count = function() return 3 end }
local function validate(fields)
  local p = {
    rows = { member = "rows", call = "method" },
    select = { member = "select", call = "method" },
  }
  for k, v in pairs(fields) do p[k] = v end
  local logged = {}
  local out = registrar.validatePresentation("demo", "demo", { presentation = p }, { demo = module },
    { log = function(_, line) logged[#logged + 1] = line end })
  return out, table.concat(logged, "; ")
end

local out, logged = validate({ fit = true })
check("fit = true is carried through", out.fit == true and logged == "", logged)
out, logged = validate({})
check("a presentation declaring no fit carries none", out.rows ~= nil and out.fit == nil, logged)
for label, bad in pairs({ ["a number"] = 1, ["a string"] = "yes" }) do
  out, logged = validate({ fit = bad })
  check("fit given as " .. label .. " is refused with a line naming it",
    out.rows == nil and logged:find("fit", 1, true) ~= nil, logged)
end
for label, old in pairs({ ["a number"] = 1, ["a member"] = { member = "count", call = "method" } }) do
  out, logged = validate({ rowCount = old })
  check("rowCount given as " .. label .. " is refused by name, a height is never a plugin's",
    out.rows == nil and logged:find("rowCount is retired", 1, true) ~= nil, logged)
end
out, logged = validate({ fit = true, previewPaneWidth = 320 })
check("fit beside a preview pane is refused", out.rows == nil and logged:find("preview pane", 1, true) ~= nil, logged)

-- The top edge is the full height's, so the field stays where it is and only the bottom moves.
local screen = { x = 0, y = 25, w = 1512, h = 957 }
local full = geometry.resolve(screen, nil, nil)
local one = geometry.resolve(screen, nil, nil, 1)
local many = geometry.resolve(screen, nil, nil, 500)
check("a list of one row keeps the full height's top edge", one.canvas.y == full.canvas.y and one.field.y == full.field.y)
check("and is shorter than the full height", one.canvas.h < full.canvas.h and one.rowCount == 1 and one.viewRows == 1)
check("a list past what the screen holds is the full height", many.canvas.h == full.canvas.h and many.rowCount == full.rowCount)
