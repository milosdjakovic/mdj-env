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
-- binding with what the live plan declares. The declarations are read by lib/keymap.lua, a
-- tool's open key, a plugin's own bindings, the context bindings of every list, the person's
-- toggles, a launcher special row and a registered command's key, and this probe indexes the
-- rows it returns rather than reading the plan a second time. A registered tool's function is also matched by identity against what the
-- registry holds, which is exact where a key match could be ambiguous. Two declarations that
-- claim one chord are both named, joined with a bar, since that is a collision worth seeing
-- rather than hiding. The probe reads declarations by their field names and never by a
-- plugin's name, so a plugin added later is covered without an edit here.
--
-- A second mode, with the global OLM_KEYS_MODE set to keymap, writes the keymap's own rows in this
-- same line format and never looks at an engine. The two outputs are expected to be identical,
-- byte for byte, which proves the read model holds every chord the engines do. keys.sh asks
-- for it with the keymap flag, and it only answers on a config whose root built a keymap.
--
-- What it cannot see. The bound handler of a plain hs.hotkey is not exposed, so those owners
-- come from the declarations alone. A key a plugin binds that the plan does not declare, or
-- one the person moved with a registry override the plan does not carry, is reported as a
-- question mark, which is the honest answer rather than a guess.

local OUT = OLM_KEYS_OUT
assert(type(OUT) == "string" and OUT ~= "", "set OLM_KEYS_OUT to the output path before dofile")

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local keymapLib = assert(loadfile(here .. "../lib/keymap.lua"))()
local project = assert(loadfile(here .. "keys-project.lua"))()

local olm = spoon.Olm
local composed = assert(olm and olm._composed, "the live Olm has no composed plan")
local hyper = olm.lib.hyperkey
local windowLeader = olm.lib.windowleader

local DASH = "-"
local KEYCODES = hs.keycodes.map

local function nameOf(code)
  local name = KEYCODES[code]
  if type(name) == "string" then return name end
  return "code" .. tostring(code)
end

-- nil means a catch all. An empty list means no modifier at all, which is a different binding.
local modsKey = keymapLib.modsText
local codeOf = function(key) return keymapLib.keyCode(key, KEYCODES) end

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

-- The other mode writes the keymap's own rows in the golden's line format and stops, which is
-- the proof the read model is complete. keys.sh asks for it with the global OLM_KEYS_MODE. It
-- needs the keymap the root built, so it only answers on a config that has one.
if OLM_KEYS_MODE == "keymap" then
  local keymap = assert(composed.keymap, "the live Olm has no keymap, is the worktree the live config")
  local lines = project.project(keymap.rows, WINDOW)
  local f = assert(io.open(OUT, "w"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  return "wrote " .. #lines .. " lines from the keymap"
end

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

-- The declarations are the keymap's rows. A config that built its own is read as it is, and one
-- that did not, main before the keymap landed, has the same module fed from the same live plan,
-- so this probe still describes it. The roles come from the person's own key file, and a
-- command's key is read as its manifest ships it, which is why an override held only in the
-- root's registry table shows as a question mark, as it always did.
local keymap = composed.keymap
if not keymap then
  local ok, keys = pcall(dofile, hs.configdir .. "/config/keys.lua")
  keys = ok and type(keys) == "table" and keys or {}
  keymap = keymapLib.build({
    plan = composed.plan,
    roles = { app = keys.appLeader or "HYPER", window = keys.windowLeader or "META" },
    keycodes = KEYCODES,
    shortcuts = olm.registry.shortcuts(),
    manifests = composed.manifests,
    data = composed.data,
  })
end

-- Every row of the keymap is a declaration of one chord. A row states catch all with a flag, and
-- the index here wants nil for it, which is how the engines hold one.
for _, row in ipairs(keymap.rows) do
  local mods = row.mods
  if row.anyMods then mods = nil end
  declare(project.engineLabel(row.leader, WINDOW), row.key, mods, row.when, row.owner)
end

-- A registered tool's own function, matched by identity against what the engines hold, which
-- is exact where a key match could be ambiguous. A person's override of a command's key lives
-- in the root's registry table and not in the plan, so the keymap reads it through the same
-- lookup the binder uses, and this match is the second opinion.
local fnOwner = {}
for _, entry in pairs(olm.registry.shortcuts() or {}) do
  if type(entry.fn) == "function" then fnOwner[entry.fn] = entry.name end
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
