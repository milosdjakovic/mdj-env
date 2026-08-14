-- Turning a catalog entry into a real keycode, and the one place the window binding stamp
-- is produced.
--
-- The catalog in config/keys.lua names a physical key and an unused function key it maps
-- to. Nothing else here needs to know a physical key exists, it only needs the keycode that
-- key resolves to once KeyRemap has applied the mapping, and that resolution has to happen
-- in exactly one place, because two call sites resolving the same catalog entry separately
-- can drift the moment one of them is edited and the other is not.
--
-- The window leader stamp lives here for the same reason. WindowManager and WindowCheatSheet
-- both act on the window bindings, one to dispatch a key and one to draw an overlay of what
-- that key does, and both have to be reading the SAME table, not two tables that merely agree
-- today. Stamping the leader keycode onto one list and handing that one list to both closes
-- that gap, which the audit recorded as the first of three facts a manifest cannot express.
-- This module produces that one stamped list. It is the composition root's job to call it
-- once and hand the result to both destinations by reference, never to call it twice.
--
-- This module names no plugin, no engine, and no physical key. It reads a catalog and a
-- roles table the composition root already built from what the user's own config
-- references, and it never calls KeyRemap, addLeader, or anything else that would make it a
-- second place deciding wiring order.

local obj = {}

-- catalog[name] carries an fkey naming the target function key, and hs.keycodes.map turns
-- that friendly name into the numeric code hs.hotkey and hs.eventtap actually compare
-- against. Answering nil for a name or an fkey that is not there, rather than raising, is
-- what lets a caller ask "is this leader real" as a plain value check instead of wrapping
-- every call in a pcall, the same reason KeyRemap's own apply logs and skips an unknown row
-- rather than aborting the whole remap over one bad entry.
function obj.keycode(catalog, name)
  local row = catalog and catalog[name]
  local fkey = row and row.fkey
  if not fkey then return nil end
  return hs.keycodes.map[fkey]
end

-- A catalog key is active only by being referenced. roles maps a role word, one per domain
-- that claims a leader, to the catalog name that domain actually uses, so the active set is
-- computed from what is referenced rather than written down as a fixed list that the day
-- someone adds a domain or moves one to another key quietly stops matching what is true.
--
-- catalog is accepted, and not read, for the same reason keycode above takes it, both
-- functions answer a question about one catalog and a caller building both from the same
-- root should not be passing two different shaped arguments to ask two related questions.
-- Dropping a role that names an entry the catalog does not carry is left to KeyRemap's own
-- apply, which already logs and skips an unknown row, so checking it here as well would
-- either repeat that same log line or, worse, filter the bad entry out before apply ever
-- sees it and turn a visible warning into a silent one.
--
-- Two roles naming the same catalog entry collapse to one, since hidutil only needs to hear
-- about a physical key once, and the result is built in a fixed order, sorted by role word,
-- so the same roles table always answers with the same list rather than one that depends on
-- Lua's own unordered table iteration.
function obj.activeNames(catalog, roles)
  roles = roles or {}

  local words = {}
  for word in pairs(roles) do words[#words + 1] = word end
  table.sort(words)

  local seen, names = {}, {}
  for _, word in ipairs(words) do
    local name = roles[word]
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return names
end

-- The window bindings in config/keys.lua carry no leader, because the leader is a runtime
-- choice, so the composition root stamps one resolved keycode onto every entry before
-- handing the list to the two consumers that dispatch and describe it. The copy is shallow
-- per entry rather than a deep copy of the whole list, because each entry also carries a
-- `when` predicate name and a `description` string that have to ride along completely
-- unchanged, and the input list itself must never be mutated, since it may still be read
-- elsewhere as the plain data it started as.
function obj.stampBindings(bindings, code)
  local out = {}
  for i, binding in ipairs(bindings or {}) do
    local copy = {}
    for k, v in pairs(binding) do copy[k] = v end
    copy.leader = code
    out[i] = copy
  end
  return out
end

-- HyperKey's trigger table is the caller's own settings block plus two things the resolved
-- catalog decides, a kind that defaults to leader when the caller has no opinion, and the
-- keycode itself. The live root once also passed that same keycode a second time as a plain
-- keyCode option alongside the trigger table, because the spoon behind an atom toggle read
-- only that second copy while the trigger table's own copy fed the other side of the toggle.
-- That toggle is retired, so there is only one consumer left and it reads the trigger table,
-- which is why this answers one descriptor rather than a pair that could drift apart.
function obj.mergeTrigger(trigger, code)
  local merged = {}
  for k, v in pairs(trigger or {}) do merged[k] = v end
  merged.kind = merged.kind or "leader"
  merged.keyCode = code
  return merged
end

return obj
