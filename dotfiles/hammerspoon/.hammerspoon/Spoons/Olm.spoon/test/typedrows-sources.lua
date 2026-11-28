-- The launcher's typed sources loaded in plain Lua, for test/typedrows-record.lua and the replay in
-- test/fixtures.lua. Each is the plugin's own file, given only the few hs calls its rows touch, so
-- what is recorded is what the plugin answers. Convert never runs its tool here: a query that passes
-- its gate answers a pending row first, and that is the answer the gate is about.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local root = here .. "../"

local saved = rawget(_G, "hs")
local stub = {
  logger = { new = function() return setmetatable({}, { __index = function() return function() end end }) end },
  timer = { doAfter = function() return { stop = function() end } end },
  task = { new = function() return nil end },
  printf = function() end,
}

local function load(path)
  _G.hs = stub
  local chunk = assert(loadfile(root .. path))
  local ok, mod = pcall(chunk)
  _G.hs = saved
  assert(ok, mod)
  return mod
end

local arithmetic = load("plugins/arithmetic/init.lua")
arithmetic:init()
arithmetic:configure({})

local convert = load("plugins/convert/init.lua")
convert:init()
convert:configure({ deps = { path = function() return "/qalc" end } })

local windowsize = load("plugins/windowsize/init.lua")
if windowsize.init then windowsize:init() end

local queryscope = load("host/queryscope/init.lua")

local M = {}

--- The calculator's row title for a query, or nil.
function M.sum(q)
  local rows = arithmetic:rows(q)
  return rows[1] and rows[1].title or nil
end

--- Whether convert takes q as a conversion, its gate, the pending row it answers first.
function M.converts(q)
  _G.hs = stub
  local ok, rows = pcall(convert.rows, convert, q)
  _G.hs = saved
  return ok and rows ~= nil and #rows > 0
end

--- Whether a source other than the calculator answers q, the scope over words, convert and window
--- size, and whether q is plain words: no digit and nothing answering.
function M.gate(q, words)
  local byAlias = {}
  for _, w in ipairs(words) do byAlias[w] = { name = w } end
  queryscope._byAlias = byAlias
  local scoped = queryscope:resolve(q) ~= nil
  _G.hs = stub
  local ok, rows = pcall(convert.rows, convert, q)
  _G.hs = saved
  local converts = ok and rows and #rows > 0
  local sized = windowsize:parse(q) ~= nil
  local answers = scoped or converts or sized
  return answers, (not answers) and not q:find("%d")
end

return M
