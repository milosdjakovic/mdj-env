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
  end },
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
  hs.application = nil
end

print(string.format("bridge: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
