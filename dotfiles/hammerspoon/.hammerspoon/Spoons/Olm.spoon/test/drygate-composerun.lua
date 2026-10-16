-- One run of the composition root under a stub, printed as a snapshot of what it decided.
--
-- test/drygate-rename.lua runs this twice, once over the spoon as it is and once over a copy
-- whose plugins all carry scrambled names, and compares the two snapshots after turning the
-- scrambled names back. Any difference means core behaves differently depending on what a
-- plugin is called, which is the layer rule seen from the outside rather than read from the
-- source, so it catches every route a name can take into core, a field, a table key, a
-- concatenation, a format string or anything computed, and it runs root/compose.lua itself,
-- which no unit case does.
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
-- start, hs.settings, which answers nothing, and a logger that records every line.
--
-- THE SANDBOX. Nothing here may change a file, so os.remove, os.rename, os.execute, io.popen
-- and every io.open other than a read are refused after the listing is taken. A read outside
-- the spoon and the config directory, or of any json file, is refused too, since that is
-- runtime data, and a store keyed by a plugin's name would read differently under a scrambled
-- name for a reason that has nothing to do with core.
--
-- THE SNAPSHOT is a sorted list of lines. Every log line, everything printed, the wiring
-- report, and a walk of what Olm:start recorded and of the shared atoms, with array positions
-- written as [] so two runs that built the same list in a different order agree. A plugin's
-- own module table is left out, since what a plugin keeps inside itself is the plugin's own
-- business and only what core did with it is in question.

local spoonDir, hsRoot, sandbox, mapPath = arg[1], arg[2], arg[3], arg[4]
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

local realOpen = io.open
local function refused() return nil, "refused by the dry gate sandbox" end
os.remove, os.rename = refused, refused
os.execute = function() return nil, "exit", 1 end
io.popen = refused
local spoonPrefix, configPrefix = clean(spoonDir), clean(hsRoot)
io.open = function(path, mode)
  mode = mode or "r"
  if not mode:match("^r") or mode:find("+", 1, true) then return refused() end
  local p = clean(path)
  local inside = p:sub(1, #spoonPrefix + 1) == spoonPrefix .. "/" or p:sub(1, #configPrefix + 1) == configPrefix .. "/"
  if not inside or p:match("%.json$") then return refused() end
  return realOpen(path, mode)
end

----------------------------------------------------------------------------------------
-- The stub.
----------------------------------------------------------------------------------------

local lines = {}
local function add(line) lines[#lines + 1] = line end

-- Every call into the stub is recorded by the path it was reached through and its plain
-- arguments, hs.hotkey.bind with its modifiers and key, hs.settings keys and the rest, so a
-- core that binds, asks or starts something for one name only shows it here. A table or a
-- function argument is written by its type, since its identity differs from run to run.
local function argText(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  return t
end
local recording = false
local function stub(path)
  return setmetatable({}, {
    __index = function(_, key)
      if type(key) == "number" then return nil end
      return stub(path .. "." .. tostring(key))
    end,
    __call = function(_, ...)
      if recording then
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = argText((select(i, ...))) end
        add("call " .. path .. "(" .. table.concat(parts, ", ") .. ")")
      end
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

hs = stub("hs")
spoon = {}
hs.configdir = hsRoot
local fs = stub("hs.fs")
fs.dir = function(path)
  local names = children[clean(path)]
  if not names then return nil end
  local all = { ".", ".." }
  for _, n in ipairs(names) do all[#all + 1] = n end
  local i = 0
  return function() i = i + 1 return all[i] end, {}
end
fs.attributes = function(path, field)
  local mode = kinds[clean(path)]
  if not mode then return nil end
  if field == nil then return { mode = mode } end
  if field == "mode" then return mode end
  return nil
end
hs.fs = fs
hs.settings = { get = function() return nil end, set = function() end }
hs.execute = function() return "", true, "exit", 0 end
hs.json = { read = function() return nil end, write = function() return false end,
  decode = function() return nil end, encode = function() return "{}" end }
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
    return realDofile(path)
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
recording = false
debug.sethook()
if not ok then add("raised " .. tostring(err)) end

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

local LIMIT = 200000
local function walk(v, path, depth, onPath)
  if #lines > LIMIT then return end
  local s = scalar(v)
  if s then add(path .. " = " .. s) return end
  if type(v) ~= "table" then add(path .. " = " .. type(v)) return end
  if onPath[v] then add(path .. " = cycle") return end
  if depth <= 0 then add(path .. " = table") return end
  onPath[v] = true
  local any = false
  for k, child in pairs(v) do
    any = true
    local seg
    if math.type(k) == "integer" then seg = "[]"
    elseif type(k) == "string" then seg = "." .. k
    else seg = "[" .. (scalar(k) or type(k)) .. "]" end
    walk(child, path .. seg, depth - 1, onPath)
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
        walk(v, "record." .. tostring(k), 7, {})
      end
    end
    if type(record.text) == "string" then
      for line in record.text:gmatch("[^\n]+") do add("report " .. line) end
    end
  else
    add("no record")
  end
  for name, atom in pairs(olm.lib or {}) do walk(atom, "lib." .. name, 5, {}) end
  walk(olm.registry, "registry", 6, {})
end

-- The run's own paths are not part of what it decided.
for i, line in ipairs(lines) do
  lines[i] = line:gsub(spoonDir:gsub("%p", "%%%0"), "<spoon>/")
end
table.sort(lines)
io.stdout:write(table.concat(lines, "\n"), "\n")
