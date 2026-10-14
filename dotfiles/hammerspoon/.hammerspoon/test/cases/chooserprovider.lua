-- Unit case for the provider choice in Olm.spoon/lib/chooser/init.lua, phase four of the
-- canvas chooser build, docs/BRIEF-CANVAS-SELECT.md. It loads the facade by a path derived
-- from this file, configures it with a stand in provider that satisfies the picker
-- contract, and checks that new builds through it, and that new falls back to native when
-- no provider is configured. The native build is only constructed, never shown.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local facadePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/init.lua"
local contractPath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/contract.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local facadeChunk, err = loadfile(facadePath)
if not facadeChunk then
  print("FAIL load lib/chooser/init.lua, " .. tostring(err))
  return
end
local contract = dofile(contractPath)
local Chooser = facadeChunk()

check("the facade exposes a native provider", type(Chooser.providers) == "table" and type(Chooser.providers.native) == "table")
check("the facade exposes a canvas provider", type(Chooser.providers) == "table" and type(Chooser.providers.canvas) == "table")
check("the two providers are distinct modules", Chooser.providers.native ~= Chooser.providers.canvas)

-- A stand in provider whose instances carry every required method at a generous arity.
local built = {}
local fake = {
  new = function(config)
    local instance = { marker = "fake", config = config }
    for _, name in ipairs(contract.requiredMethods) do
      instance[name] = function(self, a, b) end
    end
    built[#built + 1] = instance
    return instance
  end,
}

Chooser.configure({ provider = fake })
local config = {}
local instance = Chooser.new(config)
check("a configured provider builds the instance", instance.marker == "fake" and #built == 1)
check("the provider is handed the caller's config table", instance.config == config)

local decorated = nil
Chooser.configure({ provider = fake, decorate = function(inst) decorated = inst end })
local second = Chooser.new({})
check("decorate runs on an instance from the configured provider", decorated == second)

Chooser.configure({})
local ok, native = pcall(Chooser.new, {})
check("with no provider configured new builds through native", ok and type(native) == "table" and native.marker == nil,
  ok and nil or tostring(native))

local bad = { new = function() return {} end }
Chooser.configure({ provider = bad })
local okBad, reason = pcall(Chooser.new, {})
check("a provider breaking the contract is refused before decorate", not okBad and tostring(reason):find("contract", 1, true) ~= nil)

Chooser.configure({})

-- The native provider reads body and caption from an injected kit, and keeps its own literals
-- when none is injected. The facade forwards opts.ui, so this goes through Chooser.configure.
check("with no kit native keeps its literal row of 42 and sizes 16 and 12",
  ok and native.layout.rowH == 42 and native.layout.titleSize == 16 and native.layout.subSize == 12,
  ok and (tostring(native.layout.rowH)) or tostring(native))

local kit = { tokens = function()
  return { text = {
    body = { font = "BodyFont", size = 18, lineHeight = 25 },
    caption = { font = "CaptionFont", size = 15, lineHeight = 21 },
  } }
end }
Chooser.configure({ ui = kit })
local okKit, withKit = pcall(Chooser.new, {})
check("with a kit native takes the body font and size for titles and caption for subtitles",
  okKit and withKit.layout.font == "BodyFont" and withKit.layout.titleSize == 18
    and withKit.layout.subFont == "CaptionFont" and withKit.layout.subSize == 15,
  okKit and nil or tostring(withKit))
-- This stub kit has no measurer and no inset, so the rule falls back to a capital of seven
-- tenths of the body size, 12.6, and the inset of 10, giving 10 plus 12.6 plus 21 plus 10.
check("with a kit native grows its row to the inset, the body capital, one caption line and the inset, 54",
  okKit and withKit.layout.rowH == 54, okKit and tostring(withKit.layout.rowH) or tostring(withKit))
local okOwn, own = pcall(Chooser.new, { layout = { rowH = 70 } })
check("a consumer's own rowH still wins over the derived one",
  okOwn and own.layout.rowH == 70, okOwn and tostring(own.layout.rowH) or tostring(own))
Chooser.providers.native.configure({ ui = false })
Chooser.configure({})
