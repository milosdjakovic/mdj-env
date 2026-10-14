-- Unit case for the one key the canvas field's tap does not claim, a key down the injected
-- yields predicate gives away, and for HyperKey:owns, the answer the composition root builds
-- that predicate over. Both are driven with event shaped tables and fakes, so nothing here
-- touches the running Hammerspoon or installs a tap.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone, the same convention every other case follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function ev(code, flags, chars)
  return {
    getKeyCode = function() return code end,
    getFlags = function() return flags or {} end,
    getCharacters = function() return chars end,
  }
end

--------------------------------------------------------------------------------
-- The field
--------------------------------------------------------------------------------

do
  local input = loadfile(olm .. "lib/chooser/providers/default/field/input.lua")()
  local ESCAPE, KEY_I = 53, 34

  local function field(opts)
    opts = opts or {}
    local dismissed, typed = 0, nil
    opts.onDismiss = function() dismissed = dismissed + 1 end
    opts.onChange = function(state) typed = state.text end
    return input.Field.new(opts), function() return dismissed, typed end
  end

  local f = field()
  check("with no predicate injected a printable key is claimed and typed",
    f:_handle(ev(KEY_I, {}, "i")) == true and f:getState().text == "i")

  local seen
  local g, read = field({ yields = function(e) seen = e:getKeyCode(); return e:getKeyCode() == KEY_I end })
  check("a key the predicate answers true for passes on unclaimed",
    g:_handle(ev(KEY_I, { ctrl = true }, "i")) == false)
  check("a yielded key is never typed into the buffer", g:getState().text == "")
  check("a key the predicate answers false for is still claimed and typed",
    g:_handle(ev(0, {}, "a")) == true and g:getState().text == "a")

  local escapeAsked = false
  local h, readH = field({ yields = function() escapeAsked = true; return true end })
  check("escape is answered before the predicate is ever asked",
    h:_handle(ev(ESCAPE, {})) == true and escapeAsked == false and readH() == 1)

  local p = field({ yields = function() error("boom") end })
  local quiet = print
  print = function() end
  local claimed = p:_handle(ev(0, {}, "z"))
  print = quiet
  check("an error in the predicate is treated as false and the key is claimed",
    claimed == true and p:getState().text == "z")

  local q = field({ yields = function() return "yes" end })
  check("only a true answer yields, a truthy value that is not true does not",
    q:_handle(ev(0, {}, "z")) == true)
end

--------------------------------------------------------------------------------
-- HyperKey:owns
--------------------------------------------------------------------------------

do
  local mods = {}
  local env = setmetatable({
    hs = {
      logger = { new = function() return { w = function() end, i = function() end, e = function() end } end },
      eventtap = { checkKeyboardModifiers = function() return mods end },
    },
  }, { __index = _G })
  local chunk = loadfile(olm .. "lib/hyperkey.lua", "t", env)
  local function fresh(trigger, held)
    local hk = setmetatable({}, { __index = chunk() })
    hk:init()
    hk:configure({ chord = { isActive = function() return held.value end }, trigger = trigger })
    return hk
  end

  local held = { value = false }
  local leader = fresh({ kind = "leader", keyCode = 79 }, held)
  check("under the leader shape the leader key itself is owned even when not yet held",
    leader:owns(ev(79)) == true)
  check("under the leader shape another key is not owned while the leader is up",
    leader:owns(ev(34)) == false)
  held.value = true
  check("under the leader shape any key is owned while the leader is held",
    leader:owns(ev(34)) == true)

  mods = {}
  local chord = fresh({ kind = "chord", mods = { "ctrl", "alt" } }, { value = false })
  check("under the chord shape a key is not owned with no modifier held", chord:owns(ev(34)) == false)
  mods = { ctrl = true }
  check("under the chord shape a partial chord does not own a key", chord:owns(ev(34)) == false)
  mods = { ctrl = true, alt = true }
  check("under the chord shape the full chord owns any key", chord:owns(ev(34)) == true)
end
