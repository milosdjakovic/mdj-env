-- Unit case for how FileSearch's sources ask for a typed word, aligned with the shared search on
-- 2026-10-17. Spotlight asks a word shorter than the shared search's inside length at a word
-- start, the walker matches the file name rather than the path, and the hidden index asks fzf
-- for whole words with the file name first. The sources are loaded by path into an environment
-- of their own over a stand in hs that records what each would ask Spotlight or run, so nothing
-- is searched and the live hs is never touched. The runner reaches this file with a dofile call
-- carrying an absolute path, so it locates itself through debug.getinfo.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local fs = caseDir .. "/../../Spoons/Olm.spoon/plugins/filesearch/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. tostring(detail))
  else
    print("FAIL " .. description)
  end
end

local noop = function() end
local queries, tasks = {}, {}
local fakeHs = {
  logger = { new = function() return setmetatable({}, { __index = function() return noop end }) end },
  timer = { doAfter = function() return { stop = noop } end },
  fs = {
    attributes = function(_, field) if field == "modification" then return os.time() end return nil end,
    dir = function() error("no listing here") end,
    mkdir = noop,
  },
  spotlight = { new = function()
    local q = setmetatable({}, { __index = function() return noop end })
    q.queryString = function(_, s) queries[#queries + 1] = s end
    q.count = function() return 0 end
    return q
  end },
  task = { new = function(binary, _, _, args)
    tasks[#tasks + 1] = { binary = binary, args = args }
    return { start = noop, terminate = noop }
  end },
}
local env = setmetatable({ hs = fakeHs }, { __index = _G })
env.loadfile = function(path, mode, e) return loadfile(path, mode or "t", e or env) end
local function load(path) return assert(env.loadfile(path))() end

local query = load(fs .. "query.lua")
local spotlight = load(fs .. "sources/spotlight.lua")
local walk = load(fs .. "sources/walk.lua")
local hidden = load(fs .. "sources/hidden.lua")

--------------------------------------------------------------------------------
-- Spotlight
--------------------------------------------------------------------------------

spotlight.configure({ insideFrom = 3 })
spotlight.search(query.parse("ab report", {}), { cap = 10, timeoutSeconds = 5 }, noop)
local pred = queries[#queries] or ""
check("a short word is asked at a word start", pred:find('kMDItemFSName LIKE[cdw] "ab*"', 1, true) ~= nil, pred)
check("a word of the inside length is asked anywhere in the name",
  pred:find('kMDItemFSName LIKE[cd] "*report*"', 1, true) ~= nil, pred)

spotlight.configure({})
spotlight.search(query.parse("ab report", {}), { cap = 10, timeoutSeconds = 5 }, noop)
pred = queries[#queries] or ""
check("without an inside length every word is asked anywhere, as before",
  pred:find('LIKE[cd] "*ab*"', 1, true) ~= nil and not pred:find("cdw", 1, true), pred)

--------------------------------------------------------------------------------
-- The walker
--------------------------------------------------------------------------------

walk.configure({ path = "/bin/fd", prune = {}, insideFrom = 3 })
local got
walk.search(query.parse("dev/ ab", {}), { scopePath = "/home/dev", cap = 10, timeoutSeconds = 5 },
  function(rows) got = rows end)
local args = tasks[#tasks].args
local joined = table.concat(args, " ")
check("a short first word goes to the walker as a word start pattern, case stated inside it",
  joined:find("--case-sensitive", 1, true) ~= nil and joined:find("(?i:ab)", 1, true) ~= nil
    and not joined:find("--fixed-strings", 1, true), joined)

walk.search(query.parse("dev/ report", {}), { scopePath = "/home/dev", cap = 10, timeoutSeconds = 5 }, noop)
joined = table.concat(tasks[#tasks].args, " ")
check("a longer first word is still a fixed string anywhere in the name",
  joined:find("--fixed-strings report", 1, true) ~= nil, joined)

--------------------------------------------------------------------------------
-- The hidden index
--------------------------------------------------------------------------------

hidden.configure({ fdPath = "/bin/fd", fzfPath = "/bin/fzf",
  storage = { cacheDir = function() return "/cache" end } })
hidden.search(query.parse(". zshrc", {}), { cap = 10, timeoutSeconds = 5 }, noop)
local cmd = tasks[#tasks].args and tasks[#tasks].args[2] or ""
check("fzf is asked for whole words, file names first",
  cmd:find("--exact", 1, true) ~= nil and cmd:find("--scheme=path", 1, true) ~= nil, cmd)
