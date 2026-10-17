-- Unit case for choosing the launcher's Aliases row. The row is a catalog row of kind special
-- with no owner and no tool, so the registry has no presentation for it, and it used to run and
-- close the launcher before seeding a field that was already gone. It now answers through the
-- launcher's replacement question like a directory row does, so the list stays open and the
-- field takes the word the directory scope answers to.
--
-- The answer comes from lib/registrar.lua, the same function the composition root hands to the
-- launcher as rowIntercept, and the launcher is a fresh copy loaded straight out of this
-- checkout with a recording stage, so nothing here touches the running config.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoon = caseDir .. "/../../Spoons/Olm.spoon/"

if hs == nil then
  hs = {
    settings = { get = function() return nil end, set = function() end },
    processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
    logger = { new = function()
      return setmetatable({}, { __index = function() return function() end end })
    end },
    timer = { doAfter = function(_, fn) return { fire = function() fn() end, stop = function() end } end },
    image = { imageFromAppBundle = function() return nil end },
    application = {
      runningApplications = function() return {} end,
      pathForBundleID = function() return "" end,
      nameForBundleID = function() return nil end,
    },
    hotkey = { bind = function() end },
  }
end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function load(rel)
  local chunk, err = loadfile(spoon .. rel)
  if not chunk then error("could not load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

local registrar = load("lib/registrar.lua")
local launcherManifest = load("host/launcher/manifest.lua")

local launcher = load("host/launcher/init.lua")
launcher:init()

local typed = nil
launcher._stage = { setQuery = function(_, text) typed = text end, setPlaceholder = function() end }

local words = { aliasDirectory = "? " }
launcher._actions = {
  rowIntercept = registrar.aliasRowReplacement({
    name = "aliasDirectory",
    queryFor = function(name) return words[name] end,
    seed = function(query) launcher:seedQuery(query) end,
  }),
}

local aliasRow
for _, spec in ipairs(launcherManifest.defaults.specialRows) do
  if spec.name == "aliasDirectory" then aliasRow = { kind = "special", name = spec.name } end
end
check("the catalog declares an Aliases row", aliasRow ~= nil)

local replace = launcher:_replacementFor(aliasRow)
check("the Aliases row answers a callable", type(replace) == "function")
if type(replace) == "function" then
  replace()
  check("the callable seeds the word the directory answers to", typed == "? ", tostring(typed))
end

check("a row another plugin owns is never taken for it",
  launcher:_replacementFor({ kind = "special", name = "aliasDirectory", owner = "somebody" }) == nil)
check("another special row is left to run", launcher:_replacementFor({ kind = "special", name = "lock" }) == nil)

words.aliasDirectory = nil
check("a row with no word to seed falls through to the ordinary run",
  launcher:_replacementFor(aliasRow) == nil)
