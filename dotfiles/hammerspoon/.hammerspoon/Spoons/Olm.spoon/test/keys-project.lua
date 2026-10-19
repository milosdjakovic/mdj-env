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

--------------------------------------------------------------------------------
-- What was bound, as the same lines
--------------------------------------------------------------------------------

local MOD_NAMES = {
  shift = "shift", ctrl = "ctrl", control = "ctrl", alt = "alt", option = "alt", opt = "alt",
  cmd = "cmd", command = "cmd",
}

-- The same spelling lib/keymap.lua gives, written again here so this file stays loadable beside
-- a copy of an older spoon whose keymap module may differ. A table that knows the key gives its
-- own name for it, anything else is lowercased.
local function keyName(key, keycodes)
  if type(keycodes) == "table" then
    local code = type(key) == "number" and key or (type(key) == "string" and keycodes[key:lower()])
    if type(code) == "number" then
      local name = keycodes[code]
      if type(name) == "string" then return name end
      return "code" .. tostring(code)
    end
  end
  if type(key) == "string" then return key:lower() end
  return tostring(key)
end

-- nil is a catch all, an empty list demands no modifier, which are two different bindings.
local function modsText(mods)
  if mods == nil then return "any" end
  local seen, list = {}, {}
  for _, m in ipairs(mods) do
    local canon = MOD_NAMES[tostring(m):lower()] or tostring(m):lower()
    if not seen[canon] then seen[canon] = true list[#list + 1] = canon end
  end
  if #list == 0 then return "none" end
  table.sort(list)
  return table.concat(list, "+")
end

--- obj.boundLines(calls, rows, windowName, keycodes, fnOwner, ordered) -> list of lines
--- One line per recorded bind call, the engine, the key, the modifiers, the gate and the
--- priority as the call carried them. A call carries no owner, so the owner is found the way
--- the live probe finds it, by crossing the call with the keymap rows declaring that chord,
--- plus a match of the bound function against what the registry holds. Two owners on one chord
--- are joined with a bar, and none is a question mark.
---
--- Sorted as plain strings by default, which is the golden's own order. With ordered set, the
--- lines are grouped by engine and key and each group keeps the order the calls were made in,
--- since two bindings on one key are resolved by that order and only by that order. A list's
--- own keys are the exception. The root binds them by walking its contexts with pairs, whose
--- order Lua does not promise from one run to the next, and each sits under its own gate, so
--- within a group they are written sorted after the global keys. A list key bound before a
--- global key in the same group would change which one an engine meets first, so that case is
--- written as a line of its own beginning ORDER, which a comparison then shows.
function obj.boundLines(calls, rows, windowName, keycodes, fnOwner, ordered)
  local declared = {}
  local function id(engine, key, mods, when)
    return table.concat({ engine, key, mods, when or DASH }, "|")
  end
  for _, row in ipairs(rows or {}) do
    local k = id(obj.engineLabel(row.leader, windowName), row.key, modsWord(row), row.when)
    declared[k] = declared[k] or {}
    declared[k][tostring(row.owner)] = true
  end

  local entries = {}
  for i, call in ipairs(calls or {}) do
    local engine = HOTKEY
    if call.engine == "hyper" then engine = HYPER
    elseif call.engine == "window" then engine = windowName or "window" end
    local key, mods = keyName(call.key, keycodes), modsText(call.mods)
    local names = {}
    for owner in pairs(declared[id(engine, key, mods, call.when)] or {}) do names[owner] = true end
    -- The live probe cannot read a plain combo's handler, so its owner comes from the
    -- declarations alone, and this does the same so the two agree.
    if engine ~= HOTKEY and call.fn and fnOwner and fnOwner[call.fn] then names[fnOwner[call.fn]] = true end
    local list = {}
    for owner in pairs(names) do list[#list + 1] = owner end
    table.sort(list)
    local owner = #list > 0 and table.concat(list, "|") or "?"
    entries[#entries + 1] = {
      group = engine .. "\t" .. key, index = i, context = call.when ~= nil,
      line = table.concat({ engine, key, mods, call.when or DASH,
        call.priority ~= nil and tostring(call.priority) or DASH, owner }, "\t"),
    }
  end

  local lines = {}
  if ordered then
    local firstContext = {}
    for _, e in ipairs(entries) do
      if e.context and (firstContext[e.group] == nil or e.index < firstContext[e.group]) then
        firstContext[e.group] = e.index
      end
    end
    for _, e in ipairs(entries) do
      if not e.context and firstContext[e.group] and firstContext[e.group] < e.index then
        lines[#lines + 1] = "ORDER\t" .. e.group .. "\ta list key was bound before " .. e.line
      end
    end
    table.sort(entries, function(a, b)
      if a.group ~= b.group then return a.group < b.group end
      if a.context ~= b.context then return not a.context end
      if a.context then return a.line < b.line end
      return a.index < b.index
    end)
  else
    table.sort(entries, function(a, b) return a.line < b.line end)
  end
  for _, e in ipairs(entries) do lines[#lines + 1] = e.line end
  return lines
end

return obj
