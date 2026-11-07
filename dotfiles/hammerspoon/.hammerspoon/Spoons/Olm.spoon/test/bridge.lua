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

local said, started = {}, {}
local present = {}
hs = {
  logger = { new = function() return {
    i = function(m) said[#said + 1] = m end,
    w = function(m) said[#said + 1] = m end,
  } end },
  fs = { attributes = function(path) return present[path] and "directory" or nil end },
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
eq(b._tasks[t], true, "the task's handle is kept while it runs")
t.done(0, "", "")
eq(b._tasks[t], nil, "and let go when it ends")

print(string.format("bridge: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
