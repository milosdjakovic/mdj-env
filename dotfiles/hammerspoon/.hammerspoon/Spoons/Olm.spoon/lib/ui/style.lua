-- What the current look is. One style spec arrives at configure time and every call to
-- tokens answers a resolved table for the half the system is on right now, so a pane that
-- asks on every draw tracks the light and dark switch without a watcher of its own.
--
-- This is the only file in the kit that asks hs.host.interfaceStyle, and the call is
-- injected through M.new, so the unit loads and resolves in plain Lua with no hs at all.
-- When nothing is injected the real call is made, and only at the moment tokens is asked,
-- never at load.
--
-- The spec carries what policy knows, the colours of each half and the two radii settings
-- owns, and this file carries everything else as its shipped values below. A spec field
-- always wins over a shipped one. Colours arrive either as "#RRGGBB" strings, which is how
-- the surface and preview settings spell them, or as hs colour tables, which is how the row
-- text colours are spelled, and both come back out as colour tables.
--
-- Four colours are derived rather than given, one rule each, so a spec never has to restate
-- them. dim is subtext at the dim alpha, selection is foreground at 0.20, highlight is
-- foreground at 0.14, and surface is background until the palette step gives it its own.

local M = {}

-- The half names the resolver answers and the spec is keyed by.
M.halves = { dark = "dark", light = "light" }

-- Shipped colours, used only where the spec says nothing. The foreground and subtext pairs
-- are the literals lib/cheatsheet.lua and lib/hints.lua fall back to, and the preview four
-- are the fallback the chooser providers and three plugins repeat today. The badge pair is
-- the cheat sheet chip, white 1 at 0.12 on dark and white 0 at 0.06 on light, which settings
-- never carried. The light half has no preview fallback of its own, so it inherits the dark
-- one, the same rule the spec follows.
local SHIPPED_COLORS = {
  dark = {
    foreground = { white = 0.92 },
    subtext = { white = 0.55 },
    accent = "#dcdcdc",
    overlay = "#8a8a8a",
    path = "#7a7a7a",
    note = "#c8a86a",
    badge = { white = 1, alpha = 0.12 },
  },
  light = {
    foreground = { white = 0.15 },
    subtext = { white = 0.42 },
    badge = { white = 0, alpha = 0.06 },
  },
}

-- Every token that is not a colour. Values come from the brief that settled stage one and
-- are what the tree draws today, where the tree agrees with itself.
local SHIPPED = {
  fonts = { ui = ".AppleSystemUIFont", mono = "Menlo" },

  -- Each variant names a font token rather than a font, and states a lineHeight only when
  -- it departs from the one rule in lineHeightFor below. heading is the one variant that
  -- names a colour token of its own, subtext, and every other variant draws in foreground
  -- unless the text node names a colour.
  text = {
    title = { font = "ui", size = 16 },
    body = { font = "ui", size = 14 },
    sub = { font = "ui", size = 12 },
    label = { font = "mono", size = 11 },
    heading = { font = "ui", size = 16, color = "subtext" },
    mono = { font = "mono", size = 12 },
    big = { font = "mono", size = 20 },
  },

  space = { xs = 2, s = 6, m = 10, l = 14, xl = 20 },

  -- surface and badge are overwritten from settings by the spec, and these two are only what
  -- an unconfigured kit draws, square chrome and the cheat sheet's own default badge radius.
  radius = { surface = 0, badge = 5, chip = 6 },

  alpha = { dim = 0.4, fade = 0.55 },

  icon = { row = 28, list = 28, sheet = 32 },

  -- The three badge sizes badge(key, size) names. Not in the design's token list, which
  -- names the sizes but not where their geometry lives, so they sit here beside the other
  -- geometry rather than as literals inside the layout engine. cheat is the cheat sheet
  -- chip, 28 high with 10 of padding and its glyph in the cheat sheet's 16 point type, which
  -- is the title variant. hint is the hint bar chip, 18 high with 6 of padding, drawn in
  -- label, since the brief names label as mono 11 and the hint bar's own ui 11 is one of the
  -- literals stage two corrects. button has no consumer yet, so it was chosen as the
  -- smallest step between the two, 22 high with 10 of padding in sub.
  badge = {
    cheat = { height = 28, padX = 10, text = "title" },
    hint = { height = 18, padX = 6, text = "label" },
    button = { height = 22, padX = 10, text = "sub" },
  },
}

-- Every colour role a resolved table answers, the design's list, kept here because the kit
-- refuses a colour name outside it at build time and the names are this file's to own.
local COLOR_ROLES = {
  "foreground", "subtext", "dim", "overlay", "accent", "note", "path",
  "background", "surface", "border", "selection", "highlight", "badge",
}

local function keysOf(t)
  local out = {}
  for k in pairs(t) do out[k] = true end
  return out
end

--- M.names, the vocabulary a node may name, as sets. The kit validates every variant a
--- primitive is given against these, so a misspelled variant fails where it was written
--- rather than as a blank space at draw time.
M.names = {
  colors = (function()
    local out = {}
    for _, role in ipairs(COLOR_ROLES) do out[role] = true end
    return out
  end)(),
  text = keysOf(SHIPPED.text),
  space = keysOf(SHIPPED.space),
  icon = keysOf(SHIPPED.icon),
  badge = keysOf(SHIPPED.badge),
}

-- The one line height rule, ceil of size times 1.35, unless a variant states its own.
local function lineHeightFor(size)
  return math.ceil(size * 1.35)
end

local function hexColor(hex)
  local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1.0 }
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- A colour as an hs colour table, whichever of the two spellings it arrived in. A fresh
-- copy every time, so a caller adjusting alpha on what it was handed never reaches back
-- into the resolved table or the spec.
local function toColor(value)
  if type(value) == "string" then return hexColor(value) end
  if type(value) == "table" then return copy(value) end
  return nil
end

-- A colour with its alpha multiplied, the one way alpha is applied anywhere in the kit.
function M.withAlpha(color, factor)
  if not color then return nil end
  local out = copy(color)
  out.alpha = (color.alpha or 1) * factor
  return out
end

-- Merge a shallow table of groups, spec over shipped, one level down, so a spec naming one
-- space value keeps every other shipped one.
local function mergeGroup(shipped, given)
  local out = {}
  for k, v in pairs(shipped or {}) do out[k] = type(v) == "table" and copy(v) or v end
  for k, v in pairs(given or {}) do
    if type(v) == "table" and type(out[k]) == "table" then
      for k2, v2 in pairs(v) do out[k][k2] = v2 end
    else
      out[k] = v
    end
  end
  return out
end

--- M.new(opts) -> instance
--- opts.appearance, optional, a function answering "Dark" on the dark half and anything
--- else on the light one, the same answer hs.host.interfaceStyle gives. Injected so a test
--- can stub it and so this file loads with no hs.
function M.new(opts)
  opts = opts or {}
  local appearance = opts.appearance or function()
    return hs.host.interfaceStyle()
  end
  local spec = {}
  local instance = {}

  --- instance.configure(newSpec)
  --- Takes the whole spec, replacing any earlier one, since the composition root builds it
  --- once from policy and has nothing to merge.
  ---   colors   { dark = { role = colour }, light = { role = colour } }, light optional
  ---   fonts, text, space, radius, alpha, icon, badge, each optional and merged over the
  ---            shipped values one level down
  function instance.configure(newSpec)
    spec = newSpec or {}
    return instance
  end

  --- instance.half() -> "dark" | "light", which half the system is on now.
  function instance.half()
    return appearance() == "Dark" and M.halves.dark or M.halves.light
  end

  --- instance.tokens() -> the resolved token table for the current half.
  --- Built fresh on every call, so a caller may keep or mutate what it receives. The light
  --- half falls back to the dark half role by role when the spec gives no light colours.
  function instance.tokens()
    local half = instance.half()
    local colors = spec.colors or {}
    local given = colors[half] or colors.dark or {}

    local resolved = {}
    -- The light half starts from the dark shipped colours so every role has an answer, then
    -- takes its own shipped colours, then the spec.
    for role, value in pairs(SHIPPED_COLORS.dark) do resolved[role] = toColor(value) end
    if half == M.halves.light then
      for role, value in pairs(SHIPPED_COLORS.light) do resolved[role] = toColor(value) end
    end
    for role, value in pairs(given) do resolved[role] = toColor(value) end

    local alpha = mergeGroup(SHIPPED.alpha, spec.alpha)
    resolved.surface = resolved.surface or toColor(resolved.background)
    resolved.dim = resolved.dim or M.withAlpha(resolved.subtext, alpha.dim)
    resolved.selection = resolved.selection or M.withAlpha(resolved.foreground, 0.20)
    resolved.highlight = resolved.highlight or M.withAlpha(resolved.foreground, 0.14)

    local fonts = mergeGroup(SHIPPED.fonts, spec.fonts)
    local text = {}
    for name, variant in pairs(mergeGroup(SHIPPED.text, spec.text)) do
      text[name] = {
        font = fonts[variant.font] or variant.font,
        size = variant.size,
        lineHeight = variant.lineHeight or lineHeightFor(variant.size),
        color = variant.color,
      }
    end

    return {
      half = half,
      colors = resolved,
      fonts = fonts,
      text = text,
      space = mergeGroup(SHIPPED.space, spec.space),
      radius = mergeGroup(SHIPPED.radius, spec.radius),
      alpha = alpha,
      icon = mergeGroup(SHIPPED.icon, spec.icon),
      badge = mergeGroup(SHIPPED.badge, spec.badge),
    }
  end

  return instance
end

return M
