-- Unit case for the BrowserTabs plugin's handling of the optional chromeBundleID.
-- The runner reaches this file with a dofile call carrying an absolute path, so this file
-- locates itself through debug.getinfo and loads the plugin by path with loadfile, never
-- require. No absolute path is written down here.
--
-- The promise under test is the one the manifest makes for that field. A missing or unusable
-- Chrome bundle id costs the person Chrome and nothing else, so configure must never raise
-- and Safari must always be built.
--
-- The built list is read from obj._providers, the validated list configure leaves behind and
-- the one the engine is handed. Nothing else on the module exposes it, and no test only hook
-- was added for this.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local pluginPath = caseDir .. "/../../Spoons/Olm.spoon/plugins/browsertabs/init.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function names(list)
  local out = {}
  for _, p in ipairs(list or {}) do out[#out + 1] = p.name end
  return table.concat(out, "+")
end

local function has(list, wanted)
  for _, p in ipairs(list or {}) do
    if p.name == wanted then return true end
  end
  return false
end

local scenarios = {
  { label = "nil", value = nil, chrome = false },
  { label = "an empty string", value = "", chrome = false },
  { label = "a number", value = 42, chrome = false },
  { label = "a valid bundle id", value = "com.google.Chrome", chrome = true },
}

for _, s in ipairs(scenarios) do
  local chunk, err = loadfile(pluginPath)
  if not chunk then error("could not load the browsertabs plugin, " .. tostring(err)) end
  local obj = chunk()
  local ran, why = pcall(function()
    obj:configure({
      providers = { "safari", "chrome" },
      chromeBundleID = s.value,
      settingsKey = "Olm.test.browsertabs.chromeid",
    })
  end)
  check("configure with chromeBundleID " .. s.label .. " does not raise", ran, tostring(why))
  check("Safari is built with chromeBundleID " .. s.label, has(obj._providers, "Safari"),
    "built " .. names(obj._providers))
  check("Chrome is " .. (s.chrome and "built" or "absent") .. " with chromeBundleID " .. s.label,
    has(obj._providers, "Chrome") == s.chrome, "built " .. names(obj._providers))
end
