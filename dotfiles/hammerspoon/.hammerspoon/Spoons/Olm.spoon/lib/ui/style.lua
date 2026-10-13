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
--
-- quiet and outline arrived in stage two, each holding a literal a shared surface drew with
-- so the move onto the kit changes nothing. quiet is the empty state's own default text
-- colour, a gray at 0.55 on both halves, which is not dim, since dim is subtext at the dim
-- alpha and the two have never been equal. outline is the colour toast's swatch stroke,
-- white 1 at 0.25 on dark and white 0 at 0.2 on light.
local SHIPPED_COLORS = {
  dark = {
    foreground = { white = 0.92 },
    subtext = { white = 0.55 },
    accent = "#dcdcdc",
    overlay = "#8a8a8a",
    path = "#7a7a7a",
    note = "#c8a86a",
    badge = { white = 1, alpha = 0.12 },
    quiet = { white = 0.6, alpha = 0.55 },
    outline = { white = 1, alpha = 0.25 },
  },
  light = {
    foreground = { white = 0.15 },
    subtext = { white = 0.42 },
    badge = { white = 0, alpha = 0.06 },
    outline = { white = 0, alpha = 0.2 },
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
  --
  -- The second group holds the type the shared surfaces drew with before stage two moved
  -- them onto the kit, one variant per distinct font, size and box, so each surface draws
  -- exactly what it drew before. Every one of them sets pin to false, since those surfaces
  -- drew plain canvas text with no pinned line height, and a pinned one moves the glyphs.
  -- lineHeight is the frame height each surface gave its text. frameY and extraW say where
  -- the frame sits against the box the layout reserves, frameY points lower and extraW
  -- points wider, neither taking any room in the layout, which is how the hint bar label
  -- was placed. Stage three replaces this group with the new look.
  text = {
    title = { font = "ui", size = 16 },
    body = { font = "ui", size = 14 },
    sub = { font = "ui", size = 12 },
    label = { font = "mono", size = 11 },
    heading = { font = "ui", size = 16, color = "subtext" },
    mono = { font = "mono", size = 12 },
    big = { font = "mono", size = 20 },

    hintKey = { font = "ui", size = 11, lineHeight = 15, pin = false },
    hintLabel = { font = "ui", size = 12, lineHeight = 16, pin = false, color = "subtext",
                  frameY = 3, extraW = 4 },
    cheat = { font = "ui", size = 16, lineHeight = 20, pin = false },
    cheatTitle = { font = "ui", size = 16, lineHeight = 20, pin = false, color = "subtext" },
    toast = { font = "mono", size = 18, lineHeight = 24, pin = false },
    report = { font = "ui", size = 16, lineHeight = 22, pin = false },
    reportDetail = { font = "ui", size = 14, lineHeight = 20, pin = false },
    empty = { font = "ui", size = 13, lineHeight = 20.8, pin = false, color = "quiet" },
  },

  -- sm and lg are the hint bar's two gaps, eight between lines and sixteen between hints,
  -- added in stage two beside the scale they fall between.
  space = { xs = 2, s = 6, sm = 8, m = 10, l = 14, lg = 16, xl = 20 },

  -- surface and badge are overwritten from settings by the spec, and these two are only what
  -- an unconfigured kit draws, square chrome and the cheat sheet's own default badge radius.
  -- swatch is the colour toast's swatch corner, kept apart from badge since the badge radius
  -- follows a setting and the swatch never did.
  radius = { surface = 0, badge = 5, chip = 6, swatch = 5 },

  -- muted is the report toast's alpha for a row naming something that was not there, added
  -- in stage two beside the two the design names.
  alpha = { dim = 0.4, fade = 0.55, muted = 0.5 },

  -- swatch is the colour toast's square, the one size the toast draws that no icon shares.
  icon = { row = 28, list = 28, sheet = 32, swatch = 26 },

  -- The three badge sizes badge(key, size) names. Not in the design's token list, which
  -- names the sizes but not where their geometry lives, so they sit here beside the other
  -- geometry rather than as literals inside the layout engine. Each holds its height, its
  -- padding either side of the glyph, and the text variant the glyph is drawn in. Three
  -- fields are optional. minWidth is the narrowest the chip may be, the height when absent,
  -- so a lone glyph stays square. textY moves the glyph frame down from where centring its
  -- line box would put it. radius names the radius token the chip is rounded with, badge
  -- when absent.
  --
  -- Every value is what stage two found each surface drawing. cheat is the cheat sheet chip,
  -- 28 high with 10 of padding, its glyph in the cheat sheet's own type. hint is the hint bar
  -- chip, 18 high with 6 of padding, its glyph in the ui font at 11, and with no minimum,
  -- since the bar never had one. button is the report toast's Dismiss chip, 28 high with 12
  -- of padding, rounded at the chip radius.
  badge = {
    cheat = { height = 28, padX = 10, text = "cheat", textY = 1 },
    hint = { height = 18, padX = 6, text = "hintKey", minWidth = 0, textY = 1 },
    button = { height = 28, padX = 12, text = "reportDetail", textY = 2, radius = "chip" },
  },
}

-- Every colour role a resolved table answers, the design's list, kept here because the kit
-- refuses a colour name outside it at build time and the names are this file's to own.
local COLOR_ROLES = {
  "foreground", "subtext", "dim", "overlay", "accent", "note", "path",
  "background", "surface", "border", "selection", "highlight", "badge",
  "quiet", "outline",
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
        pin = variant.pin ~= false,
        frameY = variant.frameY or 0,
        extraW = variant.extraW or 0,
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
