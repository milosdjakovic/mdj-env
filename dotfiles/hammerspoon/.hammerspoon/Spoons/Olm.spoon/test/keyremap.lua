-- The remap applier, in plain Lua.
--
-- What this pins is the one command lib/keyremap.lua runs, since every other test reaches the
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

-- Today's two leaders in use land on the function keys they always had.
do
  local command = remap({ { name = "HYPER", key = "capsLock" }, { name = "META", key = "rightOption" } })
  eq(command:find(CAPS_TO_F18, 1, true) ~= nil, true, "Caps Lock is remapped to F18")
  eq(command:find(ROPT_TO_F16, 1, true) ~= nil, true, "Right Option is remapped to F16")
end

-- Two leaders on one key are remapped once.
do
  local command = remap({ { name = "A", key = "capsLock" }, { name = "B", key = "capsLock" } })
  local _, count = command:gsub("HIDKeyboardModifierMappingSrc", "")
  eq(count, 1, "one key is remapped once")
end

-- A key the remap does not know is left alone, and nothing in use leaves an empty mapping.
do
  eq(remap({ { name = "X", key = "letterQ" } }):find('"UserKeyMapping":[]', 1, true) ~= nil, true,
    "an unknown key is left as it is")
  eq(remap({}):find('"UserKeyMapping":[]', 1, true) ~= nil, true, "no leader in use remaps nothing")
end

-- The preferred targets the root reads.
eq(KeyRemap.targetFor("capsLock"), "f18", "Caps Lock prefers F18")
eq(KeyRemap.targetFor("rightOption"), "f16", "Right Option prefers F16")
eq(KeyRemap.targetFor("rightCommand"), "f17", "Right Command prefers F17")
eq(KeyRemap.sources().capsLock, true, "Caps Lock is a source")

print(string.format("keyremap: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
