-- The keymap's rows written as the key inventory's own lines.
--
-- test/keys.golden is what the engines hold, one line per bound chord. The keymap is built from
-- declarations and never looks at an engine, so writing its rows in the golden's format and
-- comparing the two is the proof the read model is complete. This is the one place that format
-- is spelled from rows, shared by the live probe and by the offline run, so the two cannot drift.
-- See keys-probe.lua for the six fields. A row has no owner list, so each row is one line.
--
-- It is pure Lua and touches no hs global.

local obj = {}

local HYPER = "hyper"
local HOTKEY = "hotkey"
local DASH = "-"

--- obj.engineLabel(leader, windowName) -> string
--- The engine word the probe gives a leader. A plain combo has none and is hotkey. The app
--- leader is hyper. The window leader wears its catalog name as the person's config spells it,
--- found by lowercasing, since a row carries the catalog name lowercased.
function obj.engineLabel(leader, windowName)
  if leader == nil then return HOTKEY end
  if leader == HYPER then return HYPER end
  if windowName and windowName:lower() == leader then return windowName end
  return leader
end

local function modsWord(row)
  if row.anyMods then return "any" end
  if #row.mods == 0 then return "none" end
  return table.concat(row.mods, "+")
end

--- obj.line(row, windowName) -> string
function obj.line(row, windowName)
  return table.concat({
    obj.engineLabel(row.leader, windowName), row.key, modsWord(row), row.when or DASH,
    row.priority ~= nil and tostring(row.priority) or DASH, tostring(row.owner),
  }, "\t")
end

--- obj.project(rows, windowName) -> sorted list of lines
function obj.project(rows, windowName)
  local lines = {}
  for _, row in ipairs(rows) do lines[#lines + 1] = obj.line(row, windowName) end
  table.sort(lines)
  return lines
end

return obj
