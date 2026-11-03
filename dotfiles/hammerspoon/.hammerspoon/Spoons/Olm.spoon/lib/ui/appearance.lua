-- The look a person picks, answered for whichever chooser is serving.
--
-- Each chooser provider says how far it can be themed, in its own appearance table, and this is
-- the one reader of that table. The root builds it once for the chosen provider and the Olm
-- Theme list asks it, so neither the list nor the root ever names a provider, and one provider
-- never learns that another exists. Two kinds are understood.
--
--   themes     every theme file a person keeps under config/themes, the whole of every role.
--              The canvas chooser declares this, and the store it is handed does all the work.
--   highlight  the provider's own fixed palette, one theme file it carries, and a short list of
--              choices that change only the highlight role. The glass chooser declares this,
--              since its palette is Apple's own semantic colours and a full theme over glass
--              only fights the glass. A choice whose highlight is "system" takes the accent
--              colour a person set in System Settings, the one a menu fills its selected item
--              with, solid unless the provider names an alpha.
--
-- The appearance table a provider declares.
--   kind        "themes" or "highlight".
--   label       what the Olm Theme list's field says, Canvas Theme or Glass Highlight.
--   default     highlight only, the name of the choice used before one is made.
--   settingsKey highlight only, the hs.settings key the choice persists under.
--   alpha       highlight only, optional, the alpha of the system colour, two hex digits.
--   choices     highlight only, a list of { name, title, highlight }, highlight being "system"
--               or nil for the palette's own.
--
-- Everything outside plain Lua is injected, which is what lets the unit load with no hs.
--   declared    the provider's appearance table, nil reading as themes.
--   themes      the theme store over config/themes, lib/ui/themes.lua.
--   palette     highlight only, a theme store over the provider's own palette file.
--   store       a table with get and set, hs.settings in the running config.
--   accent      a function answering the system accent as "#rrggbb", nil when it cannot.
--   apply       a function of colours that hands the kit a new spec, as a theme switch does.
--   log         a table with w.

local M = {}

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

function M.new(opts)
  opts = opts or {}
  local declared = opts.declared or { kind = "themes" }
  local log = opts.log or { w = function(message) print(message) end }
  local store = opts.store or { get = function() return nil end, set = function() end }
  local instance = {}

  if declared.kind ~= "highlight" then
    local themes = assert(opts.themes, "appearance, a themes kind needs a themes store")
    function instance.label() return declared.label or "Theme" end
    function instance.names() return themes.names() end
    function instance.current() return themes.current() end
    function instance.colors() return themes.colors() end
    function instance.set(name) return themes.set(name) end
    function instance.refresh() return false end
    return instance
  end

  local palette = assert(opts.palette, "appearance, a highlight kind needs its palette store")
  local choices = declared.choices or {}
  local byTitle, byName = {}, {}
  for _, choice in ipairs(choices) do
    byTitle[choice.title] = choice
    byName[choice.name] = choice
  end

  local function chosen()
    local name = store.get(declared.settingsKey)
    if name ~= nil and byName[name] == nil then
      log.w("the stored highlight " .. tostring(name) .. " is not one this chooser offers, so "
        .. tostring(declared.default) .. " is used")
      name = nil
    end
    return byName[name or declared.default] or choices[1]
  end

  function instance.label() return declared.label or "Highlight" end

  --- instance.names() -> the choices' titles, in the order the provider declared them.
  function instance.names()
    local out = {}
    for _, choice in ipairs(choices) do out[#out + 1] = choice.title end
    return out
  end

  function instance.current()
    local choice = chosen()
    return choice and choice.title or nil
  end

  --- instance.colors() -> { dark, light }, the palette with the highlight the choice names.
  --- A system accent the machine cannot answer leaves the palette's own highlight.
  function instance.colors()
    local base = palette.colors()
    local choice = chosen()
    if not (choice and choice.highlight == "system" and opts.accent) then return base end
    local hex = opts.accent()
    if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then return base end
    local out = { dark = copy(base.dark), light = copy(base.light) }
    local tinted = hex .. (declared.alpha or "")
    out.dark.highlight, out.light.highlight = tinted, tinted
    return out
  end

  --- instance.set(title) -> bool. Persists the choice and applies it at once.
  function instance.set(title)
    local choice = byTitle[title] or byName[title]
    if not choice then
      log.w("set refused the highlight " .. tostring(title) .. ", this chooser does not offer it")
      return false
    end
    store.set(declared.settingsKey, choice.name)
    if opts.apply then opts.apply(instance.colors()) end
    return true
  end

  --- instance.refresh() -> bool. Applies again when the live choice follows the system accent,
  --- for a change of accent in System Settings, and answers whether it did.
  function instance.refresh()
    local choice = chosen()
    if not (choice and choice.highlight == "system") then return false end
    if opts.apply then opts.apply(instance.colors()) end
    return true
  end

  return instance
end

return M
