-- What Olm.app is handed of the keys, lib/keyshare.lua, in plain Lua, step 5.1 of
-- docs/PLAN-STANDALONE.md. It pins the share, the leaders in use only, every bindable row in the
-- binder's order with its modifiers as the binder binds them, and the wrap, a run that tells the
-- app which row ran and still runs with its arguments, with the keymap's own rows left unchanged.
--
-- It needs no Hammerspoon and no lock.
--
-- Run it.
--   lua test/keyshare.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local keyshare = assert(loadfile(here .. "../lib/keyshare.lua"))()
local binder = assert(loadfile(here .. "../lib/binder.lua"))()

local ran = {}
local function runner(name) return function(...) ran[#ran + 1] = { name, ... }; return name end end

local rows = {
  { layer = "global", leader = "hyper", key = "a", mods = {}, anyMods = false, owner = "apptoggler", action = "Safari", run = runner("safari") },
  { layer = "global", leader = "meta", key = "left", mods = nil, anyMods = true, owner = "windowmanager", action = "leftHalf", repeats = true, run = runner("left") },
  { layer = "global", leader = nil, key = "`", mods = { "alt" }, anyMods = false, owner = "apptoggler", action = "Ghostty", when = "multipleDisplays", run = runner("ghostty") },
  { layer = "global", leader = nil, key = "c", mods = nil, anyMods = false, owner = "clipboard", action = "append", run = runner("append") },
  { layer = "clipboard", leader = "hyper", key = "j", mods = {}, owner = "clipboard", action = "selectNext", run = runner("next") },
  { layer = "global", leader = "hyper", key = "q", mods = {}, owner = "gone", action = "nothing" },
}
local leaders = {
  { name = "hyper", held = true, keyCode = 79, mods = { "shift", "ctrl", "alt", "cmd" }, inUse = true, policy = { ranked = true } },
  { name = "meta", held = true, keyCode = 106, mods = { "shift", "ctrl", "alt" }, inUse = true, policy = {} },
  { name = "super", held = true, keyCode = 64, inUse = false, policy = {} },
}
local codes = { a = 0, left = 123, ["`"] = 50, c = 8, j = 38, q = 12 }

local share = keyshare.share(rows, leaders, { bindable = binder.bindable, keycodes = codes })
eq(share.version, 1, "the share's version")
eq(#share.leaders, 2, "only the leaders in use")
eq(share.leaders[1].name, "hyper", "hyper first")
eq(share.leaders[1].keyCode, 79, "hyper's function key")
eq(#share.leaders[1].mods, 4, "hyper's four modifiers")
eq(share.leaders[1].ranked, true, "hyper is ranked")
eq(share.leaders[2].ranked, false, "meta is not")
eq(#share.rows, 4, "every bindable global row, no list key and no row without a run")
eq(share.rows[1].id, "apptoggler.Safari", "a row's id is its owner and action")
eq(share.rows[1].keyCode, 0, "a row's keycode")
eq(#share.rows[1].mods, 0, "an exact row with no modifiers")
eq(share.rows[2].mods, nil, "a catch all has no modifiers")
eq(share.rows[2].repeats, true, "a repeating row says so")
eq(share.rows[3].leader, nil, "a plain combo has no leader")
eq(share.rows[3].mods[1], "alt", "a plain combo's modifiers")
eq(share.rows[3].gate, "multipleDisplays", "a row's gate")
eq(#share.rows[4].mods, 0, "a plain combo stating none demands none, as the binder binds it")

local told = {}
local wrapped = keyshare.wrap(rows, function(method, params) told[#told + 1] = method .. " " .. params.id end)
eq(#wrapped, #rows, "every row copied")
eq(wrapped[1] ~= rows[1], true, "a copy, not the row")
eq(rows[1].run ~= wrapped[1].run, true, "the keymap's own run unchanged")
eq(wrapped[2].run(3), "left", "a wrapped run answers what it answered")
eq(ran[#ran][2], 3, "and is handed its arguments")
eq(told[1], "keyFired windowmanager.leftHalf", "and tells the app which row ran")
eq(wrapped[6].run, nil, "a row with no run stays without one")
local raising = keyshare.wrap({ rows[1] }, function() error("the bridge went") end)
eq(raising[1].run(), "safari", "a notify that raises never stops the action")

print(string.format("keyshare, %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
