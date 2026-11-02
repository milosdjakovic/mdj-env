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

-- A chord drawn as key caps, the canvas twin of KeyCap in the swift chooser's Bar.swift, so a key
-- reads as a key in the bar and in both floating panes and never as a word or an icon. A chord is a kbd
-- chord, lib/kbd.lua, one entry per key, and a cap draws its keys one glyph at a time with the hint
-- badge's gap between them, so the space between two keys is that token and never a character. A
-- chip is the kit's hint badge, its height and its padding either side, filled with the foreground
-- at the keycap alpha so it reads on the background and on the highlight alike, and its glyphs are
-- the badge's role in the foreground, centred on their capitals. Alternatives, a list of chords,
-- are one chip per chord with ALT_WORD between them in the caption role, the small space step
-- either side, so it reads as press one or the other, the word the cheat sheet puts between a
-- row's badges. Its corner nests in the line or group that holds it. No chord draws nothing and
-- takes no room, and anything that is not a kbd chord is refused by kbd.alternatives.

local kbd = assert(loadfile(herePath .. "../../../kbd.lua"))()

-- The word drawn between two alternative keys.
M.ALT_WORD = "/"

local function faded(color, factor)
  local c = {}
  for k, v in pairs(color or {}) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end

-- Each chip's glyphs and their widths and the chip's own width, and the separator word's width,
-- in the order they are drawn.
local function measured(ui, tokens, chords)
  local b = tokens.badge.hint
  local v = tokens.text[b.text]
  local c = tokens.text.caption
  local wordW = math.ceil(ui.measure:exact(M.ALT_WORD, c.font, c.size))
  local caps, total = {}, 0
  for i, chord in ipairs(kbd.alternatives(chords)) do
    if i > 1 then total = total + wordW + 2 * tokens.space.s end
    local glyphs, inner = {}, 0
    for j, glyph in ipairs(kbd.glyphs(chord)) do
      local gw = math.ceil(ui.measure:exact(glyph, v.font, v.size))
      glyphs[j] = { text = glyph, w = gw }
      inner = inner + gw + (j > 1 and (b.gap or 0) or 0)
    end
    local w = inner + 2 * b.padX
    caps[i] = { glyphs = glyphs, w = w }
    total = total + w
  end
  return caps, total, wordW
end

--- M.keycapWidth(ui, tokens, chords) -> the caps' width in points, 0 for no chord. chords is a kbd
--- chord, a list of them for alternatives, or nil.
function M.keycapWidth(ui, tokens, chords)
  local _, total = measured(ui, tokens, chords)
  return total
end

--- M.keycap(ui, tokens, chords, x, top, holderH, holderRadius, enabled) -> elements, the caps from
--- x, centred in a holder holderH tall from top whose corner is holderRadius. enabled false dims
--- them by the kit's dim alpha, as a disabled line is.
function M.keycap(ui, tokens, chords, x, top, holderH, holderRadius, enabled)
  local caps, _, wordW = measured(ui, tokens, chords)
  local els = {}
  if #caps == 0 then return els end
  local b = tokens.badge.hint
  local v = tokens.text[b.text]
  local c = tokens.text.caption
  local dim = enabled == false and tokens.alpha.dim or 1
  local y = top + (holderH - b.height) / 2
  local r = ui.nestedRadius(holderRadius or 0, math.max(0, (holderH - b.height) / 2))
  local function px(n) return math.floor(n + 0.5) end
  local function centred(str, font, size, color, cx, w)
    local m = ui.measure:metrics(font, size)
    local baseline = y + b.height / 2 + m.capHeight / 2
    return { type = "text", text = str, textFont = font, textSize = size, textColor = color,
      textAlignment = "center", textLineBreak = "clip",
      frame = { x = px(cx), y = px(baseline - m.ascender), w = w, h = px(2 * (m.ascender - m.descender)) } }
  end
  for i, cap in ipairs(caps) do
    if i > 1 then
      x = x + tokens.space.s
      els[#els + 1] = centred(M.ALT_WORD, c.font, c.size, faded(tokens.colors[c.color or "subtext"], dim), x, wordW)
      x = x + wordW + tokens.space.s
    end
    els[#els + 1] = { type = "rectangle", action = "fill",
      fillColor = faded(tokens.colors.foreground, tokens.alpha.keycap * dim),
      roundedRectRadii = { xRadius = r, yRadius = r }, frame = { x = px(x), y = px(y), w = cap.w, h = b.height } }
    local gx = x + b.padX
    for j, glyph in ipairs(cap.glyphs) do
      if j > 1 then gx = gx + (b.gap or 0) end
      els[#els + 1] = centred(glyph.text, v.font, v.size, faded(tokens.colors.foreground, dim), gx, glyph.w)
      gx = gx + glyph.w
    end
    x = x + cap.w
  end
  return els
end

return M
