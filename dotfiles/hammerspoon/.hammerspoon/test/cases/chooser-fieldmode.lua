-- Unit case for the fieldModes set Olm.spoon/lib/chooser/providers/native.lua publishes
-- and for memberFieldMode, the one answer both the constructor and setFieldMode now give
-- to a value that is not a member. It loads the provider directly, which it can because
-- that file loads no siblings of its own.
--
-- memberFieldMode is what is exercised rather than either caller, deliberately. Building
-- a real instance would build a real hs.chooser widget, and both callers do nothing with
-- a mode except hand it to this function, so testing it covers both without drawing
-- anything. That is stated here so the gap is a choice on the record rather than an
-- oversight, and if either caller ever decides something of its own, this stops being
-- enough.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/native.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function freshModule()
  local chunk, err = loadfile(modulePath)
  if not chunk then error("could not load the native chooser provider, " .. tostring(err)) end
  return chunk()
end

-- The set answers its four members, the same four the config doc above it has enumerated
-- in prose since before the set existed.
do
  local M = freshModule()
  local want = { "filter", "off", "input", "hybrid" }
  local bad = {}
  for _, name in ipairs(want) do
    if M.fieldModes[name] ~= name then bad[#bad + 1] = name end
  end
  check("fieldModes answers all four members, each valued as its own name",
    #bad == 0, "wrong or absent, " .. table.concat(bad, " "))
end

-- Every member is handed back unchanged, so validation costs a correct caller nothing.
do
  local M = freshModule()
  local kept = true
  local which = ""
  for _, member in pairs(M.fieldModes) do
    if M.memberFieldMode(member) ~= member then kept = false which = member end
  end
  check("every member is answered unchanged", kept, "it changed " .. which)
end

-- No mode at all means filter, which is what the constructor's own or filter used to say
-- and what the documented default has always been.
do
  local M = freshModule()
  check("no mode means filter", M.memberFieldMode(nil) == M.fieldModes.filter)
end

-- A typo means filter with a warning, rather than being stored. Stored, it left a field
-- that silently did nothing, which reads as the tool being broken rather than as a typo.
do
  local M = freshModule()
  check("a mistyped mode falls back to filter",
    M.memberFieldMode("flter") == M.fieldModes.filter)
  check("a mode of the wrong type falls back to filter",
    M.memberFieldMode(7) == M.fieldModes.filter)
end
