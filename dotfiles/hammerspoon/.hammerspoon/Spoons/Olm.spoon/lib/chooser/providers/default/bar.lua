--- === Canvas bar ===
---
--- The canvas chooser's bar, two groups floating over the list and the pane, the canvas
--- counterpart of the swift chooser's providers/swift/native/Bar.swift and laid out by the same
--- numbers, so the two choosers put the same parts in the same places at the same sizes. The keys
--- group sits in the bottom left corner and the actions group in the bottom right, each the bar
--- pad in from its side and standing at the top of the footer rect, whose height is the group's
--- and the bar pad below it, see View:footerHeight in canvas.lua. Where swift stands each group
--- on the window's glass, this file fills it with the background colour role and outlines it in
--- the border role at the border stroke, drawn inside its shape with its corner less half the
--- stroke, the kit's rule for every outline. Neither group casts a shadow.
---
--- The keys group holds the keyboard icon, or the ? glyph where no icon engine is injected, with
--- the showKeys chord beside it. The actions group holds the footer model's right side, each
--- entry its label beside its chord. Every chord is a key cap, footer.lua's keycap. Every word is
--- the body role, the row title's font
--- and colour, which Milos chose for swift's groups on 2026-10-29, and the icon is the kit's hint
--- icon, the section role's line height, which is the side swift draws it at. The measurements
--- are the ones swift's view.lua hands Swift in View:place. The bar pad is the kit's pad. Inside a
--- group its entries are cells as tall as an action panel line, footer.lua's height, edge to edge,
--- standing the bar's one padding from the group's four edges, each cell's label and chord that
--- padding in from its sides and the small space step apart, so the pointer over a cell lights it
--- exactly as the panel lights its highlighted line, at the panel line's corner. The keys group is
--- one cell. The group's corner is handed in by the caller, the highlighted row's, the surface
--- radius less the list's margin, which is the corner swift gives its groups.
---
--- Like footer.lua and list/render.lua this file answers canvas elements and the rects a hand
--- reaches, in the caller's own canvas space, and opens no canvas. Nothing here knows a keymap,
--- an engine or a mouse. The caller tests a point against the rects it is handed back, which is
--- also how a press on the bar outside both groups falls through to the row the list shows
--- behind it.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local footerLib = assert(loadfile(herePath .. "footer.lua"))()

local M = {}

local function px(n) return math.floor(n + 0.5) end

local function append(out, els)
  for _, el in ipairs(els or {}) do out[#out + 1] = el end
end

-- How wide and how tall a node lays out on its own, read back from what the kit drew for it
-- rather than worked out a second time beside the kit. The row it is handed does not fill, so
-- every text and icon in it takes its natural width, and the rightmost frame is the node's edge.
local function sizeOf(ui, tokens, node, maxW)
  local els, h = ui.layout(node, { x = 0, y = 0, w = maxW, h = 0 }, { tokens = tokens })
  local w = 0
  for _, el in ipairs(els) do
    local f = el.frame
    if f and f.w then w = math.max(w, f.x + f.w) end
  end
  return w, h
end

-- A node laid out at x, centred in the cell's height from top, the way swift centres each
-- part of a cell in it.
local function place(ui, tokens, node, x, top, w, h, groupH)
  return (ui.layout(node, { x = x, y = top + (groupH - h) / 2, w = w, h = h }, { tokens = tokens }))
end

-- The two shapes of one group, the fill and the outline inside it. lit fills it with the
-- highlight role, the state the keys group takes while its panel is open, and the actions group
-- while the action panel is.
local function groupShape(tokens, rect, radius, lit)
  local bw = tokens.stroke.border
  local inner = math.max(0, radius - bw / 2)
  return {
    { type = "rectangle", action = "fill",
      fillColor = lit and tokens.colors.highlight or tokens.colors.background,
      roundedRectRadii = { xRadius = radius, yRadius = radius },
      frame = { x = rect.x, y = rect.y, w = rect.w, h = rect.h } },
  }, {
    type = "rectangle", action = "stroke", strokeColor = tokens.colors.border, strokeWidth = bw,
    roundedRectRadii = { xRadius = inner, yRadius = inner },
    frame = { x = rect.x + bw / 2, y = rect.y + bw / 2, w = rect.w - bw, h = rect.h - bw },
  }
end

--- M.metrics(tokens) -> the bar's measurements from the kit's tokens, the same sources swift's
--- view.lua reads for barPad, barPillPad, barGap, barGapWide, barPillH and keysIcon. cellH is a
--- cell's height, a panel line's, and height the group's, the cell with the padding around it.
function M.metrics(tokens)
  local inner = footerLib.padding(tokens)
  local cellH = footerLib.height(tokens)
  return {
    pad = tokens.pad,
    inner = inner,
    gap = tokens.space.s,
    gapWide = tokens.space.l,
    cellH = cellH,
    height = cellH + 2 * inner,
  }
end

-- A cell lit under the pointer, the highlight role at the panel line's corner.
local function cellShape(tokens, rect, radius)
  return { type = "rectangle", action = "fill", fillColor = tokens.colors.highlight,
    roundedRectRadii = { xRadius = radius, yRadius = radius },
    frame = { x = rect.x, y = rect.y, w = rect.w, h = rect.h } }
end

--- M.elements(ui, tokens, model, rect, opts) -> elements, hits
--- The bar inside rect, the footer rect in the caller's canvas space, for the footer model
--- lib/hints.lua's footerModel answers. opts, every field optional.
---   radius     the groups' corner, the caller's highlighted row radius.
---   keysImage  the keyboard icon as a picture. Without one the keys group draws the ? glyph.
---   keysLit    the keys group sits on the highlight, its panel open.
---   keysHover  the keys group's cell sits on the highlight, the pointer over it.
---   hover      the index of the action entry under the pointer, whose cell sits on the highlight.
---   keysHidden, actionsHidden  leave that group undrawn, while the panel it opens stands in its
---              corner, its rect still answered in hits as the panel's anchor.
--- hits holds keys, the keys group's rect, keysCell, its one cell, actions, the actions group's
--- rect or nil when the model has no right side, and entries, one { rect, action } per entry of
--- the right side in order, each its cell, so the padding around the cells is no entry's, as in
--- swift.
function M.elements(ui, tokens, model, rect, opts)
  opts = opts or {}
  local m = M.metrics(tokens)
  local radius = opts.radius or 0
  local els = {}
  local hits = { entries = {} }
  if not (model and rect) then return els, hits end
  local top = rect.y
  local h = m.height
  local cellH = m.cellH
  -- A cell's corner, the panel line's, the group's corner less the padding around the cells.
  local cellRadius = ui.nestedRadius(radius, m.inner)
  local bodyRow = { gap = "s", fill = false, align = ui.rowAligns.center }

  -- The keys group, one cell holding its parts side by side, the inner padding in from the cell.
  local keysNode = ui.row({ opts.keysImage and ui.icon(opts.keysImage, "hint") or ui.text(footerLib.KEYS_GLYPH, "body") }, bodyRow)
  local iconW, iconH = sizeOf(ui, tokens, keysNode, rect.w)
  local capW = footerLib.keycapWidth(ui, tokens, model.keysChord)
  local keysW = iconW + (capW > 0 and m.gap + capW or 0)
  local keysRect = { x = px(rect.x + m.pad), y = px(top), w = px(keysW + 4 * m.inner), h = px(h) }
  local keysCell = { x = keysRect.x + m.inner, y = keysRect.y + m.inner, w = keysRect.w - 2 * m.inner, h = cellH }
  if not opts.keysHidden then
    local fill, outline = groupShape(tokens, keysRect, radius, opts.keysLit)
    append(els, fill)
    if opts.keysHover then els[#els + 1] = cellShape(tokens, keysCell, cellRadius) end
    els[#els + 1] = outline
    append(els, place(ui, tokens, keysNode, keysCell.x + m.inner, keysCell.y, iconW, iconH, cellH))
    append(els, footerLib.keycap(ui, tokens, model.keysChord, keysCell.x + m.inner + iconW + m.gap,
      keysCell.y, cellH, cellRadius))
  end
  hits.keys = keysRect
  hits.keysCell = keysCell

  -- The actions group, its entries measured first so it can stand flush with the bar pad from
  -- the right edge, the way swift lays it from its right edge leftward.
  local entries = {}
  local total = 0
  for i, r in ipairs(model.right or {}) do
    local node = ui.row({ ui.text(r.label or "", "body") }, bodyRow)
    local lw, eh = sizeOf(ui, tokens, node, rect.w)
    local cw = footerLib.keycapWidth(ui, tokens, r.chord)
    -- A cell, its label and chord the inner padding in from its sides.
    local w = lw + (cw > 0 and m.gap + cw or 0) + 2 * m.inner
    entries[i] = { node = node, w = w, labelW = lw, h = eh, chord = r.chord, action = r.action }
    total = total + w
  end
  if #entries == 0 then return els, hits end
  local groupW = total + 2 * m.inner
  local actionsRect = { x = px(rect.x + rect.w - m.pad - groupW), y = px(top), w = px(groupW), h = px(h) }
  hits.actions = actionsRect

  -- The cells edge to edge, the padding in from the group's edges.
  local x = actionsRect.x + m.inner
  for i, e in ipairs(entries) do
    hits.entries[i] = { rect = { x = x, y = actionsRect.y + m.inner, w = e.w, h = cellH }, action = e.action }
    x = x + e.w
  end

  if opts.actionsHidden then return els, hits end
  local fill, outline = groupShape(tokens, actionsRect, radius, model.panelOpen == true)
  append(els, fill)
  -- The cell under the pointer lights as a panel line does, beneath the outline so the group's
  -- edge stays drawn.
  local lit = opts.hover and hits.entries[opts.hover]
  if lit then els[#els + 1] = cellShape(tokens, lit.rect, cellRadius) end
  els[#els + 1] = outline
  for i, e in ipairs(entries) do
    local cell = hits.entries[i].rect
    append(els, place(ui, tokens, e.node, cell.x + m.inner, cell.y, e.labelW, e.h, cellH))
    append(els, footerLib.keycap(ui, tokens, e.chord, cell.x + m.inner + e.labelW + m.gap, cell.y, cellH, cellRadius))
  end
  return els, hits
end

return M
