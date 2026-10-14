-- What the current look is. One style spec arrives at configure time and every call to
-- tokens answers a resolved table for the half the system is on right now, so a pane that
-- asks on every draw tracks the light and dark switch without a watcher of its own.
--
-- This is the only file in the kit that asks hs.host.interfaceStyle, and the call is
-- injected through M.new, so the unit loads and resolves in plain Lua with no hs at all.
-- When nothing is injected the real call is made, and only at the moment tokens is asked,
-- never at load.
--
-- The spec carries the colours of each half, which the current theme file supplies, and the
-- two radii settings owns, and this file carries everything else as its shipped values
-- below. A spec field always wins over a shipped one. Colours arrive either as "#RRGGBB" or
-- "#RRGGBBAA" strings, which is how a theme file spells them, or as hs colour tables, and
-- both come back out as colour tables.
--
-- The shipped colours below are only the fallback for a theme that leaves a role out. Stage
-- four of the kit retires the preview four once the plugin panes draw through it.
--
-- theme-exempt, shipped fallbacks for a role a theme leaves out, retired in stage four
--
-- Four colours are derived rather than given, one rule each, so a spec never has to restate
-- them. dim is subtext at the dim alpha, selection is foreground at 0.20, highlight is
-- foreground at 0.14, and surface is background until the palette step gives it its own.

local tomlLib = (function()
  local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
  local chunk, err = loadfile(here .. "toml.lua")
  if not chunk then error("Olm style failed to load toml.lua, " .. tostring(err)) end
  return chunk()
end)()

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

-- The fonts and sizes of the five type roles, shipped. config/typography.toml overrides them
-- key by key, see M.loadTypography below, and anything it leaves out or gets wrong is the
-- value here. Only fonts and sizes are ever configured. The line height, the font each role
-- takes and the colour each role is drawn in are derived, one rule each, in ROLE_RULES.
local SHIPPED_TYPOGRAPHY = {
  fonts = { ui = ".AppleSystemUIFont", mono = ".AppleSystemUIFontMonospaced" },
  sizes = { title = 20, body = 16, caption = 14, section = 12, code = 14 },
}

--- M.roles, the five type roles in reading order. A text node names one of them as its
--- variant. They are derived, never configured, apart from the fonts and sizes above.
M.roles = { "title", "body", "caption", "section", "code" }

-- Which font token and which colour role each type role is drawn with. code is the mono
-- font and every other role the ui font. title, body and code draw in the foreground,
-- caption in subtext and section in overlay, which is the theme's meta colour. A text node
-- may still pass a colour role of its own to override. No role changes the case of its text,
-- since the kit applies no text transform of any kind, upper casing a section heading is
-- the caller's job.
local ROLE_RULES = {
  title = { font = "ui", color = "foreground" },
  body = { font = "ui", color = "foreground" },
  caption = { font = "ui", color = "subtext" },
  section = { font = "ui", color = "overlay" },
  code = { font = "mono", color = "foreground" },
}

-- Every token that is not a colour. Values come from the brief that settled stage one and
-- are what the tree draws today, where the tree agrees with itself.
local SHIPPED = {
  -- ui and mono here are the typography fonts, filled from SHIPPED_TYPOGRAPHY and the
  -- typography file when the table is built. legacyMono is the font the retiring variants
  -- below drew in before the typography existed, kept apart so they change nothing.
  fonts = { legacyMono = "Menlo" },

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
  --
  -- Every variant in this table is retiring, to be removed as each consumer migrates to the
  -- five type roles built from the typography below. title and body are already shadowed by
  -- the roles of the same name, which win, so the two entries here are never what a node
  -- resolves to, and they stay only so the list reads as it did.
  text = {
    title = { font = "ui", size = 16 }, -- retiring, shadowed by the title role
    body = { font = "ui", size = 14 }, -- retiring, shadowed by the body role
    sub = { font = "ui", size = 12 }, -- retiring
    label = { font = "legacyMono", size = 11 }, -- retiring
    heading = { font = "ui", size = 16, color = "subtext" }, -- retiring
    mono = { font = "legacyMono", size = 12 }, -- retiring
    big = { font = "legacyMono", size = 20 }, -- retiring

    hintKey = { font = "ui", size = 11, lineHeight = 15, pin = false },
    hintLabel = { font = "ui", size = 12, lineHeight = 16, pin = false, color = "subtext",
                  frameY = 3, extraW = 4 },
    cheat = { font = "ui", size = 16, lineHeight = 20, pin = false },
    cheatTitle = { font = "ui", size = 16, lineHeight = 20, pin = false, color = "subtext" },
    toast = { font = "legacyMono", size = 18, lineHeight = 24, pin = false },
    report = { font = "ui", size = 16, lineHeight = 22, pin = false },
    reportDetail = { font = "ui", size = 14, lineHeight = 20, pin = false },
    empty = { font = "ui", size = 13, lineHeight = 20.8, pin = false, color = "quiet" },
    -- The parity group above is retiring as well, each variant going with its surface.
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
  text = (function()
    local out = keysOf(SHIPPED.text)
    for _, role in ipairs(M.roles) do out[role] = true end
    return out
  end)(),
  roles = M.roles,
  space = keysOf(SHIPPED.space),
  icon = keysOf(SHIPPED.icon),
  badge = keysOf(SHIPPED.badge),
}

-- The one line height rule, ceil of size times 1.35, unless a retiring variant states its own.
-- A type role never states one.
local function lineHeightFor(size)
  return math.ceil(size * 1.35)
end

-- A "#rrggbb" string, or "#rrggbbaa" when a theme file gives an alpha, as a colour table.
local function hexColor(hex)
  local r, g, b, a = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  if not r or #a == 1 then return nil end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = a ~= "" and tonumber(a, 16) / 255 or 1.0 }
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

local function positiveNumber(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

--- M.loadTypography(path, read, log) -> { fonts = {...}, sizes = {...} }
--- Reads the typography file with lib/ui/toml.lua and answers only the keys that are valid,
--- which the spec then lays over the shipped values. read is a function of a path answering
--- the text or nil, log a table with w. A path of nil, a file that is not there or cannot be
--- parsed is one warning and an empty answer. A missing key, an unknown key, a font that is
--- not a non empty string and a size that is not a positive number are each one warning
--- naming the key, and that key keeps its shipped value.
function M.loadTypography(path, read, log)
  log = log or { w = function(message) print(message) end }
  local out = { fonts = {}, sizes = {} }
  if path == nil then return out end
  local ok, parsed = pcall(tomlLib.read, path, read, { numbers = true })
  if not ok then
    log.w("typography is not loaded, " .. tostring(parsed) .. ", so the shipped fonts and sizes are used")
    return out
  end
  for section in pairs(parsed) do
    if section ~= "" and section ~= "fonts" and section ~= "sizes" then
      log.w("typography has an unknown section " .. section .. ", it is ignored")
    end
  end
  if parsed[""] and next(parsed[""]) ~= nil then
    for key in pairs(parsed[""]) do
      log.w("typography key " .. key .. " is outside a section, it is ignored")
    end
  end
  for _, section in ipairs({ "fonts", "sizes" }) do
    local given = parsed[section] or {}
    for key in pairs(given) do
      if SHIPPED_TYPOGRAPHY[section][key] == nil then
        log.w("typography has an unknown key " .. section .. "." .. key .. ", it is ignored")
      end
    end
    for key in pairs(SHIPPED_TYPOGRAPHY[section]) do
      local value = given[key]
      local valid
      if section == "fonts" then
        valid = type(value) == "string" and value ~= ""
      else
        valid = positiveNumber(value)
      end
      if value == nil then
        log.w("typography has no " .. section .. "." .. key .. ", so the shipped "
          .. tostring(SHIPPED_TYPOGRAPHY[section][key]) .. " is used")
      elseif not valid then
        log.w("typography " .. section .. "." .. key .. " is " .. tostring(value) .. ", which is not "
          .. (section == "fonts" and "a font name" or "a positive number")
          .. ", so the shipped " .. tostring(SHIPPED_TYPOGRAPHY[section][key]) .. " is used")
      else
        out[section][key] = value
      end
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
  -- The resolved table per half, built once per configure. Cleared by configure.
  local cache = {}

  --- instance.configure(newSpec)
  --- Takes the whole spec, replacing any earlier one, since the composition root builds it
  --- once from policy and has nothing to merge.
  ---   colors   { dark = { role = colour }, light = { role = colour } }, light optional
  ---   typography { fonts = { ui, mono }, sizes = { title ... code } }, validated, see
  ---            M.loadTypography, laid over the shipped fonts and sizes of the type roles
  ---   fonts, text, space, radius, alpha, icon, badge, each optional and merged over the
  ---            shipped values one level down
  function instance.configure(newSpec)
    spec = newSpec or {}
    cache = {}
    return instance
  end

  --- instance.half() -> "dark" | "light", which half the system is on now.
  function instance.half()
    return appearance() == "Dark" and M.halves.dark or M.halves.light
  end

  --- instance.tokens() -> the resolved token table for the current half.
  --- Built once per half after each configure and handed out as a shallow copy, so a caller
  --- may replace a top level field of what it receives. The groups inside are shared, so a
  --- caller that changes one, a colour or a text variant, copies that group first. The light
  --- half falls back to the dark half role by role when the spec gives no light colours.
  function instance.tokens()
    local half = instance.half()
    local built = cache[half]
    if not built then
      built = instance._build(half)
      cache[half] = built
    end
    return copy(built)
  end

  -- Resolves the table for one half from the spec and the shipped values.
  function instance._build(half)
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

    local typography = mergeGroup(SHIPPED_TYPOGRAPHY, spec.typography)
    local fonts = mergeGroup(SHIPPED.fonts, typography.fonts)
    fonts = mergeGroup(fonts, spec.fonts)
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
    -- The five type roles are derived from the typography and win over a retiring variant
    -- of the same name.
    for _, role in ipairs(M.roles) do
      local rule = ROLE_RULES[role]
      local size = typography.sizes[role]
      text[role] = {
        font = fonts[rule.font],
        size = size,
        lineHeight = lineHeightFor(size),
        color = rule.color,
        pin = true,
        frameY = 0,
        extraW = 0,
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
