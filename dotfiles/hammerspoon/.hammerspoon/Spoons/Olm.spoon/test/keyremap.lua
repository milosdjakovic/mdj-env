-- The remap applier and the allocation of function keys, in plain Lua.
--
-- The allocation is pure, so it is pinned case by case, the preferred targets, remapTo, the first
-- free key, a leader on F13 to F20 used as it is, and every refusal. What this also pins is the
-- one command lib/keyremap.lua runs, since every other test reaches the
-- remap through a stub and a mapping that came out empty would leave every held leader its own
-- native key with nothing offline to say so. That happened once while phase 1 of the leaders plan
-- was built, a renamed parameter leaving the loop reading a name that was never set.
--
-- It needs no Hammerspoon. A stub records the command hs.execute is handed.
--
-- Run it.
--   lua test/keyremap.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local lib = here .. "../lib/"

local commands = {}
hs = {
  logger = {
    new = function()
      return setmetatable({}, { __index = function() return function() end end })
    end,
  },
  execute = function(command) commands[#commands + 1] = command end,
}

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print("FAIL " .. what .. ", got " .. tostring(got) .. ", want " .. tostring(want))
  end
end

local KeyRemap = dofile(lib .. "keyremap.lua")
local function remap(held)
  commands = {}
  local k = setmetatable({}, KeyRemap)
  k:apply(held, "hidutil")
  return commands[1] or ""
end

local function pair(src, dst)
  return string.format('{"HIDKeyboardModifierMappingSrc":%d,"HIDKeyboardModifierMappingDst":%d}', src, dst)
end
local CAPS_TO_F18 = pair(0x700000039, 0x70000006D)
local ROPT_TO_F16 = pair(0x7000000E6, 0x70000006B)

local function has(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

-- The rows the root hands apply, from allocate, the way the root builds them, every leader of the
-- table in use and only the remapped ones listed.
local function rowsOf(allocation)
  return allocation.remaps
end
local function allocate(rows) return KeyRemap.allocate(rows) end
local function fkey(result, name) return result.leaders[name] and result.leaders[name].fkey end
local function target(result, name) return result.leaders[name] and result.leaders[name].target end
local function issueFor(result, name)
  for _, issue in ipairs(result.issues) do if issue.name == name then return issue.why end end
  return nil
end

local SHIPPED = {
  { name = "hyper", key = "capsLock" },
  { name = "meta", key = "rightOption" },
  { name = "super", key = "rightCommand" },
}

-- The shipped three land on the keys they always had, the command is the live one.
do
  local r = allocate(SHIPPED)
  eq(#r.issues, 0, "shipped: no issue")
  eq(#r.notes, 0, "shipped: no note")
  eq(fkey(r, "hyper"), "f18", "shipped: Caps Lock listens on F18")
  eq(fkey(r, "meta"), "f16", "shipped: Right Option on F16")
  eq(fkey(r, "super"), "f17", "shipped: Right Command on F17")
  eq(target(r, "hyper"), "f18", "shipped: Caps Lock is remapped to F18")
  local command = remap({ rowsOf(r)[1], rowsOf(r)[2] })
  eq(command:find(CAPS_TO_F18, 1, true) ~= nil, true, "Caps Lock is remapped to F18")
  eq(command:find(ROPT_TO_F16, 1, true) ~= nil, true, "Right Option is remapped to F16")
  eq(#rowsOf(r), 3, "shipped: three remaps")
  eq(rowsOf(r)[1].name, "hyper", "shipped: remaps come in name order")
end

-- Two leaders on one key are remapped once.
do
  local command = remap({ { name = "A", key = "capsLock", target = "f18" }, { name = "B", key = "capsLock", target = "f18" } })
  local _, count = command:gsub("HIDKeyboardModifierMappingSrc", "")
  eq(count, 1, "one key is remapped once")
end

-- A key the remap does not know is left alone, and nothing in use leaves an empty mapping.
do
  eq(remap({ { name = "X", key = "letterQ" } }):find('"UserKeyMapping":[]', 1, true) ~= nil, true,
    "an unknown key is left as it is")
  eq(remap({}):find('"UserKeyMapping":[]', 1, true) ~= nil, true, "no leader in use remaps nothing")
  eq(remap({ { name = "X", key = "f13" } }):find('"UserKeyMapping":[]', 1, true) ~= nil, true,
    "a function key with no target is not a source")
end

-- The allow list is every key USAGE holds.
do
  local sources = KeyRemap.sources()
  for _, name in ipairs({ "capsLock", "rightCommand", "rightOption", "rightControl",
    "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20" }) do
    eq(sources[name], true, name .. " is on the allow list")
  end
  for _, name in ipairs({ "leftCommand", "space", "f12", "f21", "a" }) do
    eq(sources[name], nil, name .. " is not on the allow list")
  end
end

-- remapTo pins the target, a preferred target is only a preference.
do
  local r = allocate({ { name = "hyper", key = "capsLock", remapTo = "f19" }, SHIPPED[2], SHIPPED[3] })
  eq(#r.issues, 0, "remapTo: a pin is no issue")
  eq(fkey(r, "hyper"), "f19", "remapTo: Caps Lock is pinned to F19")
  eq(fkey(r, "meta"), "f16", "remapTo: the others keep their preferred keys")
  local command = remap(r.remaps)
  eq(command:find(pair(0x700000039, 0x70000006E), 1, true) ~= nil, true, "remapTo: the command maps Caps Lock to F19")
  eq(command:find(CAPS_TO_F18, 1, true), nil, "remapTo: and not to F18")
end

-- A pin taking another leader's preferred key sends that leader to the first free key, with a note.
do
  local r = allocate({ { name = "hyper", key = "capsLock", remapTo = "f16" }, SHIPPED[2] })
  eq(#r.issues, 0, "fallback: a taken preference is no issue")
  eq(fkey(r, "hyper"), "f16", "fallback: the pin wins the key")
  eq(fkey(r, "meta"), "f13", "fallback: Right Option takes the first free key")
  eq(#r.notes, 1, "fallback: and says so once")
  eq(has(r.notes[1], "leader meta on rightOption prefers f16, which is in use, so it takes f13"), true, "fallback: the note names both keys")
end

-- A leader on F13 is heard as it is, takes F13 out of the pool and is no remap source.
do
  local rows = { { name = "pedal", key = "f13" }, SHIPPED[1], SHIPPED[2], { name = "ctl", key = "rightControl" } }
  local r = allocate(rows)
  eq(#r.issues, 0, "direct: no issue")
  eq(fkey(r, "pedal"), "f13", "direct: F13 is used as it is")
  eq(target(r, "pedal"), nil, "direct: with no remap target")
  eq(fkey(r, "ctl"), "f14", "direct: Right Control takes the first key F13 left free")
  eq(#r.remaps, 3, "direct: three remaps and not the pedal")
  local command = remap(r.remaps)
  eq(has(command, "HIDKeyboardModifierMappingSrc\":" .. 0x700000068), false, "direct: F13 is not a remap source")
  eq(command:find(pair(0x7000000E4, 0x700000069), 1, true) ~= nil, true, "direct: Right Control is remapped to F14")
  eq(command:find(CAPS_TO_F18, 1, true) ~= nil, true, "direct: and Caps Lock still to F18")
  -- Fed the rows including the direct leader, as a root that forgot to filter would, apply still skips it.
  local unfiltered = remap({ { name = "pedal", key = "f13" }, r.remaps[1] })
  local _, count = unfiltered:gsub("HIDKeyboardModifierMappingSrc", "")
  eq(count, 1, "direct: a function key row with no target is skipped by the applier")
end

-- Right Control with nothing in its way takes F13.
do
  local r = allocate({ { name = "ctl", key = "rightControl" } })
  eq(fkey(r, "ctl"), "f13", "rightControl: the first free key is F13")
  eq(#r.notes, 0, "rightControl: with no note, it has no preference to miss")
  r = allocate({ { name = "ctl", key = "rightControl" }, { name = "a", key = "f13" }, { name = "b", key = "f14" } })
  eq(fkey(r, "ctl"), "f15", "rightControl: direct leaders on F13 and F14 push it to F15")
end

-- Every refusal names the leader and says why.
do
  local r = allocate({ { name = "x", key = "capsLock", remapTo = "f12" } })
  eq(has(issueFor(r, "x"), "remapTo of 'f12', which is not one of f13 to f20"), true, "refuse: a remapTo off the function keys")
  r = allocate({ { name = "x", key = "capsLock", remapTo = 7 } })
  eq(has(issueFor(r, "x"), "remapTo of '7'"), true, "refuse: a remapTo that is no word")
  r = allocate({ { name = "x", key = "f13", remapTo = "f14" } })
  eq(has(issueFor(r, "x"), "remapTo beside the key f13"), true, "refuse: remapTo beside a function key")
  r = allocate({ { name = "x", key = "space" } })
  eq(has(issueFor(r, "x"), "not a key Olm can make a leader"), true, "refuse: a key off the list")
  r = allocate({ { name = "a", key = "capsLock" }, { name = "b", key = "capsLock" }, { name = "c", key = "f13" } })
  eq(has(issueFor(r, "a"), "shares the key capsLock with a, b"), true, "refuse: two leaders on one physical key, first")
  eq(has(issueFor(r, "b"), "shares the key capsLock with a, b"), true, "refuse: and the second")
  eq(issueFor(r, "c"), nil, "refuse: a bystander is not named")
  r = allocate({ { name = "a", key = "f13" }, { name = "b", key = "f13" } })
  eq(#r.issues, 2, "refuse: two leaders on F13 are two issues")
  r = allocate({ { name = "pedal", key = "f13" }, { name = "hyper", key = "capsLock", remapTo = "f13" } })
  eq(has(issueFor(r, "hyper"), "remapTo of f13, which leader pedal uses directly"), true, "refuse: a pin on a direct key, the pin")
  eq(has(issueFor(r, "pedal"), "uses f13 directly, which leader hyper names as its remapTo"), true, "refuse: and the direct leader")
  r = allocate({ { name = "hyper", key = "capsLock", remapTo = "f19" }, { name = "meta", key = "rightOption", remapTo = "f19" } })
  eq(has(issueFor(r, "hyper"), "which hyper, meta all name"), true, "refuse: two pins on one function key, first")
  eq(has(issueFor(r, "meta"), "which hyper, meta all name"), true, "refuse: and the second")
  local rows = { { name = "d1", key = "f13" }, { name = "d2", key = "f14" }, { name = "d3", key = "f15" },
    { name = "d4", key = "f16" }, { name = "d5", key = "f17" }, { name = "d6", key = "f18" },
    { name = "d7", key = "f19" }, { name = "d8", key = "f20" }, { name = "ctl", key = "rightControl" } }
  r = allocate(rows)
  eq(has(issueFor(r, "ctl"), "no function key left"), true, "refuse: no function key left to remap to")
end

-- The same rows give the same answer however they are ordered or repeated.
do
  local rows = { { name = "ctl", key = "rightControl" }, { name = "meta", key = "rightOption", remapTo = "f13" },
    { name = "hyper", key = "capsLock" }, { name = "pedal", key = "f14" }, { name = "super", key = "rightCommand" } }
  local function signature(r)
    local parts = {}
    for _, row in ipairs(r.remaps) do parts[#parts + 1] = row.name .. ">" .. row.target end
    return table.concat(parts, ",") .. "|" .. table.concat(r.notes, ";")
  end
  local first = signature(allocate(rows))
  local reversed = {}
  for i = #rows, 1, -1 do reversed[#reversed + 1] = rows[i] end
  eq(signature(allocate(reversed)), first, "determinism: row order changes nothing")
  eq(signature(allocate(rows)), first, "determinism: nor does asking twice")
  eq(first, "ctl>f15,hyper>f18,meta>f13,super>f17|", "determinism: and the answer is the expected one")
end

print(string.format("keyremap: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
