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
--- entry its label beside its chord. Every word and chord is the body role, the row title's font
--- and colour, which Milos chose for swift's groups on 2026-10-29, and the icon is the kit's hint
--- icon, the section role's line height, which is the side swift draws it at. The measurements
--- are the ones swift's view.lua hands Swift in View:place. The bar pad is the kit's pad, the
--- room inside a group on its left and right is the kit's inner padding, a label and its chord
--- stand the small space step apart and two entries the large one, and a group is as tall as
--- footer.lua's height. The corner is handed in by the caller, the highlighted row's, the surface
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

-- A node laid out at x, centred in the group's height from top, the way swift centres each
-- part of a group in it.
local function place(ui, tokens, node, x, top, w, h, groupH)
  return (ui.layout(node, { x = x, y = top + (groupH - h) / 2, w = w, h = h }, { tokens = tokens }))
end

-- The two shapes of one group, the fill and the outline inside it. lit fills it with the
-- highlight role, the state the keys group takes under the pointer or while its panel is open,
-- and the actions group while the action panel is.
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
--- view.lua reads for barPad, barPillPad, barGap, barGapWide, barPillH and keysIcon.
function M.metrics(tokens)
  return {
    pad = tokens.pad,
    inner = tokens.inner or tokens.space.sm,
    gap = tokens.space.s,
    gapWide = tokens.space.l,
    height = footerLib.height(tokens),
  }
end

--- M.elements(ui, tokens, model, rect, opts) -> elements, hits
--- The bar inside rect, the footer rect in the caller's canvas space, for the footer model
--- lib/hints.lua's footerModel answers. opts, every field optional.
---   radius     the groups' corner, the caller's highlighted row radius.
---   keysImage  the keyboard icon as a picture. Without one the keys group draws the ? glyph.
---   keysLit    the keys group sits on the highlight, its panel open or the pointer over it.
---   hover      the index of the action entry under the pointer, which sits on the highlight.
--- hits holds keys, the keys group's rect, actions, the actions group's rect or nil when the
--- model has no right side, and entries, one { rect, action } per entry of the right side in
--- order. An entry reaches from half the wide gap before its label to half after its chord, the
--- first from the group's left edge and the last to its right, so every point of the group is
--- one entry's, and swift's own press on an entry is answered across the same span.
function M.elements(ui, tokens, model, rect, opts)
  opts = opts or {}
  local m = M.metrics(tokens)
  local radius = opts.radius or 0
  local els = {}
  local hits = { entries = {} }
  if not (model and rect) then return els, hits end
  local top = rect.y
  local h = m.height
  local bodyRow = { gap = "s", fill = false, align = ui.rowAligns.center }

  -- The keys group, its parts side by side from the inner padding in.
  local keysParts = { opts.keysImage and ui.icon(opts.keysImage, "hint") or ui.text(footerLib.KEYS_GLYPH, "body") }
  if model.keysChord then keysParts[#keysParts + 1] = ui.text(model.keysChord, "body") end
  local keysNode = ui.row(keysParts, bodyRow)
  local keysW, keysH = sizeOf(ui, tokens, keysNode, rect.w)
  local keysRect = { x = px(rect.x + m.pad), y = px(top), w = px(keysW + 2 * m.inner), h = px(h) }
  local fill, outline = groupShape(tokens, keysRect, radius, opts.keysLit)
  append(els, fill)
  els[#els + 1] = outline
  append(els, place(ui, tokens, keysNode, keysRect.x + m.inner, keysRect.y, keysW, keysH, h))
  hits.keys = keysRect

  -- The actions group, its entries measured first so it can stand flush with the bar pad from
  -- the right edge, the way swift lays it from its right edge leftward.
  local entries = {}
  local total = 0
  for i, r in ipairs(model.right or {}) do
    local node = ui.row({ ui.text(r.label or "", "body"), ui.text(r.chord or "", "body") }, bodyRow)
    local w, eh = sizeOf(ui, tokens, node, rect.w)
    entries[i] = { node = node, w = w, h = eh, action = r.action }
    total = total + w + (i > 1 and m.gapWide or 0)
  end
  if #entries == 0 then return els, hits end
  local groupW = total + 2 * m.inner
  local actionsRect = { x = px(rect.x + rect.w - m.pad - groupW), y = px(top), w = px(groupW), h = px(h) }
  hits.actions = actionsRect

  local half = m.gapWide / 2
  local x = actionsRect.x + m.inner
  local spans = {}
  for i, e in ipairs(entries) do
    local lo = i == 1 and actionsRect.x or x - half
    local hi = i == #entries and actionsRect.x + actionsRect.w or x + e.w + half
    spans[i] = { x = x, lo = lo, hi = hi }
    hits.entries[i] = { rect = { x = lo, y = actionsRect.y, w = hi - lo, h = actionsRect.h }, action = e.action }
    x = x + e.w + m.gapWide
  end

  fill, outline = groupShape(tokens, actionsRect, radius, model.panelOpen == true)
  append(els, fill)
  -- The entry under the pointer lights across its whole span, the way a row lights under it,
  -- beneath the outline so the group's edge stays drawn.
  local lit = opts.hover and hits.entries[opts.hover]
  if lit then
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = tokens.colors.highlight,
      roundedRectRadii = { xRadius = radius, yRadius = radius },
      frame = { x = lit.rect.x, y = lit.rect.y, w = lit.rect.w, h = lit.rect.h } }
  end
  els[#els + 1] = outline
  for i, e in ipairs(entries) do
    append(els, place(ui, tokens, e.node, spans[i].x, actionsRect.y, e.w, e.h, h))
  end
  return els, hits
end

return M
