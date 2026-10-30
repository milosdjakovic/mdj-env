--- === Action bar ===
---
--- The bar's height and the key panel the default chooser draws above it, docs/
--- PLAN-ACTION-BAR.md. The bar itself, the two floating groups, is bar.lua beside this file since
--- 2026-10-30, when the canvas chooser took the swift chooser's layout, and the single row this
--- file drew until then went with it. The height stays here because the engine, the swift view
--- and bar.lua all read it, so every chooser sizes its bar by one rule. The model is
--- lib/hints.lua's footerModel, pure data the provider is handed through its footer collaborator,
--- so nothing here knows a keymap, a binding or a plugin, only the lists that model holds.
---
--- Everything is drawn through the UI kit handed in, the caption role for every word, since each
--- is a hint label and Milos chose caption for those, the kit's hint badge for every key, its glyph
--- in the section role, the kit's divider for the panel's top edge and the background colour role
--- behind it, so no font, size, colour, radius or stroke is written here. Both roles are 14 points
--- as shipped. The bar's height is a row, the taller of the hint badge and the caption line,
--- with the small space step above and below it, the same rule the toasts' footers follow, so a
--- size set in config/typography.toml reflows it.
---
--- Coordinates are the canvas's own, the same local space the provider hands list render, and
--- the key panel's rect comes back in that space too, so the provider turns it into screen
--- points for its hit test in the one place it already converts.

local M = {}

-- The word on the keys group where no icon engine draws the keyboard, see bar.lua.
M.KEYS_GLYPH = "?"

-- The height of the bar's row and of a key panel row, the taller of a hint badge and a caption
-- line, since a label in the caption role sits beside the badges on each.
local function rowHeight(tokens)
  return math.max(tokens.badge.hint.height, tokens.text.caption.lineHeight)
end

--- M.height(tokens) -> the footer row's height in points, the row with the small space step
--- above and below it.
function M.height(tokens)
  return rowHeight(tokens) + 2 * tokens.space.s
end

local function append(out, els)
  for _, el in ipairs(els or {}) do out[#out + 1] = el end
end

-- One key as the cheat sheets draw it, its badges beside a hint label naming what it does.
local function keyNode(ui, entry)
  local parts = {}
  for _, b in ipairs(entry.badges or {}) do parts[#parts + 1] = ui.badge(b, "hint") end
  parts[#parts + 1] = ui.text(entry.label or "", "caption", { lineBreak = ui.lineBreaks.truncateTail })
  return ui.row(parts, { gap = "s", align = ui.rowAligns.center })
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
