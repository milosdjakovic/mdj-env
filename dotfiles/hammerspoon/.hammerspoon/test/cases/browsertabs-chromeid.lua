-- Unit case for the BrowserTabs plugin's handling of the optional chromeBundleID.
-- The runner reaches this file with a dofile call carrying an absolute path, so this file
-- locates itself through debug.getinfo and loads the plugin by path with loadfile, never
-- require. No absolute path is written down here.
--
-- The promise under test is the one the manifest makes for that field. A missing or unusable
-- Chrome bundle id costs the person Chrome and nothing else, so configure must never raise
-- and Safari must always be built.
--
-- The skip reasons are read by wrapping hs.logger.new only while the plugin file loads, so the
-- logger the plugin keeps records what its w method is given and still passes it on. That is a
-- wrap of a global around the load, not a hook in the plugin.
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

local warnings
local realNew = hs.logger.new
local function loadPlugin()
  local chunk, err = loadfile(pluginPath)
  if not chunk then error("could not load the browsertabs plugin, " .. tostring(err)) end
  hs.logger.new = function(...)
    local logger = realNew(...)
    local realW = logger.w
    -- The plugin calls log.w with a dot and no self, so the wrapper takes the message first.
    logger.w = function(...)
      warnings[#warnings + 1] = table.concat({ ... }, " ")
      return realW(...)
    end
    return logger
  end
  local loaded, obj = pcall(chunk)
  hs.logger.new = realNew
  if not loaded then error(obj) end
  return obj
end

local scenarios = {
  { label = "nil", value = nil, chrome = false },
  { label = "an empty string", value = "", chrome = false, reason = "no Chrome bundle id was supplied" },
  { label = "a number", value = 42, chrome = false, reason = "a bundleID is required" },
  { label = "a valid bundle id", value = "com.google.Chrome", chrome = true },
}

for _, s in ipairs(scenarios) do
  warnings = {}
  local obj = loadPlugin()
  local ran, why = pcall(function()
    obj:configure({
      providers = { "safari", "arc", "chrome" },
      chromeBundleID = s.value,
      settingsKey = "Olm.test.browsertabs.chromeid",
    })
  end)
  check("configure with chromeBundleID " .. s.label .. " does not raise", ran, tostring(why))
  check("Safari is built with chromeBundleID " .. s.label, has(obj._providers, "Safari"),
    "built " .. names(obj._providers))
  check("Arc is built with chromeBundleID " .. s.label, has(obj._providers, "Arc"),
    "built " .. names(obj._providers))
  check("Chrome is " .. (s.chrome and "built" or "absent") .. " with chromeBundleID " .. s.label,
    has(obj._providers, "Chrome") == s.chrome, "built " .. names(obj._providers))

  if s.reason then
    local skip
    for _, w in ipairs(warnings) do
      if w:find("skipping the browser 'chrome'", 1, true) then skip = w end
    end
    local reason = skip and skip:match("skipping the browser 'chrome', (.*)$") or ""
    check("the Chrome skip reason for " .. s.label .. " contains " .. s.reason,
      reason:find(s.reason, 1, true) ~= nil, "reason was " .. reason)
    check("the Chrome skip reason for " .. s.label .. " starts with neither a path nor nil",
      reason ~= "" and not reason:find("^[^%s]*/") and not reason:find("^[^:]*:%d+:")
        and not reason:find("^nil"), "reason was " .. reason)
  end
end
