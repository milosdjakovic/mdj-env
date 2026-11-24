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

local APP = "/Applications/Olm.app"
local RUN = os.getenv("HOME") .. "/.olm/run"

obj._pieces = {}
obj._serves = {}
-- The tools whose own list the app shows inside its launcher, step 3.3, docs/DESIGN-APP-HOSTED.md.
obj._hosts = {}
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
-- The tool whose cycle the app shows, lowered, step 3.9, so a further press of its key steps it
-- rather than opening it again, and the handles of the retyped keys waiting to be posted.
obj._cycling = nil
obj._retypes = {}

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
  if type(opts.hosts) == "table" or (opts.hosts == nil and type(opts.pieces) == "table") then
    self._hosts = {}
    for _, identity in ipairs(opts.hosts or {}) do
      if type(identity) == "string" and identity:match("^%a%w*$") then self._hosts[identity] = true end
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
  -- Whether Hyper and Space opens the app's launcher, step 3.5, off unless the config says true.
  -- Held off on 2026-11-17 until every tool the launcher leads to is shown in the app.
  if opts.launcherFlip ~= nil then self._flip = opts.launcherFlip == true end
  -- Whether the app's launcher builds its catalog itself, step 6.1, off unless the config says true,
  -- written into the catalog's share for the app to read at each open.
  if opts.launcherCatalog ~= nil then self._catalog = opts.launcherCatalog == true end
  -- The leaders whose modifier combinations Olm.app claims while its socket is up, step 5.3,
  -- docs/DESIGN-APP-KEYS.md, by the name a row spells each, none unless the config names them.
  if type(opts.appKeys) == "table" then
    self._appKeys = {}
    for _, name in ipairs(opts.appKeys) do
      if type(name) == "string" then self._appKeys[#self._appKeys + 1] = name:lower() end
    end
  end
  -- Whether a leader's cheat sheet is drawn by the app while its socket is up, step 5.2,
  -- docs/DESIGN-APP-KEYS.md, off unless the config says true.
  if opts.sheetsInApp ~= nil then self._sheetsInApp = opts.sheetsInApp == true end
  -- Whether a press on an app is run by the app, step 6.2, docs/DESIGN-APP-APPS.md, off unless the
  -- config says true, and even then only while the app has said it may act.
  if opts.appToggler ~= nil then self._appToggler = opts.appToggler == true end
  if opts.windowsInApp ~= nil then self._windowsInApp = opts.windowsInApp == true end
  -- Whether the app keeps the app catalog, each app's key, mode and place, step 6.2b,
  -- docs/DESIGN-APP-APPS.md, off unless the config says true.
  if opts.appCatalog ~= nil then self._appCatalog = opts.appCatalog == true end
  -- Whether a tool's own key opens its list in the app, step 3.8, off unless the config says true.
  if opts.keysFlip ~= nil then self._keysFlip = opts.keysFlip == true end
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
---
--- obj:hosted() -> the identities whose own list the app shows inside its launcher, step 3.3, sorted,
--- which the root hands shareEach as also for the keys their bar shows.
function obj:hosted()
  local out = {}
  for identity in pairs(self._hosts) do out[#out + 1] = identity end
  table.sort(out)
  return out
end

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
  self._shares = self._shares or {}
  self._shares[suffix] = { build = build, also = also }
  for _, identity in ipairs(names) do
    self:_write(identity:lower() .. suffix, function() return build(identity) end)
  end
end

--- obj:reshare() writes every share shareEach wrote again, from the same builders, for a value
--- that has since changed, a picture the icon source drew after load.
function obj:reshare()
  local shares = self._shares or {}
  self._shares = {}
  for suffix, share in pairs(shares) do self:shareEach(suffix, share.build, share.also) end
end

-- The siblings that serve over the socket, step 2.2, loaded from beside this file since a host's
-- directory is not on the module path.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*/)")) or "./"
obj.PICTURES = os.getenv("HOME") .. "/.olm/cache/bridge"

-- An hs.image as a Picture, written once under a name taken from its content, the protocol's
-- Picture. The icon engine hands the same image object for the same icon, so each is kept weakly.
local pictures = setmetatable({}, { __mode = "k" })
local function pictureOf(img)
  if type(img) ~= "userdata" or not img.encodeAsURLString then return nil end
  if pictures[img] then return pictures[img] end
  local okUrl, url = pcall(img.encodeAsURLString, img, false, "PNG")
  if not okUrl or type(url) ~= "string" then return nil end
  local path = obj.PICTURES .. "/" .. hs.hash.MD5(url) .. ".png"
  if not hs.fs.attributes(path) then
    hs.fs.mkdir(os.getenv("HOME") .. "/.olm/cache")
    hs.fs.mkdir(obj.PICTURES)
    local b64 = url:match("^data:[^,]*;base64,(.*)$")
    local bytes = b64 and hs.base64.decode(b64)
    local f = bytes and io.open(path, "wb")
    if not f then return nil end
    f:write(bytes)
    f:close()
  end
  pictures[img] = { path = path }
  return pictures[img]
end

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
  self._facade = self._facade or sibling("facade").new()
  -- A timer handle nothing refers to may be collected before it fires, so each is kept until then.
  local turns = {}
  local function later(seconds, fn)
    local t
    t = hs.timer.doAfter(seconds, function() turns[t] = nil; fn() end)
    turns[t] = true
  end
  local service = serve.new({ rpc = rpc, clean = frame.clean, launcher = provider.launcher, later = later,
    icons = provider.icons or function() return nil end, version = provider.version,
    rowLimit = provider.rowLimit, presentationFor = provider.presentationFor,
    pending = function(name) return self:_takePending(name) end,
    facade = self._facade, stampIcons = provider.stampIcons, verbs = provider.verbs,
    picture = pictureOf, cycleIdle = provider.cycleIdle, settings = provider.settings,
    retype = function(code, mods) self:_retype(code, mods) end,
    -- A hosted tool's list is shown in the app when the config's hosts names it, by the name its
    -- presentation carries, a child taking its tool's.
    hosted = function(p) return type(p) == "table" and type(p.name) == "string" and self._hosts[p.name] == true end,
    -- A tool the app serves itself is shown as its own source, step 3.3e, never as a Lua list, so
    -- File Search's launcher row and its typed word open the app's file search.
    native = function(p) return type(p) == "table" and type(p.name) == "string" and self._serves[p.name] == true end,
    styled = function(v)
      if type(v) == "userdata" and v.getString then return v:getString() end
      return tostring(v)
    end })
  self:_keyMethods(service.methods)
  local conn
  local session = rpc.new({ json = hs.json, methods = service.methods,
    send = function(text) if conn then conn:send(text) end end,
    defer = function(fn) later(0, fn) end,
    log = function(text) log.w(text) end })
  conn = transport.new({ path = (self._run or RUN) .. "/" .. self.SOCKET, frame = frame,
    onMessage = function(text) session:receive(text) end,
    onUp = function() log.i("connected to Olm.app's socket") end,
    onDown = function()
      session:reset(); service.closeAll(); self:_reclaimKeys(); log.i("Olm.app's socket went")
    end,
    log = function(text) log.w(text) end })
  self._conn = conn:start()
  self._service, self._session = service, session
  return conn
end

--- obj:onAppsChanged(fn)
--- fn is handed the app keys the app keeps, step 6.2b, a list of { bundle, leader, key, mods }, each
--- time it sends them.
function obj:onAppsChanged(fn)
  self._onAppsChanged = type(fn) == "function" and fn or nil
end

--- obj:switchOn(name) -> whether one of the bridge's switches is on, by its name in
--- config/plugins.lua, so a setting may apply live while its owner is the app.
local SWITCHES = { appCatalog = "_appCatalog", windowsInApp = "_windowsInApp", appToggler = "_appToggler" }
function obj:switchOn(name)
  local field = SWITCHES[name]
  return field ~= nil and self[field] == true
end

--- obj:windowsInApp() -> whether the app runs the window manager's keys itself, step 6.3b.
function obj:windowsInApp()
  return self._windowsInApp == true
end

--- obj:appKeys() -> the leaders whose modifier combinations the app may claim, step 5.3, a list.
function obj:appKeys()
  return self._appKeys or {}
end

--- obj:keyHost(leaders, rows) hands the bridge the leaders by the name a row spells each and the
--- rows the binder bound, so a press the app claimed runs the very row the binder would have run,
--- step 5.3. Called by the root as it binds.
function obj:keyHost(leaders, rows)
  self._keyLeaders = leaders or {}
  local runs = {}
  for _, row in ipairs(rows or {}) do
    if type(row.run) == "function" then
      runs[tostring(row.owner) .. "." .. tostring(row.action)] = { run = row.run, leader = row.leader,
        afterRelease = row.afterRelease == true }
    end
  end
  self._keyRuns = runs
end

--- obj:keysReady() tells the app the leaders have started, so it asks for the keys it claims, which
--- it also does each time a session opens.
function obj:keysReady()
  if #(self._appKeys or {}) > 0 then self:notify("keysReady", {}) end
end

-- The three words of step 5.3. releaseKeys hands the app the combinations of every leader it names
-- that the config lets it claim, answering which were released and why any was not. reclaimKeys
-- takes some back, for combinations the app could not claim. runKey, a request so a repeat is
-- chained on its answer, runs one bound row by its id with its depth and takes that row's leader's
-- sheet down, as a press of the key does.
function obj:_keyMethods(methods)
  methods.releaseKeys = { run = function(params)
    -- The second pass of a reclaim, a second after a socket went, stops here, since an app that came
    -- back within that second now claims the keys and the pass would fail on every combination it
    -- holds exclusively, -9878, as each quick relaunch of the app did on 2026-11-23.
    if self._keyTimer then
      self._keyTimer:stop()
      self._keyTimer = nil
    end
    local allowed = {}
    for _, name in ipairs(self._appKeys or {}) do allowed[name] = true end
    local released, refused, lists = {}, {}, {}
    for _, name in ipairs(type(params.leaders) == "table" and params.leaders or {}) do
      local leader = (self._keyLeaders or {})[name]
      if not allowed[name] then
        refused[#refused + 1] = { leader = name, why = "the config does not hand it to the app" }
      elseif not leader then
        refused[#refused + 1] = { leader = name, why = "it is not in use" }
      else
        -- The plain leader, the rows with no leader on their own modifiers, is released by name.
        local ok, why = leader:releaseModifiers({ plain = name == "plain" })
        if ok then
          released[#released + 1] = name
          lists[name] = type(leader.listCombos) == "function" and leader:listCombos() or {}
          self._released = self._released or {}
          self._released[name] = leader
        else
          refused[#refused + 1] = { leader = name, why = why }
        end
      end
    end
    for _, r in ipairs(refused) do log.i("the app does not claim " .. r.leader .. "'s keys, " .. tostring(r.why)) end
    return { released = released, refused = refused, lists = lists }
  end }
  methods.reclaimKeys = { run = function(params)
    for _, name in ipairs(type(params.leaders) == "table" and params.leaders or {}) do
      local leader = self._released and self._released[name]
      if leader then
        leader:reclaimModifiers()
        self._released[name] = nil
      end
    end
    return true
  end }
  methods.runKey = { run = function(params)
    local entry = (self._keyRuns or {})[tostring(params.id)]
    if not entry then return false end
    local leader = entry.leader and (self._keyLeaders or {})[entry.leader]
    if leader then leader:conceal() end
    local depth = tonumber(params.depth) or 0
    -- A row that waits for its leader's release, a capture, waits here as a press here would, on
    -- isActive, which reads the live modifiers whoever holds the combinations.
    if entry.afterRelease and leader then
      leader:afterRelease(function() entry.run(depth) end)
      return true
    end
    -- A row whose run answers a report hands it back, the window manager's read and plan for the
    -- app's shadow, step 6.3b, docs/DESIGN-APP-WINDOWS.md.
    local answer = entry.run(depth)
    if type(answer) == "table" and type(answer.window) == "table" then
      return { ran = true, window = answer.window }
    end
    return true
  end }
  -- A row the app ran itself, the window manager's since 6.3b, told so the row's leader takes its
  -- sheet down as a press run here would. A notification, so the press waits on nothing.
  -- An app's key the app keeps, step 6.2b, is no row here, so it names its leader itself.
  methods.keyRan = { run = function(params)
    local entry = (self._keyRuns or {})[tostring(params.id)]
    local name = entry and entry.leader or (type(params.leader) == "string" and params.leader or nil)
    local leader = name and (self._keyLeaders or {})[name]
    if leader then leader:conceal() end
    return true
  end }
  -- The app's own app keys, step 6.2b, docs/DESIGN-APP-APPS.md, sent each time the app takes its
  -- keys, so the Hyper sheet and the launcher's app rows say what a press does with no reload.
  methods.appsChanged = { run = function(params)
    if self._onAppsChanged and type(params.apps) == "table" then
      local ok, err = pcall(self._onAppsChanged, params.apps, params.replaces)
      if not ok then log.w("the app keys the app sent raised, " .. tostring(err)) end
    end
    return true
  end }
  -- A press the app claimed on a list key's combination, run by the leader's list pass while a list
  -- is open on it, answering whether it ran and whether that binding repeats. Otherwise the app runs
  -- the global row, _resolve's order.
  methods.listKey = { run = function(params)
    local leader = (self._released or {})[tostring(params.leader)]
    if not leader then return { ran = false, repeats = false } end
    local flags = {}
    for _, m in ipairs(type(params.mods) == "table" and params.mods or {}) do flags[m] = true end
    local ran, repeats = leader:runListKey(tonumber(params.code), flags, tonumber(params.depth) or 0)
    if ran then leader:conceal() end
    return { ran = ran == true, repeats = repeats == true }
  end }
end

-- Every leader the app held, taken back when the socket goes, at once and again a second later, since
-- the app may still have held a combination at the first.
function obj:_reclaimKeys()
  local held = self._released
  self._released = nil
  if not held or next(held) == nil then return end
  local function all() for _, leader in pairs(held) do leader:reclaimModifiers() end end
  all()
  self._keyTimer = hs.timer.doAfter(1, all)
end

--- obj:catalogInApp() -> whether the app's launcher builds its catalog itself, step 6.1.
function obj:catalogInApp()
  return self._catalog == true
end

--- obj:sheetsShown() -> whether a cheat sheet goes to the app now, step 5.2: the switch on and a
--- session open.
function obj:sheetsShown()
  return self._sheetsInApp == true and self._session ~= nil and self._session.open == true
end

--- obj:appsInApp() -> whether a press on an app goes to the app now, step 6.2: the switch on, a
--- session open and the app having said it may act.
function obj:appsInApp()
  return self._appToggler == true and self._session ~= nil and self._session.open == true
    and self._service ~= nil and self._service.appsReady == true
end

--- obj:appForwarder(plan) -> the forwarder lib/appfocus.lua is handed, step 6.2. It sends the press
--- as the notification appRun with what Lua would have done, plan(bundle, hides), for the app's
--- shadow, and answers whether it was sent, false whenever appsInApp says no so Lua runs it.
function obj:appForwarder(plan)
  return function(press)
    if not self:appsInApp() then return false end
    local lua = type(plan) == "function" and plan(press.bundle, press.hides == true) or nil
    return self:notify("appRun", { id = press.id, bundle = press.bundle, hides = press.hides == true,
      placement = type(press.placement) == "table" and press.placement or nil, lua = lua }) == true
  end
end

--- obj:notify(method, params) -> true when sent, a notification to the app over the socket, sent
--- only while a session is open, so nothing queues for an app that is not there
function obj:notify(method, params)
  if not (self._conn and self._session) then return false end
  return self._session:notify(method, params)
end

--- obj:presentedRedraw(name, token, resetRow) is the root's redrawPresented reaching a list the app
--- hosts, step 3.3. Asked while a request runs that list's code, it is recorded as that answer's
--- rows effect. Otherwise each hosted level showing that list is sent the effects notification, the
--- app redrawing it where it is on screen. Answers whether it reached any.
function obj:presentedRedraw(name, token, resetRow)
  if not self._service then return false end
  if self._facade and self._facade.recording() then
    return self._facade.record({ rows = { hold = not resetRow } })
  end
  local sent = false
  for _, params in ipairs(self._service.redraws(name, token, resetRow)) do
    sent = self:notify("effects", params) or sent
  end
  return sent
end

-- The words that change a list, asked outside any request while a hosted list is the app's, step
-- 3.8, sent to it as the effects notification, the way a redraw already is. A tool's own code calls
-- them after a key or a timer, Clipboard History's Manage History changing its placeholder and
-- clearing its field, and before this only the redraw reached the app. While a tool's own key is
-- still opening its list in the app, the placeholder waits for the level's open and goes with it.
local OUTSIDE = { stageSetQuery = true, stageSetPlaceholder = true, stageHide = true }

function obj:_wordOutside(name, ...)
  if not OUTSIDE[name] or not self._service then return false end
  local text = tostring((...) or "")
  local service = self._service
  local top = type(service.hostedTop) == "function" and service.hostedTop() or nil
  local pending = self._presenting
  if pending and (top ~= pending.name) and hs.timer.secondsSinceEpoch() - pending.at < self.OPENING then
    if name == "stageSetPlaceholder" then pending.placeholder = text; return true end
    return false
  end
  if not (top and self:hosting(top)) then return false end
  local level = service.paneLevel(top)
  if not level then return false end
  local effect
  if name == "stageSetQuery" then effect = { setQuery = { level = level.id, q = level.q, query = text } }
  elseif name == "stageSetPlaceholder" then effect = { setPlaceholder = { level = level.id, text = text } }
  else effect = { hide = {} } end
  self:notify("effects", { level = level.id, q = level.q, effects = { effect } })
  return true
end

--- obj:_takePending(name) -> the placeholder a tool's code set while its own key was opening its list
--- in the app, once, step 3.8, for serve's open.
function obj:_takePending(name)
  local pending = self._presenting
  if not (pending and pending.name == name) then return nil end
  self._presenting = nil
  return { placeholder = pending.placeholder }
end

--- obj:hostedWord(name, ...) -> handled, value, the root's stage words asking first, step 3.3c of
--- docs/PLAN-STANDALONE.md. While a request from the app runs a hosted list's code, the words that
--- read the list answer from that request's own row and query, and the words that change it are
--- recorded as the answer's effects, docs/PROTOCOL-BRIDGE.md The stage words. handled is false
--- outside a request, and the word then acts on the Lua stage as before.
function obj:hostedWord(name, ...)
  local f = self._facade
  if not (f and f.recording()) and self:_wordOutside(name, ...) then return true end
  if not (f and f.recording()) then
    -- Outside a request, the row the app highlights while it shows a hosted list, step 3.3d, so a
    -- tool's own timer, Speed Test's run ticking, asks the app's row and not the hidden Lua stage's.
    if (name == "stageSelectedItem" or name == "stageSelectedRow") and self._service
      and type(self._service.shownItem) == "function" then
      local handled, item, row = self._service.shownItem()
      if handled then
        local top = self._service.hostedTop()
        if top and self:hosting(top) then
          if name == "stageSelectedItem" then return true, item end
          return true, row
        end
      end
    end
    return false
  end
  local context = f.context() or {}
  if name == "stageSelectedItem" then return true, context.item end
  if name == "stageSelectedRow" then return true, context.row end
  if name == "stageQuery" then return true, context.query or "" end
  if name == "stageHide" then f.record({ hide = {} }); return true end
  if name == "stagePop" then f.record({ pop = {} }); return true, true end
  if name == "stageSetQuery" then
    f.record({ setQuery = { query = tostring((...) or "") } })
    return true
  end
  if name == "stageSetPlaceholder" then
    f.record({ setPlaceholder = { text = tostring((...) or "") } })
    return true
  end
  if name == "stagePush" then
    local child = ...
    if type(child) ~= "table" then return true, false end
    f.record({ pushChild = child })
    return true, true
  end
  return false
end

-- A colour of hs.canvas's as its red, green, blue and alpha, through hs.drawing.color where it is
-- named some other way, a list or a hex.
local function rgbaOf(c)
  if type(c) ~= "table" then return nil end
  if c.red == nil and c.green == nil and c.blue == nil and hs.drawing and hs.drawing.color then
    local ok, v = pcall(hs.drawing.color.asRGB, c)
    if ok and type(v) == "table" then c = v end
  end
  return { red = tonumber(c.red) or 0, green = tonumber(c.green) or 0, blue = tonumber(c.blue) or 0,
    alpha = tonumber(c.alpha) or 1 }
end

-- An hs.styledtext of the kit's, one run, as a Text, docs/PROTOCOL-BRIDGE.md The preview pane.
local function textOf(st)
  if not (type(st) == "userdata" and st.asTable) then return nil end
  local ok, t = pcall(st.asTable, st)
  if not ok or type(t) ~= "table" or type(t[1]) ~= "string" then return nil end
  local run = type(t[2]) == "table" and t[2].attributes or {}
  local font, para = run.font or {}, run.paragraphStyle or {}
  return { string = t[1], font = font.name, size = tonumber(font.size), color = rgbaOf(run.color),
    alignment = para.alignment, lineBreak = para.lineBreak,
    -- type-exempt, the kit's own line height read off its styled text to cross to Olm.app, set nowhere here
    lineHeight = tonumber(para.maximumLineHeight) or tonumber(para.minimumLineHeight),
    -- The kit pins the mono font's tightening to zero, layout.lua's textElement, and NSParagraphStyle's
    -- own default is above it.
    tight = tonumber(para.tighteningFactorForTruncation) == 0 or nil }
end

local paneLib = nil
local function panes()
  paneLib = paneLib or sibling("pane")
  return paneLib
end

--- obj:paneBackend(owner, localFactory) -> the drawing backend factory for owner's preview pane,
--- step 3.3d. While the app shows owner's list hosted on top, what the pane draws goes to the app as
--- paneDrawn. Otherwise it draws through localFactory, the backend the root chose before.
function obj:paneBackend(owner, localFactory)
  local lib = panes()
  local remote = lib.backend(function(content, scroll) self:_paneDrawn(owner, content, scroll) end)
  return lib.router(localFactory, remote, function() return self:hosting(owner) end)
end

--- obj:sheetBackend() -> the cheat sheet panel's backend, lib/panel.lua's per instance one, step
--- 5.2. While sheetsShown says yes a show goes to the app as the notification sheet, the panel's
--- frame, its corner and its content elements, and a hide as sheet with hide true. Otherwise, and
--- for a show the app could not be sent, it draws through the configured backend as before.
function obj:sheetBackend()
  return function(frame, window, configured)
    local lib = panes()
    local remote = lib.sheetBackend(function(placed, surface, content)
      if not self:sheetsShown() then return false end
      local elements, dropped = lib.encode(content, { color = rgbaOf, text = textOf, picture = pictureOf })
      for _, kind in ipairs(dropped) do
        if not self._said["sheet:" .. kind] then
          self._said["sheet:" .. kind] = true
          log.w("a " .. kind .. " element of a cheat sheet could not cross to Olm.app and was left out")
        end
      end
      return self:notify("sheet", { frame = { x = placed.x, y = placed.y, w = placed.w, h = placed.h },
        radius = lib.radiusOf(surface), elements = elements }) == true
    end, function() self:notify("sheet", { hide = true }) end)
    local localFactory = function(f, w) return configured and configured(f, w) or nil end
    return lib.router(localFactory, remote, function() return self:sheetsShown() end)(frame, window)
  end
end

-- One paint of owner's pane sent to the level that shows it, naming the highlight the Lua side was
-- last told, docs/PROTOCOL-BRIDGE.md The preview pane.
function obj:_paneDrawn(owner, content, scroll)
  local level = self._service and self._service.paneLevel(owner)
  if not level then return false end
  local elements, dropped = panes().encode(content, { color = rgbaOf, text = textOf, picture = pictureOf })
  for _, kind in ipairs(dropped) do
    if not self._said["pane:" .. kind] then
      self._said["pane:" .. kind] = true
      log.w("a " .. kind .. " element of " .. owner .. "'s pane could not cross to Olm.app and was left out")
    end
  end
  local lit = level.lit or {}
  local frame = level.paneFrame or {}
  return self:notify("paneDrawn", { level = level.id, h = lit.h or 0, ref = lit.ref,
    elements = elements, contentHeight = scroll and scroll.height or frame.h or 0,
    keepScroll = scroll ~= nil and scroll.reset == false })
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
    -- Quits Olm.app, so every list it shows goes back to Hammerspoon's own until it starts again,
    -- the back out of the plan's stage 3 as a row, asked for by Milos on 2026-11-17.
    { name = "quit", description = "Quit Olm App", icon = "quit", when = "olmAppRunning",
      keywords = "olm.app, stop, exit", run = function() self:_quitApp() end },
    -- Olm Settings, the app's own window, docs/DESIGN-APP-SETTINGS.md, olm://settings. A row where
    -- the app is built, starting it when it is not running, since only the app draws the window.
    { name = "settings", description = "Olm Settings", icon = "settings", when = "olmAppReady",
      keywords = "preferences, options, configure, theme, placement, chooser, plugins",
      run = function() self:openSettings() end },
  }
end

--- obj:openSettings() -> true when Olm.app was asked to show its Olm Settings window, olm://settings.
--- Always handed over by open in the foreground, running or not, never by the notification, since
--- macOS 14's activation is cooperative and an app told by a notification may only ask to come
--- forward, which the app in front declines. LaunchServices opening a URL brings its app forward,
--- found in the S.2 trial on 2026-11-20 when the window opened behind.
function obj:openSettings()
  local open, app = self:_ready()
  if not open then return false end
  self:_open(open, app, "olm://settings", true)
  return true
end

-- Asks Olm.app to quit, the way the Dock's Quit does, so it closes its socket on the way out.
function obj:_quitApp()
  local apps = hs.application
  if not (apps and type(apps.applicationsForBundleID) == "function") then return end
  local ok, list = pcall(apps.applicationsForBundleID, self.BUNDLE_ID)
  if not (ok and type(list) == "table") then return end
  for _, app in ipairs(list) do pcall(function() app:kill() end) end
  self._runningAt = nil
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

--- obj:launcherOpen(fallback) -> function or nil, the run of the launcher's open key, step 3.5 of
--- docs/PLAN-STANDALONE.md, docs/DESIGN-APP-LAUNCHER.md under step 3.5. Nil where the app's launcher
--- cannot open here, the piece off, the app not built or the socket setting off, so the key keeps the
--- Lua launcher. Otherwise a function that asks at every press: the app's launcher while its socket
--- is up, and the Lua launcher, fallback, while it is not, an app quit or not connected yet. The
--- fallback never starts the app, so quitting it hands the key back to Lua until the next load.
function obj:launcherOpen(fallback)
  if type(fallback) ~= "function" then return nil end
  if not self._flip then return nil end
  if not self:_launcherReady() then return nil end
  sayOnce(self, "Hyper and Space opens Olm.app's launcher while its socket is up, the olmapp piece is on")
  return function(...)
    if self._conn and type(self._conn.isUp) == "function" and self._conn:isUp() then
      return self:_openLauncher()
    end
    return fallback(...)
  end
end

--- obj:presentInApp(name, presentation) -> true when Olm.app shows the list, step 3.8 of
--- docs/PLAN-STANDALONE.md, docs/DESIGN-APP-HOSTED.md under 3.8. The root's stagePresent, the one
--- door a tool's own key shows its list through, asks this before the Lua stage. The app takes the
--- list when keysFlip is on, the config hosts the presentation's tool, and the app's socket is up,
--- asked at every press, so a quit app hands every key back to the Lua list at once. It then opens
--- olm://tool?name=<name> with Olm's placement, and the app asks open for that tool's level.
function obj:presentInApp(name, presentation)
  if not self:_openTool(name, presentation, "") then return false end
  self._cycling = nil
  return true
end

-- The open both a tool's key and its cycle key share, false where the app cannot take the list,
-- extra appended to the URL.
function obj:_openTool(name, presentation, extra)
  if not self._keysFlip then return false end
  local p = presentation
  if type(p) ~= "table" or type(p.name) ~= "string" or not self._hosts[p.name] then return false end
  if not self:_launcherReady() then return false end
  if not (self._conn and type(self._conn.isUp) == "function" and self._conn:isUp()) then return false end
  if not tostring(name or p.name):match("^%a%w*$") then return false end
  sayOnce(self, "a hosted tool's own key opens its list in Olm.app while its socket is up, the olmapp piece is on")
  self:_listen()
  self:_opened(p.name:lower())
  self._presenting = { name = p.name, at = hs.timer.secondsSinceEpoch() }
  local mode = nil
  if self._screenMode then
    local ok, answer = pcall(self._screenMode)
    if ok then mode = answer end
  end
  local screen = (type(mode) == "string" and mode:match("^%a+$")) and ("screen=" .. mode .. "&") or ""
  return self:_post(self.OPEN_NOTE, "olm://tool?" .. screen .. "name=" .. p.name .. "&query=" .. extra) == true
end

--- obj:cycleInApp(name, presentation) -> true when the app took a press of the tool's cycle key, step
--- 3.9, docs/DESIGN-APP-HOSTED.md under 3.9, under presentInApp's conditions. The first press opens
--- olm://tool?name=<name>&cycle=1, the list shown bare in the app, and each press while that cycle is
--- up or opening posts the verb cycleStep, which the app's stage runs on its own highlight.
function obj:cycleInApp(name, presentation)
  local p = presentation
  local tool = type(p) == "table" and type(p.name) == "string" and p.name:lower() or nil
  if tool and self._cycling == tool and (self._up[tool] or self._opening[tool]) and self:_runningNow() then
    self:_post(self.VERB_NOTE, tool .. ":cycleStep")
    return true
  end
  if not self:_openTool(name, p, "&cycle=1") then return false end
  self._cycling = tool
  return true
end

-- A key typed over a list cycled in the app, posted again into the app underneath once the app has
-- hidden, as the Lua stage's _onBareKey posts it, step 3.9. Hammerspoon posts it since it holds the
-- Accessibility grant posting a key needs and Olm.app does not.
obj.RETYPE_DELAY = 0.05
function obj:_retype(code, mods)
  local t
  t = hs.timer.doAfter(self.RETYPE_DELAY, function()
    self._retypes[t] = nil
    hs.eventtap.event.newKeyEvent(mods or {}, code, true):post()
  end)
  self._retypes[t] = true
end

obj.predicates = {
  olmAppLauncher = function() return obj:_launcherReady() ~= nil end,
  olmAppRunning = function() return obj:_ready() ~= nil and obj:_runningNow() == true end,
  olmAppReady = function() return obj:_ready() ~= nil end,
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
-- with no URL starts the app hidden and in the background. front hands the URL in the foreground,
-- bringing the app forward, for a window of its own.
function obj:_open(open, app, url, front)
  local task
  local args = url and (front and { "-a", app, url } or { "-g", "-a", app, url }) or { "-g", "-j", "-a", app }
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
    if not (at and hs.timer.secondsSinceEpoch() - at < self.DOWN_SLACK) then
      self:_endOpening(tool)
      if self._cycling == tool then self._cycling = nil end
    end
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

-- The served tool whose list in the app holds identity's hosted list on top, or nil. A hosted list
-- is open while it is the app's top level and the list it was pushed in is up, so its own keys,
-- Hyper and O for its actions pane among them, are live there as in the Lua list, step 3.3, found
-- missing in Milos's trial on 2026-11-16. The launcher keeps its own keys beside them.
function obj:_hostOf(identity)
  local service = self._service
  if not (service and type(service.hostedTop) == "function") or service.hostedTop() ~= identity then return nil end
  -- A hosted list its own key opened alone, step 3.8, sits in no other list of the app's, so it is
  -- its own host, and its pane, its keys and its verbs reach the app exactly as they do when it
  -- sits in the launcher. Missing this drew Clipboard History's pane in a window of Hammerspoon's,
  -- found in 3.8's trial on 2026-11-18.
  local tool = identity:lower()
  if self._hosts[identity] and (self._up[tool] or self._opening[tool]) and self:_runningNow() then return identity end
  for served in pairs(self._serves) do
    if self:showing(served) then return served end
  end
  if self:showing(self.LAUNCHER) then return self.LAUNCHER end
  return nil
end

-- The app's launcher, a list the app shows over the socket rather than one the serves share names.
obj.LAUNCHER = "launcher"

-- Whether identity names a list of the app's own whose keys Hyper reaches, a served tool's, or the
-- launcher wherever the socket serves it, step 3.4 brought forward for the launcher on 2026-11-16,
-- since a hosted list's keys go to the launcher they sit in.
function obj:_keyed(identity)
  return self._serves[identity] == true or (identity == self.LAUNCHER and self._socket == true)
end

--- obj:showing(identity) -> whether the app's list for a tool it serves is up now, or being opened,
--- step 1.4f. lib/listopen.lua asks it through the root, so every list key, gate and the rule that
--- no cheat sheet shows over an open list treat the app's list as an open one. A quit app answers
--- false, so a crash never leaves list keys bound to a list that is gone.
function obj:showing(identity)
  if type(identity) ~= "string" then return false end
  if not self:_keyed(identity) then return false end
  local tool = identity:lower()
  if not (self._up[tool] or self._opening[tool]) then return false end
  if not self:_runningNow() then
    self._up[tool] = nil
    self:_endOpening(tool)
    return false
  end
  return true
end

--- obj:hosting(identity) -> whether identity's list is hosted on top of a list of the app's that is up,
--- so its keys are live, step 3.3. Apart from showing, since the root's calls into the tool, the
--- actions pane's choices and verbs, still run its Lua code while its list is hosted.
function obj:hosting(identity)
  return type(identity) == "string" and not self:_keyed(identity) and self:_hostOf(identity) ~= nil
end

--- obj:verb(identity, name) posts one list verb to the app, which runs it on its own highlight,
--- never waited on. name is the method lib/nav.lua routes to, selectNext or insertSelected.
function obj:verb(identity, name)
  if type(identity) ~= "string" or type(name) ~= "string" or not name:match("^%a%w*$") then return end
  -- A hosted list's key goes to the served list it sits in, whose stage runs it on the level on top.
  if not self:_keyed(identity) then identity = self:_hostOf(identity) or identity end
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
