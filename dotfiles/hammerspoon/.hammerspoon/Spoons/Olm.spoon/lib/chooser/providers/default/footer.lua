--- === Action bar ===
---
--- What the default chooser draws in its footer row and in the key panel above it, docs/
--- PLAN-ACTION-BAR.md. This file answers one question, given a footer model and the rects the
--- provider resolved, which canvas elements to draw and where the key button sits. The model is
--- lib/hints.lua's footerModel, pure data the provider is handed through its footer collaborator,
--- so nothing here knows a keymap, a binding or a plugin, only the three lists that model holds.
---
--- Everything is drawn through the UI kit handed in, the caption role for every word, the kit's
--- hint badge for every key, the kit's divider for each edge and the background colour role
--- behind the key panel, so no font, size, colour, radius or stroke is written here. The bar's
--- height is the hint badge's height with the small space step above and below it, the same
--- rule the toasts' footers follow, so a size set in config/typography.toml reflows it.
---
--- Coordinates are the canvas's own, the same local space the provider hands list render, and
--- the key button's rect comes back in that space too, so the provider turns it into screen
--- points for its hit test in the one place it already converts.

local M = {}

-- The word on the button that opens the key panel, drawn as a key badge like every other key.
M.KEYS_GLYPH = "?"

--- M.height(tokens) -> the footer row's height in points, the hint badge with the small space
--- step above and below it.
function M.height(tokens)
  return tokens.badge.hint.height + 2 * tokens.space.s
end

-- The smallest rect holding every shape and picture the kit drew, how the key button's rect is read
-- back from what the kit drew for it rather than worked out a second time beside the kit. Text is
-- not counted, since a glyph's frame is nudged to centre its capitals and is not the chip's edge.
local function bounds(els)
  local x0, y0, x1, y1
  for _, el in ipairs(els) do
    local f = el.frame
    if (el.type == "rectangle" or el.type == "image") and f and f.w and f.h then
      x0 = x0 and math.min(x0, f.x) or f.x
      y0 = y0 and math.min(y0, f.y) or f.y
      x1 = x1 and math.max(x1, f.x + f.w) or f.x + f.w
      y1 = y1 and math.max(y1, f.y + f.h) or f.y + f.h
    end
  end
  if not x0 then return nil end
  return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function append(out, els)
  for _, el in ipairs(els or {}) do out[#out + 1] = el end
end

-- One key as the cheat sheets draw it, its badges beside a caption naming what it does.
local function keyNode(ui, entry)
  local parts = {}
  for _, b in ipairs(entry.badges or {}) do parts[#parts + 1] = ui.badge(b, "hint") end
  parts[#parts + 1] = ui.text(entry.label or "", "caption", { lineBreak = ui.lineBreaks.truncateTail })
  return ui.row(parts, { gap = "s", align = ui.rowAligns.center })
end

--- M.bar(ui, tokens, model, rect, inset, lit, keysImage) -> elements, keysRect
--- The footer row inside rect, the canvas's own footer band, inset by inset points on the left
--- and the right so its edges line up with the list's rows. A divider runs along its top, the key
--- button sits on the left, and the model's right side runs flush against the right edge, each
--- entry its label beside its chord. The key button is the ? glyph and, beside it, the chord of
--- showKeys, model.keysChord, when it has one. keysRect is the whole button's rect, for the hit test.
---
--- keysImage is the button's icon, the keyboard the icon engine drew, which the provider resolves
--- from model.keysIcon. Without one the button falls back to the ? glyph in a hint badge.
---
--- lit says the key button is under the pointer or its panel is open. A lit button sits on the
--- highlight colour role across its whole rect, icon and chord badge alike, which is the state a
--- list row takes under the pointer. At rest every highlight fill of the button is left out, so the
--- icon and the chord's glyph stand alone, and the pointer arriving reads the way it does over a row.
function M.bar(ui, tokens, model, rect, inset, lit, keysImage)
  local els = {}
  append(els, (ui.layout(ui.divider(), { x = rect.x, y = rect.y, w = rect.w, h = 0 }, { tokens = tokens })))

  local rowH = tokens.badge.hint.height
  local inner = { x = rect.x + inset, y = rect.y + (rect.h - rowH) / 2, w = rect.w - 2 * inset, h = rowH }

  -- The key button, its glyph and, when showKeys has a key, that key's chord beside it, both lit
  -- and hit together as one button.
  -- An icon has no chip of its own, so a small space before it keeps it off the lit edge.
  local buttonParts = keysImage and { ui.spacer("xs"), ui.icon(keysImage, "hint") }
    or { ui.badge(M.KEYS_GLYPH, "hint") }
  if model and model.keysChord then buttonParts[#buttonParts + 1] = ui.badge(model.keysChord, "hint") end
  local keysEls = ui.layout(ui.row(buttonParts, { gap = "s", fill = false, align = ui.rowAligns.center }),
    { x = inner.x, y = inner.y, w = inner.w, h = rowH }, { tokens = tokens })
  local keysRect = bounds(keysEls)
  -- The button starts where its row starts, the leading space included, since a spacer draws
  -- nothing for bounds to find.
  if keysRect and keysRect.x > inner.x then
    keysRect.w = keysRect.w + (keysRect.x - inner.x)
    keysRect.x = inner.x
  end
  if lit and keysRect then
    -- One highlight behind the whole button, so the icon lights with the chord beside it. Its
    -- corner is the kit's nested radius, the corner a hint badge takes.
    local r = tokens.radius.nested
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = tokens.colors.highlight,
      roundedRectRadii = { xRadius = r, yRadius = r },
      frame = { x = keysRect.x, y = keysRect.y, w = keysRect.w, h = keysRect.h } }
  end
  for _, el in ipairs(keysEls) do
    if lit or not (el.type == "rectangle" and el.action == "fill") then els[#els + 1] = el end
  end
  local left = keysRect and (keysRect.w + tokens.space.l) or 0

  local items = {}
  for _, r in ipairs((model and model.right) or {}) do
    items[#items + 1] = ui.row({
      ui.text(r.label or "", "caption", { lineBreak = ui.lineBreaks.truncateTail }),
      ui.badge(r.chord or "", "hint"),
    }, { gap = "s", fill = false, align = ui.rowAligns.center })
  end
  if #items > 0 then
    -- An empty text takes whatever width the entries leave, so the entries sit flush right.
    local children = { ui.text("", "caption") }
    for _, item in ipairs(items) do children[#children + 1] = item end
    append(els, (ui.layout(ui.row(children, { gap = "l", align = ui.rowAligns.center, fillIndex = 1 }),
      { x = inner.x + left, y = inner.y, w = math.max(0, inner.w - left), h = rowH }, { tokens = tokens })))
  end
  return els, keysRect
end

--- M.keysPanel(ui, tokens, model, rect, maxH) -> elements, panelRect
--- The key panel rising from the bottom edge of rect, the footer band, over the rows above it,
--- every entry of the model's keys in two columns on the background colour with a divider along
--- its top. It is as tall as its keys and the panel padding, never taller than maxH, the room the
--- list has, and it never scrolls, since a list answers about a dozen keys. panelRect is what the
--- provider keeps out of its row hit test while the panel is up.
function M.keysPanel(ui, tokens, model, rect, maxH)
  local nodes = {}
  for _, entry in ipairs((model and model.keys) or {}) do nodes[#nodes + 1] = keyNode(ui, entry) end
  local grid = ui.grid(nodes, { columns = 2, gapX = "l", gapY = "s" })
  local pad = tokens.pad
  local contentW = math.max(0, rect.w - 2 * pad)
  local _, contentH = ui.layout(grid, { x = 0, y = 0, w = contentW, h = 0 }, { tokens = tokens })
  local h = math.min(contentH + 2 * pad, maxH or math.huge)
  local panelRect = { x = rect.x, y = rect.y - h, w = rect.w, h = h }

  local els = {
    { type = "rectangle", action = "fill", fillColor = tokens.colors.background,
      frame = { x = panelRect.x, y = panelRect.y, w = panelRect.w, h = panelRect.h } },
  }
  append(els, (ui.layout(ui.divider(), { x = panelRect.x, y = panelRect.y, w = panelRect.w, h = 0 },
    { tokens = tokens })))
  append(els, (ui.layout(grid, { x = panelRect.x + pad, y = panelRect.y + pad, w = contentW,
    h = math.max(0, h - 2 * pad) }, { tokens = tokens, clip = true })))
  return els, panelRect
end

return M
