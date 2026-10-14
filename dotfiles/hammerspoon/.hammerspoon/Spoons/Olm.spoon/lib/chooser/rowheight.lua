--- === Row height ===
---
--- The one rule both choosers size a row and the field with, so a size set in
--- config/typography.toml or the kit's inset reflows them with no number to edit. Pure Lua,
--- no hs, so the canvas geometry and the native provider read the same arithmetic and a unit
--- case can prove it.
---
--- The inset's y is measured to the letters rather than to a line box, the kit's rule. The
--- field is as tall as a row, asked for on 2026 10 14 so the two read alike, and taller only
--- when the title's capital height plus the inset above and below would not fit. Its padding
--- above and below is then FIELD_PAD_Y times a row's, asked for the same day to give the
--- query more room than a row. A row stacks a body title over a caption subtitle, so its height is the inset
--- above the title's capital, the title's capital height, M.subStep from the title's baseline
--- to the subtitle's, and the inset below that baseline. Heights round up to whole
--- points and the renderers centre the letters in what they are given, so any rounding is
--- split evenly above and below.
---
--- text is the kit's tokens.text, a lineHeight per role. cap answers a role's capital height,
--- read by the caller from the real font metrics. inset is the kit's tokens.inset.

local M = {}

--- The gap in points from the title's baseline to the top of the subtitle's capitals. A full
--- caption line left about 9, asked down to 5.3 on 2026 10 14 so the pair reads as one item.
M.SUB_GAP = 5.3

--- How much larger a row's icon is than the text beside it, asked for on 2026 10 14.
M.ICON_SCALE = 1.26

--- How much more vertical padding the field has than a row, as a multiple of the inset's y.
M.FIELD_PAD_Y = 1.5

--- How much of an icon image its artwork fills, Apple's icon grid, 824 of 1024 points, the
--- rest transparent margin. lib/glyphicon.lua frames every glyph icon to the same grid, so
--- one ratio holds for every row icon.
M.ICON_ART = 824 / 1024

local function capOf(cap, text, role)
  if type(cap) == "function" then return cap(role) end
  if type(cap) == "table" and cap[role] then return cap[role] end
  -- No metrics to hand, a unit case or a caller with no kit. The system font's capital is
  -- seven tenths of its size near enough for a fallback.
  return (text[role].size or text[role].lineHeight / 1.35) * 0.7
end

--- M.subStep(text, cap, fullLine) -> the distance from the title's baseline to the
--- subtitle's, the caption's capital height plus M.SUB_GAP. The native chooser passes fullLine,
--- one whole caption line, since the system spaces its own lines.
function M.subStep(text, cap, fullLine)
  if fullLine then return text.caption.lineHeight end
  return capOf(cap, text, "caption") + M.SUB_GAP
end

--- M.rowH(text, cap, inset, fullLine) -> the height of one row, a body title over a caption
--- subtitle. The native chooser asks only this, since the system draws its field.
function M.rowH(text, cap, inset, fullLine)
  return math.ceil(2 * inset.y + capOf(cap, text, "body") + M.subStep(text, cap, fullLine))
end

--- M.fieldH(text, cap, inset) -> the height of the field, one title line in a row's height.
function M.fieldH(text, cap, inset)
  local extra = 2 * inset.y * (M.FIELD_PAD_Y - 1)
  return math.ceil(math.max(M.rowH(text, cap, inset), 2 * inset.y + capOf(cap, text, "title")) + extra)
end

--- M.iconH(text, cap) -> the side of a row's icon, the span from the top of the title's
--- capitals to the subtitle's baseline times M.ICON_SCALE. At a scale of one the icon stands
--- exactly as tall as the text beside it, and above one it reaches into the inset, and the
--- canvas geometry's iconPad gives it the same room on its left as above and below.
function M.iconH(text, cap)
  return math.floor((capOf(cap, text, "body") + M.subStep(text, cap)) * M.ICON_SCALE)
end

--- M.iconFrame(text, cap) -> the side the icon image is drawn at, larger than M.iconH by the
--- transparent margin, so the artwork inside it is exactly M.iconH tall.
function M.iconFrame(text, cap)
  return math.floor(M.iconH(text, cap) / M.ICON_ART + 0.5)
end

--- M.heights(text, cap, inset) -> { rowH, baseH }, both at once for a provider that draws
--- its own field.
function M.heights(text, cap, inset)
  return { rowH = M.rowH(text, cap, inset), baseH = M.fieldH(text, cap, inset),
    iconSize = M.iconH(text, cap), iconFrame = M.iconFrame(text, cap),
    subStep = M.subStep(text, cap) }
end

return M
