-- The icon engine and its small neighbours, in plain Lua with fake sources and a stub of the few
-- hs calls the two real sources make, so no Hammerspoon and no lock are needed.
--
-- Covered, the order and the fallback, the string shorthand, a spec entry for a source nothing
-- registered, caching so an icon is drawn once, the colour keyed cache for a tinted source
-- only, a draw that answers nothing, the contract refusing a bad source, the config file, the
-- row resolver, the manifest check in the registrar, and what the sf source does with a name.
-- And the sf source rendering out of process, that it never calls hs.osascript, that a missing
-- picture answers nil and pending and one paint's misses start one run, that a finished run fires
-- the refresh callback, and that a picture on disk is loaded with no run at all.
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

-- A source's variant keys the cache, so a picture drawn at one scale is not served at another.
do
  local scale = "1x"
  local sf = fake("sf")
  function sf.variant() return scale end
  local engine = icons.new({ sources = { sf }, order = { "sf" } })
  engine.image({ sf = "a" }, 28)
  engine.image({ sf = "a" }, 28)
  check("an icon is drawn once for one variant", sf.draws, 1)
  scale = "2x"
  engine.image({ sf = "a" }, 28)
  check("a variant change redraws the icon", sf.draws, 2)
  raises("the contract refuses a variant that is not a function", function()
    icons.new({ sources = { { name = "x", draw = function() end, variant = "2x" } } })
  end, "variant field")
end

-- A draw that answers nil and pending is not remembered, so the picture is found once it exists,
-- and meanwhile the next source in the order answers.
do
  local ready = false
  local sf = { name = "sf", draws = 0 }
  function sf.draw(value)
    sf.draws = sf.draws + 1
    if not ready then return nil, true end
    return { from = "sf", value = value }
  end
  local emoji = fake("emoji")
  local engine = icons.new({ sources = { sf, emoji }, order = { "sf", "emoji" } })
  check("a pending picture falls back to the next source", engine.image({ sf = "a", emoji = "E" }, 28).from, "emoji")
  engine.image({ sf = "a", emoji = "E" }, 28)
  check("a pending picture is asked again", sf.draws, 2)
  ready = true
  check("a pending picture is answered once it exists", engine.image({ sf = "a", emoji = "E" }, 28).from, "sf")
  engine.image({ sf = "a", emoji = "E" }, 28)
  check("and then cached", sf.draws, 3)
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
  check("a row with no icon is returned untouched", resolver.stamp(plain, "vpn"), plain)
  local keyed = { title = "k", icon = "on" }
  local stamped = resolver.stamp(keyed, "vpn")
  check("stamping names the owner on the row", stamped.iconOwner, "vpn")
  check("stamping keeps the icon as data", stamped.icon, "on")
  check("stamping draws no picture", stamped.image, nil)
  check("the plugin's own row table is not mutated", keyed.iconOwner, nil)
  local picture = { icon = "on", image = "real" }
  check("a row that carries an image is returned untouched", resolver.stamp(picture, "vpn"), picture)
  local owned = { icon = "on", iconOwner = "clipboard" }
  check("a row that already names its owner keeps it", resolver.stamp(owned, "vpn"), owned)
  local list = { plain, picture, owned }
  check("a list needing nothing comes back as itself", resolver.stampAll(list, "vpn"), list)
  local out = resolver.stampAll({ plain, keyed }, "vpn")
  check("a list that needed something is a new list", out[2].iconOwner, "vpn")
  check("the rows that needed nothing are the same rows", out[1], plain)
  check("resolve is gone, a row never holds a picture of an icon", resolver.resolve, nil)
  check("resolveAll is gone", resolver.resolveAll, nil)

  -- What the chooser does at paint, ask image for a row's icon and owner.
  check("a stamped key resolves against the owner's icons", resolver.image(stamped.icon, stamped.iconOwner).value, "A")
  check("the resolved size is the one asked for", resolver.image("on", "vpn").points, 72)
  check("a table spec is drawn as it is", resolver.image({ emoji = "Z" }, "other").value, "Z")
  check("an unknown key shows no icon", resolver.image("missing", "vpn"), nil)
  resolver.image("missing", "vpn")
  check("an unknown key warns once per owner and key", #warnings, 1)
  resolver.image("on", "other")
  check("the same key under another owner warns again", #warnings, 2)

  -- The one resolution every reader of an icon shares, an identity icon included.
  check("image resolves a declared key for its owner", resolver.image("on", "vpn").value, "A")
  check("image draws a table spec as it stands", resolver.image({ emoji = "Q" }, "any").value, "Q")
  check("image reads a string that is not an identifier as an emoji", resolver.image("\u{2615}", "vpn").value, "\u{2615}")
  check("image answers nil for nil", resolver.image(nil, "vpn"), nil)
  check("image answers nil for an identifier nobody declared", resolver.image("coffee", "vpn"), nil)
end

-- Resolving at paint reads the colour on every call, so a switch of halves between two paints
-- answers a different picture for the same row, and the same colour answers the same picture.
do
  local tint = { red = 1, green = 1, blue = 1, alpha = 1 }
  local engine = icons.new({
    sources = { fake("sf", { tinted = true }) }, order = { "sf" },
    color = function() return tint end,
  })
  local resolver = rowsLib.new({
    engine = engine, points = 72,
    declared = function() return { go = { sf = "arrow" } } end,
  })
  local stamped = resolver.stamp({ icon = "go" }, "demo")
  local light = resolver.image(stamped.icon, stamped.iconOwner)
  check("the first paint draws in the current colour", light.color.red, 1)
  check("a second paint in the same colour is the same picture", resolver.image(stamped.icon, stamped.iconOwner), light)
  tint = { red = 0, green = 0, blue = 0, alpha = 1 }
  local dark = resolver.image(stamped.icon, stamped.iconOwner)
  check("a paint after the colour changed is a different picture", dark ~= light, true)
  check("the new picture is in the new colour", dark.color.red, 0)
  check("the stamped row never held either picture", stamped.image, nil)
  check("going back to the first colour answers the cached picture", (function()
    tint = { red = 1, green = 1, blue = 1, alpha = 1 }
    return resolver.image(stamped.icon, stamped.iconOwner)
  end)(), light)
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
  local function defaultsVerdict(icons, identity)
    local logs = {}
    local _, good = registrarLib.validateIcons("x", { icons = icons, defaults = { icon = identity } }, {
      log = function(level, msg) logs[#logs + 1] = msg end,
    })
    return good, logs
  end
  ok = defaultsVerdict({ x = { emoji = "A" } }, "x")
  check("a defaults icon naming a declared key is accepted", ok, true)
  local dlogs
  ok, dlogs = defaultsVerdict({ x = { emoji = "A" } }, "y")
  check("a defaults icon naming an undeclared key is refused", ok, false)
  check("that refusal names the plugin and the key", dlogs[1]:find("registrar refused 'x'", 1, true) ~= nil and dlogs[1]:find("'y'", 1, true) ~= nil, true)
  ok = defaultsVerdict(nil, "y")
  check("a defaults icon with no icons table is refused", ok, false)
  ok = defaultsVerdict(nil, { emoji = "A" })
  check("a defaults icon given as a table spec is accepted", ok, true)
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

-- The two real sources, against a stub of the hs calls they make. The sf source renders out of
-- process, so the stub records every task it is asked to start and every timer, and keeps a
-- table of files standing for the disk. hs.osascript is a function that fails the run, since the
-- source must never call it.
do
  local sfSource = dofile(here .. "../lib/icons/sources/sf.lua")
  local emojiSource = dofile(here .. "../lib/icons/sources/emoji.lua")
  local canvases = {}
  local disk, tasks, timers, loaded = {}, {}, {}, {}
  local osascriptCalls = 0
  local function image(w, h)
    local img = { w = w, h = h }
    function img:size() return { w = self.w, h = self.h } end
    function img:setSize(size) return { w = size.w, h = size.h, sized = true } end
    return img
  end
  _G.hs = {
    osascript = setmetatable({}, { __index = function()
      return function() osascriptCalls = osascriptCalls + 1 return false, "never" end
    end }),
    fs = { attributes = function(path)
      if disk[path] then return "file" end
      local f = io.open(path)
      if f then f:close() return "file" end
      return nil
    end },
    image = { imageFromPath = function(path)
      loaded[#loaded + 1] = path
      return disk[path] and image(72, 72) or nil
    end },
    timer = { doAfter = function(_, fn)
      timers[#timers + 1] = fn
      return {}
    end },
    task = { new = function(path, callback, args)
      local t = { path = path, callback = callback, args = args }
      function t:start() self.started = true return self end
      tasks[#tasks + 1] = t
      return t
    end },
    screen = { allScreens = function()
      return { { currentMode = function() return { scale = 1 } end },
               { currentMode = function() return { scale = _G.testScale } end } }
    end },
    canvas = { new = function(frame)
      local c = { frame = frame }
      function c:imageFromCanvas() return image(frame.w, frame.h) end
      function c:delete() end
      canvases[#canvases + 1] = c
      return setmetatable(c, { __newindex = function(t, k, v) rawset(t, k, v) end })
    end },
  }
  local function runTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
  end
  -- Finishes the last task as osascript would, writing every picture it was asked for except
  -- the names in unknown, and printing a line for each of those.
  local function finishTask(task, unknown)
    local script = io.open(task.args[3]):read("a")
    local lines = {}
    for name, path in script:gmatch("job%('([^']+)', [^\n]-, '([^']+)'%);") do
      if unknown and unknown[name] then lines[#lines + 1] = "unknown\t" .. path
      else disk[path] = true end
    end
    task.callback(0, table.concat(lines, "\n"), "")
  end
  local dir = os.tmpname()
  os.remove(dir)
  os.execute("mkdir -p '" .. dir .. "'")
  local red = { red = 1, green = 0, blue = 0, alpha = 1 }
  local blue = { red = 0, green = 0, blue = 1, alpha = 1 }
  _G.testScale = 2

  local source = sfSource.new({ dir = function() return dir end })
  local readies = 0
  check("the sf source is named sf", source.name, "sf")
  check("the sf source is tinted", source.tinted, true)

  -- The script, one run for many jobs.
  local script = sfSource.script({
    { name = "circle", color = red, scale = 2, path = "/tmp/a.png" },
    { name = "globe", color = nil, scale = 0.5, path = "/tmp/b.png" },
  })
  check("the sf script paints every layer with a palette", script:find("configurationWithPaletteColors($([col]))", 1, true) ~= nil, true)
  check("the sf script no longer asks for a hierarchical colour", script:find("Hierarchical", 1, true), nil)
  check("one script renders every job", select(2, script:gsub("\njob%(", "")), 2)
  check("the colour is spliced into its job", script:find("1.0000, 0.0000, 0.0000, 1.0000", 1, true) ~= nil, true)
  check("the script falls back to the label colour for no colour", script:find("$.NSColor.labelColor", 1, true) ~= nil, true)
  check("the job renders at its scale", script:find("2.0000, '/tmp/a.png'", 1, true) ~= nil, true)
  check("a scale below 1 is raised to 1", script:find("1.0000, '/tmp/b.png'", 1, true) ~= nil, true)
  check("the script writes the size in points", script:find("rep.size = $.NSMakeSize(side, side)", 1, true) ~= nil, true)
  check("the longest side fills 60 of 72 points", script:find("k = 60 /", 1, true) ~= nil, true)
  local file = sfSource.fileName("cup.and.saucer.fill", red, 2)
  check("the file is keyed by name, side, scale and colour", file, "sf-cup.and.saucer.fill-72pt-2x-ff0000ff.png")
  check("no colour has a file of its own", sfSource.fileName("globe", nil, 1), "sf-globe-72pt-1x-label.png")

  -- Names.
  check("an unsafe name is refused", source.draw("a'); evil('", 28, nil), nil)
  check("a name with a space is refused", source.draw("a b", 28, nil), nil)
  check("a name that climbs out of the directory is refused", source.draw("../x", 28, nil), nil)

  -- A missing picture answers nil and pending, and one paint's misses start one run.
  local img, pending = source.draw("cup.and.saucer.fill", 28, red)
  check("a missing picture answers nil", img, nil)
  check("and says it is pending", pending, true)
  source.draw("globe", 28, red)
  source.draw("cup.and.saucer.fill", 28, red)
  check("nothing runs before the door has answered", #timers + #tasks, 0)
  source.configure({ osascript = "/door/osascript", onReady = function() readies = readies + 1 end })
  check("configure schedules one run", #timers, 1)
  source.draw("star", 28, red)
  check("a later miss in the same turn joins it", #timers, 1)
  runTimers()
  check("one run starts for every miss", #tasks, 1)
  check("the run is osascript from the door", tasks[1].path, "/door/osascript")
  check("it runs a JavaScript file", tasks[1].args[1] .. " " .. tasks[1].args[2], "-l JavaScript")
  local queuedScript = io.open(tasks[1].args[3]):read("a")
  check("the run holds all three symbols", select(2, queuedScript:gsub("\njob%(", "")), 3)
  img, pending = source.draw("globe", 28, red)
  check("a picture in flight is still pending", pending, true)
  source.draw("moon", 28, red)
  runTimers()
  check("a miss while a run is in flight starts no second run", #tasks, 1)
  finishTask(tasks[1], { star = true })
  check("a finished run fires the refresh callback", readies, 1)
  check("the script file is removed", io.open(tasks[1].args[3]), nil)
  local marker = io.open(dir .. "/" .. sfSource.fileName("star", red, 2) .. ".none")
  check("an unknown symbol leaves a marker", marker ~= nil, true)
  if marker then marker:close() end
  img, pending = source.draw("star", 28, red)
  check("an unknown symbol answers a plain nil", img == nil and pending == nil, true)
  runTimers()
  check("the miss queued during the run starts the next one", #tasks, 2)
  finishTask(tasks[2])
  check("that run fires the callback too", readies, 2)

  -- A picture on disk is loaded with no run.
  local before, timersBefore = #tasks, #timers
  loaded = {}
  img = source.draw("cup.and.saucer.fill", 28, red)
  check("a picture on disk is loaded", img and img.w, 28)
  check("from its file", loaded[1], dir .. "/" .. file)
  check("without any render", #tasks .. "," .. #timers, before .. "," .. timersBefore)

  -- Another colour, a switch of halves, queues every symbol the source knows, in one run.
  source.draw("globe", 28, blue)
  runTimers()
  check("a new colour starts one run", #tasks, before + 1)
  local switchScript = io.open(tasks[#tasks].args[3]):read("a")
  check("that run holds every known symbol at the new colour", select(2, switchScript:gsub("\njob%(", "")), 4)
  finishTask(tasks[#tasks])

  -- Prefetch queues only what is missing.
  local fresh = sfSource.new({ dir = function() return dir end })
  fresh.configure({ osascript = "/door/osascript" })
  fresh.prefetch({ "cup.and.saucer.fill", "globe", "bolt", "bad name" }, red)
  runTimers()
  local prefetchScript = io.open(tasks[#tasks].args[3]):read("a")
  check("prefetch renders only the declared symbols not on disk", select(2, prefetchScript:gsub("\njob%(", "")), 1)
  check("and that one is bolt", prefetchScript:find("job('bolt'", 1, true) ~= nil, true)

  -- No tool means no run, and a plain nil.
  local none = sfSource.new({ dir = function() return dir end })
  none.configure({ osascript = nil })
  local n0 = #tasks
  img, pending = none.draw("bolt", 28, blue)
  runTimers()
  check("without osascript a missing picture answers a plain nil", img == nil and pending == nil, true)
  check("and starts nothing", #tasks, n0)

  -- Scale.
  check("the scale is the largest among the screens", sfSource.scale(), 2)
  check("the variant names the scale", source.variant(), "2x")
  _G.testScale = 1
  check("the variant follows a change of screens", source.variant(), "1x")
  _G.testScale = 9
  check("the scale is bounded", sfSource.scale(), 4)
  local saved = _G.hs.screen
  _G.hs.screen = nil
  check("no hs.screen answers a scale of 1", sfSource.scale(), 1)
  _G.hs.screen = saved
  check("the sf source never calls hs.osascript", osascriptCalls, 0)
  local code = {}
  for line in io.lines(here .. "../lib/icons/sources/sf.lua") do
    if not line:match("^%s*%-%-") then code[#code + 1] = line end
  end
  check("no code line in the sf source names hs.osascript", table.concat(code, "\n"):find("hs.osascript", 1, true), nil)
  os.execute("rm -rf '" .. dir .. "'")
  local glyph = emojiSource.new().draw("E", 72, nil)
  check("the emoji source draws on a 72 point canvas", glyph.w, 72)
  check("the emoji source answers nil for an empty glyph", emojiSource.new().draw("", 72, nil), nil)
  local els = emojiSource.new().elements("E", { x = 10, y = 20, w = 36, h = 36 }, { white = 1 })
  check("the emoji source answers one text element", #els .. els[1].type, "1text")
  check("the text fills 60 of 72 of the frame, as the picture does", els[1].textSize, 30)
  check("the text sits in the frame it was handed", els[1].frame.x .. "," .. els[1].frame.y, "10,20")
  check("the text takes the colour it is handed", els[1].textColor.white, 1)
  check("the emoji source answers no elements for an empty glyph",
    emojiSource.new().elements("", { x = 0, y = 0, w = 1, h = 1 }, nil), nil)
  _G.hs = nil
end

-- Elements, the same walk for a canvas that paints the icon itself.
do
  local sf = fake("sf", { refuse = { unknown = true } })
  local emoji = fake("emoji", { tinted = true })
  function emoji.elements(value, frame, color)
    return { { type = "text", text = value, frame = frame, color = color } }
  end
  local engine = icons.new({ sources = { emoji, sf }, order = { "sf", "emoji" },
    color = function() return { red = 1 } end })
  local box = { x = 1, y = 2, w = 3, h = 4 }
  local els = engine.elements({ emoji = "E", sf = "known" }, box, 72)
  check("a source without elements answers its picture as an image element", els[1].type, "image")
  check("that picture is drawn at points", els[1].image.points, 72)
  check("that picture is placed in the frame", els[1].frame.h, 4)
  engine.elements({ emoji = "E", sf = "known" }, box, 72)
  check("that picture is drawn once", sf.draws, 1)
  els = engine.elements({ emoji = "E", sf = "unknown" }, box, 72)
  check("a refused picture falls back to a source with elements", els[1].type, "text")
  check("a tinted source with elements takes the colour", els[1].color.red, 1)
  engine.elements("E", box, 72)
  check("a source with elements never draws a picture", emoji.draws, 0)
  check("the string shorthand reaches elements", engine.elements("E", box, 72)[1].text, "E")
  check("a spec nothing can draw answers nil", engine.elements({ other = "x" }, box, 72), nil)
  local resolver = rowsLib.new({ engine = engine, points = 72,
    declared = function() return { cup = { emoji = "C", sf = "unknown" } } end })
  check("the resolver answers a declared key as elements", resolver.elements("cup", "p", box)[1].text, "C")
  raises("the contract refuses elements that is not a function", function()
    icons.new({ sources = { { name = "x", draw = function() end, elements = true } } })
  end, "elements field")
end

if failed then os.exit(1) end

-- The static checks the dry gate runs, see test/drygate-icons.lua.
do
  local scan = dofile(here .. "drygate-icons.lua")
  local hits = scan.literalKeys('local a = { icon = "on" }\n-- icon = "commented"\nlocal b = { icon = "\u{2615}" } -- icon = "trailing"\nlocal c = { icon = "off", x = 1 }\n')
  check("the scan finds a literal key on a code line", hits[1].key .. "@" .. hits[1].line, "on@1")
  check("the scan skips a comment, an emoji and a trailing comment", #hits, 2)
  check("the scan finds the next literal key", hits[2].key .. "@" .. hits[2].line, "off@4")
  check("a source is a file under lib/icons/sources", table.concat(scan.sourceNames({
    "x/lib/icons/sources/sf.lua", "x/lib/icons/init.lua", "x/lib/icons/sources/emoji.lua" }), ","), "emoji,sf")
  local report = scan.coverage({
    { owner = "a", key = "one", spec = { emoji = "1", sf = "one" } },
    { owner = "a", key = "two", spec = { emoji = "2" } },
    { owner = "b", key = "flag", spec = { emoji = "F", content = true } },
  }, { "emoji", "sf" })
  check("coverage counts the specs that are not content", report.total, 2)
  check("coverage counts content apart", report.content, 1)
  check("coverage counts a source entry", report.covered.sf, 1)
  check("coverage names a spec with no entry for a source", report.missing.sf[1], "a two")
  check("a source that covers everything names nothing", #report.missing.emoji, 0)
end
