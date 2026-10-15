-- The icon engine and its small neighbours, in plain Lua with fake sources and a stub of the few
-- hs calls the two real sources make, so no Hammerspoon and no lock are needed.
--
-- Covered, the order and the fallback, the string shorthand, a spec entry for a source nothing
-- registered, caching so an icon is drawn once, the colour keyed cache for a tinted source
-- only, a draw that answers nothing, the contract refusing a bad source, the config file, the
-- row resolver, the manifest check in the registrar, and what the sf source does with a name.
--
-- Run it.
--   lua test/icons.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local icons = dofile(here .. "../lib/icons/init.lua")
local configLib = dofile(here .. "../lib/icons/config.lua")
local rowsLib = dofile(here .. "../lib/icons/rows.lua")
local registrarLib = dofile(here .. "../lib/registrar.lua")

local failed = false

local function check(name, got, want)
  if got ~= want then
    failed = true
    print(("FAIL %s, wanted %s, got %s"):format(name, tostring(want), tostring(got)))
  else
    print(("ok   %s"):format(name))
  end
end

local function raises(name, fn, needle)
  local ok, err = pcall(fn)
  if ok or not tostring(err):find(needle, 1, true) then
    failed = true
    print(("FAIL %s, wanted an error holding '%s', got %s"):format(name, needle, tostring(ok and "no error" or err)))
  else
    print(("ok   %s"):format(name))
  end
end

-- A fake source that counts its draws and answers a table naming what it was asked, or nil for
-- a value in its refuse set.
local function fake(name, opts)
  opts = opts or {}
  local source = { name = name, tinted = opts.tinted, draws = 0 }
  function source.draw(value, points, color)
    source.draws = source.draws + 1
    if opts.refuse and opts.refuse[value] then return nil end
    return { from = name, value = value, points = points, color = color }
  end
  return source
end

-- Order and fallback.
do
  local sf, emoji = fake("sf", { refuse = { unknown = true } }), fake("emoji")
  local engine = icons.new({ sources = { emoji, sf }, order = { "sf", "emoji" } })
  local img = engine.image({ emoji = "E", sf = "known" }, 28)
  check("the active set is tried first", img.from, "sf")
  check("the size is passed through", img.points, 28)
  img = engine.image({ emoji = "E", sf = "unknown" }, 28)
  check("a draw that answers nothing falls back", img.from, "emoji")
  img = engine.image({ emoji = "E" }, 28)
  check("a spec with no entry for the active set falls back", img.from, "emoji")
  img = engine.image({ sf = "known" }, 28)
  check("only the source named in the order that has an entry draws", img.from, "sf")
  check("a spec nothing can draw answers nil", engine.image({ sf = "unknown" }, 28), nil)
  check("an entry for a source nothing registered is skipped", engine.image({ nope = "x", emoji = "E" }, 28).from, "emoji")
  check("an entry for an unregistered source alone answers nil", engine.image({ nope = "x" }, 28), nil)
  check("a nil spec answers nil", engine.image(nil, 28), nil)
  check("has answers for a registered name", engine.has("sf"), true)
  check("has refuses an unregistered name", engine.has("nope"), false)
end

-- The string shorthand.
do
  local emoji = fake("emoji")
  local engine = icons.new({ sources = { emoji }, order = { "emoji" } })
  local img = engine.image("E", 72)
  check("a string is shorthand for an emoji entry", img.from .. img.value, "emojiE")
end

-- An order naming a source nothing registered is skipped rather than raising.
do
  local emoji = fake("emoji")
  local engine = icons.new({ sources = { emoji }, order = { "ghost", "emoji" } })
  check("an order entry with no source is skipped", engine.image({ emoji = "E" }, 72).from, "emoji")
end

-- Caching.
do
  local emoji = fake("emoji")
  local engine = icons.new({ sources = { emoji }, order = { "emoji" } })
  local a = engine.image({ emoji = "E" }, 72)
  local b = engine.image({ emoji = "E" }, 72)
  check("the same image comes back", a, b)
  check("an icon is drawn once", emoji.draws, 1)
  engine.image({ emoji = "E" }, 28)
  check("another size is another drawing", emoji.draws, 2)
  local refusing = fake("emoji", { refuse = { E = true } })
  local second = icons.new({ sources = { refusing }, order = { "emoji" } })
  second.image({ emoji = "E" }, 72)
  second.image({ emoji = "E" }, 72)
  check("a draw that answers nothing is asked once", refusing.draws, 1)
end

-- The colour keys the cache for a tinted source and not for one that ignores it.
do
  local tint = { red = 1, green = 0, blue = 0, alpha = 1 }
  local plain, tinted = fake("emoji"), fake("sf", { tinted = true })
  local engine = icons.new({ sources = { plain, tinted }, order = { "sf", "emoji" },
    color = function() return tint end })
  engine.image({ sf = "a" }, 28)
  engine.image({ sf = "a" }, 28)
  check("a tinted icon is drawn once for one colour", tinted.draws, 1)
  tint = { red = 0, green = 0, blue = 1, alpha = 1 }
  local redrawn = engine.image({ sf = "a" }, 28)
  check("a colour change redraws a tinted icon", tinted.draws, 2)
  check("the new colour is the one handed to draw", redrawn.color.blue, 1)
  engine.image({ emoji = "e" }, 28)
  tint = { red = 0, green = 1, blue = 0, alpha = 1 }
  engine.image({ emoji = "e" }, 28)
  check("a colour change does not redraw an icon that ignores colour", plain.draws, 1)
  check("a source that ignores colour is handed none", engine.image({ emoji = "e" }, 28).color, nil)
end

-- The contract.
do
  raises("a source with no name is refused", function() icons.new({ sources = { { draw = function() end } } }) end, "no name")
  raises("a source with no draw is refused and named", function() icons.new({ sources = { { name = "x" } } }) end, "'x' has no draw")
  raises("a source that is not a table is refused", function() icons.new({ sources = { "x" } }) end, "not a table")
  raises("a tinted field that is not a boolean is refused", function()
    icons.new({ sources = { { name = "x", draw = function() end, tinted = "yes" } } })
  end, "'x' has a tinted field")
  raises("two sources of one name are refused", function()
    icons.new({ sources = { fake("emoji"), fake("emoji") } })
  end, "registered twice")
end

-- The config file.
do
  local function load(text, known)
    local warned = {}
    local out = configLib.load("icons.toml", function() return text end,
      { w = function(m) warned[#warned + 1] = m end }, known)
    return out, warned
  end
  local known = function(name) return name == "emoji" or name == "sf" end
  local out, warned = load('set = "sf"\nfallback = "emoji"\n', known)
  check("the set is read", out.set, "sf")
  check("the fallback is read", out.fallback, "emoji")
  check("a clean file warns nothing", #warned, 0)
  out, warned = load('set = "bogus"\n', known)
  check("an unknown set keeps the shipped one", out.set, "emoji")
  check("an unknown set warns once", #warned, 1)
  out, warned = load('set = "sf"\nextra = "x"\n', known)
  check("an unknown key warns and the rest is kept", out.set .. #warned, "sf1")
  out = configLib.load(nil, nil, { w = function() end }, known)
  check("no path is the shipped set", out.set .. out.fallback, "emojiemoji")
  out, warned = load("not toml at all", known)
  check("a file that does not parse is the shipped set with one warning", out.set .. #warned, "emoji1")
  check("the order puts the set first", table.concat(configLib.order({ set = "sf", fallback = "emoji" }), ","), "sf,emoji")
  check("the order drops a repeated name", table.concat(configLib.order({ set = "emoji", fallback = "emoji" }), ","), "emoji")
end

-- The row resolver.
do
  local engine = icons.new({ sources = { fake("emoji") }, order = { "emoji" } })
  local warnings = {}
  local resolver = rowsLib.new({
    engine = engine, points = 72,
    declared = function(owner) return owner == "vpn" and { on = { emoji = "A" } } or nil end,
    log = { w = function(m) warnings[#warnings + 1] = m end },
  })
  local plain = { title = "plain" }
  check("a row with no icon is returned untouched", resolver.resolve(plain, "vpn"), plain)
  local keyed = { title = "k", icon = "on" }
  local resolved = resolver.resolve(keyed, "vpn")
  check("a key resolves against the owner's icons", resolved.image.value, "A")
  check("the resolved size is the one asked for", resolved.image.points, 72)
  check("the plugin's own row table is not mutated", keyed.image, nil)
  resolved = resolver.resolve({ icon = { emoji = "Z" } }, "other")
  check("a table spec is drawn as it is", resolved.image.value, "Z")
  local picture = { icon = "on", image = "real" }
  check("a row that carries an image keeps it", resolver.resolve(picture, "vpn"), picture)
  resolved = resolver.resolve({ icon = "missing" }, "vpn")
  check("an unknown key shows no icon", resolved.image, nil)
  resolver.resolve({ icon = "missing" }, "vpn")
  check("an unknown key warns once per owner and key", #warnings, 1)
  resolver.resolve({ icon = "on" }, "other")
  check("the same key under another owner warns again", #warnings, 2)
  local list = { plain, picture }
  check("a list needing nothing comes back as itself", resolver.resolveAll(list, "vpn"), list)
  local out = resolver.resolveAll({ plain, keyed }, "vpn")
  check("a list that needed something is a new list", out[2].image.value, "A")
  check("the rows that needed nothing are the same rows", out[1], plain)
end

-- The manifest check.
do
  local function verdict(icons)
    local logs = {}
    local table_, ok = registrarLib.validateIcons("x", { icons = icons }, {
      log = function(level, msg) logs[#logs + 1] = msg end,
    })
    return table_, ok, logs
  end
  local _, ok = verdict(nil)
  check("no icons is fine", ok, true)
  local t
  t, ok = verdict({ on = { emoji = "A", sf = "b" } })
  check("a good table is accepted and answered", ok and t.on.sf, "b")
  local logs
  _, ok, logs = verdict("nope")
  check("a non table is refused", ok, false)
  check("a refusal names the plugin", logs[1]:find("registrar refused 'x'", 1, true) ~= nil, true)
  _, ok = verdict({ [1] = { emoji = "A" } })
  check("a key that is not a string is refused", ok, false)
  _, ok = verdict({ on = {} })
  check("an entry with no value is refused", ok, false)
  _, ok = verdict({ on = { emoji = 5 } })
  check("an entry with no string value is refused", ok, false)
  _, ok = verdict({ on = "A" })
  check("an entry that is not a table is refused", ok, false)
  t, ok = registrarLib.validateIcons("x", { icons = { on = 1 } })
  check("no log means a quiet refusal", ok, false)
end

-- The two real sources, against a stub of the hs calls they make.
do
  local sfSource = dofile(here .. "../lib/icons/sources/sf.lua")
  local emojiSource = dofile(here .. "../lib/icons/sources/emoji.lua")
  local scripts = {}
  local canvases = {}
  local function image(w, h)
    local img = { w = w, h = h }
    function img:size() return { w = self.w, h = self.h } end
    function img:setSize(size) return { w = size.w, h = size.h, sized = true } end
    return img
  end
  _G.hs = {
    osascript = { javascript = function(script)
      scripts[#scripts + 1] = script
      if script:find("'nope.nope'", 1, true) then return true, "unknown" end
      return true, "ok"
    end },
    image = { imageFromPath = function() return image(98, 72) end },
    canvas = { new = function(frame)
      local c = { frame = frame }
      function c:imageFromCanvas() return image(frame.w, frame.h) end
      function c:delete() end
      canvases[#canvases + 1] = c
      return setmetatable(c, { __newindex = function(t, k, v) rawset(t, k, v) end })
    end },
  }
  local source = sfSource.new({ scratchDir = function() return "/tmp" end })
  check("the sf source is named sf", source.name, "sf")
  check("the sf source is tinted", source.tinted, true)
  check("an unsafe name is refused without calling out", source.draw("a'); evil('", 28, nil), nil)
  check("no script ran for an unsafe name", #scripts, 0)
  check("a name with a space is refused", source.draw("a b", 28, nil), nil)
  check("an unknown name answers nil", source.draw("nope.nope", 28, nil), nil)
  scripts = {}
  local img = source.draw("cup.and.saucer.fill", 28, { red = 0.5, green = 0.25, blue = 1, alpha = 1 })
  check("a known name answers an image sized to the points", img and img.w, 28)
  check("the colour is spliced into the script", scripts[1]:find("0.5000, 0.2500, 1.0000, 1.0000", 1, true) ~= nil, true)
  local square = canvases[#canvases][1]
  check("the symbol is centred keeping its aspect", math.abs((72 - square.frame.w) / 2 - square.frame.x) < 1e-9
    and math.abs(square.frame.w / square.frame.h - 98 / 72) < 1e-9, true)
  check("the longest side fills 60 of 72 points", square.frame.w, 60)
  local glyph = emojiSource.new().draw("E", 72, nil)
  check("the emoji source draws on a 72 point canvas", glyph.w, 72)
  check("the emoji source answers nil for an empty glyph", emojiSource.new().draw("", 72, nil), nil)
  _G.hs = nil
end

if failed then os.exit(1) end
