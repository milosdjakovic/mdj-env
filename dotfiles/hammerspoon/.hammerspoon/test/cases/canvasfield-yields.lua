-- Unit case for the one key the canvas field's tap does not claim, a key down the injected
-- yields predicate gives away, and for Leader:owns, the answer the composition root builds
-- that predicate over, asked of the leader whose policy turns contexts on. Both are driven with event shaped tables and fakes, so nothing here
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
-- Leader:owns
--------------------------------------------------------------------------------

-- The leader adapter answers owns through its trigger, so each trigger is loaded into the same
-- environment and handed to a fresh leader. The held trigger owns its own key and every key while
-- that key is held. The modifier trigger, which the person's named sets of modifiers will use and
-- which owned keys under Hyper's old chord shape, owns a key exactly while its whole base set is held.
do
  local mods = {}
  local env = setmetatable({
    hs = {
      logger = { new = function() return { w = function() end, i = function() end, e = function() end } end },
      eventtap = { checkKeyboardModifiers = function() return mods end },
    },
  }, { __index = _G })
  local leaderChunk = loadfile(olm .. "lib/leader.lua", "t", env)
  local heldChunk = loadfile(olm .. "lib/leader/triggers/held.lua", "t", env)
  local modifierChunk = loadfile(olm .. "lib/leader/triggers/modifier.lua", "t", env)
  local function fresh(trigger)
    return leaderChunk().new({ name = "hyper", policy = { contexts = true }, trigger = trigger })
  end

  local held = { value = false }
  local leader = fresh(heldChunk().new({ chord = { isActive = function() return held.value end }, keyCode = 79 }))
  check("under the held trigger the leader key itself is owned even when not yet held",
    leader:owns(ev(79)) == true)
  check("under the held trigger another key is not owned while the leader is up",
    leader:owns(ev(34)) == false)
  held.value = true
  check("under the held trigger any key is owned while the leader is held",
    leader:owns(ev(34)) == true)

  mods = {}
  local chord = fresh(modifierChunk().new({ mods = { "ctrl", "alt" } }))
  check("under the modifier trigger a key is not owned with no modifier held", chord:owns(ev(34)) == false)
  mods = { ctrl = true }
  check("under the modifier trigger a partial base set does not own a key", chord:owns(ev(34)) == false)
  mods = { ctrl = true, alt = true }
  check("under the modifier trigger the whole base set owns any key", chord:owns(ev(34)) == true)

  local plain = fresh(modifierChunk().new({ mods = {} }))
  check("an empty base set, the plain leader, owns nothing whatever is held", plain:owns(ev(34)) == false)
end
