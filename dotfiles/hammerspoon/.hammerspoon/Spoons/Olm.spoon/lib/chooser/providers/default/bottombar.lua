--- === Bottom bar ===
---
--- The bar's height, docs/PLAN-ACTION-BAR.md. The bar itself, the two floating groups, is bar.lua
--- beside this file since 2026-10-30, when the canvas chooser took the swift chooser's layout, and
--- the info pane is floatingpane.lua, drawn above the left side. The single row and the info pane over
--- the bottom rows this file drew until then went with them. The height stays here because the
--- engine, the swift view, bar.lua and floatingpane.lua all read it, so every chooser sizes its bar by
--- one rule. The height is a row, the taller of the key cap and the body line, with the bar's one
--- padding, the kit's barInner, above and below it, the same padding the groups take on their
--- left and right and the panels on every side, so a size set in config/typography.toml or
--- spacing.bar in config/settings.lua reflows it.

local M = {}

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

-- The word on the left side where no icon engine draws the keyboard, see bar.lua.
M.KEYS_GLYPH = "?"

-- The tallest part of a bar group or a panel line, a key cap or a label in the body role beside it.
local function rowHeight(tokens)
  return math.max(tokens.badge.hint.height, tokens.text.body.lineHeight)
end

--- M.padding(tokens) -> the bar's one padding, inside each group and each panel on every side.
function M.padding(tokens)
  return tokens.barInner or tokens.space.s
end

--- M.height(tokens) -> the bottom bar row's height in points, the row with the bar's padding above
--- and below it.
function M.height(tokens)
  return rowHeight(tokens) + 2 * M.padding(tokens)
end

-- A chord drawn as key caps is the kit's one key cap, lib/ui/keycap.lua, at the hint badge's size,
-- the canvas twin of KeyCap in the swift chooser's Bar.swift. This file only fits it into a line
-- or group, its corner nested in the holder and its alpha dimmed for a disabled line, so the
-- bottom bar, both floating panes and a cheat sheet draw a key by one rule.

local keycapLib = assert(loadfile(herePath .. "../../../ui/keycap.lua"))()

-- The word drawn between two alternative keys, the kit's own.
M.ALT_WORD = keycapLib.ALT_WORD

--- M.keycapWidth(ui, tokens, chords) -> the caps' width in points, 0 for no chord. chords is a kbd
--- chord, a list of them for alternatives, or nil.
function M.keycapWidth(ui, tokens, chords)
  return keycapLib.width(ui.measure, tokens, chords, "hint")
end

--- M.keycap(ui, tokens, chords, x, top, holderH, holderRadius, enabled) -> elements, the caps from
--- x, centred in a holder holderH tall from top whose corner is holderRadius. enabled false dims
--- them by the kit's dim alpha, as a disabled line is.
function M.keycap(ui, tokens, chords, x, top, holderH, holderRadius, enabled)
  local b = tokens.badge.hint
  return keycapLib.elements(ui.measure, tokens, chords, "hint", x, top, holderH, {
    radius = ui.nestedRadius(holderRadius or 0, math.max(0, (holderH - b.height) / 2)),
    alpha = enabled == false and tokens.alpha.dim or 1,
  })
end

return M
