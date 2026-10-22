-- Turning a held leader's function key into a real keycode.
--
-- A held leader names a physical key, and lib/keyremap.lua says which spare function key that key
-- is remapped to. Nothing else here needs to know a physical key exists, it only needs the keycode
-- that function key resolves to once the mapping is applied, and that resolution has to happen in
-- exactly one place, because two call sites resolving the same key separately can drift the
-- moment one of them is edited and the other is not.
--
-- This module names no plugin, no engine, and no physical key. It is handed the function key the
-- root already asked the remap for, and it never calls the remap, addLeader, or anything else that
-- would make it a second place deciding wiring order.

local obj = {}

-- hs.keycodes.map turns the friendly function key name into the numeric code hs.hotkey and
-- hs.eventtap actually compare against. Answering nil for a name that is not there, rather than
-- raising, is what lets a caller ask "is this leader real" as a plain value check instead of
-- wrapping every call in a pcall, the same reason the remap's own apply logs and skips an unknown
-- key rather than aborting the whole remap over one bad entry.
function obj.keycode(fkey)
  if not fkey then return nil end
  return hs.keycodes.map[fkey]
end

return obj
