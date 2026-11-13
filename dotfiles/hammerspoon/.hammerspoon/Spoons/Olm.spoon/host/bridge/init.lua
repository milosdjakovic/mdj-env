-- Bridge, the Lua side of Olm.app, step 1.2 of docs/PLAN-STANDALONE.md.
--
-- It answers one question for the root, serves(identity), which is the function a tool's open key
-- runs instead of its own while Olm.app serves that tool on this machine, or nil to leave the key
-- alone. Olm.app serves a tool here when this machine's olmapp piece is on, the app is built where
-- src/setup-olmapp.sh puts it and the open tool resolved. Each condition that fails is said once in
-- the console, so a key that still opens the Lua list says why.
--
-- The key opens the app's list with `open -g`, which hands the URL to the app without bringing it
-- forward, since its chooser is a panel that takes key without activating the app. It runs as a
-- task, so a slow LaunchServices never holds the main thread, and the task's handle is kept until
-- it ends, since a task nothing refers to can be collected before it runs.
--
-- It also runs the shadow of step 1.3e, for each tool the config lists under shadows. The Lua list
-- stays the one a person uses, and each answer it settles on is handed to the app through
-- `<run>/<tool>shadow.json` and olm://shadow, and the app answers the same query with its own
-- engine and logs every difference to ~/.olm/log/shadow-<tool>.jsonl. The Lua side asks rather
-- than the app, since rule 9 of the plan keeps the daily path on the list with every feature, so
-- that is where real queries are typed. Nothing is shown and nothing waits on the app.
--
-- And it carries list keys to the app's list, step 1.4f, docs/DESIGN-APP-LIST-KEYS.md. The app
-- posts local.olm.Olm.state, "<tool>:up" or "<tool>:down", as its list shows and hides, and
-- showing(identity) answers from it, so lib/listopen.lua treats the app's list as an open one. A
-- list key routed to it is posted back as local.olm.Olm.verb, "<tool>:<verb>", and the app runs it
-- on its own highlight. Hammerspoon never waits on either.

local obj = {}
obj.__index = obj

obj.name = "Bridge"
obj.version = "0.1"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Bridge", "info")

-- Which tools Olm.app serves is the person's config, config/plugins.lua, since only that and a
-- plugin may name a plugin. A served tool's open key hands the app olm://<identity lowercased>,
-- docs/PROTOCOL-BRIDGE.md, file search's being olm://filesearch. The screen is Olm's placement
-- choice read at the press, since the Placement page changes it with no reload.
local function urlFor(identity, mode)
  local screen = (type(mode) == "string" and mode:match("^%a+$")) and ("screen=" .. mode .. "&") or ""
  return "olm://" .. identity:lower() .. "?" .. screen .. "query="
end

local APP = os.getenv("HOME") .. "/.olm/app/Olm.app"
local RUN = os.getenv("HOME") .. "/.olm/run"

obj._pieces = {}
obj._serves = {}
obj._deps = nil
obj._tasks = {}
obj._said = {}
obj._screenMode = nil
obj._shadows = {}
obj._shadowTimers = {}
obj._shadowLast = {}
obj._shadowId = 0
-- Whether each served tool's list is up in the app, step 1.4f, docs/DESIGN-APP-LIST-KEYS.md. _up is
-- what the app last said, _opening the moment a served key asked the app to open, kept until the
-- app says up or OPENING passes, and _openTimers the handles of those waits.
obj._up = {}
obj._opening = {}
obj._openTimers = {}
obj._runningAt = nil
obj._runningWas = false

-- How long a list's answer must stay put before the shadow hands it over, so typing sends one
-- request per pause rather than one per key.
obj.SHADOW_SETTLE = 0.8

function obj:configure(opts)
  opts = opts or {}
  if type(opts.pieces) == "table" then self._pieces = opts.pieces end
  -- The root's configure always hands the pieces, and a config with no serves line serves
  -- nothing, so the share below says so rather than keeping what an earlier load wrote.
  local serves = opts.serves
  if serves == nil and type(opts.pieces) == "table" then serves = {} end
  if type(serves) == "table" then
    self._serves = {}
    for _, identity in ipairs(serves) do
      if type(identity) == "string" and identity:match("^%a%w*$") then self._serves[identity] = true end
    end
  end
  if type(opts.shadows) == "table" then
    self._shadows = {}
    for _, identity in ipairs(opts.shadows) do
      if type(identity) == "string" and identity:match("^%a%w*$") then self._shadows[#self._shadows + 1] = identity end
    end
  end
  if opts.deps ~= nil then self._deps = opts.deps end
  if opts.app ~= nil then self._app = opts.app end
  if opts.run ~= nil then self._run = opts.run end
  -- Whether the bridge connects to the app's socket and serves, step 2.2, off unless the config
  -- says true, so going back is the setting.
  if opts.socket ~= nil then self._socket = opts.socket == true end
  if type(opts.shares) == "table" then self:_share(opts.shares) end
  -- Which tools the app serves, so it keeps the first open of each warm while it is hidden, step
  -- 1.5's prewarm. Written on every configure, an empty list included, so a tool taken back stops.
  if type(serves) == "table" then
    local tools = {}
    for identity in pairs(self._serves) do tools[#tools + 1] = identity:lower() end
    table.sort(tools)
    self:_write("serves", { tools = tools, count = #tools })
  end
  return self
end

local function sayOnce(self, why)
  if self._said[why] then return end
  self._said[why] = true
  log.i(why)
end

-- Whether Olm.app takes keys on this machine, and the open command when it does.
function obj:_ready()
  if self._pieces.olmapp ~= "on" then return nil end
  local app = self._app or APP
  if not hs.fs.attributes(app, "mode") then
    sayOnce(self, "the olmapp piece is on and " .. app .. " is not built, so every key opens the Lua list, src/setup-olmapp.sh builds it")
    return nil
  end
  local open = self._deps and self._deps.path and self._deps.path("open")
  if not open then
    sayOnce(self, "the olmapp piece is on and open did not resolve, so every key opens the Lua list")
    return nil
  end
  return open, app
end

-- Writes one share the app reads as <run>/<name>.json, only where the olmapp piece is on, so a
-- machine without the app gets no file. Written through a temporary file and a rename, so the app
-- never reads half of one. A name is a plain word, so it cannot reach outside the folder. A value
-- may be a function, asked only here, so what costs work to build is built only where it is read,
-- and its nil and reason are said once rather than written.
function obj:_write(name, value)
  if self._pieces.olmapp ~= "on" then return end
  if type(name) ~= "string" or not name:match("^%a%w*$") then return end
  if type(value) == "function" then
    local ok, built, why = pcall(value)
    if not ok then why, built = built, nil end
    if type(built) ~= "table" then
      sayOnce(self, "Olm.app is not handed " .. name .. ", " .. tostring(why))
      return
    end
    value = built
  end
  if type(value) ~= "table" then return end
  local run = self._run or RUN
  hs.fs.mkdir(run)
  local text = hs.json.encode(value)
  local tmp = run .. "/." .. name .. ".json.tmp"
  local f = text and io.open(tmp, "w")
  if f then
    f:write(text)
    f:close()
    os.rename(tmp, run .. "/" .. name .. ".json")
  else
    log.w("could not write " .. run .. "/" .. name .. ".json for Olm.app")
  end
end

-- Every share the person's config names, config/plugins.lua.
function obj:_share(shares)
  for name, value in pairs(shares) do self:_write(name, value) end
end

--- obj:share(name, value) writes a share the root builds rather than the config, the chooser's
--- look today, value a table or a function answering one, or nil and why.
function obj:share(name, value)
  self:_write(name, value)
end

--- obj:shareEach(suffix, build, also) writes one share per tool this machine serves, named the tool
--- lowercased and suffix, build(identity) answering its table, the keys a served list shows, step
--- 1.4f, and one for each identity in also, a list the app shows without serving its key, the
--- launcher on its trial key, step 3.2. The bridge knows which tools it serves and nothing of what
--- a share holds.
function obj:shareEach(suffix, build, also)
  if type(suffix) ~= "string" or type(build) ~= "function" then return end
  local names, seen = {}, {}
  for identity in pairs(self._serves) do
    names[#names + 1] = identity
    seen[identity] = true
  end
  for _, identity in ipairs(type(also) == "table" and also or {}) do
    if type(identity) == "string" and identity:match("^%a%w*$") and not seen[identity] then
      names[#names + 1] = identity
      seen[identity] = true
    end
  end
  table.sort(names)
  for _, identity in ipairs(names) do
    self:_write(identity:lower() .. suffix, function() return build(identity) end)
  end
end

-- The siblings that serve over the socket, step 2.2, loaded from beside this file since a host's
-- directory is not on the module path.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)")) or "./"
local function sibling(name) return assert(loadfile(HERE .. name .. ".lua"))() end

obj.SOCKET = "bridge.sock"

--- obj:serveLauncher(provider) connects to Olm.app's socket and serves the launcher read only,
--- step 2.2 of docs/PLAN-STANDALONE.md, docs/PROTOCOL-BRIDGE.md. Only where the socket setting
--- is true and the olmapp piece is on. provider.launcher answers rows, memoryKey, memory and
--- placeholder, provider.icons(owner) a manifest's icons, provider.version the olm version.
function obj:serveLauncher(provider)
  if self._conn then self._conn:stop(); self._conn = nil end
  if not self._socket then return nil end
  if self._pieces.olmapp ~= "on" then
    sayOnce(self, "the bridge's socket is on and the olmapp piece is off, so nothing is served")
    return nil
  end
  if type(provider) ~= "table" or type(provider.launcher) ~= "table" then return nil end
  local frame, rpc, serve, transport = sibling("frame"), sibling("rpc"), sibling("serve"), sibling("transport")
  -- A timer handle nothing refers to may be collected before it fires, so each is kept until then.
  local turns = {}
  local function later(seconds, fn)
    local t
    t = hs.timer.doAfter(seconds, function() turns[t] = nil; fn() end)
    turns[t] = true
  end
  local service = serve.new({ rpc = rpc, clean = frame.clean, launcher = provider.launcher, later = later,
    icons = provider.icons or function() return nil end, version = provider.version,
    rowLimit = provider.rowLimit,
    styled = function(v)
      if type(v) == "userdata" and v.getString then return v:getString() end
      return tostring(v)
    end })
  local conn
  local session = rpc.new({ json = hs.json, methods = service.methods,
    send = function(text) if conn then conn:send(text) end end,
    defer = function(fn) later(0, fn) end,
    log = function(text) log.w(text) end })
  conn = transport.new({ path = (self._run or RUN) .. "/" .. self.SOCKET, frame = frame,
    onMessage = function(text) session:receive(text) end,
    onUp = function() log.i("connected to Olm.app's socket") end,
    onDown = function() session:reset(); log.i("Olm.app's socket went") end,
    log = function(text) log.w(text) end })
  self._conn = conn:start()
  self._service, self._session = service, session
  return conn
end

--- obj:notify(method, params) -> true when sent, a notification to the app over the socket, sent
--- only while a session is open, so nothing queues for an app that is not there
function obj:notify(method, params)
  if not (self._conn and self._session) then return false end
  return self._session:notify(method, params)
end

--- obj:memoryChanged() tells the app the launcher's memory moved, after a pick the launcher
--- recorded, with only the queries whose order differs from what this connection was sent, the
--- protocol's memory notification. Nothing goes before the app opened a launcher level.
function obj:memoryChanged()
  if not self._service then return end
  local params = self._service.memoryChanges()
  if params then self:notify("memory", params) end
end

--- obj:appState(identity, name) -> table or nil
--- What Olm.app keeps for a tool, its state folder's <name>.json beside the run folder, read
--- whatever the piece says, since going back is the piece turned off and the app's store is then
--- what is handed back, file search's frecency, docs/DESIGN-APP-FRECENCY.md.
function obj:appState(identity, name)
  if type(identity) ~= "string" or not identity:match("^%a%w*$") then return nil end
  if type(name) ~= "string" or not name:match("^%a%w*$") then return nil end
  local run = self._run or RUN
  local path = run:gsub("/[^/]*$", "") .. "/state/" .. identity:lower() .. "/" .. name .. ".json"
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  local ok, doc = pcall(hs.json.decode, text or "")
  return ok and type(doc) == "table" and doc or nil
end

--- obj:placeWith(fn) takes the function answering Olm's placement choice, activeWindow or cursor,
--- lib/overlaydisplay.lua's mode, asked at every press so a URL opens the app's list on the screen
--- the Lua one would open on.
function obj:placeWith(fn)
  if type(fn) == "function" then self._screenMode = fn end
end

--- obj:serves(identity) -> function or nil
--- The function the identity's open key runs while Olm.app serves it here, or nil.
function obj:serves(identity)
  -- The piece first and the identity after, so what is asked does not depend on a tool's name.
  local open, app = self:_ready()
  if not open then return nil end
  if type(identity) ~= "string" or not self._serves[identity] then return nil end
  sayOnce(self, identity .. "'s open key opens Olm.app, the olmapp piece is on")
  self:_listen()
  return self:_opener(identity, open, app)
end

-- The function that opens the app's list for an identity, olm://<identity lowercased>.
function obj:_opener(identity, open, app)
  return function()
    self:_opened(identity:lower())
    local mode = nil
    if self._screenMode then
      local ok, answer = pcall(self._screenMode)
      if ok then mode = answer end
    end
    local url = urlFor(identity, mode)
    -- A running app is told by a notification, which reaches it some fifty milliseconds sooner
    -- than open does, measured in the 1.4a trial on 2026-11-08, and an app not running is
    -- started by open, which hands it the URL as it launches.
    if self:_running() then
      self:_post(self.OPEN_NOTE, url)
    else
      self:_open(open, app, url)
    end
  end
end

--- obj:actions() -> the trial key's action, step 3.2 of docs/PLAN-STANDALONE.md,
--- docs/DESIGN-APP-LAUNCHER.md. bridge.launcher opens Olm.app's own launcher, olm://launcher, while
--- Hyper and Space still opens the Lua one. Its key is this machine's alone, set in
--- machines/<name>/hammerspoon-apps.lua, and its row and its key are gated on olmAppLauncher, so on
--- a machine whose olmapp piece is off it shows nowhere.
function obj:actions()
  return {
    { name = "launcher", description = "App Launcher", icon = "launcher", when = "olmAppLauncher",
      run = function() self:_openLauncher() end },
  }
end

-- Whether the app's launcher can open here, the piece on, the app built and the socket setting on,
-- since the app's launcher answers only over the socket.
function obj:_launcherReady()
  if not self._socket then return nil end
  return self:_ready()
end

function obj:_openLauncher()
  local open, app = self:_launcherReady()
  if not open then return end
  self:_listen()
  self:_opener("launcher", open, app)()
end

obj.predicates = {
  olmAppLauncher = function() return obj:_launcherReady() ~= nil end,
}

-- The app's bundle id, app/build.sh's, and the name of the notification a served key opens it by.
obj.BUNDLE_ID = "local.olm.Olm"
obj.OPEN_NOTE = "local.olm.Olm.open"

-- Whether the app is running now, asked on every press since it can have quit.
function obj:_running()
  local apps = hs.application
  if not (apps and type(apps.applicationsForBundleID) == "function") then return false end
  local ok, list = pcall(apps.applicationsForBundleID, self.BUNDLE_ID)
  return ok and type(list) == "table" and #list > 0
end

function obj:_post(name, object)
  local notes = hs.distributednotifications
  if not (notes and type(notes.post) == "function") then return false end
  return pcall(notes.post, name, object)
end

-- Hands one URL to the app in the background, as a task whose handle is kept until it ends, or
-- with no URL starts the app hidden and in the background.
function obj:_open(open, app, url)
  local task
  local args = url and { "-g", "-a", app, url } or { "-g", "-j", "-a", app }
  task = hs.task.new(open, function(code, _, err)
    self._tasks[task] = nil
    if code ~= 0 then log.w("Olm.app did not take " .. tostring(url or "a start") .. ", " .. tostring(err)) end
  end, args)
  if task then
    self._tasks[task] = true
    task:start()
  end
end

-- How long a served key's open counts as an open list before the app has said up, so a list key
-- typed straight after the open key reaches the app rather than the global binding.
obj.OPENING = 1.0
-- A down arriving this soon after a served key asked to open is the list before, posted before the
-- press, and leaves the open standing.
obj.DOWN_SLACK = 0.15
-- How long an answer of whether the app runs is kept, since it is asked on every leader press
-- while a list is up and the app cannot both quit and reopen in that time.
obj.RUNNING_TTL = 0.5

obj.STATE_NOTE = "local.olm.Olm.state"
obj.VERB_NOTE = "local.olm.Olm.verb"
obj.ASK_NOTE = "local.olm.Olm.ask"

-- Starts listening for the app's up and down once, and asks a running app for its state, since a
-- reload forgets what the app said before it.
function obj:_listen()
  if self._stateWatch then return end
  local notes = hs.distributednotifications
  if not (notes and type(notes.new) == "function") then return end
  self._stateWatch = notes.new(function(_, object) self:_state(object) end, self.STATE_NOTE)
  if self._stateWatch then self._stateWatch:start() end
  if self:_running() then self:_post(self.ASK_NOTE, "state") end
end

-- One state note from the app, "<tool>:up" or "<tool>:down".
function obj:_state(object)
  if type(object) ~= "string" then return end
  local tool, word = object:match("^(%a%w*):(%a+)$")
  if not tool then return end
  if word == "up" then
    self._up[tool] = true
    -- A note from the app proves it runs, so an answer kept from before it started is dropped.
    self._runningAt, self._runningWas = hs.timer.secondsSinceEpoch(), true
    self:_endOpening(tool)
  elseif word == "down" then
    self._up[tool] = nil
    local at = self._opening[tool]
    if not (at and hs.timer.secondsSinceEpoch() - at < self.DOWN_SLACK) then self:_endOpening(tool) end
  end
end

function obj:_opened(tool)
  self._opening[tool] = hs.timer.secondsSinceEpoch()
  if self._openTimers[tool] then self._openTimers[tool]:stop() end
  self._openTimers[tool] = hs.timer.doAfter(self.OPENING, function()
    self._openTimers[tool] = nil
    self._opening[tool] = nil
  end)
end

function obj:_endOpening(tool)
  self._opening[tool] = nil
  if self._openTimers[tool] then
    self._openTimers[tool]:stop()
    self._openTimers[tool] = nil
  end
end

-- Whether the app runs, kept for RUNNING_TTL.
function obj:_runningNow()
  local now = hs.timer.secondsSinceEpoch()
  if not self._runningAt or now - self._runningAt > self.RUNNING_TTL then
    self._runningAt = now
    self._runningWas = self:_running()
  end
  return self._runningWas
end

--- obj:showing(identity) -> whether the app's list for a tool it serves is up now, or being opened,
--- step 1.4f. lib/listopen.lua asks it through the root, so every list key, gate and the rule that
--- no cheat sheet shows over an open list treat the app's list as an open one. A quit app answers
--- false, so a crash never leaves list keys bound to a list that is gone.
function obj:showing(identity)
  if type(identity) ~= "string" or not self._serves[identity] then return false end
  local tool = identity:lower()
  if not (self._up[tool] or self._opening[tool]) then return false end
  if not self:_runningNow() then
    self._up[tool] = nil
    self:_endOpening(tool)
    return false
  end
  return true
end

--- obj:verb(identity, name) posts one list verb to the app, which runs it on its own highlight,
--- never waited on. name is the method lib/nav.lua routes to, selectNext or insertSelected.
function obj:verb(identity, name)
  if type(identity) ~= "string" or type(name) ~= "string" or not name:match("^%a%w*$") then return end
  self:_post(self.VERB_NOTE, identity:lower() .. ":" .. name)
end

--- obj:shadowed() -> the identities whose answers the shadow hands the app on this machine, from
--- the config's shadows list, empty unless the piece is on and the app is built.
function obj:shadowed()
  if not self:_ready() then return {} end
  return self._shadows
end

--- obj:shadowWith(identity, source) runs the shadow for one tool. source.watch(fn) calls fn after
--- every change of the tool's list, and source.answer() says what the list settled on, { query,
--- status, keys }, keys naming its rows in the order the shared search ranked them. A list still
--- searching is not handed over, and neither is the query sent last. source.socket true sends the
--- answer over the app's socket as the notification shadow, step 2.3's road for a list the app
--- answers through the bridge, the launcher, in place of the file and the distributed notification
--- a native list's shadow keeps.
function obj:shadowWith(identity, source)
  if type(identity) ~= "string" or not identity:match("^%a%w*$") then return end
  if type(source) ~= "table" or type(source.watch) ~= "function" or type(source.answer) ~= "function" then return end
  -- The app is started once here, while no list is open, since each settled answer only tells a
  -- running app, see _tell.
  local open, app = self:_ready()
  if open and not self._shadowLaunched then
    self._shadowLaunched = true
    self:_open(open, app, nil)
  end
  source.watch(function()
    if self._shadowTimers[identity] then self._shadowTimers[identity]:stop() end
    self._shadowTimers[identity] = hs.timer.doAfter(self.SHADOW_SETTLE, function()
      self._shadowTimers[identity] = nil
      self:_shadow(identity, source)
    end)
  end)
end

function obj:_shadow(identity, source)
  local open, app = self:_ready()
  if not open then return end
  local ok, answer = pcall(source.answer)
  if not ok or type(answer) ~= "table" or type(answer.query) ~= "string" then
    if not ok then log.w("the " .. identity .. " shadow could not read its list, " .. tostring(answer)) end
    return
  end
  if answer.status == "searching" or answer.status == "loading" then return end
  if self._shadowLast[identity] == answer.query then return end
  if source.socket then
    if self:notify("shadow", { tool = identity:lower(), query = answer.query, status = answer.status,
      claimed = answer.claimed == true, keys = answer.keys or {} }) then
      self._shadowLast[identity] = answer.query
    end
    return
  end
  self._shadowLast[identity] = answer.query
  self._shadowId = self._shadowId + 1
  local name = identity:lower() .. "shadow"
  self:_write(name, { id = self._shadowId, tool = identity:lower(), query = answer.query,
    status = answer.status, keys = answer.keys or {} })
  self:_tell(identity:lower(), self._shadowId)
end

-- The name of the notification each settled answer is told to the app by.
obj.SHADOW_NOTE = "local.olm.Olm.shadow"

-- Tells the running app an answer is waiting, as a distributed notification whose object is the
-- tool and the id, "filesearch:12". Not through open and olm://shadow, which it did until
-- 2026-11-08, since running open while the list was up left file search's own list, the one its
-- open key shows, with no rows for whatever was typed, found in the 1.3f trial.
function obj:_tell(tool, id)
  self:_post(self.SHADOW_NOTE, tool .. ":" .. tostring(id))
end

return obj
