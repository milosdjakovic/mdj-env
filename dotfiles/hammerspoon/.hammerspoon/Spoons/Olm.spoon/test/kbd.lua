-- lib/kbd.lua, the one vocabulary of keys, for what the legend leans on: a held leader's physical
-- key as the keys a person reads, every spelling of Caps Lock as one key, and modifiers alone as a
-- chord in the menu bar's order. Plain Lua, no Hammerspoon and no lock.
--
-- Run it.
--   lua test/kbd.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local kbd = assert(loadfile(here .. "../lib/kbd.lua"))()

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

-- Caps Lock is one key with its own symbol, whatever it is called.
for _, name in ipairs({ "capsLock", "capslock", "caps", "caps_lock", "Caps Lock" }) do
  eq(kbd.named(name), kbd.CapsLock, "named: every spelling of Caps Lock is the one key, " .. name)
end
eq(kbd.CapsLock.symbol ~= nil, true, "Caps Lock draws its SF Symbol in a key cap")

-- A held leader's physical key.
eq(kbd.physical("capsLock").keys[1], kbd.CapsLock, "physical: Caps Lock is its own key")
for name, mod in pairs({ rightOption = kbd.Alt, rightCommand = kbd.Cmd, rightControl = kbd.Ctrl, rightShift = kbd.Shift }) do
  local c = kbd.physical(name)
  eq(#c.keys, 2, "physical: " .. name .. " is two keys")
  eq(c.keys[1], kbd.RightHand, "physical: " .. name .. " leads with right")
  eq(c.keys[2], mod, "physical: " .. name .. " is read from its name, not a list")
end
eq(kbd.physical("f13").keys[1], kbd.named("f13"), "physical: a function key is itself")
eq(kbd.physical("rightArrow").keys[1], kbd.named("rightArrow"), "physical: right and a key that is no modifier stays one key")

-- Modifiers alone, in the menu bar's order whatever order they were listed in.
eq(kbd.text(kbd.modifiers({ "cmd", "shift", "ctrl", "alt" })), kbd.text(kbd.of(kbd.Ctrl, kbd.Alt, kbd.Shift, kbd.Cmd)),
  "modifiers: the menu bar's order")
eq(kbd.modifiers({ "x" }), nil, "modifiers: none of them a modifier is no chord")
eq(kbd.modifiers(nil), nil, "modifiers: nothing is no chord")

print(string.format("kbd: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
