--- === FloatingPane ===
---
--- The canvas chooser's floating pane, the one shape both the info pane and the actions pane are drawn
--- in, standing over the chooser above one of the bar's groups. It is the canvas clone of the
--- swift chooser's floating pane, providers/swift/native/FloatingPane.swift, the same parts in the same places
--- at the same sizes, filled with the background colour role and outlined in the border role
--- rather than glass. It knows neither panel, only the title and the lines it is handed. A line
--- is a label on the left and its chord on the right, and may carry a picture on its left, a
--- section heading above the first line of each run naming the same section, and an enabled flag,
--- a disabled line drawn in the dimmed colours a disabled row takes.
---
--- It answers elements and hit rects and opens no canvas, the way bottombar.lua and list/render.lua
--- do, so the view appends what it answers to its own surface and keeps the rects for its mouse.
--- Coordinates are the window's own local space, the space the view draws in.
---
--- The padding rules are swift's. Its lines stand the outer padding from all four edges, the way
--- the list's highlighted rows stand from the window's, a line's picture and words stand the inner
--- padding in from the line's edge, and the highlight's corner is the floating pane's less the outer
--- padding, the kit's nested radius. The info pane, whose lines are only read, is laid out the
--- same, so both panels and the bar's cells share one size, Milos's choice of 2026-11-02. A header
--- is the row title's role and colour, laid out as one more line, with a rule in the border role
--- on the header line's bottom edge and the first line right below it. The corner is the
--- highlighted row's, the surface radius less the list margin, as swift hands its floating pane the
--- highlight radius.
---
--- Every value is a token. The words and the header are the body role, the row title the swift
--- chooser hands its floating pane as titleFont, the label in the foreground colour, the chord a key
--- cap, bottombar.lua's keycap, as swift's KeyCap, a heading is the caption role in its own
--- colour, the outer padding is the kit's pad, the inner padding its inner, the gap the large space step, a picture's side the
--- section line height, and a line's height the bar's row, which the view hands in since the bar
--- owns it. No shadow, swift's glass has none.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local bottomBarLib = assert(loadfile(herePath .. "bottombar.lua"))()

local M = {}

local function px(n) return math.floor(n + 0.5) end

-- A colour with its alpha multiplied by factor, how a disabled line is dimmed by the kit's dim
-- alpha, the same plain alpha cut the list takes for a disabled row.
local function faded(color, factor)
  local c = {}
  for k, v in pairs(color or {}) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end

local function append(out, els)
  for _, el in ipairs(els or {}) do out[#out + 1] = el end
end

--- M.style(ui, tokens, marginX, lineH) -> the floating pane's style, every colour, role and size read
--- from the kit's tokens. marginX is the list's margin, which the corner nests inside the
--- surface's by, and lineH the height of one line, the bar's row, both the view's to hand in.
function M.style(ui, tokens, marginX, lineH)
  local T = tokens
  local body, caption = T.text.body, T.text.caption
  local radius = ui.nestedRadius(T.radius.surface, marginX)
  return {
    -- The bar's one padding on every side inside the panel and inside a line, bottombar.lua's, and
    -- the outer padding only between the panel and the group it stands above.
    outer = bottomBarLib.padding(T),
    inner = bottomBarLib.padding(T),
    standoff = T.pad,
    gap = T.space.l,
    iconSide = T.text.section.lineHeight,
    lineH = lineH,
    radius = radius,
    lineRadius = ui.nestedRadius(radius, bottomBarLib.padding(T)),
    tokens = T,
    stroke = T.stroke.border,
    font = body.font, size = body.size, textH = body.lineHeight,
    headFont = caption.font, headSize = caption.size,
    text = T.colors.foreground,
    textDim = faded(T.colors.foreground, T.alpha.dim),
    sub = T.colors.subtext,
    subDim = faded(T.colors.subtext, T.alpha.dim),
    caption = T.colors[caption.color],
    highlight = T.colors.highlight,
    background = T.colors.background,
    border = T.colors.border,
  }
end

--- M.layout(ui, style, title, lines, selectable) -> a floating pane's measured content, its preferred
--- size among it. title is the header, nil for none. Each line is { label, chord, picture,
--- section, enabled }, picture a function(frame) -> elements or nil. selectable says the lines
--- are chosen rather than only read, so a highlight is drawn. The preferred size is every line
--- showing, as wide as the widest label and chord, never narrower than the header.
function M.layout(ui, style, title, lines, selectable)
  local st = style
  local measure = ui.measure
  local function width(str, font, size) return measure:exact(str or "", font, size) end
  local pictured = false
  for _, line in ipairs(lines) do
    if line.picture then pictured = true break end
  end
  -- The room a line's picture takes, nothing for lines without one.
  local lead = pictured and (st.iconSide + st.gap) or 0
  -- How far a line's text stands in from the floating pane's sides, the inner padding inside a line the
  -- outer padding from the edge.
  local side = st.outer + st.inner

  -- Each line's top and each heading's from the top of the lines, a heading as tall as a line,
  -- taken above the first line of a run naming a section different from the line before it.
  local tops, headings = {}, {}
  local y, previous = 0, nil
  local widest = 0
  for i, line in ipairs(lines) do
    if line.section and line.section ~= previous then
      headings[#headings + 1] = { text = line.section, top = y }
      y = y + st.lineH
    end
    previous = line.section
    tops[i] = y
    y = y + st.lineH
    line.labelW = width(line.label, st.font, st.size)
    line.chordW = bottomBarLib.keycapWidth(ui, st.tokens, line.chord)
    widest = math.max(widest, lead + line.labelW + st.gap + line.chordW)
  end
  local headerH = 0
  local w = widest + 2 * side
  if title then
    -- The header, one line, the rule on its bottom edge and the outer padding under the rule, so
    -- a lit first line stands off the rule as the last one stands off the bottom edge.
    headerH = st.lineH + st.stroke + st.outer
    w = math.max(w, width(title, st.font, st.size) + 2 * side)
  end
  return {
    style = st, title = title, lines = lines, selectable = selectable == true,
    tops = tops, headings = headings, contentH = y,
    lead = lead, side = side, headerH = headerH,
    w = math.ceil(w), h = math.ceil(headerH + y + 2 * st.outer),
  }
end

--- M.place(pop, anchor, align, room) -> the floating pane's rect. anchor is the rect of the group whose
--- corner it takes, align "left" for the info pane, its left and bottom edges on the group's, and
--- "right" for the actions pane, its right and bottom edges on the group's. room is
--- { w, top, other }, the window's width, the list's top edge and the rect of the other group, the
--- one that stays on screen, or nil where there is none.
---
--- Both floating panes follow one rule, written once for a pane standing on the left and mirrored
--- for one on the right, so a change to it reaches both, Milos's call on 2026-11-04. A pane is as
--- wide as its lines laid out as a table and never narrower than the group it stands above, so a bar side wider
--- than its panel's lines, the clipboard's Paste, Copy and Actions, gives the panel its width,
--- Milos's call on 2026-11-03. It grows from its group's outer edge toward the other group and
--- stops the outer padding clear of it, or of the window's far edge where there is no other
--- group, past which its labels truncate, so neither pane ever covers the group that stays. It is
--- as tall as its lines and never above the list's top, where it scrolls instead. swift's
--- floatingFrame in native/Panel.swift is the twin rule.
local function mirrored(r, w)
  if not r then return nil end
  return { x = w - r.x - r.w, y = r.y, w = r.w, h = r.h }
end

function M.place(pop, anchor, align, room)
  if align == "right" then
    local W = room.w
    local r = M.place(pop, mirrored(anchor, W), "left",
      { w = W, top = room.top, other = mirrored(room.other, W) })
    return mirrored(r, W)
  end
  local pad = pop.style.standoff
  local bottom = anchor.y + anchor.h
  local h = math.min(pop.h, math.max(0, bottom - room.top))
  local stop = room.other and (room.other.x - pad) or (room.w - pad)
  local w = math.min(math.max(pop.w, anchor.w), math.max(0, stop - anchor.x))
  return { x = anchor.x, y = bottom - h, w = w, h = h }
end

-- Where the lines start inside the floating pane, from its top, and how much of them shows, the
-- scrolled region running from there to the bottom edge with the outer padding kept under the
-- last line, the bottom inset of swift's scroll view.
local function region(pop, rect)
  local st = pop.style
  local start = st.outer + pop.headerH
  local viewH = math.max(0, rect.h - start)
  local inset = st.outer
  return start, viewH, math.max(0, pop.contentH + inset - viewH)
end

-- A text centred on its capitals in a band, the way list render centres a row's title, the
-- frame twice the ascender to descender span so a descender is never cut.
local function centredText(ui, str, font, size, color, x, top, h, w, align)
  local m = ui.measure:metrics(font, size)
  local baseline = top + h / 2 + m.capHeight / 2
  local lineH = m.ascender - m.descender
  return { type = "text", text = str or "", textFont = font, textSize = size, textColor = color,
    textAlignment = align or "left", textLineBreak = "truncateTail",
    frame = { x = px(x), y = px(baseline - m.ascender), w = px(math.max(0, w)), h = px(2 * lineH) } }
end

--- M.elements(ui, pop, rect, opts) -> elements, info. The floating pane drawn in rect. opts.highlight is
--- the line lit, from one, or nil, drawn only for a floating pane whose lines are chosen, and
--- opts.scroll how far its lines are scrolled, clamped here. opts.reveal scrolls just enough to
--- show the lit line, as swift's revealHighlight does. info.scroll is the scroll drawn,
--- info.maxScroll the furthest it can go, and info.lines each line on screen as { index, rect },
--- cut to the region the lines show in, for the view's hit test.
function M.elements(ui, pop, rect, opts)
  opts = opts or {}
  local st = pop.style
  local els = {}
  local r = st.radius
  els[#els + 1] = { type = "rectangle", action = "fill", fillColor = st.background,
    roundedRectRadii = { xRadius = r, yRadius = r },
    frame = { x = rect.x, y = rect.y, w = rect.w, h = rect.h } }
  -- The outline inset by half its stroke, so all of it lies inside the fill, and its corner the
  -- nested one, so the line follows the fill's curve, the way the shared surface draws its own.
  local half = st.stroke / 2
  local sr = ui.nestedRadius(r, half)
  els[#els + 1] = { type = "rectangle", action = "stroke", strokeColor = st.border,
    strokeWidth = st.stroke, roundedRectRadii = { xRadius = sr, yRadius = sr },
    frame = { x = rect.x + half, y = rect.y + half, w = rect.w - st.stroke, h = rect.h - st.stroke } }

  local side = pop.side
  if pop.title then
    local top = rect.y + st.outer
    els[#els + 1] = centredText(ui, pop.title, st.font, st.size, st.text, rect.x + side, top, st.lineH,
      rect.w - 2 * side)
    -- The rule on the header line's bottom edge and across the floating pane inside its outline, the
    -- first line right below it.
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = st.border,
      frame = { x = rect.x + st.stroke, y = top + st.lineH, w = rect.w - 2 * st.stroke, h = st.stroke } }
  end

  local start, viewH, maxScroll = region(pop, rect)
  local scroll = math.max(0, math.min(opts.scroll or 0, maxScroll))
  local lit = pop.selectable and opts.highlight or nil
  if lit and not pop.tops[lit] then lit = nil end
  if lit and opts.reveal then
    local t = pop.tops[lit]
    local visible = viewH - st.outer
    if t < scroll then scroll = t
    elseif t + st.lineH > scroll + visible then scroll = math.min(maxScroll, t + st.lineH - visible) end
  end
  local origin = rect.y + start - scroll
  local view = { x = rect.x, y = rect.y + start, w = rect.w, h = viewH }

  -- The lines are cut to the region they scroll in, inside the floating pane's own rounded shape.
  els[#els + 1] = { type = "rectangle", action = "clip", roundedRectRadii = { xRadius = r, yRadius = r },
    frame = { x = rect.x, y = rect.y, w = rect.w, h = rect.h } }
  els[#els + 1] = { type = "rectangle", action = "clip", frame = view }

  local function shows(top) return top + st.lineH > view.y and top < view.y + view.h end
  for _, heading in ipairs(pop.headings) do
    local top = origin + heading.top
    if shows(top) then
      els[#els + 1] = centredText(ui, heading.text, st.headFont, st.headSize, st.caption,
        rect.x + side, top, st.lineH, rect.w - 2 * side)
    end
  end

  local lines = {}
  for i, line in ipairs(pop.lines) do
    local top = origin + pop.tops[i]
    if shows(top) then
      if i == lit then
        local lr = st.lineRadius
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = st.highlight,
          roundedRectRadii = { xRadius = lr, yRadius = lr },
          frame = { x = rect.x + st.outer, y = top, w = rect.w - 2 * st.outer, h = st.lineH } }
      end
      local enabled = line.enabled ~= false
      local chordX = rect.x + rect.w - side - line.chordW
      append(els, bottomBarLib.keycap(ui, st.tokens, line.chord, chordX, top, st.lineH, st.lineRadius, enabled))
      local labelX = rect.x + side + pop.lead
      els[#els + 1] = centredText(ui, line.label, st.font, st.size, enabled and st.text or st.textDim,
        labelX, top, st.lineH, chordX - st.gap - labelX)
      if line.picture then
        append(els, line.picture({ x = px(rect.x + side), y = px(top + (st.lineH - st.iconSide) / 2),
          w = st.iconSide, h = st.iconSide }))
      end
      local y0, y1 = math.max(top, view.y), math.min(top + st.lineH, view.y + view.h)
      lines[#lines + 1] = { index = i, rect = { x = rect.x, y = y0, w = rect.w, h = y1 - y0 } }
    end
  end
  els[#els + 1] = { type = "resetClip" }
  return els, { scroll = scroll, maxScroll = maxScroll, lines = lines }
end

return M
