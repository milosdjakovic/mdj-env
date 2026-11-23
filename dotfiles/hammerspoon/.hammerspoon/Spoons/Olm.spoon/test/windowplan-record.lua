-- Records test/fixtures/windows/plan.json from plugins/windowmanager/plan.lua, step 6.3 of
-- docs/PLAN-STANDALONE.md, the way test/repeattiming.lua records the chord engine's timing. Each
-- case is a window action over a window, its screen, every screen and the settings, and what the Lua
-- answers is written as its expect, so Olm.app's WindowPlan.swift is checked against the very
-- geometry Hammerspoon places windows with. Rerun after a change to plan.lua made on purpose, and
-- read every changed case before committing it.
--
-- "$OLM_LUA" test/windowplan-record.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local Plan = assert(loadfile(here .. "../plugins/windowmanager/plan.lua"))()

local SIZING = {
  maxWidth = 2400, maxHeight = 1350, fullHeightMaxWidth = 2400,
  movePixels = 20, movePixelsHeld = 40, resizePixels = 30, resizePixelsHeld = 50,
  holdGrace = 1, minWidth = 400, minHeight = 300,
  screenRecording = { width = 2400, height = 1350 }, smallSize = { width = 700, height = 800 },
}
-- The built in panel under its menu bar, an ultrawide to its right set higher, and a portrait
-- screen to its left.
local LAPTOP = { uuid = "LAPTOP", frame = { x = 0, y = 33, w = 1512, h = 949 } }
local WIDE = { uuid = "WIDE", frame = { x = 1512, y = -400, w = 3440, h = 1415 } }
local TALL = { uuid = "TALL", frame = { x = -1080, y = -500, w = 1080, h = 1895 } }

local function margins(g) return { top = g, right = g, bottom = g, left = g } end

local function input(over)
  local s = { window = { x = 100, y = 120, w = 800, h = 600 }, id = 7, screen = "LAPTOP",
    screens = { LAPTOP }, margins = margins(0), gap = 0, sizing = SIZING }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

local cases = {}
local function case(name, action, over)
  cases[#cases + 1] = { name = name, action = action, input = input(over) }
end

for _, a in ipairs({ "maximize", "center", "fullHeight", "fullHeightReasonableWidth", "reasonableSize",
  "leftHalf", "rightHalf", "smallSize" }) do
  case(a .. " on the laptop", a)
  case(a .. " with a gap of 12", a, { margins = margins(12), gap = 12 })
  case(a .. " on the ultrawide", a, { screen = "WIDE", screens = { LAPTOP, WIDE },
    window = { x = 2000, y = -300, w = 1200, h = 900 } })
end
case("no window does nothing", "maximize", { window = false })
case("a screen not among the screens does nothing", "maximize", { screen = "GONE" })
case("an unknown action does nothing", "spin")

for _, a in ipairs({ "moveLeft", "moveRight", "moveUp", "moveDown" }) do
  case(a .. " pressed", a, { depth = 0 })
  case(a .. " held", a, { depth = 3 })
  case(a .. " stops at the canvas", a, { window = { x = 5, y = 40, w = 1500, h = 930 }, depth = 3 })
  case(a .. " with a window wider than the canvas", a, { window = { x = -50, y = 10, w = 1700, h = 1000 } })
end

case("increase pressed", "increaseSize", { depth = 0 })
case("increase held", "increaseSize", { depth = 2 })
case("increase against the left edge", "increaseSize", { window = { x = 0, y = 300, w = 800, h = 400 } })
case("increase against the top edge", "increaseSize", { window = { x = 300, y = 33, w = 800, h = 400 } })
case("increase on the ultrawide grows in its shape", "increaseSize", { screen = "WIDE", screens = { LAPTOP, WIDE },
  window = { x = 2000, y = -300, w = 1200, h = 900 }, depth = 2 })
case("increase on a portrait screen", "increaseSize", { screen = "TALL", screens = { TALL, LAPTOP },
  window = { x = -900, y = -200, w = 700, h = 900 } })
case("decrease pressed", "decreaseSize", { depth = 0 })
case("decrease held", "decreaseSize", { depth = 5 })
case("decrease near the floor takes what is left", "decreaseSize", { window = { x = 100, y = 120, w = 410, h = 320 } })
case("decrease at the floor does nothing", "decreaseSize", { window = { x = 100, y = 120, w = 400, h = 300 } })
case("decrease at the floor in height only", "decreaseSize", { window = { x = 100, y = 120, w = 900, h = 300 } })
case("a window outside the canvas grows without inverting", "increaseSize",
  { window = { x = -20, y = 0, w = 800, h = 600 } })

case("exact size", "exactSize", { size = { width = 1000, height = 700 } })
case("exact size trimmed to the screen", "exactSize", { size = { width = 3000, height = 2000 } })
case("exact size given no size does nothing", "exactSize")
case("exact size given words does nothing", "exactSize", { size = { width = "wide", height = 700 } })

local two = { LAPTOP, WIDE }
local three = { TALL, LAPTOP, WIDE }
case("next display keeps the size and the place", "nextDisplay", { screens = two })
case("previous display wraps", "previousDisplay", { screens = two })
case("next display wraps past the last", "nextDisplay", { screens = three, screen = "WIDE",
  window = { x = 3000, y = 0, w = 1400, h = 1000 } })
case("previous display from the first wraps to the last", "previousDisplay", { screens = three, screen = "TALL",
  window = { x = -1000, y = 0, w = 900, h = 1200 } })
case("a window too large for the target is trimmed to its canvas", "previousDisplay", { screens = two, screen = "WIDE",
  window = { x = 1600, y = -350, w = 3000, h = 1300 } })
case("one screen places the window back inside its canvas", "nextDisplay",
  { window = { x = 1300, y = 800, w = 800, h = 600 } })
case("a remembered frame that fits is used", "nextDisplay", { screens = two,
  memory = { WIDE = { x = 2100.4, y = -200, w = 2400, h = 1200 } } })
case("a remembered frame off the canvas is not", "nextDisplay", { screens = two,
  memory = { WIDE = { x = 5000, y = -200, w = 2400, h = 1200 } } })
case("a window with no id remembers nothing and is not remembered", "nextDisplay", { screens = two, id = false,
  memory = { WIDE = { x = 2100, y = -200, w = 2400, h = 1200 } } })
case("to a screen by uuid", "toScreen", { screens = three, target = "TALL" })
case("to a screen not among the screens does nothing", "toScreen", { screens = two, target = "GONE" })
case("screen recording on the second screen", "screenRecording", { screens = two })
case("screen recording on one screen", "screenRecording")

-- false above stands for a field left out, since a Lua table cannot hold nil.
for _, c in ipairs(cases) do
  for k, v in pairs(c.input) do if v == false then c.input[k] = nil end end
  c.expect = Plan.plan(c.action, c.input) or false
end

-- A JSON writer for these shapes, objects with sorted keys, so a recording diffs line by line.
local function encode(v, indent)
  indent = indent or ""
  local t = type(v)
  if v == false and indent ~= "" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  if #v > 0 or next(v) == nil then
    local parts = {}
    for _, x in ipairs(v) do parts[#parts + 1] = encode(x, indent) end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '": ' .. encode(v[k], indent .. "  ") end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local lines = {}
for i, c in ipairs(cases) do
  lines[i] = '    { "name": ' .. encode(c.name) .. ', "action": ' .. encode(c.action) ..
    ',\n      "input": ' .. encode(c.input, "  ") .. ',\n      "expect": ' .. (c.expect and encode(c.expect, "  ") or "null") .. ' }'
end
local out = '{\n  "kind": "windows.plan",\n  "about": "Where each window action puts the focused window, recorded from plugins/windowmanager/plan.lua by test/windowplan-record.lua, step 6.3. expect null means the action does nothing.",\n  "cases": [\n' ..
  table.concat(lines, ",\n") .. '\n  ]\n}\n'
local f = assert(io.open(here .. "fixtures/windows/plan.json", "wb"))
f:write(out)
f:close()
print("windowplan, recorded " .. #cases .. " case(s)")
