--- === Action bar ===
---
--- The bar's height, docs/PLAN-ACTION-BAR.md. The bar itself, the two floating groups, is bar.lua
--- beside this file since 2026-10-30, when the canvas chooser took the swift chooser's layout, and
--- the key panel is popover.lua, drawn above the keys group. The single row and the key panel over
--- the bottom rows this file drew until then went with them. The height stays here because the
--- engine, the swift view, bar.lua and popover.lua all read it, so every chooser sizes its bar by
--- one rule. The height is a row, the taller of the hint badge and the caption line, with the small
--- space step above and below it, the same rule the toasts' footers follow, so a size set in
--- config/typography.toml reflows it.

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

return M
