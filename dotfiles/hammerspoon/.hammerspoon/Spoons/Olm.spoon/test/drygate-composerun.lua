-- One run of the composition root under a stub, printed as a snapshot of what it decided.
--
-- test/drygate-rename.lua runs this twice, once over the spoon as it is and once over a copy
-- whose plugins all carry scrambled names, and compares the two snapshots after turning the
-- scrambled names back. Any difference means core behaves differently depending on what a
-- plugin is called, which is the layer rule seen from the outside rather than read from the
-- source. It sees a name however core spelled it, a field, a key, a concatenation, a format or
-- anything computed, but only where the decision reaches something this file records, listed
-- under THE SNAPSHOT below, and only for code that runs while the root composes. It runs
-- root/compose.lua itself, which no unit case does.
--
-- Usage
--   lua drygate-composerun.lua <spoon dir> <hammerspoon config dir> <sandbox dir> [rename map]
--
-- The rename map is a file of lines "<original> <scrambled>", one per plugin directory and one
-- per identity. Given one, every manifest under plugins/ is handed to core with its identity
-- spelled the scrambled way, its name, its surface context and any sibling need naming another
-- plugin, and the person's plugins config is handed over with its keys renamed to match. The
-- directories themselves were already renamed on disk by the caller.
--
-- THE PERSON'S OWN init.lua RUNS, unchanged, so the cfg core receives is exactly the one a
-- live load builds. hs.loadSpoon loads the spoon under test instead of the installed one, and
-- Olm:start is wrapped only to point the storage roots into the sandbox and, for the
-- scrambled run, to rename the plugin config keys.
--
-- THE STUB. Every hs answer is a permissive stand in that can be indexed, called, compared,
-- added and joined without raising, so a load runs to the end rather than stopping at the
-- first live answer it wanted. A stand in indexed by a number answers nil, so ipairs over one
-- is an empty list and never a loop that runs forever. A handful of answers are real, the
-- directory listing and the file attributes, from one listing of the two trees taken at the
-- start, hs.settings, hs.json and hs.execute, which answer nothing, and a logger that records
-- every line. Every one of them records its calls the way a stand in does. Text is measured
-- at a fixed width per character, so a content strategy can be laid out and drawn.
--
-- THE SANDBOX. Nothing here may change a file, so os.remove, os.rename, os.execute, os.tmpname,
-- io.popen, package.loadlib, io.output and io.input with an argument, and every io.open other
-- than a read are refused after the listing is taken. A read through io.open or io.lines
-- outside the spoon and the config directory, or of any json file, is refused too, since that
-- is runtime data, and a store keyed by a plugin's name would read differently under a
-- scrambled name for a reason that has nothing to do with core.
--
-- THE SNAPSHOT is a sorted list of lines, compared without order, see test/drygate-rename.lua.
--   log and print     every log line and everything printed.
--   call              every call into hs, with its arguments, a table written as its sorted
--                     plain contents four levels down.
--   atom              every call into a shared atom under Olm.lib or a host module, and into
--                     an object one of them built, with its arguments written the same way.
--                     A decision core makes at compose time and keeps inside a constructed
--                     object, a panel's delay or its content, reaches the snapshot here.
--   probe             every content strategy core handed to an atom or a host, a table with a
--                     draw, asked its state and preferred size and drawn once at a fixed size
--                     after the root finishes, so a closure core built per context answers
--                     here what it would answer on screen.
--   load              every file loaded.
--   report, record    the wiring report, and a walk of what Olm:start recorded, of the shared
--   lib, registry     atoms and of the registry, with no depth limit, a table already on the
--                     path written as a cycle, and array positions written as [] so two runs
--                     that built the same list in a different order agree.
-- A plugin's own module table is left out, since what a plugin keeps inside itself is the
-- plugin's own business and only what core did with it is in question. Not seen, a closure
-- core builds that is not a content strategy and that nothing calls while the root composes,
-- a key handler, a timer callback or a chooser's own callbacks, which run only once a person
-- acts.

-- THE KEYMAP MODE, used by the key inventory rather than by the rename proof. With the
-- environment variable DRYGATE_KEYMAP set to 1, the run stops after the root finishes and
-- writes the keymap the root built in the format of test/keys.golden, which is the offline
-- proof that the read model holds every chord the live engines do. DRYGATE_KEYCODES may name a
-- Lua file returning a real Hammerspoon keycode table, dumped from a live session, and the
-- stub then answers it, otherwise a key is only lowercased. Every tool a plugin declares is
-- reported present, so no plugin is left out for a missing program. The snapshot is not written.

local spoonDir, hsRoot, sandbox, mapPath = arg[1], arg[2], arg[3], arg[4]
local keycodesPath = os.getenv("DRYGATE_KEYCODES")
local realKeycodes = keycodesPath and keycodesPath ~= "" and dofile(keycodesPath) or nil
if not (spoonDir and hsRoot and sandbox) then
  io.stderr:write("usage: lua drygate-composerun.lua <spoon dir> <config dir> <sandbox dir> [rename map]\n")
  os.exit(2)
end
if spoonDir:sub(-1) ~= "/" then spoonDir = spoonDir .. "/" end
if hsRoot:sub(-1) == "/" then hsRoot = hsRoot:sub(1, -2) end

----------------------------------------------------------------------------------------
-- The rename map, original to scrambled, for both directories and identities.
----------------------------------------------------------------------------------------

local scramble = {}
if mapPath and mapPath ~= "" then
  for line in io.lines(mapPath) do
    local from, to = line:match("^(%S+)%s+(%S+)$")
    if from then scramble[from] = to end
  end
end
local renaming = next(scramble) ~= nil

----------------------------------------------------------------------------------------
-- One listing of both trees, taken before the sandbox closes the shell.
----------------------------------------------------------------------------------------

local kinds = {}
local children = {}
do
  local function list(root)
    for _, kind in ipairs({ "d", "f" }) do
      local p = io.popen('find "' .. root .. '" -mindepth 1 -type ' .. kind .. ' 2>/dev/null')
      for path in p:lines() do
        kinds[path] = kind == "d" and "directory" or "file"
        local parent, base = path:match("^(.*)/([^/]+)$")
        if parent then
          children[parent] = children[parent] or {}
          table.insert(children[parent], base)
        end
      end
      p:close()
    end
  end
  list(spoonDir:sub(1, -2))
  list(hsRoot .. "/config")
  kinds[hsRoot .. "/init.lua"] = "file"
end

local function clean(path)
  path = tostring(path):gsub("/+", "/"):gsub("/%./", "/")
  -- Resolve a parent step, the spoon loads its own siblings through root/../lib.
  local prev
  repeat
    prev = path
    path = path:gsub("/[^/]+/%.%./", "/", 1)
  until path == prev
  if #path > 1 then path = path:gsub("/$", "") end
  return path
end

----------------------------------------------------------------------------------------
-- The sandbox.
----------------------------------------------------------------------------------------

local realOpen, realLines = io.open, io.lines
local function refused() return nil, "refused by the dry gate sandbox" end
os.remove, os.rename = refused, refused
os.execute = function() return nil, "exit", 1 end
os.tmpname = function() error("os.tmpname is refused by the dry gate sandbox") end
io.popen = refused
package.loadlib = refused
local realOutput, realInput = io.output, io.input
io.output = function(file)
  if file ~= nil then error("io.output with an argument is refused by the dry gate sandbox") end
  return realOutput()
end
io.input = function(file)
  if file ~= nil then error("io.input with an argument is refused by the dry gate sandbox") end
  return realInput()
end
local spoonPrefix, configPrefix = clean(spoonDir), clean(hsRoot)
local function readable(path)
  local p = clean(path)
  local inside = p:sub(1, #spoonPrefix + 1) == spoonPrefix .. "/" or p:sub(1, #configPrefix + 1) == configPrefix .. "/"
  return inside and not p:match("%.json$")
end
io.open = function(path, mode)
  mode = mode or "r"
  if not mode:match("^r") or mode:find("+", 1, true) then return refused() end
  if not readable(path) then return refused() end
  return realOpen(path, mode)
end
io.lines = function(path, ...)
  if path == nil then return realLines() end
  if not readable(path) then error("io.lines on " .. tostring(path) .. " is refused by the dry gate sandbox") end
  return realLines(path, ...)
end

----------------------------------------------------------------------------------------
-- The stub.
----------------------------------------------------------------------------------------

local lines = {}
local function add(line) lines[#lines + 1] = line end

-- What a value is, as text that two runs agree on. A string, a number and a boolean are
-- themselves, a function is fn, a stand in is stub, a shared atom, a host module or an object
-- one of them built is atom, and so is any table inside one, since its contents are walked
-- once elsewhere and its state, a cache filled in call order, is not a decision. A table is its plain
-- contents ARG_DEPTH levels down, keys sorted and array items sorted, since order is not compared.
local opaque = setmetatable({}, { __mode = "k" })
local walked = setmetatable({}, { __mode = "k" })
local function deepText(v, depth, onPath)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  if t == "function" then return "fn" end
  if t ~= "table" then return t end
  local mt = getmetatable(v)
  if mt and mt.__tostring and tostring(v) == "<stub>" then return "stub" end
  if opaque[v] or walked[v] then return "atom" end
  if onPath[v] then return "cycle" end
  if depth <= 0 then return "table" end
  onPath[v] = true
  local items = {}
  for k, child in pairs(v) do
    local value = deepText(child, depth - 1, onPath)
    if math.type(k) == "integer" then
      items[#items + 1] = value
    else
      items[#items + 1] = (type(k) == "string" and k or "[" .. deepText(k, 0, onPath) .. "]") .. "=" .. value
    end
  end
  onPath[v] = nil
  table.sort(items)
  return "{" .. table.concat(items, ",") .. "}"
end
local ARG_DEPTH = 4
local function argsText(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = deepText((select(i, ...)), ARG_DEPTH, {}) end
  return table.concat(parts, ", ")
end
local recording = false
local function stub(path)
  return setmetatable({}, {
    __index = function(_, key)
      if type(key) == "number" then return nil end
      return stub(path .. "." .. tostring(key))
    end,
    __call = function(_, ...)
      if recording then add("call " .. path .. "(" .. argsText(...) .. ")") end
      return stub(path .. "()")
    end,
    __tostring = function() return "<stub>" end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __unm = function() return 0 end,
    __idiv = function() return 0 end, __pow = function() return 0 end,
    __lt = function() return false end, __le = function() return false end,
    __len = function() return 0 end,
  })
end
local function isStub(v)
  local mt = type(v) == "table" and getmetatable(v)
  return mt and mt.__tostring and tostring(v) == "<stub>"
end

-- A real answer that still records its call, the way a stand in does, so a core that asks or
-- writes one setting, one file or one command for one plugin's name shows it.
local function recorded(path, fn)
  return function(...)
    if recording then add("call " .. path .. "(" .. argsText(...) .. ")") end
    return fn(...)
  end
end

hs = stub("hs")
spoon = {}
hs.configdir = hsRoot
if realKeycodes then hs.keycodes = { map = realKeycodes } end
local fs = stub("hs.fs")
fs.dir = recorded("hs.fs.dir", function(path)
  local names = children[clean(path)]
  if not names then return nil end
  local all = { ".", ".." }
  for _, n in ipairs(names) do all[#all + 1] = n end
  local i = 0
  return function() i = i + 1 return all[i] end, {}
end)
fs.attributes = recorded("hs.fs.attributes", function(path, field)
  local mode = kinds[clean(path)]
  if not mode then return nil end
  if field == nil then return { mode = mode } end
  if field == "mode" then return mode end
  return nil
end)
hs.fs = fs
local function none() return nil end
hs.settings = { get = recorded("hs.settings.get", none), set = recorded("hs.settings.set", none),
  clear = recorded("hs.settings.clear", none) }
-- Text measures a fixed width per character, so the kit can lay a probe out to the end. A
-- scrambled name keeps its length, so it measures the same.
local drawing = stub("hs.drawing")
drawing.getTextDrawingSize = function(str, style)
  local size = type(style) == "table" and tonumber(style.size) or 13
  return { w = math.ceil((utf8.len(tostring(str)) or #tostring(str)) * size * 0.6), h = math.ceil(size * 1.2) }
end
hs.drawing = drawing
local styledtext = stub("hs.styledtext")
styledtext.fontInfo = function(font)
  local size = type(font) == "table" and tonumber(font.size) or 13
  return { ascender = size * 0.8, descender = -size * 0.2, capHeight = size * 0.7 }
end
hs.styledtext = styledtext
hs.execute = recorded("hs.execute", function() return "", true, "exit", 0 end)
-- The keymap mode answers the dependency door's one probe as if every tool were installed, the
-- way they are on the machine the golden was taken on. Otherwise a plugin whose required tool
-- is absent here is left out of the plan, and its keys with it, which says nothing about the
-- read model. The probe is one command v call naming every locator, so each name is answered.
if os.getenv("DRYGATE_KEYMAP") == "1" then
  hs.execute = function(command)
    local out = {}
    for name in tostring(command):gmatch("%S+") do
      if name ~= "command" and name ~= "-v" then out[#out + 1] = "/usr/bin/" .. name end
    end
    return table.concat(out, "\n") .. "\n", true, "exit", 0
  end
end
hs.json = { read = recorded("hs.json.read", none), write = recorded("hs.json.write", function() return false end),
  decode = recorded("hs.json.decode", none), encode = recorded("hs.json.encode", function() return "{}" end) }
local function logger(name)
  local l = {}
  local function record(level)
    return function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
      add("log " .. tostring(name) .. " " .. level .. " " .. table.concat(parts, " "))
    end
  end
  for _, level in ipairs({ "e", "w", "i", "d", "v", "f", "ef", "wf", "df", "vf", "inf" }) do
    l[level] = record(level)
  end
  l.setLogLevel = function() end
  l.getLogLevel = function() return 3 end
  l.level = 3
  return setmetatable(l, { __index = function() return function() end end })
end
hs.logger = { new = logger, defaultLogLevel = "info" }
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  add("print " .. table.concat(parts, " "))
end

package.path = hsRoot .. "/?.lua;" .. hsRoot .. "/?/init.lua;" .. package.path
package.preload["hs.ipc"] = function() return stub("hs.ipc") end

----------------------------------------------------------------------------------------
-- The atoms and the hosts, recorded at every call.
--
-- Every function on a shared atom under Olm.lib and on a host module is swapped for one that
-- records its path and its arguments and then calls through, and so is every method of an
-- object one of them builds, found through the object's metatable. A function seen twice gets
-- the same wrapper, so two fields holding one function still compare equal. A content strategy
-- handed over in an argument, a table with a draw, is kept for the probe after the root.
----------------------------------------------------------------------------------------

local wrapperOf = setmetatable({}, { __mode = "k" })
local probes, probeSeen = {}, {}
local instrument

local function noteProbes(path, ...)
  for i = 1, select("#", ...) do
    local a = select(i, ...)
    if type(a) == "table" and not opaque[a] then
      local candidates = { a }
      for _, v in pairs(a) do candidates[#candidates + 1] = v end
      for _, c in ipairs(candidates) do
        if type(c) == "table" and not probeSeen[c] and rawget(c, "draw") ~= nil and type(c.draw) == "function" then
          probeSeen[c] = true
          probes[#probes + 1] = { path = path, strategy = c }
        end
      end
    end
  end
end

local function wrap(fn, path)
  if wrapperOf[fn] then return wrapperOf[fn] end
  local w = function(...)
    if recording then
      add("atom " .. path .. "(" .. argsText(...) .. ")")
      noteProbes(path, ...)
    end
    local results = table.pack(fn(...))
    for i = 1, results.n do
      local r = results[i]
      local mt = type(r) == "table" and getmetatable(r)
      if mt and type(mt.__index) == "table" and not (mt.__tostring and tostring(r) == "<stub>") then
        opaque[r] = true
        instrument(mt.__index, path .. "()", 1)
      end
    end
    return table.unpack(results, 1, results.n)
  end
  wrapperOf[fn] = w
  wrapperOf[w] = w
  return w
end

instrument = function(t, path, depth)
  if type(t) ~= "table" or walked[t] or depth < 0 then return end
  local mt = getmetatable(t)
  if mt and mt.__tostring and tostring(t) == "<stub>" then return end
  walked[t] = true
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  for _, k in ipairs(keys) do
    local v = rawget(t, k)
    local seg = path .. "." .. tostring(k)
    if type(v) == "function" then
      rawset(t, k, wrap(v, seg))
    elseif type(v) == "table" then
      instrument(v, seg, depth - 1)
    end
  end
  if mt and type(mt.__index) == "table" then instrument(mt.__index, path, depth - 1) end
end

-- Every file loaded is recorded, so which plugin files core reached is part of the snapshot and
-- a renamed directory shows up in it the way an identity does.
do
  local realLoadfile, realDofile = loadfile, dofile
  loadfile = function(path, ...)
    add("load " .. clean(path))
    return realLoadfile(path, ...)
  end
  dofile = function(path)
    add("load " .. clean(path))
    local results = table.pack(realDofile(path))
    local host = clean(path):match("/host/([^/]+)/init%.lua$")
    if host and type(results[1]) == "table" then
      opaque[results[1]] = true
      instrument(results[1], "host." .. host, 2)
    end
    return table.unpack(results, 1, results.n)
  end
end

----------------------------------------------------------------------------------------
-- The scrambled identities, handed to core through the manifests it reads.
----------------------------------------------------------------------------------------

if renaming then
  local realLoadfile = loadfile
  local function renameSiblings(t, depth)
    if type(t) ~= "table" or depth > 6 then return end
    if type(t.plugin) == "string" and scramble[t.plugin] then t.plugin = scramble[t.plugin] end
    for _, v in pairs(t) do renameSiblings(v, depth + 1) end
  end
  loadfile = function(path, ...)
    local chunk, err = realLoadfile(path, ...)
    if not chunk or not tostring(path):match("/plugins/[^/]+/manifest%.lua$") then return chunk, err end
    return function(...)
      local m = chunk(...)
      if type(m) == "table" then
        if type(m.name) == "string" and scramble[m.name] then m.name = scramble[m.name] end
        if type(m.surface) == "table" and type(m.surface.context) == "string" and scramble[m.surface.context] then
          m.surface.context = scramble[m.surface.context]
        end
        renameSiblings(m.needs, 0)
      end
      return m
    end
  end
end

----------------------------------------------------------------------------------------
-- The spoon under test, loaded where the person's init.lua asks for one.
----------------------------------------------------------------------------------------

local olm
hs.loadSpoon = function(name)
  local chunk = assert(loadfile(spoonDir .. "init.lua"))
  olm = chunk()
  for atomName, atom in pairs(olm.lib or {}) do
    opaque[atom] = true
    instrument(atom, "lib." .. atomName, 2)
  end
  local start = olm.start
  olm.start = function(self, cfg)
    cfg = cfg or {}
    cfg.policy = cfg.policy or {}
    cfg.policy.storage = { cacheRoot = sandbox .. "/cache", olmRoot = sandbox .. "/data" }
    if renaming and type(cfg.plugins) == "table" then
      local renamed = {}
      for k, v in pairs(cfg.plugins) do renamed[scramble[k] or k] = v end
      cfg.plugins = renamed
    end
    return start(self, cfg)
  end
  spoon[name] = olm
  return olm
end

-- An instruction budget, so a loop waiting on a live answer that never comes fails this run
-- with a line saying so rather than hanging the gate.
local count = 0
debug.sethook(function()
  count = count + 1
  if count > 20000 then
    debug.sethook()
    error("the composition root did not finish under the stub's instruction budget")
  end
end, "", 1000)
recording = true
local ok, err = pcall(dofile, hsRoot .. "/init.lua")
if not ok then add("raised " .. tostring(err)) end

if os.getenv("DRYGATE_KEYMAP") == "1" then
  debug.sethook()
  recording = false
  local record = olm and olm._composed
  local keymap = type(record) == "table" and record.keymap
  if not keymap then
    io.stderr:write("the composition root recorded no keymap\n")
    os.exit(1)
  end
  local project = assert(loadfile(spoonDir .. "test/keys-project.lua"))()
  local keys = dofile(hsRoot .. "/config/keys.lua")
  for _, line in ipairs(lines) do
    if line:match("^log %S+ e ") or line:match("^log %S+ w ") then io.stderr:write(line, "\n") end
  end
  io.stdout:write(table.concat(project.project(keymap.rows, keys.windowLeader), "\n"), "\n")
  os.exit(0)
end

-- The probe. Each content strategy is asked what it would show, at one fixed size, each call
-- on its own so one that raises costs only its own line.
local PROBE_W, PROBE_H = 400, 300
for _, probe in ipairs(probes) do
  local c = probe.strategy
  for _, member in ipairs({ "state", "preferredSize", "draw" }) do
    if type(c[member]) == "function" then
      local answered = table.pack(pcall(c[member], PROBE_W, PROBE_H))
      if answered[1] then
        add("probe " .. probe.path .. " " .. member .. " = " .. deepText(answered[2], 6, {}))
      else
        add("probe " .. probe.path .. " " .. member .. " raised " .. tostring(answered[2]))
      end
    end
  end
end
recording = false
debug.sethook()

-- The wiring check. A snapshot only says two runs agree, so a decision the root makes about one
-- row is asked here directly, through the launcher the root configured, and answered as a line
-- beginning wiring pass or wiring FAIL. test/drygate-rename.lua turns any FAIL line into a
-- finding. It runs after the root has finished and records nothing else.
--
-- The launcher's own Aliases row has no tool behind it, so choosing it must replace the open
-- list with the directory word rather than close the launcher, and the special fallback that a
-- click the accessibility tree could not resolve reaches must open the launcher afresh with that
-- word, since the stage it would seed has already closed.
do
  local function wiring(description, ok) add((ok and "wiring pass " or "wiring FAIL ") .. description) end
  local ran, failure = pcall(function()
    local record = olm and olm._composed
    local identity = record and record.plan and record.plan.identity or {}
    local launcher = record and record.modules and record.modules[identity.launcher or "launcher"]
    if not (launcher and launcher._actions) then
      wiring("the launcher was composed with its actions", false)
      return
    end
    local row = { kind = "special", name = "aliasDirectory" }
    local replace = launcher:_replacementFor(row)
    wiring("intercept answers a callable for the Aliases catalog row, so the list stays open",
      type(replace) == "function")

    local seeded, shown
    launcher.seedQuery = function(_, text) seeded = text return true end
    launcher.show = function(_, text) shown = text end

    if type(replace) == "function" then
      replace()
      wiring("choosing the Aliases row seeds the open field with the directory word",
        type(seeded) == "string" and seeded:match("^%?") ~= nil)
    end
    wiring("a row another plugin owns is never taken for the Aliases row",
      launcher:_replacementFor({ kind = "special", name = "aliasDirectory", owner = "somebody" }) == nil)
    wiring("another special row is left to run", launcher:_replacementFor({ kind = "special", name = "lock" }) == nil)

    local word = seeded
    seeded, shown = nil, nil
    local special = launcher._actions.special or {}
    wiring("the special fallback for the Aliases row exists", type(special.aliasDirectory) == "function")
    if type(special.aliasDirectory) == "function" then
      special.aliasDirectory()
      wiring("the fallback opens the launcher with the same word typed", shown ~= nil and shown == word)
      wiring("the fallback never seeds a field the closed stage no longer shows", seeded == nil)
    end
  end)
  if not ran then add("wiring FAIL the wiring check raised, " .. tostring(failure)) end
end

----------------------------------------------------------------------------------------
-- The snapshot.
----------------------------------------------------------------------------------------

local function scalar(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  if t == "function" then return "fn" end
  if isStub(v) then return "stub" end
  return nil
end

-- No depth limit, a table already on the path is written as a cycle. The line cap only
-- guards against a structure that has grown without bound, and saying so is a line of its own.
local LIMIT = 400000
local capped = false
local function walk(v, path, onPath)
  if #lines > LIMIT then capped = true return end
  local s = scalar(v)
  if s then add(path .. " = " .. s) return end
  if type(v) ~= "table" then add(path .. " = " .. type(v)) return end
  if onPath[v] then add(path .. " = cycle") return end
  onPath[v] = true
  local any = false
  for k, child in pairs(v) do
    any = true
    local seg
    if math.type(k) == "integer" then seg = "[]"
    elseif type(k) == "string" then seg = "." .. k
    else seg = "[" .. (scalar(k) or type(k)) .. "]" end
    walk(child, path .. seg, onPath)
  end
  if not any then add(path .. " = {}") end
  onPath[v] = nil
end

if olm then
  local record = olm._composed
  if type(record) == "table" then
    for k, v in pairs(record) do
      if k == "modules" then
        for name in pairs(v) do add("record.modules." .. tostring(name)) end
      elseif k == "manifests" then
        for name in pairs(v) do add("record.manifests." .. tostring(name)) end
      elseif k ~= "text" then
        walk(v, "record." .. tostring(k), {})
      end
    end
    if type(record.text) == "string" then
      for line in record.text:gmatch("[^\n]+") do add("report " .. line) end
    end
  else
    add("no record")
  end
  for name, atom in pairs(olm.lib or {}) do walk(atom, "lib." .. name, {}) end
  walk(olm.registry, "registry", {})
end
if capped then add("snapshot capped at " .. LIMIT .. " lines") end

-- The run's own paths are not part of what it decided.
for i, line in ipairs(lines) do
  lines[i] = line:gsub(spoonDir:gsub("%p", "%%%0"), "<spoon>/")
end
table.sort(lines)
io.stdout:write(table.concat(lines, "\n"), "\n")
