--- === Row height ===
---
--- The one rule both choosers size a row and the field with, so a size set in
--- config/typography.toml reflows them with no number to edit. A row stacks a body title over
--- a caption subtitle with one padding value above and below, so its height is the body line
--- height, plus the caption line height, plus twice the padding. The field is a single line
--- in the title role, since the query is the one thing on the surface a person is writing, with
--- the same padding either side. Pure Lua, no hs, so the canvas geometry and the
--- native provider read the same arithmetic and a unit case can prove it.
---
--- text is the kit's tokens.text, which holds a lineHeight per role, derived by the kit from
--- the role's size. A caller never states a line height of its own.

local M = {}

--- The one vertical padding value, in points, shared by a row and the field.
M.PAD = 8

--- M.rowH(text, pad) -> the height of one row, a body line over a caption line. The native
--- chooser asks only this, since the system draws its field.
function M.rowH(text, pad)
  pad = pad or M.PAD
  return text.body.lineHeight + text.caption.lineHeight + 2 * pad
end

--- M.fieldH(text, pad) -> the height of the field, one title line.
function M.fieldH(text, pad)
  pad = pad or M.PAD
  return text.title.lineHeight + 2 * pad
end

--- M.heights(text, pad) -> { rowH, baseH, pad }, both at once for a provider that draws its
--- own field.
function M.heights(text, pad)
  pad = pad or M.PAD
  return { pad = pad, rowH = M.rowH(text, pad), baseH = M.fieldH(text, pad) }
end

return M
