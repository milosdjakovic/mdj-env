-- Unit case for the shared surfaces that moved onto the five type roles, the empty pane
-- state, the default chooser's action bar, the three toasts and the cheat sheet. They draw through the real kit
-- and the real measurer, since the runner is Hammerspoon's own interpreter, and every
-- assertion is on a height or a geometry that is arithmetic from the role line heights, so
-- the assertion text carries the sum. At the shipped sizes the line heights are title 27,
-- body 22, caption 19, section 17 and code 19, and the space steps are xs 2, s 6, sm 8, m 10.
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
-- action bar, the default chooser's footer row and the key panel above it
--------------------------------------------------------------------------------

do
  local footer = fresh("lib/chooser/providers/default/footer.lua")
  local chipH = T.badge.hint.height
  local barH = footer.height(T)
  check("the action bar is a hint chip with the small space above and below, 21 plus twice 6 is 33",
    chipH == 21 and barH == chipH + 2 * T.space.s and barH == 33, "height " .. tostring(barH))

  local model = {
    right = {
      { label = "Choose Files", chord = "\u{21A9}" },
      { label = "Uninstall", chord = "\u{2318}\u{21A9}" },
      { label = "Actions", chord = "Hyper O" },
    },
    keys = {
      { badges = { "Hyper J", "\u{2193}" }, label = "Move down" },
      { badges = { "\u{232B}" }, label = "Back" },
      { badges = { "\u{2318}1", "\u{2318}9" }, label = "Choose a visible row" },
    },
  }
  local inset = 13
  local band = { x = 1, y = 400, w = 478, h = barH }
  local els, keysRect = footer.bar(ui, T, model, band, inset, true)
  local function chipsOf(list)
    return frames(list, function(el)
      return el.type == "rectangle" and el.action == "fill" and el.frame.h == chipH
    end)
  end
  local boxes = chipsOf(els)
  check("lit, the button's highlight and its ? chip, and one chip for each entry on the right",
    #boxes == 2 + #model.right, "chips " .. #boxes)
  local restEls, restRect = footer.bar(ui, T, model, band, inset, false)
  check("at rest the key button draws its glyph and no chip, the state a row has off the pointer",
    #chipsOf(restEls) == #model.right, "chips " .. #chipsOf(restEls))
  check("and keeps the same rect, so the hit test does not move under the pointer",
    restRect ~= nil and restRect.x == keysRect.x and restRect.w == keysRect.w)
  local withChord = { right = model.right, keys = model.keys, keysChord = "\u{2318}?" }
  local chordEls, chordRect = footer.bar(ui, T, withChord, band, inset, true)
  check("lit, the key button carries its chord as a chip beside the glyph, on the button's highlight",
    #chipsOf(chordEls) == 3 + #model.right, "chips " .. #chipsOf(chordEls))
  check("and its rect covers both, so the hit test and the light take the whole button",
    chordRect ~= nil and chordRect.x == keysRect.x and chordRect.w > keysRect.w + T.space.s)
  local restChordEls = footer.bar(ui, T, withChord, band, inset, false)
  check("at rest the glyph and the chord are both drawn without a chip",
    #chipsOf(restChordEls) == #model.right, "chips " .. #chipsOf(restChordEls))
  -- With the keyboard icon the engine drew, the icon takes the glyph's place, the hint icon size,
  -- and the button's highlight spans the icon and the chord together.
  local img = hs.image.imageFromName("NSComputer")
  local iconEls, iconRect = footer.bar(ui, T, withChord, band, inset, true, img)
  local pictures = frames(iconEls, function(el) return el.type == "image" end)
  check("the key button draws its icon at the hint icon size, the section line 17",
    #pictures == 1 and pictures[1].h == T.icon.hint and T.icon.hint == 17, "pictures " .. #pictures)
  check("lit, one highlight spans the icon and the chord, beside the chord's own chip",
    #chipsOf(iconEls) == 2 + #model.right and iconRect.x == band.x + inset
      and iconRect.x + iconRect.w >= pictures[1].x + pictures[1].w, "chips " .. #chipsOf(iconEls))
  check("at rest the icon stands alone with no highlight",
    #chipsOf((footer.bar(ui, T, withChord, band, inset, false, img))) == #model.right)
  check("the key button is one chip, centred in the bar and starting at the inset",
    keysRect ~= nil and keysRect.h == chipH and keysRect.x == band.x + inset
      and keysRect.y == band.y + T.space.s,
    keysRect and string.format("%s,%s %sx%s", keysRect.x, keysRect.y, keysRect.w, keysRect.h) or "no rect")
  local last = boxes[#boxes]
  check("the right side runs flush against the bar's right edge less the inset",
    last ~= nil and math.abs(last.x + last.w - (band.x + band.w - inset)) < 1,
    last and tostring(last.x + last.w) or "no chip")
  local divider = frames(els, function(el)
    return el.type == "rectangle" and el.action == "fill" and el.frame.y == band.y and el.frame.w == band.w
  end)
  check("a divider runs along the bar's top edge", #divider == 1, "dividers " .. #divider)

  local panelEls, panelRect = footer.keysPanel(ui, T, model, band, 300)
  check("the key panel rises from the bar's top edge", panelRect.y + panelRect.h == band.y,
    tostring(panelRect.y + panelRect.h))
  local wantH = 2 * chipH + T.space.s + 2 * T.pad
  check("three keys in two columns are two chip rows, a small space between and the panel padding around, 76",
    panelRect.h == wantH and wantH == 76, "height " .. tostring(panelRect.h))
  local fill = panelEls[1]
  check("the key panel is filled in the background colour role",
    fill and fill.type == "rectangle" and fill.fillColor and fill.fillColor.red == T.colors.background.red
      and fill.fillColor.blue == T.colors.background.blue)
  local _, short = footer.keysPanel(ui, T, model, band, 50)
  check("the key panel is never taller than the room the list has", short.h == 50, "height " .. tostring(short.h))
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
  -- title band is the section line 17 plus 10, 27. Three rows in two columns are two rows.
  -- The content box is trimmed to its ink, so the padding is the same on every side, the
  -- title's leading above its capitals at the top and the last row's half spacing at the bottom.
  local sec = ui.tokens().text.section
  local topTrim = (sec.lineHeight - ui.measure:metrics(sec.font, sec.size).capHeight) / 2
  local function near(a, b) return math.abs(a - b) < 0.001 end
  check("the badge is 34, a row 44 and the title band 27, so a titled three row sheet is 27 plus 88 trimmed to its ink",
    near(built.h, 27 + 2 * 44 - topTrim - (44 - 34) / 2), "height " .. tostring(built.h))
  check("the width is the two default columns, 500", built.w == 500, "width " .. tostring(built.w))
  local boxes = chips(built.els)
  check("every key badge is the derived 34 high and square, 34 wide",
    #boxes == 3 and boxes[1].h == 34 and boxes[1].w == 34, boxes[1] and boxes[1].h .. "x" .. boxes[1].w)

  local sizes = {}
  for _, el in ipairs(built.els) do
    if el.text then sizes[#sizes + 1] = el.text:asTable()[2].attributes.font.size end
  end
  check("the section title is 12 and every label and key glyph is body 16",
    sizes[1] == 12 and sizes[2] == 16 and sizes[3] == 16, table.concat(sizes, ","))

  local over = sheet()
  over._model = { rowHeight = 60, badgeHeight = 40, badgeWidth = 50, titleHeight = 30,
    sections = { { title = "KEYS", rows = rows } } }
  local ob = over:_build()
  check("a model may still override the row, badge and title heights, 30 plus 2 times 60",
    near(ob.h, 30 + 2 * 60 - topTrim - (60 - 40) / 2) and chips(ob.els)[1].h == 40 and chips(ob.els)[1].w == 50,
    "height " .. tostring(ob.h))

  local sectionOverride = sheet()
  sectionOverride._model = { sections = { { title = "KEYS", rows = rows, rowHeight = 50 } } }
  check("a section may override a height for its own rows, 27 plus 2 times 50",
    near(sectionOverride:_build().h, 27 + 2 * 50 - topTrim - (50 - 34) / 2))

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
