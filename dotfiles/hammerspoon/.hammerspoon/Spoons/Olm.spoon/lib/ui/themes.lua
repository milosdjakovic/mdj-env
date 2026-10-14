-- The colour themes the kit can wear, one file each, and the one that is current.
--
-- A theme is a TOML file named for itself, with a [dark] and a [light] section holding the
-- colour keys listed in KEYS below as "#rrggbb" or "#rrggbbaa". This store loads every file
-- in the directory the composition root hands it, answers the sorted names, the current
-- name and the colours of the current theme, and switches. It decides nothing about how a
-- colour reaches a surface, that stays root/uispec.lua and lib/ui/style.lua, so a switch is
-- a new spec handed to the kit and the next draw shows it, with no watcher anywhere.
--
-- Everything outside plain Lua is injected, which is what lets the unit load with no hs.
--   dir        the directory holding the theme files.
--   list       a function of a directory answering the file names in it.
--   read       a function of a path answering the text of a file, nil when it is not there.
--   settings   a table with get and set, hs.settings in the running config, a stub in a test.
--   ui         the kit, anything with a configure taking { spec = ... }.
--   specFor    a function of the current colours answering the style spec for the kit.
--   onChange   called with the new name and colours after a switch has been applied.
--   log        a table with w, a warning writer. Defaults to print.
--
-- A missing [light] half is the theme's own [dark] half. A missing or malformed required key
-- is the default theme's value for that half and one warning naming the theme and the key.
-- An unknown persisted name is the default theme and one warning, and it is left in the
-- store rather than rewritten, so a theme file that returns is picked up again.

local tomlLib = (function()
  local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
  local chunk, err = loadfile(here .. "toml.lua")
  if not chunk then error("Olm themes failed to load toml.lua, " .. tostring(err)) end
  return chunk()
end)()

local M = {}

M.DEFAULT = "default"
M.SETTINGS_KEY = "olmTheme"

-- The keys a theme must answer, and the two it may. The optional two are derived by the kit
-- when absent, a list cursor bar and a field selection.
M.REQUIRED = { "text", "subtext", "background", "border", "accent", "meta", "path", "note" }
M.OPTIONAL = { "highlight", "selection" }

local HALVES = { "dark", "light" }

local function validHex(value)
  if type(value) ~= "string" then return false end
  local digits = value:match("^#(%x+)$")
  return digits ~= nil and (#digits == 6 or #digits == 8)
end

local function sortedNames(set)
  local names = {}
  for name in pairs(set) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function M.new(opts)
  opts = opts or {}
  local log = opts.log or { w = function(message) print(message) end }
  local settings = opts.settings or { get = function() return nil end, set = function() end }
  local instance = {}
  local themes = {}      -- name to { dark = {...}, light = {...} }, raw as the file said
  local resolved = {}    -- name to the colours with every fallback applied, built on demand
  local warned = {}
  local currentName = M.DEFAULT

  local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    log.w(message)
  end

  --- instance.load() reads every theme file in the directory again. A file that cannot be
  --- read or holds a refused line is warned about once and left out, the others stand.
  function instance.load()
    themes, resolved = {}, {}
    if not opts.dir or not opts.list or not opts.read then return instance end
    for _, file in ipairs(opts.list(opts.dir) or {}) do
      local name = file:match("^(.+)%.toml$")
      if name then
        local ok, parsed = pcall(tomlLib.read, opts.dir .. "/" .. file, opts.read)
        if ok then
          themes[name] = { dark = parsed.dark, light = parsed.light }
        else
          warnOnce("file " .. name, "theme " .. name .. " is not loaded, " .. tostring(parsed))
        end
      end
    end
    local stored = settings.get(M.SETTINGS_KEY)
    if stored ~= nil and themes[stored] == nil then
      warnOnce("stored " .. tostring(stored), "the stored theme " .. tostring(stored)
        .. " has no file, so the " .. M.DEFAULT .. " theme is used")
      stored = nil
    end
    currentName = stored or M.DEFAULT
    return instance
  end

  -- One half of one theme with the fallbacks applied.
  local function halfOf(name, half)
    local theme = themes[name]
    local given = (theme and (theme[half] or theme.dark)) or {}
    local fallback = themes[M.DEFAULT] and (themes[M.DEFAULT][half] or themes[M.DEFAULT].dark) or {}
    local out = {}
    for _, key in ipairs(M.REQUIRED) do
      local value = given[key]
      if not validHex(value) then
        if value ~= nil then
          warnOnce(name .. "/" .. half .. "/" .. key .. "/bad", "theme " .. name .. ", " .. half
            .. " key " .. key .. " is not a #rrggbb or #rrggbbaa colour, so the default theme's is used")
        elseif name ~= M.DEFAULT then
          warnOnce(name .. "/" .. half .. "/" .. key, "theme " .. name .. " has no " .. half
            .. " key " .. key .. ", so the default theme's is used")
        end
        value = fallback[key]
      end
      out[key] = value
    end
    for _, key in ipairs(M.OPTIONAL) do
      if validHex(given[key]) then
        out[key] = given[key]
      elseif given[key] ~= nil then
        warnOnce(name .. "/" .. half .. "/" .. key .. "/bad", "theme " .. name .. ", " .. half
          .. " key " .. key .. " is not a #rrggbb or #rrggbbaa colour, so it is derived")
      end
    end
    return out
  end

  --- instance.names() -> the theme names, sorted.
  function instance.names()
    return sortedNames(themes)
  end

  --- instance.current() -> the name of the live theme.
  function instance.current()
    return currentName
  end

  --- instance.colors(name) -> { dark = {key = hex}, light = {key = hex} } for the named
  --- theme, the current one with no name given. A theme that is not loaded answers the
  --- default theme's colours.
  function instance.colors(name)
    name = name or currentName
    if themes[name] == nil then name = M.DEFAULT end
    if not resolved[name] then
      local built = {}
      for _, half in ipairs(HALVES) do built[half] = halfOf(name, half) end
      resolved[name] = built
    end
    return resolved[name]
  end

  --- instance.set(name) -> bool
  --- Makes a loaded theme current, persists it under the hs.settings key olmTheme, hands the
  --- kit the new spec and calls onChange. A name with no file is refused with a warning and
  --- changes nothing.
  function instance.set(name)
    if themes[name] == nil then
      log.w("set refused the theme " .. tostring(name) .. ", it has no file")
      return false
    end
    currentName = name
    settings.set(M.SETTINGS_KEY, name)
    local colors = instance.colors(name)
    if opts.ui and opts.specFor then opts.ui.configure({ spec = opts.specFor(colors) }) end
    if opts.onChange then opts.onChange(name, colors) end
    return true
  end

  return instance.load()
end

return M
