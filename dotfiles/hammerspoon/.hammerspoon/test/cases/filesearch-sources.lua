-- Unit case for how FileSearch's sources ask for a typed word, aligned with the shared search on
-- 2026-10-17. Spotlight asks a word shorter than the shared search's inside length at a word
-- start, the walker asks for the first word in the file name and hands every row it answers to
-- the shared search, Spotlight hands every scope root over the same way, and the hidden index
-- asks fzf for whole words with the file name first. The sources are loaded by path into an environment
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
local queries, tasks, spotCallbacks = {}, {}, {}
-- A timer runs its function at once when a check asks it to, so a walker answer settles inside
-- the call that delivers it. It is switched on only after a search has started, or the search's
-- own timeout would fire first.
local runTimers = false
local fakeHs = {
  logger = { new = function() return setmetatable({}, { __index = function() return noop end }) end },
  timer = { doAfter = function(_, fn)
    if runTimers then fn() end
    return { stop = noop }
  end },
  fs = {
    attributes = function(_, field) if field == "modification" then return os.time() end return nil end,
    dir = function() error("no listing here") end,
    mkdir = noop,
  },
  spotlight = { new = function()
    local q = setmetatable({}, { __index = function() return noop end })
    q.queryString = function(_, s) queries[#queries + 1] = s end
    q.count = function() return 0 end
    q.setCallback = function(_, fn) spotCallbacks[#spotCallbacks + 1] = fn end
    return q
  end },
  task = { new = function(binary, onExit, onStream, args)
    tasks[#tasks + 1] = { binary = binary, args = args, onExit = onExit, onStream = onStream }
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

-- The scope roots are handed over whatever was typed, and the shared search keeps the ones the
-- words match. Here the stand in lists no home folders, so home itself is the one root.
local home = os.getenv("HOME") or ""
local answered
spotlight.search(query.parse("zzqq notthere", {}), { cap = 10, timeoutSeconds = 5 },
  function(rows) answered = rows end)
spotCallbacks[#spotCallbacks](setmetatable({}, { __index = function() return function() return 0 end end }), "didFinish")
check("a scope root is handed over though no typed word is in its name",
  answered and #answered == 1 and answered[1].path == home, answered and #answered)

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

-- The later words are the shared search's to rank, so a typo in one keeps the row the walker
-- answered, notes reprot against notes report.md, and a row naming none of them goes over too.
got = nil
walk.search(query.parse("dev/ notes reprot", {}), { scopePath = "/home/dev", cap = 10, timeoutSeconds = 5 },
  function(rows) got = rows end)
local t = tasks[#tasks]
t.onStream(nil, "/home/dev/notes report.md\n/home/dev/notes/\n/home/dev/old notes.txt\n", "")
runTimers = true
t.onExit(0)
runTimers = false
local paths = {}
for _, r in ipairs(got or {}) do paths[#paths + 1] = r.path end
check("every row the walker answers goes to the shared search, the later words unapplied",
  #paths == 3 and paths[1] == "/home/dev/notes report.md" and paths[2] == "/home/dev/notes"
    and paths[3] == "/home/dev/old notes.txt", table.concat(paths, ", "))

--------------------------------------------------------------------------------
-- The hidden index
--------------------------------------------------------------------------------

hidden.configure({ fdPath = "/bin/fd", fzfPath = "/bin/fzf",
  storage = { cacheDir = function() return "/cache" end } })
hidden.search(query.parse(". zshrc", {}), { cap = 10, timeoutSeconds = 5 }, noop)
local cmd = tasks[#tasks].args and tasks[#tasks].args[2] or ""
check("fzf is asked for whole words, file names first",
  cmd:find("--exact", 1, true) ~= nil and cmd:find("--scheme=path", 1, true) ~= nil, cmd)
