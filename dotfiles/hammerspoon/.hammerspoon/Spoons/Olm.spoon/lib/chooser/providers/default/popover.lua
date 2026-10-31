--- === Popover ===
---
--- The canvas chooser's popover, the one shape both the key panel and the action panel are drawn
--- in, standing over the chooser above one of the bar's groups. It is the canvas clone of the
--- swift chooser's popover, providers/swift/native/Popover.swift, the same parts in the same places
--- at the same sizes, filled with the background colour role and outlined in the border role
--- rather than glass. It knows neither panel, only the title and the lines it is handed. A line
--- is a label on the left and its chord on the right, and may carry a picture on its left, a
--- section heading above the first line of each run naming the same section, and an enabled flag,
--- a disabled line drawn in the dimmed colours a disabled row takes.
---
--- It answers elements and hit rects and opens no canvas, the way footer.lua and list/render.lua
--- do, so the view appends what it answers to its own surface and keeps the rects for its mouse.
--- Coordinates are the window's own local space, the space the view draws in.
---
--- The padding rules are swift's, one of two ways. A popover whose lines are chosen, the action
--- panel, stands its lines the outer padding from all four edges, the way the list's highlighted
--- rows stand from the window's, a line's picture and words stand the inner padding in from the
--- line's edge, and the highlight's corner is the popover's less the outer padding, the kit's
--- nested radius. A popover whose lines are only read, the key panel, has no line edge to see, so
--- its text itself stands the outer padding from all four edges, the top and bottom measured to
--- the text rather than to a line's height. A header is the row title's role and colour, with a
--- rule in the border role the outer padding below it and the first line the outer padding below
--- the rule. The corner is the highlighted row's, the surface radius less the list margin, as
--- swift hands its popover the highlight radius.
---
--- Every value is a token. The words, the header and the chords are the body role, the row title
--- the swift chooser hands its popover as titleFont, the label in the foreground colour and the
--- chord in subtext, a heading is the caption role in its own colour, the outer padding is the
--- kit's pad, the inner padding its inner, the gap the large space step, a picture's side the
--- section line height, and a line's height the bar's row, which the view hands in since the bar
--- owns it. No shadow, swift's glass has none.

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

--- M.style(ui, tokens, marginX, lineH) -> the popover's style, every colour, role and size read
--- from the kit's tokens. marginX is the list's margin, which the corner nests inside the
--- surface's by, and lineH the height of one line, the bar's row, both the view's to hand in.
function M.style(ui, tokens, marginX, lineH)
  local T = tokens
  local body, caption = T.text.body, T.text.caption
  local radius = ui.nestedRadius(T.radius.surface, marginX)
  return {
    outer = T.pad,
    inner = T.inner or T.space.sm,
    gap = T.space.l,
    iconSide = T.text.section.lineHeight,
    lineH = lineH,
    radius = radius,
    lineRadius = ui.nestedRadius(radius, T.pad),
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

--- M.layout(ui, style, title, lines, selectable) -> a popover's measured content, its preferred
--- size among it. title is the header, nil for none. Each line is { label, chord, picture,
--- section, enabled }, picture a function(frame) -> elements or nil. selectable says the lines
--- are chosen rather than only read, see the paddings above. The preferred size is every line
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
  -- How far a line's text stands in from the popover's sides.
  local side = selectable and (st.outer + st.inner) or st.outer
  -- The room above and below a read line's text inside its height, taken off the top and the
  -- bottom so the text itself stands the outer padding from them. None for chosen lines.
  local slack = selectable and 0 or math.max(0, (st.lineH - st.textH) / 2)

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
    line.chordW = width(line.chord, st.font, st.size)
    widest = math.max(widest, lead + line.labelW + st.gap + line.chordW)
  end
  local headerH = 0
  local w = widest + 2 * side
  if title then
    -- The header, the outer padding, the rule and the outer padding again before the lines.
    headerH = st.textH + 2 * st.outer + st.stroke
    w = math.max(w, width(title, st.font, st.size) + 2 * side)
  end
  return {
    style = st, title = title, lines = lines, selectable = selectable == true,
    tops = tops, headings = headings, contentH = y,
    lead = lead, side = side, slack = slack, headerH = headerH,
    w = math.ceil(w), h = math.ceil(headerH + y - 2 * slack + 2 * st.outer),
  }
end

--- M.place(pop, anchor, align, room) -> the popover's rect. anchor is the group's rect it stands
--- above, align "left" for the key panel, its left edge on the group's, and "right" for the
--- action panel, its right edge on the group's. room is { w, top }, the window's width and the
--- list's top edge. It stands the outer padding above the group, as wide as its widest line and
--- never wider than the window less the outer padding on its open side, as tall as its lines and
--- never above the list's top, where it scrolls instead, swift's layoutKeys and layoutActions.
function M.place(pop, anchor, align, room)
  local pad = pop.style.outer
  local bottom = anchor.y - pad
  local h = math.min(pop.h, math.max(0, bottom - room.top))
  if align == "right" then
    local right = anchor.x + anchor.w
    local w = math.min(pop.w, math.max(0, right - pad))
    return { x = right - w, y = bottom - h, w = w, h = h }
  end
  local w = math.min(pop.w, math.max(0, room.w - anchor.x - pad))
  return { x = anchor.x, y = bottom - h, w = w, h = h }
end

-- Where the lines start inside the popover, from its top, and how much of them shows, the
-- scrolled region running from there to the bottom edge with the outer padding less the slack
-- kept under the last line, the bottom inset of swift's scroll view.
local function region(pop, rect)
  local st = pop.style
  local start = st.outer + pop.headerH - pop.slack
  local viewH = math.max(0, rect.h - start)
  local inset = st.outer - pop.slack
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

--- M.elements(ui, pop, rect, opts) -> elements, info. The popover drawn in rect. opts.highlight is
--- the line lit, from one, or nil, drawn only for a popover whose lines are chosen, and
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
    els[#els + 1] = centredText(ui, pop.title, st.font, st.size, st.text, rect.x + side, top, st.textH,
      rect.w - 2 * side)
    -- The rule stands the outer padding below the header and across the popover inside its
    -- outline, the first line's text the outer padding below it.
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = st.border,
      frame = { x = rect.x + st.stroke, y = top + st.textH + st.outer, w = rect.w - 2 * st.stroke, h = st.stroke } }
  end

  local start, viewH, maxScroll = region(pop, rect)
  local scroll = math.max(0, math.min(opts.scroll or 0, maxScroll))
  local lit = pop.selectable and opts.highlight or nil
  if lit and not pop.tops[lit] then lit = nil end
  if lit and opts.reveal then
    local t = pop.tops[lit]
    local visible = viewH - (st.outer - pop.slack)
    if t < scroll then scroll = t
    elseif t + st.lineH > scroll + visible then scroll = math.min(maxScroll, t + st.lineH - visible) end
  end
  local origin = rect.y + start - scroll
  local view = { x = rect.x, y = rect.y + start, w = rect.w, h = viewH }

  -- The lines are cut to the region they scroll in, inside the popover's own rounded shape.
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
      els[#els + 1] = centredText(ui, line.chord, st.font, st.size, enabled and st.sub or st.subDim,
        chordX, top, st.lineH, line.chordW, "right")
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
