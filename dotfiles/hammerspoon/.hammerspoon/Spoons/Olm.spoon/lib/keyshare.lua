-- What Olm.app is handed of the keys, step 5.1 of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-KEYS.md.
--
-- The keymap stays compiled here. This answers what the binder binds as plain data, the leaders in
-- use and every global row in the order the binder walks them, which the root writes to
-- ~/.olm/run/keymap.json for the app to resolve presses against. And it wraps the rows the binder
-- is handed so each run tells the app which row ran, the bridge notification keyFired, which the
-- app pairs with what it resolved. The keymap's own rows are never changed, so nothing else that
-- reads them, the launcher and the sheets, tells the app anything.
--
-- It is pure Lua, handed the binder's bindable test, the keycode table and the notify function, so
-- the dry gate tests it with no Hammerspoon.

local obj = {}

obj.VERSION = 1

local function rowId(row)
  return tostring(row.owner) .. "." .. tostring(row.action)
end

-- The modifiers a row binds on, as the binder hands them, nil for a catch all and the row's own
-- list otherwise, an empty list for a plain combo stating none.
local function boundMods(row)
  local mods = (not row.anyMods) and row.mods or nil
  if row.leader == nil then mods = mods or {} end
  if mods == nil then return nil end
  local out = {}
  for i, m in ipairs(mods) do out[i] = m end
  return out
end

--- obj.share(rows, leaders, deps) -> table
---   rows     the keymap's bound list.
---   leaders  the root's leader specs, each with name, held, keyCode, mods, inUse and policy.
---   deps     bindable, the binder's own test, and keycodes, a name to its code.
--- The leaders in use and every row the binder would bind, in its order. A row's leader is the name
--- a row spells it with, absent for a plain combo, and its mods absent for a catch all.
function obj.share(rows, leaders, deps)
  deps = deps or {}
  local keycodes = deps.keycodes or {}
  local out = { version = obj.VERSION, leaders = {}, rows = {} }
  for _, spec in ipairs(leaders or {}) do
    if spec.inUse then
      local mods
      if type(spec.mods) == "table" then
        mods = {}
        for i, m in ipairs(spec.mods) do mods[i] = m end
      end
      out.leaders[#out.leaders + 1] = {
        name = spec.name,
        held = spec.held and true or false,
        keyCode = spec.keyCode,
        mods = mods,
        ranked = (spec.policy or {}).ranked and true or false,
      }
    end
  end
  for _, row in ipairs(rows or {}) do
    if deps.bindable == nil or deps.bindable(row) then
      local key = type(row.key) == "string" and row.key:lower() or row.key
      out.rows[#out.rows + 1] = {
        id = rowId(row),
        leader = row.leader,
        key = row.key,
        keyCode = keycodes[key],
        mods = boundMods(row),
        gate = row.when,
        priority = row.priority,
        repeats = row.repeats and true or false,
        afterRelease = row.afterRelease and true or false,
      }
    end
  end
  return out
end

--- obj.wrap(rows, notify) -> rows
--- A copy of every row whose run first tells the app the row ran, notify("keyFired", {id = ...}),
--- then runs it with the arguments it was handed. A row with no run is copied as it is, and a raise
--- in notify never stops the action. The rows handed in are not changed.
function obj.wrap(rows, notify)
  local out = {}
  for i, row in ipairs(rows or {}) do
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    if type(row.run) == "function" and type(notify) == "function" then
      local run, id = row.run, rowId(row)
      copy.run = function(...)
        pcall(notify, "keyFired", { id = id })
        return run(...)
      end
    end
    out[i] = copy
  end
  return out
end

return obj
