-- Unit case for Olm.spoon/lib/recency.lua, the lift to front ordering
-- service every caller with a remembered order asks its own instance from.
-- The runner reaches this file with a dofile call carrying an absolute path,
-- so this file in turn locates itself the same way, through debug.getinfo,
-- and derives the module path from there. No absolute path is ever written
-- down here, and the module under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description,
-- and the runner counts and reports from those lines alone, the same
-- convention cases/storage.lua and cases/match.lua already follow.
--
-- Every block below uses a scratch settings key of its own rather than a
-- real caller's key, and clears it both before and after its assertions with
-- hs.settings.clear, so no run touches real data and a failed run leaves
-- nothing behind for the next one to trip over.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/recency.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local function freshModule()
  local chunk, err = loadfile(modulePath)
  if not chunk then
    error("could not load Olm.spoon/lib/recency.lua, " .. tostring(err))
  end
  return chunk()
end

-- A missing opts.settingsKey raises a readable error rather than failing
-- later inside hs.settings with a generic one, the same proof cases/storage.lua
-- already makes for a builder called before configure.
do
  local M = freshModule()
  local calledOk, err = pcall(function() return M.new({}) end)
  check(
    "M.new without opts.settingsKey raises a readable error",
    calledOk == false and type(err) == "string" and #err > 0,
    "pcall returned ok=" .. tostring(calledOk) .. " err=" .. tostring(err)
  )
end

-- Touching, leading, and moving rather than duplicating, on one instance and
-- one scratch key.
do
  local scratchKey = "Olm.test.recency.touch"
  hs.settings.clear(scratchKey)

  local M = freshModule()
  local r = M.new({ settingsKey = scratchKey })

  r.touch("alpha")
  check("a touched key leads the order", r.rankOf("alpha") == 1)

  r.touch("beta")
  check("a second touch of another key takes the front", r.rankOf("beta") == 1)
  check("the earlier key drops to second rather than being dropped", r.rankOf("alpha") == 2)

  r.touch("alpha")
  check("touching an existing key moves it to the front", r.rankOf("alpha") == 1)
  check("the moved key does not duplicate, the other key still sits second", r.rankOf("beta") == 2)

  check("rankOf answers nil for a key never touched", r.rankOf("gamma") == nil)

  hs.settings.clear(scratchKey)
end

-- order, remembered items leading in remembered order, the rest following
-- in arrival order, and two items sharing a key keeping their relative
-- order.
do
  local scratchKey = "Olm.test.recency.order"
  hs.settings.clear(scratchKey)

  local M = freshModule()
  local r = M.new({ settingsKey = scratchKey })

  r.touch("b")
  r.touch("a")
  -- The remembered order is now a, b, most recent first.

  local items = {
    { key = "c", label = "c1" },
    { key = "b", label = "b1" },
    { key = "d", label = "d1" },
    { key = "a", label = "a1" },
    { key = "b", label = "b2" },
  }
  local keyOf = function(item) return item.key end
  local ordered = r.order(items, keyOf)

  local labels = {}
  for _, item in ipairs(ordered) do labels[#labels + 1] = item.label end
  local gotLabels = table.concat(labels, ",")

  check(
    "order leads with remembered items in remembered order, leaves the rest in arrival order, and keeps a shared key's relative order",
    gotLabels == "a1,b1,b2,c1,d1",
    "got " .. gotLabels
  )

  hs.settings.clear(scratchKey)
end

-- A limit drops the oldest key past the cap.
do
  local scratchKey = "Olm.test.recency.limit"
  hs.settings.clear(scratchKey)

  local M = freshModule()
  local r = M.new({ settingsKey = scratchKey, limit = 2 })

  r.touch("one")
  r.touch("two")
  r.touch("three")

  check("a limit drops the oldest key past the cap", r.rankOf("one") == nil)
  check("the cap still keeps the newer keys in order", r.rankOf("two") == 2 and r.rankOf("three") == 1)

  hs.settings.clear(scratchKey)
end

-- A second instance created on the same settings key sees the persisted
-- order, since persistence is what lets a caller's order survive a reload.
do
  local scratchKey = "Olm.test.recency.persist"
  hs.settings.clear(scratchKey)

  local M = freshModule()
  local first = M.new({ settingsKey = scratchKey })
  first.touch("x")
  first.touch("y")

  local second = M.new({ settingsKey = scratchKey })
  check(
    "a second instance created on the same settings key sees the persisted order",
    second.rankOf("y") == 1 and second.rankOf("x") == 2
  )

  hs.settings.clear(scratchKey)
end
