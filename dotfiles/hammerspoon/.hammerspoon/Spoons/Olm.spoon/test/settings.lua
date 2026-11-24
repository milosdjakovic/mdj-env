-- Olm Settings, the declarations and the one store, offline, docs/DESIGN-APP-SETTINGS.md step 1.
--
-- Pins lib/settings.lua. A saved value wins over the file's and a value the declaration does not
-- allow is said once and leaves the file's. The five keys of Hammerspoon's own settings move once
-- and are removed there, a value already in the store is kept. A store that cannot be read is kept
-- beside before the first write. The share lists the sections in order, every setting with its
-- default and value, and leaves out a hidden or absent one.
--
-- Run it.
--   lua test/settings.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local M = assert(loadfile(here .. "../lib/settings.lua"))()
local json = assert(loadfile(here .. "json.lua"))()
-- test/json.lua only decodes, so the store is handed this small encoder, enough for its tables.
function json.encode(value)
  local kind = type(value)
  if kind == "string" then return string.format("%q", value):gsub("\\\n", "\\n") end
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "nil" then return "null" end
  if #value > 0 or next(value) == nil then
    local parts = {}
    for _, v in ipairs(value) do parts[#parts + 1] = json.encode(v) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = json.encode(k) .. ":" .. json.encode(value[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local failed = false

local function check(name, got, want)
  if got ~= want then
    failed = true
    print(("FAIL %s, wanted %s, got %s"):format(name, tostring(want), tostring(got)))
  else
    print(("ok   %s"):format(name))
  end
end

local function disk(initial)
  local files, writes = {}, 0
  for k, v in pairs(initial or {}) do files[k] = v end
  return files, {
    read = function(path) return files[path] end,
    write = function(path, text)
      writes = writes + 1
      files[path] = text
      return true
    end,
    writes = function() return writes end,
  }
end

local function newStore(files, io, said)
  return M.store({ path = "/s/settings.json", read = io.read, write = io.write,
    decode = json.decode, encode = json.encode,
    log = { w = function(message) said[#said + 1] = message end } })
end

-- An empty machine, nothing saved.
do
  local said = {}
  local files, io = disk()
  local store = newStore(files, io, said)
  check("empty store answers nil", store.get("chooser"), nil)
  check("empty store writes nothing", io.writes(), 0)
  check("empty store says nothing", #said, 0)
  store.set("chooser", "default")
  check("a set is written", io.writes(), 1)
  local back = json.decode(files["/s/settings.json"])
  check("written with its version", back.version, 1)
  check("written under values", back.values.chooser, "default")
  store.set("chooser", "default")
  check("the same value again writes nothing", io.writes(), 1)
  store.set("chooser", nil)
  check("nil removes it", store.get("chooser"), nil)
  check("a fresh store reads the file", newStore(files, io, said).get("chooser"), nil)
end

-- The move of the old keys.
do
  local said = {}
  local files, io = disk({ ["/s/settings.json"] = json.encode({ version = 1, values = { theme = "kept" } }) })
  local store = newStore(files, io, said)
  local old = {
    olmChooser = "swift", olmTheme = "nord", olmGlassHighlight = "system",
    overlayDisplayPolicy = { mode = "activeWindow", fixed = "x" },
    ["Olm.disabledPlugins"] = { "vpn", "speedtest" },
    unrelated = "stays",
  }
  local cleared = {}
  local moved = store.migrate({
    get = function(key) return old[key] end,
    clear = function(key) cleared[key] = true; old[key] = nil end,
  })
  check("moved four, the theme was already saved", table.concat(moved, ","), "chooser,highlight,placement,plugins.off")
  check("chooser moved", store.get("chooser"), "swift")
  check("a saved theme wins over the old one", store.get("theme"), "kept")
  check("the placement's table becomes its mode", store.get("placement"), "activeWindow")
  check("highlight moved", store.get("highlight"), "system")
  check("the plugins list moved", table.concat(store.get("plugins.off"), ","), "vpn,speedtest")
  check("every old key is removed", cleared.olmChooser and cleared.olmTheme and cleared.olmGlassHighlight
    and cleared.overlayDisplayPolicy and cleared["Olm.disabledPlugins"], true)
  check("an unrelated key stays", old.unrelated, "stays")
  check("written once", io.writes(), 1)
  local again = store.migrate({ get = function(key) return old[key] end, clear = function() end })
  check("a second load moves nothing", #again, 0)
  check("and writes nothing", io.writes(), 1)
  local copy = store.get("plugins.off")
  copy[1] = "changed"
  check("a read is a copy", store.get("plugins.off")[1], "vpn")
end

-- A store that is not one.
do
  local said = {}
  local files, io = disk({ ["/s/settings.json"] = "{ not json" })
  local store = newStore(files, io, said)
  check("a broken file is said once", #said, 1)
  check("and answers nothing", store.get("chooser"), nil)
  store.set("chooser", "swift")
  check("it is kept beside before the first write", files["/s/settings.json.broken"], "{ not json")
  check("then the store is written", json.decode(files["/s/settings.json"]).values.chooser, "swift")
end

-- Checks.
do
  local byId = {}
  for _, decl in ipairs(M.DECLARED) do byId[decl.id] = decl end
  check("a choice in its list", (M.check(byId.placement, "cursor")), true)
  check("a choice not in its list", (M.check(byId.placement, "fixed")), false)
  check("a number in range", (M.check(byId.cornerRadius, 12)), true)
  check("a number above", (M.check(byId.cornerRadius, 40)), false)
  check("a number below", (M.check(byId.rowLimit, 2)), false)
  check("not a number", (M.check(byId.rowLimit, "50")), false)
  check("NaN is not a number", (M.check(byId.rowLimit, 0 / 0)), false)
  check("a font name", (M.check(byId["font.ui"], "Menlo")), true)
  check("an empty font", (M.check(byId["font.ui"], "")), false)
  check("a list of names", (M.check(byId["plugins.off"], { "a" })), true)
  check("a list with a number", (M.check(byId["plugins.off"], { 1 })), false)
  local _, why = M.check(byId.cornerRadius, 40)
  check("a refusal says why", why, "is above 24")
  local ids = {}
  for _, decl in ipairs(M.DECLARED) do
    check("declared once, " .. decl.id, ids[decl.id], nil)
    ids[decl.id] = true
    local section = false
    for _, s in ipairs(M.SECTIONS) do if s.id == decl.section then section = true end end
    check("in a section, " .. decl.id, section, true)
    if decl.kind == "number" then
      check("a number has its range, " .. decl.id, decl.min ~= nil and decl.max ~= nil and decl.step ~= nil, true)
      if decl.shipped ~= nil then
        check("its shipped value is in range, " .. decl.id, (M.check(decl, decl.shipped)), true)
      end
    end
  end
end

-- Precedence, laid over the root's tables.
do
  local said = {}
  local files, io = disk({ ["/s/settings.json"] = json.encode({ version = 1, values = {
    cornerRadius = 8, borderWidth = 9, rowLimit = 100, ["size.title"] = 22, ["icons.set"] = "emoji",
    cycleIdle = 1.2,
  } }) })
  local store = newStore(files, io, said)
  local settings = M.new({ store = store, log = { w = function(message) said[#said + 1] = message end } })
  local policy = { surface = { cornerRadius = 17, borderWidth = 1 }, spacing = {}, chooserRowLimit = 50,
    motion = { show = 0.15 }, chord = { holdDelay = 0.6 } }
  settings.overlay("policy", policy)
  check("a saved radius wins over the file", policy.surface.cornerRadius, 8)
  check("the file's radius is its default", settings.default("cornerRadius"), 17)
  check("a saved width out of range leaves the file's", policy.surface.borderWidth, 1)
  check("which is said once", #said, 1)
  settings.value("borderWidth")
  check("and only once", #said, 1)
  check("a saved row limit wins", policy.chooserRowLimit, 100)
  check("a key the file leaves out takes the shipped default", settings.default("spacing.outer"), 9)
  check("and stays unset in the table", policy.spacing.outer, nil)
  check("an unsaved value is the file's", settings.value("motion.show"), 0.15)

  local typography = { fonts = {}, sizes = { title = 24 } }
  settings.overlay("typography", typography, { fonts = { ui = "Kit Font" }, sizes = { title = 20, body = 16 } })
  check("a saved title size wins", typography.sizes.title, 22)
  check("its default is the file's", settings.default("size.title"), 24)
  check("a font left out takes the kit's shipped one", settings.default("font.ui"), "Kit Font")
  check("a size left out takes the kit's shipped one", settings.default("size.body"), 16)
  check("and stays unset", typography.sizes.body, nil)

  local icons = { set = "sf", fallback = "emoji" }
  settings.overlay("icons", icons)
  check("a saved icon set wins", icons.set, "emoji")
  check("its default is the file's", settings.default("icons.set"), "sf")

  local stage = { CYCLE_IDLE = 0.8 }
  settings.overlay("stage", stage)
  check("a saved cycle wait wins on the stage", stage.CYCLE_IDLE, 1.2)

  local declared = {}
  for _, decl in ipairs(M.DECLARED) do declared[#declared + 1] = decl end
  declared[#declared + 1] = { id = "deep", section = "general", title = "Deep", kind = "number", min = 0, max = 99,
    target = { "policy", "a", "b", "c" }, shipped = 1 }
  local deep = M.new({ store = store, declared = declared })
  store.set("deep", 7)
  local nested = { a = { b = { c = 3 } } }
  deep.overlay("policy", nested)
  check("a saved value reaches a nested table", nested.a.b.c, 7)
  local missing = {}
  deep.overlay("policy", missing)
  check("a group the file leaves out is not made", missing.a, nil)
  check("and the default is the shipped one", deep.default("deep"), 1)

  settings.declare("chooser", { choices = { { value = "default", title = "Canvas" }, { value = "swift", title = "Glass" } },
    default = "swift" })
  check("a declared default answers", settings.value("chooser"), "swift")
  store.set("chooser", "legacy")
  check("a saved choice not offered is refused", settings.saved("chooser"), nil)
  store.set("chooser", "default")
  check("a saved choice offered wins", settings.value("chooser"), "default")

  settings.declare("theme", { choices = { { value = "default", title = "default" } }, default = "default", absent = true })
  settings.declare("plugin.vpn", { section = "plugins", kind = "switch", applies = "reload", title = "VPN",
    member = { list = "plugins.off", name = "vpn" } })
  settings.declare("plugin.emoji", { section = "plugins", kind = "switch", applies = "reload", title = "Emoji",
    member = { list = "plugins.off", name = "emoji" } })
  store.set("plugins.off", { "vpn" })

  local share = settings.share()
  check("the share has its version", share.version, 1)
  local order = {}
  for _, section in ipairs(share.sections) do order[#order + 1] = section.id end
  check("sections in order", table.concat(order, ","), "general,appearance,motion,behaviour,applications,plugins")
  -- Applications holds Olm's own keys setting, Window Management only the window manager's.
  check("an empty section is not shared", #share.sections, 6)
  local rows = {}
  for _, section in ipairs(share.sections) do
    for _, row in ipairs(section.settings) do rows[row.id] = row end
  end
  check("an absent setting is not shared", rows.theme, nil)
  check("a hidden one is not either", rows["plugins.off"], nil)
  check("the highlight with no choices is still shared", rows.highlight ~= nil, true)
  check("a row carries its value", rows.cornerRadius.value, 8)
  check("and its default", rows.cornerRadius.default, 17)
  check("and its range", rows.cornerRadius.max, 24)
  check("and how it applies", rows.chooser.applies, "reload")
  check("a refused value shares the file's", rows.borderWidth.value, 1)
  check("a plugin switched off is off", rows["plugin.vpn"].value, false)
  check("one left on is on", rows["plugin.emoji"].value, true)
  check("a switch's default is on", rows["plugin.vpn"].default, true)
  local encoded = json.encode(share)
  check("the share encodes", type(encoded), "string")
end

-- S.3, a change from the window, checked, saved, reset, and a switch kept in its list.
do
  local files, io = disk()
  local store = newStore(files, io)
  local settings = M.new({ store = store })
  settings.overlay("policy", { surface = { cornerRadius = 17 } })
  local ok, why = settings.change("cornerRadius", 40)
  check("a value out of range is refused", ok, false)
  check("with the reason", why, "is above 24")
  check("and nothing is saved", store.get("cornerRadius"), nil)
  check("a number in range is taken", (settings.change("cornerRadius", 6)), true)
  check("and saved", store.get("cornerRadius"), 6)
  check("and is the value", settings.value("cornerRadius"), 6)
  check("a reset is taken", (settings.change("cornerRadius", nil)), true)
  check("and removes the saved value", store.get("cornerRadius"), nil)
  check("so the file's stands", settings.value("cornerRadius"), 17)
  settings.change("cornerRadius", 6)
  settings.change("cornerRadius", 17)
  check("a value equal to the file's is not saved", store.get("cornerRadius"), nil)
  check("a hidden list is refused", (settings.change("plugins.off", { "vpn" })), false)
  check("an unknown id is refused", (settings.change("nothing", 1)), false)
  settings.declare("plugin.vpn", { section = "plugins", kind = "switch", applies = "reload", title = "VPN",
    member = { list = "plugins.off", name = "vpn" } })
  settings.declare("plugin.git", { section = "plugins", kind = "switch", applies = "reload", title = "Git",
    member = { list = "plugins.off", name = "git" }, locked = "set in config/plugins.lua" })
  check("a switch turned off is taken", (settings.change("plugin.vpn", false)), true)
  check("and joins the plugins switched off", table.concat(store.get("plugins.off") or {}, ","), "vpn")
  check("a switch that is not on or off is refused", (settings.change("plugin.vpn", "off")), false)
  check("a switch turned on again is taken", (settings.change("plugin.vpn", true)), true)
  check("and leaves an empty list unsaved", store.get("plugins.off"), nil)
  local lockedOk, lockedWhy = settings.change("plugin.git", false)
  check("a locked switch is refused", lockedOk, false)
  check("saying where it is set", lockedWhy, "is locked, set in config/plugins.lua")
end

-- S.4, a plugin's own settings from its manifest, laid over its data before it is handed over.
do
  local files, io = disk()
  local store = newStore(files, io, {})
  store.set("wm.movePixels", 35)
  store.set("wm.minWidth", 9999)
  local said = {}
  local settings = M.new({ store = store, log = { w = function(message) said[#said + 1] = message end } })
  local specs = {
    { key = "movePixels", at = { "settings", "windowSizing", "movePixels" }, section = "windows",
      title = "Move step", kind = "number", min = 5, max = 200, step = 5, unit = "pixels", shipped = 20 },
    { key = "minWidth", at = { "settings", "windowSizing", "minWidth" }, section = "windows",
      title = "Smallest width", kind = "number", min = 100, max = 2000, step = 10, shipped = 400 },
    { key = "resizePixels", at = { "settings", "windowSizing", "resizePixels" }, section = "windows",
      title = "Resize step", kind = "number", min = 5, max = 200, step = 5, shipped = 30 },
    { key = "bad", at = { "settings", "x" }, section = "nowhere", title = "Bad", kind = "number", min = 1, max = 2, step = 1 },
    { key = "movePixels", at = { "settings", "y" }, section = "windows", title = "Again", kind = "switch" },
    { key = "word", at = { "settings", "z" }, section = "windows", title = "Word", kind = "choice" },
  }
  local data = { settings = { windowSizing = { minWidth = 500 } } }
  local problems = settings.plugin("wm", specs, data)
  check("a spec naming no section is a problem", problems[1], "settings[4] names no section of the window, nowhere, so it is left out")
  check("a repeated key is a problem", problems[2], "settings[5] repeats the key movePixels, so it is left out")
  check("a choice with no choices is a problem", problems[3], "settings[6] is a choice with no list of two or more, each a value and a title, shipping one of them, so it is left out")
  check("and the rest are declared", settings.declaration("wm.movePixels") ~= nil and settings.declaration("wm.bad") == nil, true)
  check("the id is the identity, a dot and the key", settings.declaration("wm.resizePixels").section, "windows")
  check("every one applies on reload", settings.declaration("wm.movePixels").applies, "reload")
  check("a saved value is laid over the data", data.settings.windowSizing.movePixels, 35)
  check("a key the file leaves out defaults to shipped", settings.default("wm.movePixels"), 20)
  check("a key the file sets defaults to the file", settings.default("wm.minWidth"), 500)
  check("a saved value out of range leaves the file's", data.settings.windowSizing.minWidth, 500)
  check("and is said", #said, 1)
  check("an unsaved one the file leaves out takes its shipped value in the data", data.settings.windowSizing.resizePixels, 30)
  check("a change is checked against the manifest's range", (settings.change("wm.resizePixels", 500)), false)
  local share = settings.share()
  local windows
  for _, section in ipairs(share.sections) do if section.id == "windows" then windows = section end end
  check("the share has a Window Management section", windows and windows.title, "Window Management")
  check("holding the declared three", windows and #windows.settings, 3)
  local noData = settings.plugin("other", specs, nil)
  check("no data still answers the problems", #noData, 3)
  -- A choice, the app toggler's mode, its choices carried to the window and a change checked
  -- against them.
  local modeFiles, modeIo = disk()
  local modeStore = newStore(modeFiles, modeIo, {})
  modeStore.set("apps.mode", "hides")
  local modeSettings = M.new({ store = modeStore, log = { w = function() end } })
  local modeData = {}
  local modeProblems = modeSettings.plugin("apps", { { key = "mode", at = { "mode" }, section = "behaviour",
    title = "App Keys", kind = "choice", shipped = "cycle",
    choices = { { value = "cycle", title = "Cycle through windows" }, { value = "hides", title = "Show and hide" } } } }, modeData)
  check("a choice with its choices is declared", #modeProblems, 0)
  check("its choices reach the window", #modeSettings.declaration("apps.mode").choices, 2)
  check("a saved choice is laid over the data", modeData.mode, "hides")
  check("a value not among its choices is refused", (modeSettings.change("apps.mode", "spin")), false)
  local _, unshipped = M.fromManifest("x", { { key = "m", at = { "m" }, section = "behaviour", title = "M",
    kind = "choice", shipped = "none", choices = { { value = "a", title = "A" }, { value = "b", title = "B" } } } })
  check("a choice shipping none of its choices is a problem", #unshipped, 1)
  -- The Applications page's setting, a table of applications by bundle id, its catalog answered by
  -- the plugin's member as the share is written.
  local appsFiles, appsIo = disk()
  local appsSettings = M.new({ store = newStore(appsFiles, appsIo, {}), log = { w = function() end } })
  local appsData = {}
  appsSettings.plugin("apps", { { key = "apps", at = { "overrides" }, section = "applications",
    title = "Applications", kind = "apps", shipped = {}, extra = "catalog" } }, appsData,
    function(member) return function() return { member = member, list = { "x" } } end end)
  local appsDecl = appsSettings.declaration("apps.apps")
  check("an applications table by bundle id is taken", (appsSettings.change("apps.apps",
    { ["a.b"] = { mode = "hides" }, ["c.d"] = { name = "C", path = "/x/C.app" } })), true)
  check("and laid over the data on the next load", appsSettings.value("apps.apps")["a.b"].mode, "hides")
  check("a mode that is neither is refused", (appsSettings.change("apps.apps", { ["a.b"] = { mode = "spin" } })), false)
  check("a list is refused", (M.check(appsDecl, { { mode = "hides" } })), false)
  check("an own place is taken", (M.check(appsDecl, { ["a.b"] = { place = { display = "pointer", center = true,
    size = { width = 90, height = 80, unit = "percent", maxWidth = 2400 }, padding = { x = 40, y = 20 } } } })), true)
  check("a place on a display of four is refused", (M.check(appsDecl, { ["a.b"] = { place = { display = "builtin" } } })), false)
  check("a percent past all of the display is refused", (M.check(appsDecl, { ["a.b"] = { place = {
    size = { width = 120, height = 80, unit = "percent" } } } })), false)
  check("a size with no height is refused", (M.check(appsDecl, { ["a.b"] = { place = {
    size = { width = 800, unit = "points" } } } })), false)
  -- An application's own key, step 6.2b.
  check("an own key is taken", (M.check(appsDecl, { ["a.b"] = { key = { leader = "hyper", key = "`", code = 50,
    mods = { "shift" } } } })), true)
  check("a key with no code is refused", (M.check(appsDecl, { ["a.b"] = { key = { leader = "hyper", key = "f" } } })), false)
  check("a key with a modifier of none of the four is refused", (M.check(appsDecl, { ["a.b"] = { key = {
    key = "f", code = 3, mods = { "fn" } } } })), false)
  -- A setting naming a switch in liveWhen applies live while the switch is on, and on reload otherwise.
  local liveSettings = M.new({ store = newStore({}, appsIo, {}), log = { w = function() end } })
  liveSettings.plugin("apps", { { key = "apps", at = { "overrides" }, section = "applications",
    title = "Applications", kind = "apps", shipped = {}, liveWhen = "appCatalog" } }, {})
  check("a liveWhen setting applies on reload with no switch answering", liveSettings.applies("apps.apps"), "reload")
  local switchOn = false
  liveSettings.liveWhen(function(name) return name == "appCatalog" and switchOn end)
  check("and still while its switch is off", liveSettings.applies("apps.apps"), "reload")
  switchOn = true
  check("and live while it is on", liveSettings.applies("apps.apps"), "live")
  local appsShare
  for _, section in ipairs(appsSettings.share().sections) do
    if section.id == "applications" then
      for _, row in ipairs(section.settings) do if row.id == "apps.apps" then appsShare = row end end
    end
  end
  check("the share carries the member's answer as extra", appsShare and appsShare.extra and appsShare.extra.member, "catalog")
  -- Olm's own keys, an action to its chord or none, and an exported config taken whole, a saved
  -- value the file leaves out reset.
  check("a key per action is taken", (appsSettings.change("keys", { ["apptoggler.Chrome"] = "hyper+C",
    ["apptoggler.Mail"] = false })), true)
  check("a key that is no chord is refused", (appsSettings.change("keys", { ["apptoggler.Chrome"] = "C" })), false)
  check("an action that is no id is refused", (appsSettings.change("keys", { Chrome = "hyper+C" })), false)
  local imported = {}
  local refused = appsSettings.import({ ["apps.apps"] = { ["a.b"] = { mode = "cycle" } }, rowLimit = 9999 },
    function(id, value) imported[#imported + 1] = id; return appsSettings.change(id, value) end)
  check("import hands each value to change", appsSettings.value("apps.apps")["a.b"].mode, "cycle")
  check("and a value the declaration refuses is said", refused[1] and refused[1].id, "rowLimit")
  check("and a saved value the file leaves out is reset", appsSettings.saved("keys"), nil)
  local _, wrong = M.fromManifest("x", "words")
  check("a settings field that is not a list is a problem", wrong[1], "settings is a string rather than a list")
end

if failed then
  print("settings, FAILED")
  os.exit(1)
end
print("settings, every check passed")
