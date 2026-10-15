-- Reads config/icons.toml, the one place the active icon set is chosen. Two keys, set and
-- fallback, each the name of an icon source. Nothing else is configurable and a stray key is
-- named in a warning and ignored, the same stance as the typography file.
--
-- Pure Lua with no hs, the way lib/ui/toml.lua is, so a test loads it in plain Lua. The
-- composition root hands in the path and the reader and says which names are real sources, so
-- this file knows no source either.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local toml = assert(loadfile(here .. "../ui/toml.lua"))()

local M = {}

--- The shipped values, used for any key the file leaves out or gets wrong.
M.SHIPPED = { set = "emoji", fallback = "emoji" }

--- M.load(path, read, log, known) -> { set = string, fallback = string }
--- read is a function of a path answering the text or nil, log a table with w, known a function
--- of a name answering whether a source of that name exists. A path of nil, a file that is not
--- there or one that cannot be parsed is one warning and the shipped answer. A key that is not
--- a non empty string, or names no source, is one warning naming it and keeps its shipped value.
function M.load(path, read, log, known)
  log = log or { w = function(message) print(message) end }
  local out = { set = M.SHIPPED.set, fallback = M.SHIPPED.fallback }
  if path == nil then return out end
  local ok, parsed = pcall(toml.read, path, read)
  if not ok then
    log.w("icons are not loaded, " .. tostring(parsed) .. ", so the shipped icon set is used")
    return out
  end
  for section in pairs(parsed) do
    if section ~= "" then log.w("icons has an unknown section " .. section .. ", it is ignored") end
  end
  local given = parsed[""] or {}
  for key in pairs(given) do
    if M.SHIPPED[key] == nil then log.w("icons has an unknown key " .. key .. ", it is ignored") end
  end
  for key in pairs(M.SHIPPED) do
    local value = given[key]
    if value ~= nil then
      if type(value) ~= "string" or value == "" then
        log.w("icons " .. key .. " is not a source name, so the shipped " .. M.SHIPPED[key] .. " is used")
      elseif known and not known(value) then
        log.w("icons " .. key .. " is " .. value .. ", which no icon source answers to, so the shipped "
          .. M.SHIPPED[key] .. " is used")
      else
        out[key] = value
      end
    end
  end
  return out
end

--- M.order(config) -> array of source names, the active set first and the fallback after it,
--- without repeating a name, since drawing the same source twice finds nothing new.
function M.order(config)
  if config.fallback == config.set then return { config.set } end
  return { config.set, config.fallback }
end

return M
