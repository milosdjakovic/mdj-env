--- === Row height ===
---
--- The one rule both choosers size a row and the field with, so a size set in
--- config/typography.toml reflows them with no number to edit. A row stacks a body title over
--- a caption subtitle with one padding value above and below, so its height is the body line
--- height, plus the caption line height, plus twice the padding. The field is a single body
--- line with the same padding either side. Pure Lua, no hs, so the canvas geometry and the
--- native provider read the same arithmetic and a unit case can prove it.
---
--- text is the kit's tokens.text, which holds a lineHeight per role, derived by the kit from
--- the role's size. A caller never states a line height of its own.

local M = {}

--- The one vertical padding value, in points, shared by a row and the field.
M.PAD = 8

--- M.heights(text, pad) -> { rowH, baseH, pad }
function M.heights(text, pad)
  pad = pad or M.PAD
  local body = text.body.lineHeight
  local caption = text.caption.lineHeight
  return {
    pad = pad,
    rowH = body + caption + 2 * pad,
    baseH = body + 2 * pad,
  }
end

return M
