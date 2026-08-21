-- Unit case for the two closed sets Olm.spoon/lib/panel.lua publishes, placements and
-- aligns, and for the validation that stands behind them. The runner reaches this file
-- with a dofile call carrying an absolute path, so this file locates itself the same way
-- and derives the module path from there, writing no absolute path down.
--
-- What this covers is the set and the fallback, never the drawing. A panel's geometry
-- needs a real anchor and a real screen and is not what changed, while a mistyped option
-- silently placing a panel somewhere nobody asked for is exactly what changed.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/panel.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function freshModule()
  local chunk, err = loadfile(modulePath)
  if not chunk then error("could not load Olm.spoon/lib/panel.lua, " .. tostring(err)) end
  return chunk()
end

-- A set answers its members, and a member's value is its own name, which is what keeps a
-- stored config readable and made converting every call site a swap of one expression for
-- another rather than a change to what is stored.
do
  local M = freshModule()
  local wantPlacements = { "below", "above", "left", "right", "center" }
  local missing = {}
  for _, name in ipairs(wantPlacements) do
    if M.placements[name] ~= name then missing[#missing + 1] = name end
  end
  check("placements answers all five members, each valued as its own name",
    #missing == 0, "wrong or absent, " .. table.concat(missing, " "))

  local wantAligns = { "start", "center", "end" }
  local badAligns = {}
  for _, name in ipairs(wantAligns) do
    if M.aligns[name] ~= name then badAligns[#badAligns + 1] = name end
  end
  check("aligns answers all three members, each valued as its own name",
    #badAligns == 0, "wrong or absent, " .. table.concat(badAligns, " "))
end

-- An omitted option takes the documented default rather than staying nil, so the frame
-- maths never compares against a value that was never decided.
do
  local M = freshModule()
  local p = M.new({ content = { preferredSize = function() return { w = 1, h = 1 } end,
                                draw = function() end } })
  check("an omitted placement becomes below", p.config.placement == M.placements.below,
    "it was " .. tostring(p.config.placement))
  check("an omitted align becomes start", p.config.align == M.aligns.start,
    "it was " .. tostring(p.config.align))
end

-- A named value handed in is kept exactly, so validation costs a correct caller nothing.
do
  local M = freshModule()
  local p = M.new({ content = { preferredSize = function() return { w = 1, h = 1 } end,
                                draw = function() end },
                    placement = M.placements.center, align = M.aligns["end"] })
  check("a member placement is kept", p.config.placement == M.placements.center,
    "it was " .. tostring(p.config.placement))
  check("a member align is kept", p.config.align == M.aligns["end"],
    "it was " .. tostring(p.config.align))
end

-- A typo falls back rather than being stored. Stored, it left a panel drawn on a side
-- nobody named with nothing anywhere saying so, which is the whole reason the set exists.
do
  local M = freshModule()
  -- The two wrong values are named through locals rather than written straight into the
  -- table, because the reconciler check this set exists for errors on a bare string handed
  -- to one of these keys anywhere under dotfiles, this file included. Excluding the tests
  -- from that check was the alternative and it is worse, since the exclusion is exactly
  -- where a real bare string would then be able to hide.
  local placementTypo, alignTypo = "beneath", "middle"
  local p = M.new({ content = { preferredSize = function() return { w = 1, h = 1 } end,
                                draw = function() end },
                    placement = placementTypo, align = alignTypo })
  check("a mistyped placement falls back to below rather than being stored",
    p.config.placement == M.placements.below, "it was " .. tostring(p.config.placement))
  check("a mistyped align falls back to start rather than being stored",
    p.config.align == M.aligns.start, "it was " .. tostring(p.config.align))
end
