-- The key names Olm reads a keymap row with, Hammerspoon's own table and the few keys it does not
-- name.
--
-- hs.keycodes.map holds name to code and code to name in one table, and every keymap row, leader
-- binding and list key is read against it. It has no name for the Globe key, which macOS posts
-- as code 179 when fn is tapped alone, measured through kanata on 2026-10-25, a tap arriving as
-- fn down and up followed by a key down of this code, and a hold of fn arriving with none. That
-- key can be bound like any other, an hs.hotkey on code 179 with no modifiers fires on each tap,
-- measured on 2026-10-26, so all it lacked was a name a row can spell.
--
-- A key named here is also standalone, a key no app reads as typing, so a keymap row may bind it
-- with neither a leader nor a modifier. Every other key needs one or the other, since a bare key
-- bound globally would be taken from every app, see placeOfRow in lib/keymap.lua.
--
-- It is pure Lua over the table it is handed, so a plain test builds it over a stub.

local M = {}

-- The keys Hammerspoon does not name, each name to its code.
local EXTRA = {
  globe = 179,
}

--- M.new(base) -> table
--- A key table answering exactly as base does, name to code and code to name, with the keys
--- above added both ways. base is hs.keycodes.map in the running config.
function M.new(base)
  local extra = {}
  for name, code in pairs(EXTRA) do
    extra[name] = code
    extra[code] = name
  end
  return setmetatable(extra, { __index = base })
end

--- M.standalone(key) -> boolean
--- Whether a key, by name or code, is one no app reads as typing, which a row may bind bare.
function M.standalone(key)
  if type(key) == "string" then return EXTRA[key:lower()] ~= nil end
  for _, code in pairs(EXTRA) do
    if code == key then return true end
  end
  return false
end

return M
