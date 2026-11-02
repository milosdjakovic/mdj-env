-- The key cap, the one way Olm draws a key a person presses.
--
-- A chord is a kbd chord, lib/kbd.lua, an array of keys, kbd.of(kbd.Shift, kbd.Return) in code or
-- kbd.binding("k", { "shift" }, "hyper") from data, and a list of chords is alternatives, keys a
-- person may press for one thing. Each chord is one chip and its keys are drawn one glyph at a
-- time with the badge's gap between them, so the space between two keys is a token and never a
-- character. Alternatives are one chip per chord with ALT_WORD between them in the caption role,
-- the small space step either side. The bottom bar, its floating panes and a cheat sheet all draw
-- through here, and the swift chooser's KeyCap in native/Bar.swift draws the same measurements
-- from the same tokens, so a key reads the same everywhere.
--
-- A chip sizes to its keys, the glyphs plus the badge's padding either side. opts.width constrains
-- it to a width, the cheat sheet's square column among them, and a chip whose keys need more grows
-- to fit them rather than cutting a key off, its keys centred in whatever width it takes. The fill is
-- lib/ui/style.lua's keycapColor, the foreground at the keycap alpha, and never the highlight.
--
-- Pure Lua over an injected measurer with exact and metrics, so it loads with no hs.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
local function load(rel)
  local chunk, err = loadfile(here .. rel)
  if not chunk then error("ui.keycap failed to load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

local kbd = load("../kbd.lua")
local styleLib = load("style.lua")

local M = {}

-- The word drawn between two alternative chords.
M.ALT_WORD = "/"

local function px(n) return math.floor(n + 0.5) end

--- M.measure(measure, T, chords, size, opts) -> caps, total, wordW
--- Each chip's glyphs with their widths and the chip's own width, the whole block's width and the
--- separator word's, in the order they are drawn. size names a badge of the kit, hint or cheat.
function M.measure(measure, T, chords, size, opts)
  opts = opts or {}
  local b = T.badge[size]
  local v = T.text[b.text]
  local c = T.text.caption
  local wordW = math.ceil(measure:exact(M.ALT_WORD, c.font, c.size))
  local caps, total = {}, 0
  for i, chord in ipairs(kbd.alternatives(chords)) do
    if i > 1 then total = total + wordW + 2 * T.space.s end
    local glyphs, inner = {}, 0
    for j, glyph in ipairs(kbd.glyphs(chord)) do
      local gw = math.ceil(measure:exact(glyph, v.font, v.size))
      glyphs[j] = { text = glyph, w = gw }
      inner = inner + gw + (j > 1 and (b.gap or 0) or 0)
    end
    local w = math.max(inner + 2 * b.padX, opts.width or 0)
    caps[i] = { glyphs = glyphs, inner = inner, w = w }
    total = total + w
  end
  return caps, total, wordW
end

--- M.width(measure, T, chords, size, opts) -> the block's width in points, 0 for no chord.
function M.width(measure, T, chords, size, opts)
  local _, total = M.measure(measure, T, chords, size, opts)
  return total
end

--- M.elements(measure, T, chords, size, x, top, holderH, opts) -> elements
--- The chips from x, centred in a holder holderH tall from top. opts.width constrains each chip,
--- opts.radius is the chip's corner, the badge's own radius token when not given, and opts.alpha
--- multiplies every colour, a disabled line's dim or a fading group's alpha.
function M.elements(measure, T, chords, size, x, top, holderH, opts)
  opts = opts or {}
  local caps, _, wordW = M.measure(measure, T, chords, size, opts)
  local els = {}
  if #caps == 0 then return els end
  local b = T.badge[size]
  local v = T.text[b.text]
  local c = T.text.caption
  local alpha = opts.alpha or 1
  local y = top + (holderH - b.height) / 2
  local r = opts.radius or T.radius[b.radius or "nested"] or 0
  local function centred(str, font, sz, color, cx, w)
    local m = measure:metrics(font, sz)
    local baseline = y + b.height / 2 + m.capHeight / 2
    return { type = "text", text = str, textFont = font, textSize = sz, textColor = color,
      textAlignment = "center", textLineBreak = "clip",
      frame = { x = px(cx), y = px(baseline - m.ascender), w = w, h = px(2 * (m.ascender - m.descender)) } }
  end
  for i, cap in ipairs(caps) do
    if i > 1 then
      x = x + T.space.s
      els[#els + 1] = centred(M.ALT_WORD, c.font, c.size,
        styleLib.withAlpha(T.colors[c.color or "subtext"], alpha), x, wordW)
      x = x + wordW + T.space.s
    end
    els[#els + 1] = { type = "rectangle", action = "fill",
      fillColor = styleLib.keycapColor(T, alpha),
      roundedRectRadii = { xRadius = r, yRadius = r }, frame = { x = px(x), y = px(y), w = cap.w, h = b.height } }
    -- A chip wider than its keys, held to a width, centres them in it.
    local gx = x + (cap.w - cap.inner) / 2
    for j, glyph in ipairs(cap.glyphs) do
      if j > 1 then gx = gx + (b.gap or 0) end
      els[#els + 1] = centred(glyph.text, v.font, v.size, styleLib.withAlpha(T.colors.foreground, alpha), gx, glyph.w)
      gx = gx + glyph.w
    end
    x = x + cap.w
  end
  return els
end

return M
