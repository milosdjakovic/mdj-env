-- The key inventory probe, every chord the running configuration has bound.
--
-- This reads LIVE state and nothing else. It posts no key, opens no list and reloads
-- nothing. It is run inside the running Hammerspoon with dofile, since the two leader engines
-- and the plan the root built exist only there, and it writes its answer to a file rather than
-- returning it over the port, which loses or truncates large replies.
--
-- Run it through test/keys.sh, which sets the output path, bounds the call and diffs the
-- result against test/keys.golden. By hand, the shape is this, with the output path taken
-- from the global OLM_KEYS_OUT.
--
--   hs -q -c 'OLM_KEYS_OUT = "/some/path"; return dofile("/path/to/keys-probe.lua")'
--
-- One line per bound chord, six fields separated by tabs, sorted as plain strings so two runs
-- on an unchanged configuration are byte identical.
--
--   engine   the binding engine. hyper is the app leader's engine, the window leader appears
--            under the name its catalog entry has in config/keys.lua, and hotkey is a plain
--            hs.hotkey combo with no leader at all.
--   key      the key as Hammerspoon's own keycode table spells it, whatever case or alias the
--            declaration used.
--   mods     the required modifiers, sorted and joined with a plus. any is a catch all binding
--            that fires whatever extra modifiers are held, and none is a binding that demands
--            no modifier at all, the two differ in both engines' resolvers.
--   when     the context predicate gating the binding, or a dash.
--   priority the context priority, or a dash.
--   owner    who declared the chord, or a question mark where nothing declares it.
--
-- Owners. The engines keep only functions, so an owner is worked out by crossing each stored
-- binding with what the live plan declares, a tool's open key, a plugin's own bindings, the
-- context bindings of every list, the person's toggles, a launcher special row and a registered
-- command's key. A registered tool's function is also matched by identity against what the
-- registry holds, which is exact where a key match could be ambiguous. Two declarations that
-- claim one chord are both named, joined with a bar, since that is a collision worth seeing
-- rather than hiding. The probe reads declarations by their field names and never by a
-- plugin's name, so a plugin added later is covered without an edit here.
--
-- What it cannot see. The bound handler of a plain hs.hotkey is not exposed, so those owners
-- come from the declarations alone. A key a plugin binds that the plan does not declare, or
-- one the person moved with a registry override the plan does not carry, is reported as a
-- question mark, which is the honest answer rather than a guess.

local OUT = OLM_KEYS_OUT
assert(type(OUT) == "string" and OUT ~= "", "set OLM_KEYS_OUT to the output path before dofile")

local olm = spoon.Olm
local composed = assert(olm and olm._composed, "the live Olm has no composed plan")
local plan = composed.plan
local hyper = olm.lib.hyperkey
local windowLeader = olm.lib.windowleader

local DASH = "-"

--------------------------------------------------------------------------------
-- Spelling, one way to write a key and a set of modifiers
--------------------------------------------------------------------------------

local function codeOf(key)
  if type(key) == "number" then return key end
  if type(key) ~= "string" then return nil end
  return hs.keycodes.map[key:lower()]
end

local function nameOf(code)
  local name = hs.keycodes.map[code]
  if type(name) == "string" then return name end
  return "code" .. tostring(code)
end

local ALIASES = {
  shift = "shift", ctrl = "ctrl", control = "ctrl", alt = "alt", option = "alt", opt = "alt",
  cmd = "cmd", command = "cmd",
}

-- nil means a catch all. An empty list means no modifier at all, which is a different binding.
local function modsKey(mods)
  if mods == nil then return "any" end
  local seen, list = {}, {}
  for _, m in ipairs(mods) do
    local canon = ALIASES[tostring(m):lower()] or tostring(m):lower()
    if not seen[canon] then
      seen[canon] = true
      list[#list + 1] = canon
    end
  end
  if #list == 0 then return "none" end
  table.sort(list)
  return table.concat(list, "+")
end

--------------------------------------------------------------------------------
-- The engines' own names
--------------------------------------------------------------------------------

-- The window leader's catalog name lives in the person's config, which is plain data and safe
-- to read. A missing file or field falls back to a neutral word rather than failing the probe.
local function windowLeaderName()
  local ok, keys = pcall(dofile, hs.configdir .. "/config/keys.lua")
  if ok and type(keys) == "table" and type(keys.windowLeader) == "string" then
    return keys.windowLeader
  end
  return "window"
end

local WINDOW = windowLeaderName()
local HYPER = "hyper"
local HOTKEY = "hotkey"

--------------------------------------------------------------------------------
-- Declarations, indexed by engine, keycode, modifiers and context
--------------------------------------------------------------------------------

local declared = {}
local function declare(engine, key, mods, when, owner)
  local code = codeOf(key)
  if not code or not owner then return end
  local id = table.concat({ engine, code, modsKey(mods), when or DASH }, "|")
  declared[id] = declared[id] or {}
  declared[id][owner] = true
end

-- The engine a declared leader role binds on. Only the window role is the window engine, any
-- other word, or none, is the app leader, which is where the root binds a tool's own key.
local function engineFor(role)
  if role == "window" then return WINDOW end
  return HYPER
end

local directories = {}
for directory in pairs(plan.effective or {}) do directories[#directories + 1] = directory end
table.sort(directories)

for _, directory in ipairs(directories) do
  local eff = plan.effective[directory]
  local owner = (plan.identity or {})[directory] or directory

  -- A tool's open key, and a host's, both a key on a leader.
  if eff.key then declare(engineFor(eff.leader), eff.key, eff.mods, nil, owner) end

  -- A plugin's own bindings, each carrying a key and optionally its own gate.
  for _, b in ipairs(eff.bindings or {}) do
    declare(engineFor(eff.leader), b.key, b.mods, b.when, owner)
  end

  -- The special rows of a host that carry a key, which the root binds on the app leader.
  for _, row in ipairs(eff.specialRows or {}) do
    if row.key then declare(HYPER, row.key, nil, nil, owner) end
  end
end

-- Every list's context bindings, bound on the app leader under the context's own gate.
local contexts = {}
for name in pairs(plan.contexts or {}) do contexts[#contexts + 1] = name end
table.sort(contexts)
for _, name in ipairs(contexts) do
  local block = plan.contexts[name]
  for _, b in ipairs(block.bindings or {}) do
    if b.chord ~= false then declare(HYPER, b.key, b.mods, block.when, name) end
  end
end

-- The person's toggles. An entry stating its own modifiers is a plain combo, any other is a
-- key on the app leader. The list is the one the plugin was configured with.
local dataKeys = {}
for directory in pairs(composed.data or {}) do dataKeys[#dataKeys + 1] = directory end
table.sort(dataKeys)
for _, directory in ipairs(dataKeys) do
  local data = composed.data[directory]
  local owner = (plan.identity or {})[directory] or directory
  if type(data) == "table" and type(data.toggles) == "table" then
    for _, t in ipairs(data.toggles) do
      if t.modifiers then
        declare(HOTKEY, t.key, t.modifiers, nil, owner)
      else
        declare(HYPER, t.key, nil, nil, owner)
      end
    end
  end
end

-- A registered command's own key. The command belongs to the manifest declaring it, and a
-- global one is a plain combo, a leader one a key on the app leader. A person's override of
-- the key lives in the root's registry table and is not carried by the plan, so a command moved
-- that way shows as a question mark, which is the point of reporting one.
local kindOf = {}
local fnOwner = {}
for _, entry in ipairs((function()
  local list = {}
  for _, e in pairs(olm.registry.shortcuts() or {}) do list[#list + 1] = e end
  table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return list
end)()) do
  kindOf[entry.name] = entry.kind
  if type(entry.fn) == "function" then fnOwner[entry.fn] = entry.name end
end

local manifestNames = {}
for directory in pairs(composed.manifests or {}) do manifestNames[#manifestNames + 1] = directory end
table.sort(manifestNames)
for _, directory in ipairs(manifestNames) do
  local commands = ((composed.manifests[directory] or {}).registry or {}).commands or {}
  for name, spec in pairs(commands) do
    if spec.key and kindOf[name] then
      local engine = kindOf[name] == "global" and HOTKEY or HYPER
      declare(engine, spec.key, spec.mods, nil, (plan.identity or {})[directory] or directory)
    end
  end
end

--------------------------------------------------------------------------------
-- Collect what the engines actually hold
--------------------------------------------------------------------------------

local lines = {}

local function ownerOf(engine, code, mods, when, fn)
  local names = {}
  local id = table.concat({ engine, code, modsKey(mods), when or DASH }, "|")
  for owner in pairs(declared[id] or {}) do names[owner] = true end
  if fn and fnOwner[fn] then names[fnOwner[fn]] = true end
  local list = {}
  for owner in pairs(names) do list[#list + 1] = owner end
  if #list == 0 then return "?" end
  table.sort(list)
  return table.concat(list, "|")
end

local function emit(engine, code, mods, when, priority, owner)
  lines[#lines + 1] = table.concat({
    engine, nameOf(code), modsKey(mods), when or DASH,
    priority ~= nil and tostring(priority) or DASH, owner,
  }, "\t")
end

-- The app leader's engine, every stored binding, base and contextual alike.
for code, list in pairs(hyper._bindings or {}) do
  for _, b in ipairs(list) do
    emit(HYPER, code, b.mods, b.when, b.priority, ownerOf(HYPER, code, b.mods, b.when, b.fn))
  end
end

-- The window leader, one table per leader keycode. The leader that is the configured window
-- keycode wears its catalog name, any other is named by its keycode.
for leaderCode, leader in pairs(windowLeader._leaders or {}) do
  local engine = leaderCode == windowLeader._keyCode and WINDOW or ("leader" .. tostring(leaderCode))
  for code, list in pairs(leader.bindings or {}) do
    for _, b in ipairs(list) do
      emit(engine, code, b.mods, b.when, b.priority, ownerOf(engine, code, b.mods, b.when, b.fn))
    end
  end
end

-- Plain hs.hotkey combos. Hammerspoon exposes the keycode and the carbon modifier mask only
-- through the hotkey object's own description, and the glyph string it indexes by is a second
-- spelling of the same, so the description is parsed and the glyphs are the fallback.
local MASKS = { { 0x100, "cmd" }, { 0x200, "shift" }, { 0x800, "alt" }, { 0x1000, "ctrl" } }
local GLYPHS = { ["⌘"] = "cmd", ["⇧"] = "shift", ["⌥"] = "alt", ["⌃"] = "ctrl" }

local function hotkeyChord(h)
  local desc = tostring(h._hk or "")
  local code, mask = desc:match("keycode: (%d+), mods: 0x(%x+)")
  if code then
    code, mask = tonumber(code), tonumber(mask, 16)
    local mods = {}
    for _, m in ipairs(MASKS) do
      if mask & m[1] ~= 0 then mods[#mods + 1] = m[2] end
    end
    return code, mods
  end
  local idx = tostring(h.idx or "")
  local mods, rest = {}, idx
  for glyph, name in pairs(GLYPHS) do
    if rest:find(glyph, 1, true) then
      mods[#mods + 1] = name
      rest = rest:gsub(glyph, "")
    end
  end
  return codeOf(rest), mods
end

for _, h in ipairs(hs.hotkey.getHotkeys() or {}) do
  if h.enabled ~= false then
    local code, mods = hotkeyChord(h)
    if code then
      emit(HOTKEY, code, mods, nil, nil, ownerOf(HOTKEY, code, mods, nil, nil))
    else
      lines[#lines + 1] = table.concat({ HOTKEY, tostring(h.idx), "?", DASH, DASH, "?" }, "\t")
    end
  end
end

table.sort(lines)

local f = assert(io.open(OUT, "w"))
f:write(table.concat(lines, "\n"), "\n")
f:close()

return "wrote " .. #lines .. " lines"
