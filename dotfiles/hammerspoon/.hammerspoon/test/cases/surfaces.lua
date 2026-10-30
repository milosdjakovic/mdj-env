-- Unit case for the shared surfaces that moved onto the five type roles, the empty pane
-- state, the default chooser's action bar and its popovers, the three toasts and the cheat sheet. They draw through the real kit
-- and the real measurer, since the runner is Hammerspoon's own interpreter, and every
-- assertion is on a height or a geometry that is arithmetic from the role line heights, so
-- the assertion text carries the sum. At the shipped sizes the line heights are title 27,
-- body 22, caption 19, section 19 and code 19, and the space steps are xs 2, s 6, sm 8, m 10.
--
-- The old parity probes for these surfaces claimed the look had not changed, which stopped
-- being true on purpose, so this case replaces them with what the new look derives.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoonDir = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(rel)
  local chunk, err = loadfile(spoonDir .. rel)
  if not chunk then error("could not load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

-- theme-exempt, fixture colours for a unit case, not a tool's look
local SPEC = {
  colors = {
    dark = { foreground = { white = 0.92 }, subtext = { white = 0.55 }, overlay = { white = 0.4 },
             background = "#29292e", border = "#59575C" },
  },
  radius = { surface = 0, badge = 5 },
}

local ui = fresh("lib/ui/init.lua")
ui.configure({ spec = SPEC })
-- The runner may be on the light half, which falls back to the dark colours, so every
-- colour assertion below reads the tokens rather than a literal.
local T = ui.tokens()

local function fakePanel()
  local fake = { placements = { below = "below", above = "above", left = "left", right = "right",
                                center = "center" } }
  function fake.new(cfg)
    fake.content = cfg.content
    fake.config = cfg
    return { arm = function() end, poke = function() end, hide = function() end,
             show = function() end, isShowing = function() return false end }
  end
  return fake
end

local function frames(els, pick)
  local out = {}
  for _, el in ipairs(els) do
    if pick(el) then out[#out + 1] = el.frame end
  end
  return out
end

local function chips(els)
  return frames(els, function(el) return el.type == "rectangle" and el.action == "fill" end)
end

--------------------------------------------------------------------------------
-- empty pane state, the caption role
--------------------------------------------------------------------------------

do
  local panel = fresh("lib/panel.lua")
  panel.configure({ ui = ui })
  local els = panel.emptyStateElements(300, 200)
  local want = T.text.caption.lineHeight
  check("the empty state is one text of the caption line height, 19",
    #els == 1 and els[1].frame.h == want, "height " .. tostring(els[1] and els[1].frame.h))
  local attrs = els[1].text:asTable()[2].attributes
  check("the empty state is in the caption size, 14, and the subtext colour by default",
    attrs.font.size == T.text.caption.size
      and math.abs(attrs.color.red - T.colors.subtext.white) < 0.01,
    tostring(attrs.font.size))
  local mine = { white = 0.1, alpha = 1 }
  local tinted = panel.emptyStateElements(300, 200, { color = mine, size = 30 })
  local a2 = tinted[1].text:asTable()[2].attributes
  check("a caller colour wins and a caller size is ignored, there is no size override",
    math.abs(a2.color.red - 0.1) < 0.01 and a2.font.size == T.text.caption.size)
end

--------------------------------------------------------------------------------
-- action bar, the default chooser's two floating groups and the popovers above them
--------------------------------------------------------------------------------

do
  local footer = fresh("lib/chooser/providers/default/footer.lua")
  local bar = fresh("lib/chooser/providers/default/bar.lua")
  local popover = fresh("lib/chooser/providers/default/popover.lua")
  local chipH = T.badge.hint.height
  local barH = footer.height(T)
  local captionH = T.text.caption.lineHeight
  check("the action bar is its row, the taller of the hint chip 23 and the caption line 19, with the small space above and below, 35",
    chipH == 23 and captionH == 19 and barH == math.max(chipH, captionH) + 2 * T.space.s and barH == 35,
    "height " .. tostring(barH))

  local model = {
    right = {
      { label = "Choose Files", chord = "\u{21A9}", action = "choose" },
      { label = "Uninstall", chord = "\u{2318}\u{21A9}", action = "secondary" },
      { label = "Actions", chord = "Hyper O", action = "actions" },
    },
    keys = {
      { badges = { "Hyper J", "\u{2193}" }, label = "Move down" },
      { badges = { "\u{232B}" }, label = "Back" },
      { badges = { "\u{2318}1", "\u{2318}9" }, label = "Choose a visible row" },
    },
    keysChord = "\u{2318}?",
  }
  -- The footer rect a spanning view is handed, the group's height and the bar pad below it.
  local rect = { x = 0, y = 500, w = 900, h = barH + T.pad }
  local img = hs.image.imageFromName("NSComputer")
  local els, hits = bar.elements(ui, T, model, rect, { radius = 4, keysImage = img })
  check("the keys group stands the bar pad in from the left at the top of the footer rect, as tall as the bar",
    hits.keys and hits.keys.x == rect.x + T.pad and hits.keys.y == rect.y and hits.keys.h == barH,
    hits.keys and string.format("%s,%s h%s", hits.keys.x, hits.keys.y, hits.keys.h) or "no rect")
  check("the actions group stands the bar pad in from the right",
    hits.actions and math.abs(hits.actions.x + hits.actions.w - (rect.x + rect.w - T.pad)) <= 1,
    hits.actions and tostring(hits.actions.x + hits.actions.w) or "no rect")
  check("each entry on the right is one hit naming its action",
    #hits.entries == 3 and hits.entries[2].action == "secondary", "entries " .. #hits.entries)
  local pictures = frames(els, function(el) return el.type == "image" end)
  check("the keys group draws its icon at the hint icon size, the section line 19",
    #pictures == 1 and pictures[1].h == T.icon.hint and T.icon.hint == 19, "pictures " .. #pictures)
  -- The body role, measured by the real measurer, since the runner is Hammerspoon's own.
  local labels = frames(els, function(el)
    if el.type ~= "text" then return false end
    local run = el.text.asTable and el.text:asTable()[2]
    local size = run and run.attributes.font.size or el.textSize
    local str = el.text.getString and el.text:getString() or el.text
    return size == T.text.body.size and str == "Uninstall"
  end)
  check("the groups' words are the body role, as swift's are", #labels == 1, "body labels " .. #labels)
  local fills = frames(els, function(el)
    return el.type == "rectangle" and el.action == "fill" and el.fillColor
      and el.fillColor.red == T.colors.background.red and el.fillColor.blue == T.colors.background.blue
  end)
  check("both groups are filled in the background colour role", #fills == 2, "fills " .. #fills)

  local style = popover.style(ui, T, 13, barH)
  local lines = {}
  for i, k in ipairs(model.keys) do lines[i] = { label = k.label, chord = table.concat(k.badges, " ") } end
  local pop = popover.layout(ui, style, "Keys", lines, false)
  local placed = popover.place(pop, hits.keys, "left", { w = rect.w, top = 60 })
  check("the key panel stands the outer padding above the keys group, its left edge on it",
    placed.x == hits.keys.x and placed.y + placed.h == hits.keys.y - T.pad,
    string.format("%s,%s %sx%s", placed.x, placed.y, placed.w, placed.h))
  local low = popover.place(pop, hits.keys, "left", { w = rect.w, top = hits.keys.y - T.pad - 30 })
  check("and never rises above the list's top", low.h == 30, "height " .. tostring(low.h))
  local acts = popover.layout(ui, style, "Actions", { { label = "Open" }, { label = "Reveal" } }, true)
  local right = popover.place(acts, hits.actions, "right", { w = rect.w, top = 60 })
  check("the action panel's right edge sits on the actions group's",
    right.x + right.w == hits.actions.x + hits.actions.w, tostring(right.x + right.w))
end

--------------------------------------------------------------------------------
-- toasts
--------------------------------------------------------------------------------

do
  local hints = fresh("lib/hints.lua")
  local toast = hints.toast({ ui = ui })

  local message = toast.message({ text = "Appended to the clipboard entry" })
  check("the message toast is one title line high, 27",
    message.preferredSize().h == T.text.title.lineHeight and message.preferredSize().h == 27)

  local color = toast.color({ hex = "#3a7bd5", color = { red = 0.2, green = 0.4, blue = 0.8, alpha = 1 } })
  local cs = color.preferredSize()
  check("the colour toast is the swatch 26 high, taller than the 19 high code line",
    cs.h == T.icon.swatch and cs.h == 26 and T.text.code.lineHeight == 19, "height " .. tostring(cs.h))
  local cdraw = color.draw(cs.w, cs.h)
  -- The swatch is a fill and an outline drawn inside it, inset by half the border width.
  local bw = T.stroke.border
  check("the swatch outline is the border width, inset by half of it inside the fill",
    cdraw[2].action == "stroke" and cdraw[2].strokeWidth == bw and cdraw[2].frame.x == bw / 2
      and cdraw[2].frame.w == T.icon.swatch - bw)
  local hex = cdraw[3].text:asTable()[2].attributes
  check("the hex value is drawn in the code font at the code size, 14",
    hex.font.size == T.text.code.size and cdraw[3].frame.h == 19)

  local icon = hs.image.imageFromName("NSCaution")
  local list = toast.list({ title = "Not open", secondsLeft = 4, rows = {
    { icon = icon, label = "Google Chrome", detail = "not running" },
    { label = "Terminal", detail = "skipped", dim = true },
  } }, function() end)
  local size = list.preferredSize()
  -- Title band 27 plus 10, a row the 32 icon plus 2 times 6, a footer the 31 chip plus 2 times 6.
  local titleH = 27 + 10
  local rowH = 32 + 2 * 6
  local footerH = (19 + 2 * 6) + 2 * 6
  check("the report toast is title band 37, two rows of 44 and a footer of 43, 168",
    size.h == titleH + 2 * rowH + footerH and size.h == 168, "height " .. tostring(size.h))
  local els = list.draw(size.w, size.h)
  local dismiss = frames(els, function(el) return el.id == "dismiss" and el.type == "rectangle" end)
  check("the Dismiss chip is a caption line 19 plus 2 times 6, 31 high, centred in the 43 footer",
    #dismiss == 1 and dismiss[1].h == 31 and dismiss[1].y == size.h - footerH + (footerH - 31) / 2,
    dismiss[1] and tostring(dismiss[1].y))
  local sizes = {}
  for _, el in ipairs(els) do
    if el.text then sizes[#sizes + 1] = el.text:asTable()[2].attributes.font.size end
  end
  check("the heading is title 20, the labels body 16, the details caption 14 and the chip caption 14",
    sizes[1] == 20 and sizes[2] == 16 and sizes[3] == 14 and sizes[#sizes] == 14,
    table.concat(sizes, ","))
end

--------------------------------------------------------------------------------
-- cheat sheet
--------------------------------------------------------------------------------

do
  local function sheet()
    local obj = fresh("lib/cheatsheet.lua")
    obj:init()
    obj:configure({ ui = ui, padding = 20, canvasPanel = fakePanel() })
    return obj
  end
  local rows = { { badge = "A", label = "Alpha" }, { badge = "B", label = "Beta" },
                 { badge = "C", label = "Gamma" } }
  local obj = sheet()
  obj._model = { sections = { { title = "KEYS", rows = rows } } }
  local built = obj:_build()
  -- Badge 22 plus 2 times 6 is 34, a row is the badge plus the medium space 10, 44, and a
  -- title band is the section line 19 plus 10, 29. Three rows in two columns are two rows.
  -- The content box is trimmed to its ink, so the padding is the same on every side, the
  -- title's leading above its capitals at the top and the last row's half spacing at the bottom.
  local sec = ui.tokens().text.section
  local topTrim = (sec.lineHeight - ui.measure:metrics(sec.font, sec.size).capHeight) / 2
  local function near(a, b) return math.abs(a - b) < 0.001 end
  check("the badge is 34, a row 44 and the title band 29, so a titled three row sheet is 29 plus 88 trimmed to its ink",
    near(built.h, 29 + 2 * 44 - topTrim - (44 - 34) / 2), "height " .. tostring(built.h))
  check("the width is the two default columns, 500", built.w == 500, "width " .. tostring(built.w))
  local boxes = chips(built.els)
  check("every key badge is the derived 34 high and square, 34 wide",
    #boxes == 3 and boxes[1].h == 34 and boxes[1].w == 34, boxes[1] and boxes[1].h .. "x" .. boxes[1].w)

  local sizes = {}
  for _, el in ipairs(built.els) do
    if el.text then sizes[#sizes + 1] = el.text:asTable()[2].attributes.font.size end
  end
  check("the section title is 14 and every label and key glyph is body 16",
    sizes[1] == 14 and sizes[2] == 16 and sizes[3] == 16, table.concat(sizes, ","))

  local over = sheet()
  over._model = { rowHeight = 60, badgeHeight = 40, badgeWidth = 50, titleHeight = 30,
    sections = { { title = "KEYS", rows = rows } } }
  local ob = over:_build()
  check("a model may still override the row, badge and title heights, 30 plus 2 times 60",
    near(ob.h, 30 + 2 * 60 - topTrim - (60 - 40) / 2) and chips(ob.els)[1].h == 40 and chips(ob.els)[1].w == 50,
    "height " .. tostring(ob.h))

  local sectionOverride = sheet()
  sectionOverride._model = { sections = { { title = "KEYS", rows = rows, rowHeight = 50 } } }
  check("a section may override a height for its own rows, 29 plus 2 times 50",
    near(sectionOverride:_build().h, 29 + 2 * 50 - topTrim - (50 - 34) / 2))

  local alt = sheet()
  alt._model = { sections = { { rows = { { badges = { "H", "←" }, label = "Left" } } } } }
  local ab = alt:_build()
  local altSizes = {}
  for _, el in ipairs(ab.els) do
    if el.text then altSizes[#altSizes + 1] = el.text:asTable()[2].attributes.font.size end
  end
  check("a content sized row draws its separator word in caption 14 between body 16 glyphs",
    altSizes[1] == 16 and altSizes[2] == 14 and altSizes[3] == 16 and altSizes[4] == 16,
    table.concat(altSizes, ","))
end
