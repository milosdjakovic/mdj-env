-- Unit case for the UI kit under Olm.spoon/lib/ui, stage one of docs/DESIGN-UI-KIT.md. The
-- runner reaches this file with a dofile call carrying an absolute path, so this file
-- locates itself through debug.getinfo and derives every module path from there, writing
-- no absolute path down.
--
-- Style and kit are checked as the plain Lua they are, with the appearance stubbed. Layout
-- is checked with a stub measurer whose widths are seven points a character, so every
-- frame below is arithmetic rather than whatever the system font measures today, and with
-- the real hs.styledtext, since the runner is Hammerspoon's own interpreter.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local uiDir = caseDir .. "/../../Spoons/Olm.spoon/lib/ui/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(name)
  local chunk, err = loadfile(uiDir .. name)
  if not chunk then error("could not load lib/ui/" .. name .. ", " .. tostring(err)) end
  return chunk()
end

local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.001 end

-- The stub measurer, seven points a character and greedy wrapping by whole characters.
local stubMeasure = {}
function stubMeasure:width(str) return #(str or "") * 7 end
function stubMeasure:wrap(str, _, _, maxW)
  local per = math.max(1, math.floor(maxW / 7))
  local lines = {}
  for i = 1, math.max(1, #str), per do lines[#lines + 1] = str:sub(i, i + per - 1) end
  return lines
end

-- theme-exempt, fixture colours for a unit case, not a tool's look
local SPEC = {
  colors = {
    dark = { foreground = { white = 0.92 }, subtext = { white = 0.55 }, background = "#29292e",
             border = "#59575C" },
    light = { foreground = { white = 0.15 }, subtext = { white = 0.42 }, background = "#cecace",
              border = "#A09F9F" },
  },
  radius = { surface = 0, badge = 5 },
}

local function styleFor(answer, spec)
  local s = fresh("style.lua").new({ appearance = function() return answer end })
  s.configure(spec or SPEC)
  return s
end

--------------------------------------------------------------------------------
-- style
--------------------------------------------------------------------------------

do
  local dark = styleFor("Dark").tokens()
  local light = styleFor("Light").tokens()
  check("style answers the dark half when the appearance is Dark",
    dark.half == "dark" and near(dark.colors.foreground.white, 0.92),
    "half " .. tostring(dark.half))
  check("style answers the light half when the appearance is not Dark",
    light.half == "light" and near(light.colors.foreground.white, 0.15),
    "half " .. tostring(light.half))
  check("a hex colour comes back as a colour table",
    near(dark.colors.background.red, 0x29 / 255) and near(dark.colors.background.blue, 0x2e / 255))
  check("surface is background until the palette step",
    near(light.colors.surface.red, light.colors.background.red))
  check("dim is subtext at the dim alpha",
    near(dark.colors.dim.white, 0.55) and near(dark.colors.dim.alpha, 0.4))
  check("selection and highlight are foreground at 0.20 and 0.14",
    near(dark.colors.selection.alpha, 0.20) and near(dark.colors.highlight.alpha, 0.14)
      and near(dark.colors.selection.white, 0.92))
  check("badge is white 1 at 0.12 on dark and white 0 at 0.06 on light",
    near(dark.colors.badge.white, 1) and near(dark.colors.badge.alpha, 0.12)
      and near(light.colors.badge.white, 0) and near(light.colors.badge.alpha, 0.06))
  check("line height is ceil of size times 1.35",
    dark.text.title.lineHeight == 27 and dark.text.body.lineHeight == 22
      and dark.text.caption.lineHeight == 19 and dark.text.section.lineHeight == 17
      and dark.text.code.lineHeight == 19)
  check("a text variant names its font, not the font token",
    dark.text.code.font == ".AppleSystemUIFontMonospaced"
      and dark.text.body.font == ".AppleSystemUIFont")
  check("caption draws in subtext", dark.text.caption.color == "subtext")
  check("a badge is its glyph's line height plus twice its vertical space",
    dark.badge.hint.height == 17 + 2 * 2 and dark.badge.cheat.height == 22 + 2 * 6
      and dark.badge.button.height == 19 + 2 * 6,
    dark.badge.hint.height .. " " .. dark.badge.cheat.height .. " " .. dark.badge.button.height)
  check("a badge pads its glyph by a space step and draws it in a role",
    dark.badge.hint.padX == 6 and dark.badge.hint.text == "section"
      and dark.badge.cheat.padX == 10 and dark.badge.cheat.text == "body"
      and dark.badge.button.padX == 14 and dark.badge.button.text == "caption")
  check("space, radius, alpha and icon carry the settled values",
    dark.space.xs == 2 and dark.space.xl == 20 and dark.radius.chip == 6
      and dark.radius.badge == 5 and dark.alpha.fade == 0.55 and dark.icon.sheet == 32)
end

do
  local onlyDark = { colors = { dark = { foreground = { white = 0.77 } } } }
  local light = styleFor("Light", onlyDark).tokens()
  check("the light half falls back to the dark spec colours when light is absent",
    light.half == "light" and near(light.colors.foreground.white, 0.77),
    "foreground white " .. tostring(light.colors.foreground and light.colors.foreground.white))
end

do
  local t = styleFor("Dark").tokens()
  t.colors.foreground.white = 0
  check("tokens are fresh on every call, a caller's change never reaches the next",
    near(styleFor("Dark").tokens().colors.foreground.white, 0.92))
end

--------------------------------------------------------------------------------
-- kit
--------------------------------------------------------------------------------

local styleLib = fresh("style.lua")
local kit = fresh("kit.lua").new(styleLib.names)

do
  local cases = {
    { "text", function() return kit.text("a", "title") end },
    { "badge", function() return kit.badge("K", "hint") end },
    { "icon", function() return kit.icon("x", "row") end },
    { "row", function() return kit.row({}) end },
    { "stack", function() return kit.stack({}) end },
    { "flow", function() return kit.flow({}) end },
    { "grid", function() return kit.grid({}, { columns = 2 }) end },
    { "divider", function() return kit.divider() end },
    { "spacer", function() return kit.spacer("m") end },
    { "surface", function() return kit.surface() end },
    { "group", function() return kit.group({}) end },
  }
  local wrong = {}
  for _, c in ipairs(cases) do
    local node = c[2]()
    if type(node) ~= "table" or node.kind ~= c[1] then wrong[#wrong + 1] = c[1] end
  end
  check("every primitive builds a node of its own kind", #wrong == 0,
    "wrong kind for " .. table.concat(wrong, " "))
end

do
  local text = kit.text("hello", "body", { color = "dim" })
  local leaked = text.font or text.size or text.textColor or type(text.color) == "table"
  check("a node holds a variant name and never a colour, font or size",
    not leaked and text.variant == "body" and text.color == "dim")
end

do
  local refusals = {
    { "text", function() kit.text("a", "titel") end, "titel" },
    { "text color", function() kit.text("a", "body", { color = "red" }) end, "red" },
    { "badge", function() kit.badge("K", "huge") end, "huge" },
    { "icon", function() kit.icon("x", "giant") end, "giant" },
    { "spacer", function() kit.spacer("xxl") end, "xxl" },
    { "row gap", function() kit.row({}, { gap = "wide" }) end, "wide" },
    { "stack gap", function() kit.stack({}, { gap = 4 }) end, "4" },
    { "flow gapX", function() kit.flow({}, { gapX = "big" }) end, "big" },
  }
  local bad = {}
  for _, r in ipairs(refusals) do
    local ok, err = pcall(r[2])
    if ok or not tostring(err):find("'" .. r[3] .. "'", 1, true) then
      bad[#bad + 1] = r[1] .. " (" .. tostring(err) .. ")"
    end
  end
  check("every primitive refuses an unknown variant with a message naming it", #bad == 0,
    table.concat(bad, "; "))
end

--------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------

local tokens = styleFor("Dark").tokens()
local layoutLib = fresh("layout.lua")
local engine = layoutLib.new({ measure = stubMeasure })
local RECT = { x = 10, y = 20, w = 300, h = 200 }

local function textOf(el) return el.text and el.text.getString and el.text:getString() end

do
  local tree = kit.stack({
    kit.text("one", "title"), kit.text("two", "body"), kit.text("three", "caption"),
  }, { gap = "s" })
  local els, height = engine.layout(tree, RECT, tokens)
  local order = {}
  for _, el in ipairs(els) do order[#order + 1] = textOf(el) or "?" end
  check("a stack of texts answers its elements in order",
    table.concat(order, ",") == "one,two,three", table.concat(order, ","))
  local want = 27 + 22 + 19 + 2 * 6
  check("a stack's height is the summed line heights and gaps", height == want,
    "got " .. tostring(height) .. ", wanted " .. want)
  check("each text sits below the last, starting at the rect",
    els[1].frame.y == 20 and els[2].frame.y == 20 + 27 + 6 and els[3].frame.y == 20 + 27 + 6 + 22 + 6
      and els[1].frame.x == 10 and els[1].frame.w == 300)
  check("text is emitted as hs.styledtext", type(els[1].text) == "userdata")
end

do
  -- Four hint badges of three characters, each 21 wide plus 12 of padding is 33, 21 high, with a
  -- gap of 6 between, in a width of 80, fit two to a line.
  local tree = kit.flow({
    kit.badge("aaa", "hint"), kit.badge("bbb", "hint"),
    kit.badge("ccc", "hint"), kit.badge("ddd", "hint"),
  }, { gapX = "s", gapY = "s" })
  local els, height = engine.layout(tree, { x = 0, y = 0, w = 80, h = 100 }, tokens)
  local chips = {}
  for _, el in ipairs(els) do
    if el.type == "rectangle" and el.action == "fill" then chips[#chips + 1] = el.frame end
  end
  check("a flow wraps at the rect width",
    #chips == 4 and chips[1].y == 0 and chips[2].y == 0 and chips[2].x == 39
      and chips[3].y == 21 + 6 and chips[3].x == 0,
    "chip frames " .. #chips)
  check("a flow's height is its lines and the gap between them", height == 21 + 6 + 21,
    "got " .. tostring(height))
end

do
  local tree = kit.group({
    kit.text("faded", "body", { color = "dim" }),
    kit.icon(hs.image.imageFromName("NSCaution"), "row"),
    kit.group({ kit.text("deeper", "body") }, { alpha = 0.5 }),
  }, { alpha = 0.5 })
  local els = engine.layout(tree, RECT, tokens)
  local textAlpha = els[1].text:asTable()[2].attributes.color.alpha
  check("a group multiplies a child text colour's alpha",
    near(textAlpha, 0.4 * 0.5), "alpha " .. tostring(textAlpha))
  check("a group multiplies a child image's alpha",
    els[2].type == "image" and near(els[2].imageAlpha, 0.5))
  local deeper = els[3].text:asTable()[2].attributes.color.alpha
  check("nested groups multiply together", near(deeper, 0.25), "alpha " .. tostring(deeper))
end

do
  local tree = kit.stack({ kit.text("a", "body"), kit.badge("K", "cheat"), kit.divider() })
  local plain = engine.layout(tree, RECT, tokens)
  local scrolled, height = engine.layout(tree, RECT, tokens, { scrollY = 15 })
  local clips, resets, firstClip, lastReset = 0, 0, nil, nil
  local inner = {}
  for i, el in ipairs(scrolled) do
    if el.action == "clip" then clips = clips + 1; firstClip = firstClip or i
    elseif el.type == "resetClip" then resets = resets + 1; lastReset = i
    else inner[#inner + 1] = el end
  end
  check("scrollY opens the clip exactly once and closes it exactly once",
    clips == 1 and resets == 1 and firstClip == 1 and lastReset == #scrolled)
  local shifted = #inner == #plain
  for i, el in ipairs(inner) do
    if el.frame.y ~= plain[i].frame.y - 15 then shifted = false end
  end
  check("scrollY offsets every element", shifted)
  check("the clip covers the rect", scrolled[1].frame.x == 10 and scrolled[1].frame.h == 200)
  check("the content height is answered before scrolling", height == 22 + 34 + 1,
    "got " .. tostring(height))
  local noClip = true
  for _, el in ipairs(plain) do
    if el.action == "clip" or el.type == "resetClip" then noClip = false end
  end
  check("no scroll and no clip asked for means no clip", noClip)
end

do
  local tree = kit.stack({
    kit.group({ kit.text("click", "body"), kit.badge("K", "hint") }, { id = "go" }),
    kit.text("inert", "body"),
  })
  local els = engine.layout(tree, RECT, tokens)
  local tracked, untracked = 0, 0
  for _, el in ipairs(els) do
    if el.id == "go" and el.trackMouseUp == true then tracked = tracked + 1
    elseif el.id == nil and not el.trackMouseUp then untracked = untracked + 1 end
  end
  check("an id reaches trackMouseUp on every element inside its group",
    tracked == 3 and untracked == 1, "tracked " .. tracked .. ", untracked " .. untracked)
end

do
  local tree = kit.row({ kit.text("label", "caption"), kit.text("value", "body") }, { gap = "m" })
  local els, height = engine.layout(tree, RECT, tokens)
  check("a row places its children left to right and the last takes the remaining width",
    els[1].frame.x == 10 and els[1].frame.w == 35 and els[2].frame.x == 10 + 35 + 10
      and els[2].frame.w == 300 - 35 - 10)
  check("a row's height is its tallest child", height == 22, "got " .. tostring(height))
end

do
  local tree = kit.grid({
    kit.text("a", "body"), kit.text("b", "body"), kit.text("c", "body"),
  }, { columns = 2, gapX = "m" })
  local els, height = engine.layout(tree, { x = 0, y = 0, w = 210, h = 100 }, tokens)
  check("a grid places cells in columns and wraps to the next row",
    els[2].frame.x == 110 and els[2].frame.y == 0 and els[3].frame.x == 0 and els[3].frame.y == 22)
  check("a grid's height is its rows", height == 44, "got " .. tostring(height))
end

do
  local painted = {}
  local withSurface = layoutLib.new({ measure = stubMeasure, surfaceElements = function(w, h)
    painted[#painted + 1] = { w = w, h = h }
    return { { type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = w, h = h } } }
  end })
  local tree = kit.stack({ kit.surface(), kit.text("a", "body") }, { gap = "xl" })
  local els, height = withSurface.layout(tree, RECT, tokens, { scrollY = 5 })
  check("a surface paints the whole rect once, behind and outside the clip",
    #painted == 1 and painted[1].w == 300 and els[1].frame.x == 10 and els[1].frame.y == 20
      and els[2].action == "clip")
  check("a surface takes no room and no gap", height == 22 and els[3].frame.y == 15,
    "height " .. tostring(height))
end

do
  local tree = kit.text(string.rep("x", 10), "body", { wrap = true })
  local _, height = engine.layout(tree, { x = 0, y = 0, w = 35, h = 100 }, tokens)
  check("a wrapped text is as tall as its lines", height == 2 * 22, "got " .. tostring(height))
end

--------------------------------------------------------------------------------
-- measure and the joined table
--------------------------------------------------------------------------------

do
  local m = fresh("measure.lua").new()
  local w1 = m:width("hello", ".AppleSystemUIFont", 14)
  local w2 = m:width("hello", ".AppleSystemUIFont", 14)
  local wide = m:width("hello", ".AppleSystemUIFont", 20)
  check("measure answers a positive width, the same twice, wider at a larger size",
    w1 > 0 and w1 == w2 and wide > w1)
  local lines = m:wrap("one two three four five six", ".AppleSystemUIFont", 14, 60)
  check("measure wraps to more than one line in a narrow width", #lines > 1, #lines .. " lines")
end

do
  local ui = fresh("init.lua")
  ui.configure({ spec = SPEC })
  local wanted = { "text", "badge", "icon", "row", "stack", "flow", "grid", "divider",
                   "spacer", "surface", "group", "layout", "tokens", "configure", "iconImage" }
  local missing = {}
  for _, name in ipairs(wanted) do
    if type(ui[name]) ~= "function" then missing[#missing + 1] = name end
  end
  check("the joined table carries every primitive, layout, tokens and configure", #missing == 0,
    "missing " .. table.concat(missing, " "))
  check("the joined table carries the measurer", type(ui.measure) == "table"
    and type(ui.measure.width) == "function")
  local els, height = ui.layout(ui.stack({ ui.text("a", "section") }), RECT)
  check("ui.layout lays out with the current tokens", #els == 1 and height == 17)
  local a = ui.iconImage("🔥", "row")
  check("a glyph icon is an image, cached by glyph and size",
    type(a) == "userdata" and rawequal(a, ui.iconImage("🔥", "row"))
      and not rawequal(a, ui.iconImage("🔥", "sheet")))
end

--------------------------------------------------------------------------------
-- code, the visible slice and raw
--------------------------------------------------------------------------------

do
  local clh = tokens.text.code.lineHeight
  local plh = tokens.text.caption.lineHeight
  local R = { x = 10, y = 20, w = 300, h = 200 }

  local els, height = engine.layout(kit.code({ "  indented", "a\tb", "plain" }), R, tokens)
  check("code keeps leading spaces and expands a tab to the next four columns",
    #els == 3 and textOf(els[1]) == "  indented" and textOf(els[2]) == "a   b",
    tostring(textOf(els[1])) .. " | " .. tostring(textOf(els[2])))
  check("code is one element per line at the code line height",
    els[2].frame.y == 20 + clh and height == 3 * clh)

  local long = engine.layout(kit.code({ string.rep("x", 200) }), { x = 0, y = 0, w = 70, h = 100 }, tokens)
  check("code truncates a long line rather than wrapping it",
    #long == 1 and long[1].frame.w == 70 and long[1].frame.h == clh)

  local lines = {}
  for i = 1, 10 do lines[i] = "line " .. i end
  local cutEls, cutH = engine.layout(kit.code(lines, { maxHeight = 4 * clh + 1 }), R, tokens)
  check("code cuts with a closing line saying how many more",
    #cutEls == 4 and textOf(cutEls[4]) == "7 more lines" and textOf(cutEls[3]) == "line 3",
    tostring(#cutEls) .. " " .. tostring(textOf(cutEls[#cutEls])))
  check("a cut block's height is the drawn height",
    cutH == 3 * clh + plh, tostring(cutH))
  local _, whole = engine.layout(kit.code(lines, { maxHeight = 100 * clh }), R, tokens)
  check("a block that fits has the full height and no closing line", whole == 10 * clh)
  local custom = engine.layout(kit.code(lines, { maxHeight = 3 * clh,
    more = function(n) return n .. " left" end }), R, tokens)
  check("more words the closing line from the count", textOf(custom[#custom]) == "8 left")

  local many = {}
  for i = 1, 100 do many[i] = "row " .. i end
  local sliced, fullH = engine.layout(kit.code(many), { x = 0, y = 0, w = 300, h = 5 * clh }, tokens,
    { scrollY = 40 * clh })
  local texts = {}
  for _, el in ipairs(sliced) do if el.text then texts[#texts + 1] = textOf(el) end end
  check("the visible slice emits only the visible lines", #texts == 5 and texts[1] == "row 41"
    and texts[5] == "row 45", table.concat(texts, ","))
  check("the visible slice still answers the full height", fullH == 100 * clh)
  check("the slice keeps the clip balanced", sliced[1].action == "clip"
    and sliced[#sliced].type == "resetClip")
  local unsliced = engine.layout(kit.code(many), { x = 0, y = 0, w = 300, h = 5 * clh }, tokens)
  check("with no scroll every line is emitted", #unsliced == 100)

  local seen
  local tree = kit.stack({
    kit.text("above", "body"),
    kit.raw(50, function(rect, t)
      seen = { rect = rect, tokens = t }
      return { { type = "rectangle", action = "fill", fillColor = t.colors.border, frame = rect },
               { type = "rectangle", action = "stroke", frame = rect } }
    end),
    kit.text("below", "body"),
  })
  local rawEls, rawH = engine.layout(tree, R, tokens, { scrollY = 5 })
  local blh = tokens.text.body.lineHeight
  check("raw reserves its height", rawH == 2 * blh + 50, tostring(rawH))
  check("raw receives the scrolled absolute rect and the tokens",
    seen.rect.x == 10 and seen.rect.y == 20 - 5 + blh and seen.rect.w == 300 and seen.rect.h == 50
      and rawequal(seen.tokens, tokens))
  check("raw elements are inserted at its position in order",
    textOf(rawEls[2]) == "above" and rawEls[3].action == "fill" and rawEls[4].action == "stroke"
      and textOf(rawEls[5]) == "below")
  check("raw refuses a non number height", not pcall(kit.raw, "tall", function() end))
end

--------------------------------------------------------------------------------
-- text centred in its line band
--------------------------------------------------------------------------------

do
  -- A measurer that also answers metrics, cap 10 and descender minus 4 whatever the font, so
  -- the shift is arithmetic. For the body line height of 22 it is (10 + 2 * 4 - 22) / 2 plus
  -- the quarter point bias, which is minus 2 plus 0.25, minus 1.75.
  local withMetrics = setmetatable({}, { __index = stubMeasure })
  function withMetrics:metrics() return { ascender = 16, descender = -4, capHeight = 10 } end
  local metricEngine = layoutLib.new({ measure = withMetrics })
  local els = metricEngine.layout(kit.text("a", "body"), RECT, tokens)
  check("a text frame moves up so the cap height is centred in its line band",
    near(els[1].frame.y, 20 - 1.75), "frame y " .. tostring(els[1].frame.y)
      .. ", wanted " .. (20 - 1.75))
  check("the frame keeps the line height and the rect width",
    els[1].frame.h == 22 and els[1].frame.w == 300)
  local plain = engine.layout(kit.text("a", "body"), RECT, tokens)
  check("a measurer with no metrics moves nothing", plain[1].frame.y == 20)

  local chip = metricEngine.layout(kit.badge("K", "cheat"), RECT, tokens)
  -- The chip is 34 high and its glyph box 22, so the box starts 6 down, then the shift.
  check("a badge glyph is centred in the chip, then by the same cap height rule",
    near(chip[2].frame.y, 20 + 6 - 1.75), "frame y " .. tostring(chip[2].frame.y))
end
