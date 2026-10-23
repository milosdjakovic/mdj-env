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
-- The shipped colours below are only the fallback for a theme that leaves a role out. They
-- are the default theme's own values, so a theme file that is missing or wrong still draws
-- the look Olm has always had.
--
-- theme-exempt, shipped fallbacks for a role a theme leaves out, the default theme's own values
--
-- There are exactly eight colour roles and nothing derives a ninth. The text pair is
-- foreground and subtext, the fill of every panel is background, border is every outline and
-- divider and a graph baseline, highlight is the bar under the list cursor, the tint behind
-- selected text and the fill of a key chip, and primary, secondary and tertiary are the three
-- accents, ranks that carry no meaning. An alpha a rule needs, such as the dim alpha of a
-- disabled row, stays an alpha below and is never a role. See "Olm colour, eight roles and
-- nothing else" in the config's AGENTS.md.

local tomlLib = (function()
  local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
  local chunk, err = loadfile(here .. "toml.lua")
  if not chunk then error("Olm style failed to load toml.lua, " .. tostring(err)) end
  return chunk()
end)()

local M = {}

-- The half names the resolver answers and the spec is keyed by.
M.halves = { dark = "dark", light = "light" }

-- Shipped colours, used only where the spec says nothing. They are config/themes/default.toml
-- written as hex, and the light half carries every role of its own, so no role falls through
-- to the dark half's value on a light page.
local SHIPPED_COLORS = {
  dark = {
    foreground = "#ebebeb",
    subtext = "#8c8c8c",
    background = "#29292e",
    border = "#59575c",
    highlight = "#454549",
    primary = "#a58be0",
    secondary = "#6fc7a0",
    tertiary = "#d9a066",
  },
  light = {
    foreground = "#262626",
    subtext = "#6b6b6b",
    background = "#cecace",
    border = "#a09f9f",
    highlight = "#bbb7bb",
    primary = "#6a4cb8",
    secondary = "#2f7d5c",
    tertiary = "#a35f1a",
  },
}

-- The fonts and sizes of the five type roles, shipped. config/typography.toml overrides them
-- key by key, see M.loadTypography below, and anything it leaves out or gets wrong is the
-- value here. Only fonts and sizes are ever configured. The line height, the font each role
-- takes and the colour each role is drawn in are derived, one rule each, in ROLE_RULES.
local SHIPPED_TYPOGRAPHY = {
  fonts = { ui = ".AppleSystemUIFont", mono = ".AppleSystemUIFontMonospaced" },
  sizes = { title = 20, body = 16, caption = 14, section = 14, code = 14 },
}

--- M.roles, the five type roles in reading order. A text node names one of them as its
--- variant. They are derived, never configured, apart from the fonts and sizes above.
M.roles = { "title", "body", "caption", "section", "code" }

-- Which font token and which colour role each type role is drawn with. code is the mono
-- font and every other role the ui font. title, body and code draw in the foreground, and
-- caption and section in subtext. A text node
-- may still pass a colour role of its own to override. No role changes the case of its text,
-- since the kit applies no text transform of any kind, upper casing a section heading is
-- the caller's job.
local ROLE_RULES = {
  title = { font = "ui", color = "foreground" },
  body = { font = "ui", color = "foreground" },
  caption = { font = "ui", color = "subtext" },
  section = { font = "ui", color = "subtext" },
  code = { font = "mono", color = "foreground" },
}

-- Every token that is not a colour. The type is not here, the five roles above are the only
-- text there is and they are built from the typography when the table is resolved.
local SHIPPED = {
  -- ui and mono here are the typography fonts, filled from SHIPPED_TYPOGRAPHY and the
  -- typography file when the table is built.
  fonts = {},

  -- sm and lg were the retired hint bar's two gaps, eight between lines and sixteen between
  -- hints, added in stage two beside the scale they fall between and still used elsewhere.
  space = { xs = 2, s = 6, sm = 8, m = 10, l = 14, lg = 16, xl = 20 },

  -- surface is the one corner a person sets, overwritten from settings by the spec, square for
  -- an unconfigured kit. Every other corner is derived from it, see radius.nested below, so a
  -- square surface squares everything drawn inside it.
  radius = { surface = 0 },

  -- border is the one border width, overwritten from settings by the spec, and every outline
  -- and divider takes it. graph is the weight of a data line in a pane's graph, which is a mark
  -- rather than a border and so has a width of its own.
  stroke = { border = 1, graph = 1.5 },

  -- muted is the report toast's alpha for a row naming something that was not there, added
  -- in stage two beside the two the design names.
  alpha = { dim = 0.4, fade = 0.55, muted = 0.5 },

  -- swatch is the colour toast's square, the one size the toast draws that no icon shares.
  icon = { row = 28, list = 28, sheet = 32, swatch = 26 },
}

-- The three badge sizes badge(key, size) names, as rules rather than numbers. A badge is its
-- glyph's line box with space around it, so its height is the line height of the type role
-- the glyph is drawn in plus twice padY, and the padding either side of the glyph is padX,
-- both names of the space scale. Nothing here states a point value, so a size changed in
-- config/typography.toml reflows every chip. cheat is the cheat sheet chip, its glyph in
-- body. hint is the action bar chip, its glyph in section, with no minimum width since the
-- hint bar it came from never had one. button is the report toast's Dismiss chip, its word in caption, rounded at
-- the chip radius. minWidth is the narrowest the chip may be, the height when absent, so a
-- lone glyph stays square. radius names the radius token the chip is rounded with, badge
-- when absent.
-- The one inset every surface pads its content by, the chooser's list margin, a row, the field
-- and every pane, asked for on 2026 10 14 so the space around content is the same everywhere.
-- x and y are names of the space scale, y the smaller of the two. y is measured to the letters,
-- from a capital's top and from the last baseline, rather than to a line box, since a line box
-- carries leading that grows with the size and would make the same inset look different around
-- a field and a row.
local INSET_RULE = { x = "l", y = "m" }

local BADGE_RULES = {
  cheat = { role = "body", padY = "s", padX = "m", radius = "nested" },
  hint = { role = "section", padY = "xs", padX = "s", minWidth = 0, radius = "nested" },
  button = { role = "caption", padY = "s", padX = "l", radius = "nested" },
}

-- Every colour role a resolved table answers, the eight and no others, kept here because the
-- kit refuses a colour name outside it at build time and the names are this file's to own. A
-- name from before the merge, dim or path or badge and the rest, fails loudly for that reason.
local COLOR_ROLES = {
  "foreground", "subtext", "background", "border", "highlight",
  "primary", "secondary", "tertiary",
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
    local out = {}
    for _, role in ipairs(M.roles) do out[role] = true end
    return out
  end)(),
  roles = M.roles,
  space = keysOf(SHIPPED.space),
  -- hint joins the shipped sizes, derived rather than shipped, see the build below.
  icon = (function()
    local out = keysOf(SHIPPED.icon)
    out.hint = true
    return out
  end)(),
  badge = keysOf(BADGE_RULES),
}

-- The one line height rule, ceil of size times 1.35. A type role never states one.
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
--- M.nestedRadius(outer, gap) -> the corner radius for a shape sitting gap points inside a
--- shape rounded by outer, the outer radius less the gap and never below square, so both
--- corners share one centre and the inner one reads as fitting the outer one.
function M.nestedRadius(outer, gap)
  return math.max(0, (outer or 0) - (gap or 0))
end

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
  ---   fonts, space, radius, alpha, icon, badge, each optional and merged over the
  ---            shipped or derived values one level down
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
  --- half falls back to the dark half's colours when the spec gives no light colours.
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

    -- Each half starts from its own shipped colours, then takes the spec. Only the eight
    -- roles are read from the spec, so a stray key a caller passes never becomes a colour.
    local resolved = {}
    local shipped = SHIPPED_COLORS[half] or SHIPPED_COLORS.dark
    for _, role in ipairs(COLOR_ROLES) do
      resolved[role] = toColor(given[role]) or toColor(shipped[role])
    end

    local alpha = mergeGroup(SHIPPED.alpha, spec.alpha)

    local typography = mergeGroup(SHIPPED_TYPOGRAPHY, spec.typography)
    local fonts = mergeGroup(SHIPPED.fonts, typography.fonts)
    fonts = mergeGroup(fonts, spec.fonts)
    local text = {}
    -- The five type roles are derived from the typography, the font and colour by the rule
    -- of the role and the line height by the one line height rule.
    for _, role in ipairs(M.roles) do
      local rule = ROLE_RULES[role]
      local size = typography.sizes[role]
      text[role] = {
        font = fonts[rule.font],
        size = size,
        lineHeight = lineHeightFor(size),
        color = rule.color,
      }
    end

    local space = mergeGroup(SHIPPED.space, spec.space)
    local badges = {}
    for name, rule in pairs(BADGE_RULES) do
      badges[name] = {
        height = text[rule.role].lineHeight + 2 * space[rule.padY],
        padX = space[rule.padX],
        text = rule.role,
        minWidth = rule.minWidth,
        radius = rule.radius,
      }
    end

    local inset = { x = space[INSET_RULE.x], y = space[INSET_RULE.y] }
    local radius = mergeGroup(SHIPPED.radius, spec.radius)
    -- pad is what every panel and pane pads its content by, one value on all four sides, so
    -- content sits as far from the bottom edge as from the sides. inset.y stays the text inset
    -- inside a chooser row. nested is the corner of anything held against a panel's edge.
    local pad = inset.x
    radius.nested = M.nestedRadius(radius.surface, pad)

    return {
      half = half,
      colors = resolved,
      fonts = fonts,
      text = text,
      space = space,
      radius = radius,
      alpha = alpha,
      icon = (function()
        -- hint is an icon drawn among the hint badges, the action bar's key button, as tall as
        -- the glyph line a hint badge carries, so it reflows with the section role's size.
        local icon = mergeGroup(SHIPPED.icon, spec.icon)
        if icon.hint == nil then icon.hint = text[BADGE_RULES.hint.role].lineHeight end
        return icon
      end)(),
      stroke = mergeGroup(SHIPPED.stroke, spec.stroke),
      badge = mergeGroup(badges, spec.badge),
      inset = inset,
      pad = pad,
    }
  end

  return instance
end

return M
