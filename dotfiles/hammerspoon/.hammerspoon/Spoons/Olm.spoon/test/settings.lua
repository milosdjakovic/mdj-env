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
  check("sections in order", table.concat(order, ","), "general,appearance,motion,behaviour,plugins")
  check("an empty section is not shared", #share.sections, 5)
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

if failed then
  print("settings, FAILED")
  os.exit(1)
end
print("settings, every check passed")
