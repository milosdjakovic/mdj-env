-- A one shot note the root leaves for the next load, written just before a reload it asked for
-- and taken once at the end of the load that follows.
--
-- A reload replaces the whole Lua state, so anything a person was looking at is gone, and the
-- only thing that survives is hs.settings. The note carries at most two things. open says which
-- registered tool to present again, the child path to walk inside it and the row to highlight,
-- so a person who asked for the reload lands where they were. notify is one routine line to say
-- once the load is done, for a reload the person did not watch happen. Whoever writes a note
-- describes its own place, so the root names no tool and this module knows none.
--
-- Pure. The store arrives as three injected functions, so the unit case drives exactly this code
-- with a table and nothing here touches the running config.

local M = {}

-- Namespaced under Olm, the same reason the switch's own key is.
M.KEY = "Olm.resume"

-- A step or a highlight is a flat table of plain values, since it crosses hs.settings and is
-- matched field by field against a row's item. Anything else would not survive the trip or
-- could not be compared.
local function flat(t)
  if type(t) ~= "table" then return false end
  for k, v in pairs(t) do
    local kind = type(v)
    if type(k) ~= "string" or not (kind == "string" or kind == "number" or kind == "boolean") then
      return false
    end
  end
  return true
end

--- M.valid(note) -> bool
--- Whether note has the shape this module writes, an optional open with a string tool, a list of
--- flat steps and an optional flat highlight, and an optional string notify, at least one of the
--- two present.
function M.valid(note)
  if type(note) ~= "table" then return false end
  if note.notify ~= nil and type(note.notify) ~= "string" then return false end
  local open = note.open
  if open ~= nil then
    if type(open) ~= "table" or type(open.tool) ~= "string" or open.tool == "" then return false end
    if open.path ~= nil then
      if type(open.path) ~= "table" then return false end
      for _, step in ipairs(open.path) do
        if not flat(step) then return false end
      end
    end
    if open.highlight ~= nil and not flat(open.highlight) then return false end
  end
  return open ~= nil or note.notify ~= nil
end

--- M.write(store, note) -> bool
--- Leaves note for the next load, answering false and writing nothing when note is not valid.
--- store carries write(value).
function M.write(store, note)
  if not M.valid(note) then return false end
  store.write(note)
  return true
end

--- M.take(store) -> note or nil
--- Reads the note and clears it before answering, so a load that fails while acting on it does
--- not act on it again on every reload after. A note of the wrong shape is cleared and ignored.
--- store carries read() and clear().
function M.take(store)
  local note = store.read()
  if note == nil then return nil end
  store.clear()
  if not M.valid(note) then return nil end
  return note
end

return M
