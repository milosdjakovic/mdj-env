-- host/bridge in plain Lua, step 1.2 of docs/PLAN-STANDALONE.md. It pins when the bridge hands a
-- tool's open key to Olm.app, the olmapp piece on, the app built and open resolved, and that it
-- leaves every key alone otherwise, saying why once. It runs the function it hands back over a fake
-- hs.task and checks the command, open in the background with the app and the URL.
--
-- It needs no Hammerspoon and no lock.
--
-- Run it.
--   lua test/bridge.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local said, started, timers, posted = {}, {}, {}, {}
local present = {}
local clock, watchers = 1000, {}
hs = {
  timer = { doAfter = function(_, fn)
    local t = { fn = fn }
    function t:stop() self.stopped = true end
    timers[#timers + 1] = t
    return t
  end, secondsSinceEpoch = function() return clock end },
  logger = { new = function() return {
    i = function(m) said[#said + 1] = m end,
    w = function(m) said[#said + 1] = m end,
  } end },
  fs = { attributes = function(path) return present[path] and "directory" or nil end,
    mkdir = function() return true end },
  json = { encode = function(v)
    if v.tools then return "{\"tools\":[\"" .. table.concat(v.tools, "\",\"") .. "\"]}" end
    if v.bar then return "{\"bar\":{\"title\":\"" .. tostring(v.bar.title) .. "\"}}" end
    if v.query then return "{\"id\":" .. v.id .. ",\"query\":\"" .. v.query .. "\",\"keys\":" .. #v.keys .. "}" end
    return "{\"types\":" .. tostring(v.types and "t" or "none") .. "}"
  end, decode = function(s) return s ~= "" and { raw = s } or nil end },
  distributednotifications = { post = function(name, object) posted[#posted + 1] = { name = name, object = object } end,
    new = function(fn, name)
      local w = { fn = fn, name = name }
      function w:start() self.started = true; return self end
      watchers[#watchers + 1] = w
      return w
    end },
  task = { new = function(path, done, args)
    local t = { path = path, args = args, done = done }
    function t:start() started[#started + 1] = self; return self end
    return t
  end },
}

local function fresh(opts)
  said, started = {}, {}
  opts.serves = opts.serves or { "fileSearch" }
  local bridge = assert(loadfile(here .. "../host/bridge/init.lua"))()
  return bridge:configure(opts)
end

local APP = "/fake/Olm.app"
local deps = { path = function(name) return name == "open" and "/usr/bin/open" or nil end }

-- Off, by the piece missing or saying off, nothing is served and nothing is said.
eq(fresh({ deps = deps, app = APP }):serves("fileSearch"), nil, "no pieces serves nothing")
eq(fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP }):serves("fileSearch"), nil, "olmapp off serves nothing")
eq(#said, 0, "olmapp off says nothing")

-- On with no app built, the key stays the Lua one and the console says why, once.
local b = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP })
eq(b:serves("fileSearch"), nil, "no app built serves nothing")
b:serves("fileSearch")
eq(#said, 1, "a missing app is said once")
eq(said[1] and said[1]:find("setup-olmapp.sh", 1, true) ~= nil, true, "the line names the step that builds it")

-- On with the app and no open, the same.
present[APP] = true
eq(fresh({ pieces = { olmapp = "on" }, deps = { path = function() return nil end }, app = APP }):serves("fileSearch"),
  nil, "no open serves nothing")

-- On, built and resolved, file search is served and nothing else is.
b = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP })
local run = b:serves("fileSearch")
eq(type(run), "function", "file search is served")
eq(b:serves("clipboard"), nil, "a tool the config does not list is left alone")
run()
eq(#started, 1, "the key starts one task")
local t = started[1] or { args = {} }
eq(t.path, "/usr/bin/open", "the task runs open")
eq(table.concat(t.args, " "), "-g -a " .. APP .. " olm://filesearch?query=", "open hands the URL to the app in the background")
b:placeWith(function() return "cursor" end)
run()
eq(started[2] and started[2].args[4], "olm://filesearch?screen=cursor&query=", "the placement choice is asked at the press")
b:placeWith(function() return "not a word!" end)
run()
eq(started[3] and started[3].args[4], "olm://filesearch?query=", "a choice that is not a word is left out")
b:placeWith(function() error("boom") end)
run()
eq(started[4] and started[4].args[4], "olm://filesearch?query=", "a choice that raises is left out")
eq(b._tasks[t], true, "the task's handle is kept while it runs")
-- A running app is told by a notification rather than started by open.
local running = false
hs.application = { applicationsForBundleID = function(id)
  return (running and id == "local.olm.Olm") and { {} } or {}
end }
running, posted = true, {}
local before = #started
b:placeWith(function() return "cursor" end)
run()
eq(#started, before, "a running app starts no open")
eq(posted[1] and posted[1].name, "local.olm.Olm.open", "a running app is told by a notification")
eq(posted[1] and posted[1].object, "olm://filesearch?screen=cursor&query=", "naming the URL")
running, posted = false, {}
run()
eq(#started, before + 1, "an app not running is started by open")
eq(#posted, 0, "and told nothing")
hs.application = nil
t.done(0, "", "")
eq(b._tasks[t], nil, "and let go when it ends")

-- The shares the app reads are written only where the piece is on.
local run = os.tmpname() .. ".d"
os.execute("mkdir -p '" .. run .. "'")
fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run, shares = { filesearch = { types = {} } } })
eq(io.open(run .. "/filesearch.json") == nil, true, "olmapp off writes no share")
fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, shares = { filesearch = { types = {} }, ["../x"] = {} } })
local f = io.open(run .. "/filesearch.json")
eq(f and f:read("a"), '{"types":t}', "olmapp on writes each share as its name")
if f then f:close() end
eq(io.open(run .. "/../x.json") == nil, true, "a share name that is not a plain word is not written")

-- Which tools the app serves is a share of its own, so the app keeps their first open warm.
fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, serves = { "fileSearch", "bad word" } })
f = io.open(run .. "/serves.json")
local served = f and f:read("a") or ""
if f then f:close() end
eq(served:find('"filesearch"', 1, true) ~= nil and served:find("bad", 1, true) == nil, true,
  "the served tools are written lowercased, a word that is no identity left out")
-- A config with no serves line serves nothing and writes that, so an earlier load's list does not
-- linger and the app stops warming a tool taken back, found in 1.5's trial on 2026-11-12.
local bare = assert(loadfile(here .. "../host/bridge/init.lua"))()
bare:configure({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run })
f = io.open(run .. "/serves.json")
served = f and f:read("a") or ""
if f then f:close() end
eq(served ~= "" and served:find('"filesearch"', 1, true) == nil, true, "a config with no serves line writes an empty list")

-- The socket of step 2.2 serves only where its setting is on and the piece is on, and says why once.
local provider = { launcher = { rows = function() return {} end } }
eq(fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run }):serveLauncher(provider), nil,
  "the socket is off by default")
eq(fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = false }):serveLauncher(provider), nil,
  "and off when the setting says false")
said = {}
b = fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run, socket = true })
eq(b:serveLauncher(provider), nil, "a socket setting on with the piece off serves nothing")
b:serveLauncher(provider)
eq(#said, 1, "and says why once")

-- What the app keeps for a tool, read from its state folder beside the run folder, whatever the
-- piece says, since going back is the piece turned off, step 1.5.
local nest = os.tmpname() .. ".d"
os.execute("mkdir -p '" .. nest .. "/run' '" .. nest .. "/state/filesearch'")
local sf = io.open(nest .. "/state/filesearch/frecency.json", "w")
sf:write('{"entries":{}}')
sf:close()
b = fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = nest .. "/run" })
local kept = b:appState("fileSearch", "frecency")
eq(kept and kept.raw, '{"entries":{}}', "appState reads the tool's state file with the piece off")
eq(b:appState("fileSearch", "missing"), nil, "and answers nil for a file the app never wrote")
eq(b:appState("../x", "frecency"), nil, "and nothing for a name that is no identity")
os.execute("rm -rf '" .. nest .. "'")

-- A share the root builds is asked for only where the piece is on, and a nil answer is said once.
local asked = 0
b = fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run })
b:share("chooser", function() asked = asked + 1; return { types = {} } end)
eq(asked, 0, "olmapp off never builds a share")
b = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run })
b:share("chooser", function() asked = asked + 1; return { types = {} } end)
eq(asked, 1, "olmapp on builds it once")
f = io.open(run .. "/chooser.json")
eq(f and f:read("a"), '{"types":t}', "and writes it as its name")
if f then f:close() end
said = {}
b:share("look", function() return nil, "no kit" end)
b:share("look", function() return nil, "no kit" end)
eq(io.open(run .. "/look.json") == nil, true, "a share that answers nil is not written")
eq(#said, 1, "its reason is said once")
b:share("raises", function() error("boom") end)
eq(io.open(run .. "/raises.json") == nil, true, "a share that raises is not written")

-- One share per served tool, step 1.4f, named the tool lowercased and the suffix, built by the root.
b = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, serves = { "fileSearch" } })
local built = {}
b:shareEach("keys", function(identity) built[#built + 1] = identity; return { bar = { title = identity } } end)
eq(table.concat(built, ","), "fileSearch", "shareEach builds once for each served tool, by its identity")
f = io.open(run .. "/filesearchkeys.json")
eq(f and f:read("a"), '{"bar":{"title":"fileSearch"}}', "and writes it as the tool lowercased and the suffix")
if f then f:close() end
built = {}
fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, serves = {} })
  :shareEach("keys", function(identity) built[#built + 1] = identity; return {} end)
eq(#built, 0, "a machine serving nothing builds no keys share")
built = {}
fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, serves = { "fileSearch" } })
  :shareEach("keys", function(identity) built[#built + 1] = identity; return {} end, { "launcher", "fileSearch", "../x" })
eq(table.concat(built, ","), "fileSearch,launcher", "also adds the lists the app shows unserved, once each, plain words only")
do
  local shared = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, serves = { "fileSearch" } })
  local drawn = "?"
  shared:shareEach("keys", function() return { bar = { title = drawn } } end, { "launcher" })
  drawn = "info"
  shared:reshare()
  local g = io.open(run .. "/launcherkeys.json")
  eq(g and g:read("a"), '{"bar":{"title":"info"}}', "reshare writes every share again from its builder, its also lists kept")
  if g then g:close() end
end

-- The tools the app hosts in its launcher, step 3.3, plain words only, none when the config names none.
eq(table.concat(fresh({ pieces = { olmapp = "on" }, hosts = { "vpn", "caffeinate", "../x" } }):hosted(), ","), "caffeinate,vpn",
  "hosted answers the config's hosts, sorted, plain words only")
eq(#fresh({ pieces = { olmapp = "on" } }):hosted(), 0, "and a config with no hosts line hosts nothing")

-- A redraw of a hosted list, sent as the effects notification, or recorded while a request runs it.
local redrawing = fresh({ pieces = { olmapp = "on" }, hosts = { "caffeinate" } })
local notified = {}
eq(redrawing:presentedRedraw("caffeinate"), false, "no redraw is sent before the socket serves")
redrawing._service = { redraws = function(name, token, reset)
  return name == "caffeinate" and { { level = "v2", effects = { { rows = { hold = not reset } } } } } or {}
end }
redrawing._conn = {}
redrawing._session = { notify = function(_, method, params) notified[#notified + 1] = { method, params }; return true end }
redrawing._facade = assert(loadfile(here .. "../host/bridge/facade.lua"))().new()
eq(redrawing:presentedRedraw("caffeinate"), true, "a redraw of a hosted list is sent")
eq(notified[1] and notified[1][1], "effects", "as the effects notification")
eq(notified[1] and notified[1][2].level, "v2", "naming the level that shows it")
eq(redrawing:presentedRedraw("vpn"), false, "a tool with no hosted level open sends nothing")
local recorded = redrawing._facade.during(function() redrawing:presentedRedraw("caffeinate", nil, true) end)
eq(#notified, 1, "a redraw asked while a request runs is not sent")
eq(recorded[1] and recorded[1].rows.hold, false, "it is recorded for that answer instead, resetRow saying so")

-- The stage words a hosted list's code calls, step 3.3c, answered from the request's own context or
-- recorded as its effects while a request runs it, and handed back to the Lua stage outside one.
eq(redrawing:hostedWord("stageSelectedItem"), false, "outside a request a word is the Lua stage's")
local words = {}
local wordEffects = redrawing._facade.during(function()
  words.handled, words.item = redrawing:hostedWord("stageSelectedItem")
  words.row = select(2, redrawing:hostedWord("stageSelectedRow"))
  words.query = select(2, redrawing:hostedWord("stageQuery"))
  words.hid = redrawing:hostedWord("stageHide")
  words.popped = select(2, redrawing:hostedWord("stagePop"))
  words.pushed = select(2, redrawing:hostedWord("stagePush", { name = "emoji" }))
  words.notPushed = select(2, redrawing:hostedWord("stagePush", "nothing"))
  redrawing:hostedWord("stageSetQuery", "tea")
  words.unknown = redrawing:hostedWord("stageTextWidth", "x")
end, { item = "🍵", row = 3, query = "te" })
eq(words.handled == true and words.item, "🍵", "stageSelectedItem answers the request's own row")
eq(words.row, 3, "stageSelectedRow its place")
eq(words.query, "te", "stageQuery its query")
eq(words.hid and wordEffects[1].hide ~= nil, true, "stageHide is recorded as hide")
eq(words.popped == true and wordEffects[2].pop ~= nil, true, "stagePop as pop, answered true")
eq(words.pushed == true and wordEffects[3].pushChild.name, "emoji", "stagePush as the child to push")
eq(words.notPushed, false, "and a push of no table pushes nothing")
eq(wordEffects[4].setQuery.query, "tea", "stageSetQuery as setQuery with its text")
eq(#wordEffects == 4 and words.unknown, false, "a word the bridge does not answer stays the Lua stage's")
eq(wordEffects.context, nil, "the context ends with the request")

-- The trial key of step 3.2, bridge.launcher, gated on the piece, the app and the socket setting.
local tried = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true })
local actions = tried:actions()
eq(#actions == 3 and actions[1].name, "launcher", "the bridge declares three actions, launcher first")
eq(actions[1].when, "olmAppLauncher", "gated on its own predicate")
eq(tried.predicates.olmAppLauncher(), true, "on where the piece, the app and the socket are")
eq(fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = false }).predicates.olmAppLauncher(),
  false, "off with the socket setting off")
eq(fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run, socket = true }).predicates.olmAppLauncher(),
  false, "off with the piece off")
tried = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true })
started = {}
tried:placeWith(function() return "cursor" end)
tried:actions()[1].run()
eq(started[1] and started[1].args[4], "olm://launcher?screen=cursor&query=", "running it opens olm://launcher on the placement's screen")
started = {}
fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = false }):actions()[1].run()
eq(#started, 0, "and does nothing with the socket off")

-- The flip of step 3.5, the launcher's open key, the app's launcher while its socket is up and the
-- Lua launcher otherwise, asked at every press, and the key left alone where the app cannot answer.
local luaRuns = 0
local function luaLauncher() luaRuns = luaRuns + 1 end
eq(fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run, socket = true }):launcherOpen(luaLauncher),
  nil, "the piece off leaves the launcher's key alone")
eq(fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = false, launcherFlip = true }):launcherOpen(luaLauncher),
  nil, "the socket setting off leaves it alone")
eq(fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true }):launcherOpen(luaLauncher),
  nil, "the flip setting not given leaves it alone")
eq(fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true, launcherFlip = false }):launcherOpen(luaLauncher),
  nil, "the flip setting off leaves it alone")
local flip = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true, launcherFlip = true })
eq(flip:launcherOpen(nil), nil, "no Lua run to fall back on leaves it alone")
local flipped = flip:launcherOpen(luaLauncher)
eq(type(flipped), "function", "on, it answers a run")
started = {}
flipped()
eq(luaRuns, 1, "no socket yet opens the Lua launcher")
eq(#started, 0, "and starts no app")
local socketUp = false
flip._conn = { isUp = function() return socketUp end }
flipped()
eq(luaRuns, 2, "a socket that went opens the Lua launcher")
eq(#started, 0, "and starts no app, so a quit app stays quit")
socketUp = true
flipped()
eq(luaRuns, 2, "a socket up does not open the Lua launcher")
eq(started[1] and started[1].args[4], "olm://launcher?query=", "it opens the app's launcher")
socketUp = false
flipped()
eq(luaRuns, 3, "asked again at the next press")

-- A tool's own key, step 3.8, presentInApp asked by the root's stagePresent before the Lua stage.
local clip = { name = "clipboard" }
local function keyed(extra)
  local o = { pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true, keysFlip = true,
    hosts = { "clipboard" } }
  for k, v in pairs(extra or {}) do o[k] = v end
  local b = fresh(o)
  b._conn = { isUp = function() return true end }
  return b
end
posted = {}
eq(keyed({ keysFlip = false }):presentInApp("clipboard", clip), false, "own key: the switch off keeps the Lua list")
local unset = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true, hosts = { "clipboard" } })
unset._conn = { isUp = function() return true end }
eq(unset:presentInApp("clipboard", clip), false, "own key: the switch not given keeps the Lua list")
eq(keyed({ pieces = { olmapp = "off" } }):presentInApp("clipboard", clip), false, "own key: the piece off keeps the Lua list")
eq(keyed({ socket = false }):presentInApp("clipboard", clip), false, "own key: the socket setting off keeps the Lua list")
eq(keyed():presentInApp("vpn", { name = "vpn" }), false, "own key: a tool not hosted keeps the Lua list")
local down = keyed()
down._conn = { isUp = function() return false end }
eq(down:presentInApp("clipboard", clip), false, "own key: a socket that went keeps the Lua list")
eq(#posted, 0, "own key: and tells the app nothing")
local up = keyed()
up:placeWith(function() return "cursor" end)
eq(up:presentInApp("clipboard", clip), true, "own key: a hosted tool with the socket up opens in the app")
eq(posted[1] and posted[1].name, "local.olm.Olm.open", "own key: by the open notification")
eq(posted[1] and posted[1].object, "olm://tool?screen=cursor&name=clipboard&query=", "own key: naming the tool and the screen")

-- Its cycle key, step 3.9, cycleInApp asked by the root's cycleRun before the Lua stage.
local inputs = { name = "inputsources" }
local function cycler(extra)
  local o = { hosts = { "inputsources" } }
  for k, v in pairs(extra or {}) do o[k] = v end
  return keyed(o)
end
posted = {}
eq(cycler({ keysFlip = false }):cycleInApp("inputsources", inputs), false, "cycle: the switch off keeps the Lua cycle")
eq(keyed():cycleInApp("inputsources", inputs), false, "cycle: a tool not hosted keeps the Lua cycle")
local gone = cycler()
gone._conn = { isUp = function() return false end }
eq(gone:cycleInApp("inputsources", inputs), false, "cycle: a socket that went keeps the Lua cycle")
eq(#posted, 0, "cycle: and tells the app nothing")
local cyc = cycler()
eq(cyc:cycleInApp("inputsources", inputs), true, "cycle: a first press opens in the app")
eq(posted[1] and posted[1].object, "olm://tool?name=inputsources&query=&cycle=1", "cycle: as a cycle")
cyc._runningAt, cyc._runningWas = clock, true
eq(cyc:cycleInApp("inputsources", inputs), true, "cycle: a press while it opens is taken")
eq(posted[2] and posted[2].name, "local.olm.Olm.verb", "cycle: as a verb")
eq(posted[2] and posted[2].object, "inputsources:cycleStep", "cycle: that steps it")
cyc:_state("inputsources:up")
eq(cyc:cycleInApp("inputsources", inputs) and posted[3] and posted[3].object, "inputsources:cycleStep",
  "cycle: and while it is up")
clock = clock + 1
cyc:_state("inputsources:down")
cyc._runningAt, cyc._runningWas = clock, true
eq(cyc:cycleInApp("inputsources", inputs) and posted[4] and posted[4].object, "olm://tool?name=inputsources&query=&cycle=1",
  "cycle: once it went down a press opens it again")
eq(cyc:presentInApp("inputsources", inputs), true, "cycle: its own open key opens it in full")
eq(cyc._cycling, nil, "cycle: which is no cycle, so the next press opens one")

-- A key typed over a list cycled in the app, posted again a moment after the app hid.
local keyed2 = {}
hs.eventtap = { event = { newKeyEvent = function(mods, code, down)
  return { post = function() keyed2[#keyed2 + 1] = { mods = mods, code = code, down = down } end }
end } }
cyc:_retype(0, { "shift" })
eq(#keyed2, 0, "retype: nothing is posted at once")
timers[#timers].fn()
eq(keyed2[1] and keyed2[1].code, 0, "retype: the key is posted after the delay")
eq(keyed2[1] and keyed2[1].mods[1], "shift", "retype: with its modifiers")
eq(keyed2[1] and keyed2[1].down, true, "retype: as a key down")

-- Quit Olm App, a row while the app runs, asking each running copy to quit.
local quitter = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, socket = true })
local quit = quitter:actions()[2]
eq(quit.name, "quit", "the second action is quit")
eq(quit.when, "olmAppRunning", "gated on the app running")
local killed, appRunning = 0, false
hs.application = { applicationsForBundleID = function(id)
  if appRunning and id == "local.olm.Olm" then return { { kill = function() killed = killed + 1 end } } end
  return {}
end }
-- Olm Settings, a row where the app is built, olm://settings always opened in the foreground, running
-- or not, so the window comes forward.
local settingsRow = quitter:actions()[3]
eq(settingsRow and settingsRow.name, "settings", "the third action is Olm Settings")
eq(settingsRow and settingsRow.description, "Olm Settings", "named Olm Settings")
eq(settingsRow and settingsRow.when, "olmAppReady", "gated on the app being built")
eq(quitter.predicates.olmAppReady(), true, "a row where the piece is on and the app built")
eq(fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run, socket = true }).predicates.olmAppReady(),
  false, "no row where the piece is off")
do
  local posted, opened = {}, {}
  local savedPost, savedOpen = quitter._post, quitter._open
  quitter._post = function(_, name, object) posted[#posted + 1] = { name = name, object = object } return true end
  quitter._open = function(_, _, _, url, front) opened[#opened + 1] = { url = url, front = front } end
  eq(quitter:openSettings(), true, "settings: asked")
  eq(#opened, 1, "settings: a stopped app is opened")
  eq(opened[1] and opened[1].url, "olm://settings", "settings: with its URL")
  eq(opened[1] and opened[1].front, true, "settings: in the foreground")
  appRunning = true
  quitter._runningAt = nil
  eq(quitter:openSettings(), true, "settings: asked of a running app")
  eq(#opened, 2, "settings: a running app is opened too, not told")
  eq(opened[2] and opened[2].front, true, "settings: a running app brought forward")
  eq(#posted, 0, "settings: no notification, which cannot bring the app forward")
  appRunning = false
  quitter._runningAt = nil
  quitter._post, quitter._open = savedPost, savedOpen
end
eq(quitter.predicates.olmAppRunning(), false, "no row while the app is not running")
appRunning = true
quitter._runningAt = nil
eq(quitter.predicates.olmAppRunning(), true, "a row while it runs")
quit.run()
eq(killed, 1, "choosing it asks the app to quit")
eq(fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, run = run }).predicates.olmAppRunning(), false,
  "no row with the piece off")
hs.application = nil

-- The shadow of step 1.3e. It is off unless the piece is on and the app built, it hands a list over
-- only once it has settled, never while it searches, and never the same query twice running.
eq(#fresh({ pieces = { olmapp = "off" }, deps = deps, app = APP, shadows = { "fileSearch" } }):shadowed(), 0,
  "olmapp off shadows nothing")
b = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, run = run, shadows = { "fileSearch", "../x" } })
eq(#b:shadowed(), 1, "olmapp on shadows each plain identity the config lists")
eq(b:shadowed()[1], "fileSearch", "and names it")
local changed
local answer = { query = "report", status = nil, keys = { "/a/report.pdf", "/b/report.txt" } }
timers = {}
local launched = #started
b:shadowWith("fileSearch", { watch = function(fn) changed = fn end, answer = function() return answer end })
eq(type(changed), "function", "the shadow watches the tool's list")
eq(#started, launched + 1, "the app is started once as the shadow is wired")
eq(started[#started].args[2], "-j", "hidden and in the background, with no URL")
eq(started[#started].args[4], APP, "and names the app")
changed()
changed()
eq(#timers, 2, "each change waits for the list to settle")
eq(timers[1].stopped, true, "and a newer change replaces the wait before it")
local before = #started
posted = {}
timers[2].fn()
eq(#started, before, "a settled list runs no open, which left file search's own list with no rows")
eq(#posted, 1, "a settled list is told to the app")
eq(posted[1] and posted[1].name, "local.olm.Olm.shadow", "by a distributed notification")
eq(posted[1] and posted[1].object, "filesearch:1", "naming the tool and the id")
f = io.open(run .. "/filesearchshadow.json")
eq(f and f:read("a"), '{"id":1,"query":"report","keys":2}', "the answer is written for the app to read")
if f then f:close() end
changed()
timers[#timers].fn()
eq(#posted, 1, "the same query is not handed over twice running")
answer = { query = "reports", status = "searching", keys = {} }
changed()
timers[#timers].fn()
eq(#posted, 1, "a list still searching is not handed over")
answer = { query = "reports", status = nil, keys = {} }
changed()
timers[#timers].fn()
eq(posted[#posted] and posted[#posted].object, "filesearch:2", "the next settled query is")
answer = nil
changed()
timers[#timers].fn()
eq(#posted, 2, "an answer that is not a table is dropped")
local watched = false
b:shadowWith("../x", { watch = function() watched = true end, answer = function() return answer end })
eq(watched, false, "an identity that is not a plain word is not watched")

os.execute("rm -rf '" .. run .. "'")

-- List keys, step 1.4f, docs/DESIGN-APP-LIST-KEYS.md. The app's list counts as open from the
-- served key's press, through the app's up, until its down, never for a tool not served, and never
-- once the app has quit. A verb is posted as "<tool>:<verb>".
do
  local up = true
  hs.application = { applicationsForBundleID = function() return up and { {} } or {} end }
  watchers, posted, timers = {}, {}, {}
  local k = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP })
  local open = k:serves("fileSearch")
  eq(#watchers, 1, "keys: serving a tool listens for the app's state")
  eq(watchers[1] and watchers[1].name, "local.olm.Olm.state", "keys: on the state note")
  eq(watchers[1] and watchers[1].started, true, "keys: and starts listening")
  eq(posted[1] and posted[1].name, "local.olm.Olm.ask", "keys: a running app is asked its state")
  k:serves("fileSearch")
  eq(#watchers, 1, "keys: and listens once")
  local note = watchers[1].fn
  eq(k:showing("fileSearch"), false, "keys: nothing open at rest")
  open()
  eq(k:showing("fileSearch"), true, "keys: open from the press, before the app says so")
  eq(k:showing("clipboard"), false, "keys: a tool not served is never open")
  clock = clock + 0.05
  note("local.olm.Olm.state", "filesearch:down")
  eq(k:showing("fileSearch"), true, "keys: a down from the list before the press leaves the open standing")
  note("local.olm.Olm.state", "filesearch:up")
  eq(k:showing("fileSearch"), true, "keys: open once the app says up")
  clock = clock + 5
  eq(k:showing("fileSearch"), true, "keys: and stays open while it is up")
  note("local.olm.Olm.state", "filesearch:down")
  eq(k:showing("fileSearch"), false, "keys: closed once the app says down")
  open()
  timers[#timers].fn()
  eq(k:showing("fileSearch"), false, "keys: a press the app never answers counts for a second only")
  note("local.olm.Olm.state", "filesearch:up")
  up = false
  clock = clock + 1
  eq(k:showing("fileSearch"), false, "keys: an app that quit has no list open")
  up = true
  clock = clock + 1
  eq(k:showing("fileSearch"), false, "keys: and the up it last said is forgotten")
  note("local.olm.Olm.state", "nonsense")
  note("local.olm.Olm.state", nil)
  eq(k:showing("fileSearch"), false, "keys: a note that is not a state changes nothing")
  posted = {}
  k:verb("fileSearch", "selectNext")
  eq(posted[1] and posted[1].name, "local.olm.Olm.verb", "keys: a verb is posted on the verb note")
  eq(posted[1] and posted[1].object, "filesearch:selectNext", "keys: naming the tool and the verb")
  k:verb("fileSearch", "../x")
  eq(#posted, 1, "keys: a verb that is not a word is not posted")
  -- A hosted list on top of the app's launcher is open while the launcher is up, and its keys
  -- are posted to the launcher, whose stage runs them on the level on top.
  local top = "browserTabs"
  k._service = { hostedTop = function() return top end }
  note("local.olm.Olm.state", "filesearch:up")
  eq(k:hosting("browserTabs"), true, "keys: a hosted list on top is open while its launcher is up")
  eq(k:showing("browserTabs"), false, "keys: and is not the app's own list, so calls into the tool stay in Lua")
  eq(k:hosting("emoji"), false, "keys: a hosted list not on top is not")
  posted = {}
  k:verb("browserTabs", "openActionsPane")
  eq(posted[1] and posted[1].object, "filesearch:openActionsPane", "keys: its verb goes to the list it sits in")
  top = nil
  eq(k:hosting("browserTabs"), false, "keys: and closed once it is no longer on top")
  note("local.olm.Olm.state", "filesearch:down")
  top = "browserTabs"
  eq(k:hosting("browserTabs"), false, "keys: or once the list it sits in is down")
  -- A hosted list its own key opened alone, step 3.8, is its own host, so its pane and its keys
  -- reach the app as they do inside the launcher.
  k._hosts = { browserTabs = true }
  note("local.olm.Olm.state", "browsertabs:up")
  eq(k:hosting("browserTabs"), true, "own key: a hosted list opened alone is open while it is up")
  eq(k:showing("browserTabs"), false, "own key: and is still not the app's own list")
  posted = {}
  k:verb("browserTabs", "selectNext")
  eq(posted[1] and posted[1].object, "browsertabs:selectNext", "own key: its verb goes to it")
  note("local.olm.Olm.state", "browsertabs:down")
  eq(k:hosting("browserTabs"), false, "own key: and closed once it is down")
  -- The words that change a list, outside any request, reach the hosted list the app shows, step
  -- 3.8, Clipboard History's Manage History, and a placeholder set while its own key is still
  -- opening the list goes with the list's open.
  local sent = {}
  k.notify = function(_, method, params) sent[#sent + 1] = { method = method, params = params }; return true end
  k._hosts = { browserTabs = true }
  k._service.paneLevel = function(name) return name == "browserTabs" and { id = "v3", q = 4 } or nil end
  note("local.olm.Olm.state", "browsertabs:up")
  eq(k:hostedWord("stageSetPlaceholder", "Duration"), true, "words: a placeholder outside a request is the app's")
  eq(sent[1] and sent[1].params.effects[1].setPlaceholder.text, "Duration", "words: sent as the effects notification")
  eq(sent[1] and sent[1].params.level, "v3", "words: to the hosted level on top")
  eq(k:hostedWord("stageSetQuery", ""), true, "words: so is a query")
  eq(sent[2] and sent[2].params.effects[1].setQuery.level, "v3", "words: naming its level")
  eq(k:hostedWord("stageSelectedRow"), false, "words: a word that reads the list is not sent")
  note("local.olm.Olm.state", "browsertabs:down")
  eq(k:hostedWord("stageSetPlaceholder", "x"), false, "words: and none once the list is down, the Lua stage's")
  top = nil
  k._presenting = { name = "browserTabs", at = hs.timer.secondsSinceEpoch() }
  eq(k:hostedWord("stageSetPlaceholder", "Opening"), true, "words: a placeholder while the key is opening the list waits")
  eq(k:_takePending("browserTabs").placeholder, "Opening", "words: and goes with the list's open")
  eq(k:_takePending("browserTabs"), nil, "words: once")
  k.notify = nil
  k._hosts = {}
  k._service = nil
end

-- The app's launcher counts as open while it is up wherever the socket serves it, and only there,
-- so its keys and a hosted list's keys inside it reach the app.
do
  local up = true
  hs.application = { applicationsForBundleID = function() return up and { {} } or {} end }
  watchers, posted, timers = {}, {}, {}
  local k = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, socket = true })
  k:serves("fileSearch")
  local note = watchers[1].fn
  eq(k:showing("launcher"), false, "launcher: not open at rest")
  note("local.olm.Olm.state", "launcher:up")
  eq(k:showing("launcher"), true, "launcher: open once the app says up, with the socket on")
  k._service = { hostedTop = function() return "browserTabs" end }
  eq(k:hosting("browserTabs"), true, "launcher: a hosted list on top of it is open")
  posted = {}
  k:verb("browserTabs", "openActionsPane")
  eq(posted[1] and posted[1].object, "launcher:openActionsPane", "launcher: and its key goes to the launcher")
  k._service = nil
  local off = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, socket = false })
  off:_state("launcher:up")
  eq(off:showing("launcher"), false, "launcher: never open where the socket does not serve it")
  hs.application = nil
end

-- The forwarder lib/appfocus.lua is handed, step 6.2, docs/DESIGN-APP-APPS.md. A press goes to
-- the app only with the switch on, a session open and the app having said it may act, and carries
-- Lua's own plan for the shadow.
do
  local notes = {}
  local fwd = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP, appToggler = true })
  local service = { appsReady = false }
  fwd._conn, fwd._service = {}, service
  fwd._session = { open = true, notify = function(_, method, params) notes[#notes + 1] = { method, params }; return true end }
  local send = fwd:appForwarder(function(bundle, hides) return { outcome = hides and "hidden" or "cycled", window = 7 } end)
  eq(send({ id = "apptoggler.Safari", bundle = "s.s", hides = false }), false, "an app that has not said it may act takes nothing")
  service.appsReady = true
  eq(send({ id = "apptoggler.Safari", bundle = "s.s", hides = false, placement = function() end }), true,
    "an app that said it may act takes the press")
  eq(notes[1][1], "appRun", "as the notification appRun")
  eq(notes[1][2].lua.outcome, "cycled", "carrying Lua's plan")
  eq(notes[1][2].placement, nil, "and never a placement that is not a table")
  fwd._session.open = false
  eq(send({ bundle = "s.s" }), false, "a closed session takes nothing")
  local off = fresh({ pieces = { olmapp = "on" }, deps = deps, app = APP })
  off._conn, off._service, off._session = {}, { appsReady = true }, fwd._session
  off._session.open = true
  eq(off:appsInApp(), false, "with the switch off no press goes to the app")
end

print(string.format("bridge: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
