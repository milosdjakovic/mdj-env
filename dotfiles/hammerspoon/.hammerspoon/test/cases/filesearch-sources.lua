-- Unit case for what FileSearch's sources ask for. The walker asks for the first word in the file
-- name and hands every row it answers to the shared search, aligned with it on 2026-10-17. The
-- index source asks its helper for the typed words, the hidden flag and the recent window, and
-- turns the helper's lines into rows, since 2026-10-30 when it replaced Spotlight and the hidden
-- index. The sources are loaded by path into an environment of their own over a stand in hs that
-- records what each would run, so nothing is searched and the live hs is never touched. The runner
-- reaches this file with a dofile call carrying an absolute path, so it locates itself through
-- debug.getinfo.

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
local tasks = {}
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
  task = { new = function(binary, onExit, onStream, args)
    tasks[#tasks + 1] = { binary = binary, args = args, onExit = onExit, onStream = onStream }
    return { start = noop, terminate = noop }
  end },
}
local env = setmetatable({ hs = fakeHs }, { __index = _G })
env.loadfile = function(path, mode, e) return loadfile(path, mode or "t", e or env) end
local function load(path) return assert(env.loadfile(path))() end

local query = load(fs .. "query.lua")
local walk = load(fs .. "sources/walk.lua")
local index = load(fs .. "sources/index.lua")

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
-- The index
--------------------------------------------------------------------------------

-- The stand in reports every file as modified now, so the helper reads as built and the index as
-- fresh, and every search runs at once rather than waiting on a compile or a crawl.
index.configure({ storage = { cacheDir = function() return "/cache" end }, limits = { recentDays = 7 } })

index.search(query.parse("ab report", {}), { cap = 10, timeoutSeconds = 5 }, noop)
local run = tasks[#tasks]
check("a typed search runs the helper over the index with the cap and every word",
  run.binary == "/cache/fileindex" and table.concat(run.args, " ") == "search /cache/file-index.txt 10 ab report",
  run.binary .. " " .. table.concat(run.args, " "))

index.search(query.parse(". zshrc", {}), { cap = 10, timeoutSeconds = 5 }, noop)
check("a hidden search asks the helper to include hidden paths",
  table.concat(tasks[#tasks].args, " ") == "search /cache/file-index.txt 10 -h zshrc",
  table.concat(tasks[#tasks].args, " "))

local before = os.time() - 7 * 86400
index.search(query.parse("", {}), { cap = 40, timeoutSeconds = 5 }, noop)
local recentArgs = tasks[#tasks].args
check("the recent list asks for the newest files of the recent window",
  recentArgs[1] == "recent" and recentArgs[3] == "40" and tonumber(recentArgs[4]) >= before,
  table.concat(recentArgs, " "))

local status
index.search(query.parse(".", {}), { cap = 10, timeoutSeconds = 5 }, function(_, s) status = s end)
check("a lone dot asks for something to search rather than running the helper",
  status == "type something to search hidden files", status)

local rowsBack
index.search(query.parse("notes", {}), { cap = 10, timeoutSeconds = 5 }, function(rows) rowsBack = rows end)
run = tasks[#tasks]
run.onStream(nil, "1700000000\td\t/home/notes\n1700000001\t\t/home/notes.md\n", "")
runTimers = true
run.onExit(0)
runTimers = false
check("the helper's lines become rows, a folder flagged and the date carried",
  rowsBack and #rowsBack == 2 and rowsBack[1].isDir == true and rowsBack[1].path == "/home/notes"
    and rowsBack[2].isDir ~= true and rowsBack[2].modified == 1700000001,
  rowsBack and #rowsBack)

check("no status while nothing is being built", index.status() == nil, index.status())
