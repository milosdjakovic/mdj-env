-- The Lua runner for the language neutral fixtures, step 0.2 of docs/PLAN-STANDALONE.md.
--
-- A fixture is a JSON file under test/fixtures/<area>/, an input and the answer expected for it,
-- written so that a second implementation can read the same file. Olm.app's search is the one
-- that will, through `swift test`, and a behaviour moves into the app only when its fixtures pass
-- there. This runner keeps every fixture true of the Lua code, so the two can never drift apart
-- without one of them failing. The dry gate runs it, with no Hammerspoon and no test lock.
--
-- Every file names its kind at the top, and the kind says how a case is read.
--
--   rank.order     rows, a query and an optional rowLimit, through lib/chooser/rank.lua's
--                  apply with the shared fuzzy matcher of lib/chooser/match.lua. It expects the
--                  titles in order, and with more, what the limit cut.
--   rank.corpus    one list of rows and many queries, each expecting the 1 based places of the
--                  rows shown, in order. A corpus records what the code answered on the day it
--                  was written, rather than a rule, and its file says so.
--   queryassoc     steps over lib/queryassoc.lua, the launcher's learned memory.
--   launcher       the same steps plus the launcher's own, run through host/launcher's supplier
--                  and rank.apply exactly as the stage does.
--   filesearch.parse    a typed query through plugins/filesearch/query.lua's parse, with the
--                  file's own types table, expecting each field named, a field left out unchecked.
--   filesearch.narrows  two typed queries, expecting sameShape and narrows between their parses.
--   calls          calls an existing test made into a module, recorded by fixtures-record.lua,
--                  each replayed and its answer compared, see fixtures-encode.lua for the shape.
--
-- A step is an object whose one name says what it does, see STEPS below. null in a fixture is
-- json.null and means absent, so a lead of null expects no leader.
--
-- Run it.
--   lua test/fixtures.lua            every fixture
--   lua test/fixtures.lua ranking    one area
--   lua test/fixtures.lua --record   write what the Lua answers now into every corpus, see record

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoon = here .. "../"
local json = assert(loadfile(here .. "json.lua"))()
local null = json.null

-- The whole of the application these modules need, the same four fields test/ranking.lua
-- stubs and for the same reasons, see its header.
local defaults, running = {}, {}
hs = {
  settings = {
    get = function(key) return defaults[key] end,
    set = function(key, value) defaults[key] = value end,
  },
  processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
  logger = {
    new = function()
      return setmetatable({}, { __index = function() return function() end end })
    end,
  },
  application = { runningApplications = function() return running end },
}

local fuzzy = assert(loadfile(spoon .. "lib/chooser/match.lua"))().fuzzy
local rank = assert(loadfile(spoon .. "lib/chooser/rank.lua"))()
local Q = assert(loadfile(spoon .. "lib/queryassoc.lua"))()
local Launcher = assert(loadfile(spoon .. "host/launcher/init.lua"))()
local fsquery = assert(loadfile(spoon .. "plugins/filesearch/query.lua"))()
local enc = assert(loadfile(here .. "fixtures-encode.lua"))()
enc.use(json, assert(loadfile(spoon .. "lib/kbd.lua"))())

local SETTINGS_KEY = "fixtures.queryassoc"

-- Plain values for a message, a table as JSON like text.
local function show(v)
  if v == nil or v == null then return "null" end
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  if #v > 0 or next(v) == nil then
    for i = 1, #v do parts[i] = show(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do parts[#parts + 1] = show(tostring(k)) .. ":" .. show(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function same(a, b)
  if a == null then a = nil end
  if b == null then b = nil end
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- A row as a fixture writes it, JSON null fields dropped, so a supplier field is absent.
local function plain(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do if v ~= null then out[k] = plain(v) end end
  return out
end

local function titles(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.title end
  return out
end

--------------------------------------------------------------------------------
-- rank.order and rank.corpus.
--------------------------------------------------------------------------------

local function runOrder(case)
  local rows = {}
  for i, r in ipairs(case.rows) do rows[i] = plain(r) end
  local search = case.rowLimit and { rowLimit = case.rowLimit } or nil
  local got, _, more = rank.apply(rows, case.query, fuzzy, search)
  local problems = {}
  if not same(titles(got), case.expect) then
    problems[#problems + 1] = "wanted " .. show(case.expect) .. ", got " .. show(titles(got))
  end
  if case.more ~= nil and not same(more, case.more) then
    problems[#problems + 1] = "cut wanted " .. show(case.more) .. ", got " .. show(more)
  end
  return problems
end

local function runCorpus(file)
  local rows = {}
  for i, r in ipairs(file.rows) do
    rows[i] = plain(r)
    rows[i]._place = i
  end
  local results = {}
  for _, case in ipairs(file.cases) do
    local got = rank.apply(rows, case.query, fuzzy)
    local places = {}
    for i, row in ipairs(got) do places[i] = row._place end
    local problems = {}
    if not same(places, case.expect) then
      problems[1] = "wanted " .. show(case.expect) .. ", got " .. show(places)
    end
    results[#results + 1] = { name = "query " .. show(case.query), problems = problems }
  end
  return results
end

--------------------------------------------------------------------------------
-- queryassoc and launcher, as steps.
--------------------------------------------------------------------------------

-- One world per case, a fresh store and, for a launcher case, the launcher reset the way
-- test/ranking.lua resets it.
local function newWorld(case, withLauncher)
  defaults, running = {}, {}
  if case.stored ~= nil then defaults[SETTINGS_KEY] = plain(case.stored) end
  local opts = plain(case.options or {})
  opts.settingsKey = SETTINGS_KEY
  local w = { assoc = Q.new(opts), opts = opts }
  if withLauncher then
    local l = Launcher
    l._assoc = w.assoc
    l._page = nil
    l._installedApps = nil
    l._predicates = {}
    l._queryProviders = {}
    l._orderedRowsCache = {}
    l._stage = nil
    w.launcher = l
  end
  return w
end

-- A catalog row as the launcher's _orderedRows holds it, see appRow in test/ranking.lua.
local function catalogRow(r)
  return { title = r.title, subTitle = r.subTitle or "", item = { kind = "app", bundleID = r.bundleID } }
end

local STEPS = {}

function STEPS.note(w, step)
  local q, key = step.note[1], step.note[2]
  for _ = 1, step.times or 1 do w.assoc.note(q, key) end
end

function STEPS.lead(w, step)
  local q, want = step.lead[1], step.lead[2]
  local got = w.assoc.orderFor(q)[1]
  if not same(got, want) then return "lead of " .. show(q) .. " wanted " .. show(want) .. ", got " .. show(got) end
end

function STEPS.order(w, step)
  local q, want = step.order[1], step.order[2]
  local got = w.assoc.orderFor(q)
  if not same(got, want) then return "order of " .. show(q) .. " wanted " .. show(want) .. ", got " .. show(got) end
end

-- prune hands the store the keys still present and a predicate claiming every key that starts
-- with claims, so a key the caller does not claim is left alone.
function STEPS.prune(w, step)
  local present, claims = plain(step.prune.present or {}), step.prune.claims or ""
  w.assoc.prune(present, function(key) return key:sub(1, #claims) == claims end)
end

function STEPS.reload(w)
  w.assoc = Q.new(w.opts)
  if w.launcher then w.launcher._assoc = w.assoc end
end

function STEPS.storedQueriesAtMost(w, step)
  local held = 0
  for _ in pairs(defaults[SETTINGS_KEY] or {}) do held = held + 1 end
  if held > step.storedQueriesAtMost then
    return "stored queries wanted at most " .. step.storedQueriesAtMost .. ", got " .. held
  end
end

local LAUNCHER = {}

function LAUNCHER.catalog(w, step)
  local rows = {}
  for i, r in ipairs(step.catalog) do rows[i] = catalogRow(r) end
  w.launcher._orderedRowsCache = rows
end

-- A query provider, the calculator or a hosted tool. It answers its rows when the query equals
-- when, or starts with prefix, and hosted says whether those rows replace the list.
function LAUNCHER.queryRows(w, step)
  local spec = step.queryRows
  local rows = plain(spec.rows)
  w.launcher._queryProviders = { { rows = function(_, q)
    local hit = (spec.when ~= nil and q == spec.when) or (spec.prefix ~= nil and q:sub(1, #spec.prefix) == spec.prefix)
    if not hit then return {} end
    local copy = {}
    for i, r in ipairs(rows) do copy[i] = plain(r) end
    return copy, spec.hosted == true
  end } }
end

function LAUNCHER.page(w, step)
  w.launcher._page = step.page ~= null and step.page or nil
end

function LAUNCHER.shown(w, step)
  local q, want = step.shown[1], step.shown[2]
  local got = titles(rank.apply(w.launcher:_commandRows(q), q, fuzzy))
  if not same(got, want) then return "shown for " .. show(q) .. " wanted " .. show(want) .. ", got " .. show(got) end
end

-- bonus expects the launcher's memory bonus for a query, every key named, null for none, and
-- nothing beyond the keys named.
function LAUNCHER.bonus(w, step)
  local q, want = step.bonus[1], step.bonus[2]
  local got = w.launcher:_memoryBonus(q)
  if not same(got, want) then return "bonus for " .. show(q) .. " wanted " .. show(want) .. ", got " .. show(got) end
end

-- supplierBonus expects the bonus the supplier hands over on the row at a place.
function LAUNCHER.supplierBonus(w, step)
  local q, at, want = step.supplierBonus[1], step.supplierBonus[2], step.supplierBonus[3]
  local row = w.launcher:_commandRows(q)[at]
  local got = row and row.bonus
  if not same(got, want) then return "supplier bonus at " .. at .. " wanted " .. show(want) .. ", got " .. show(got) end
end

-- pick is choosing a row with the query in the field, which is when the launcher records.
function LAUNCHER.pick(w, step)
  local q, item = step.pick[1], plain(step.pick[2])
  w.launcher._stage = { query = function() return q end }
  w.launcher:_noteAssociation(item)
end

function LAUNCHER.installed(w, step)
  local set = {}
  for _, id in ipairs(step.installed) do set[id] = true end
  w.launcher._installedApps = set
end

function LAUNCHER.running(_, step)
  running = {}
  for i, id in ipairs(step.running) do running[i] = { bundleID = function() return id end } end
end

function LAUNCHER.pruneApps(w)
  w.launcher:_pruneAssociations()
end

local function runSteps(case, withLauncher)
  local w = newWorld(case, withLauncher)
  local problems = {}
  for n, step in ipairs(case.steps) do
    local name = next(step)
    if name == "times" then name = next(step, name) end
    local fn = STEPS[name] or (withLauncher and LAUNCHER[name])
    if not fn then
      problems[#problems + 1] = "step " .. n .. " is not a step this kind knows, " .. show(name)
      break
    end
    local problem = fn(w, step)
    if problem then problems[#problems + 1] = "step " .. n .. ", " .. problem end
  end
  return problems
end

--------------------------------------------------------------------------------
-- Finding and running the files.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- filesearch.parse and filesearch.narrows.
--------------------------------------------------------------------------------

local function runParse(case, file)
  local got = fsquery.parse(case.raw, plain(file.types))
  local problems = {}
  local names = {}
  for k in pairs(case.expect) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do
    if not same(got[k], case.expect[k]) then
      problems[#problems + 1] = k .. " wanted " .. show(case.expect[k]) .. ", got " .. show(got[k])
    end
  end
  return problems
end

local function runNarrows(case, file)
  local types = plain(file.types)
  local a, b = fsquery.parse(case.prev, types), fsquery.parse(case.next, types)
  local problems = {}
  local shape, narrows = fsquery.sameShape(a, b), fsquery.narrows(a, b)
  if shape ~= case.sameShape then problems[#problems + 1] = "sameShape wanted " .. show(case.sameShape) .. ", got " .. show(shape) end
  if narrows ~= case.narrows then problems[#problems + 1] = "narrows wanted " .. show(case.narrows) .. ", got " .. show(narrows) end
  return problems
end

--------------------------------------------------------------------------------
-- calls.
--------------------------------------------------------------------------------

-- A module named on a case, loaded once from the spoon.
local modules = {}
local function moduleAt(path)
  if modules[path] == nil then modules[path] = assert(loadfile(spoon .. path))() end
  return modules[path]
end

local function runCall(case)
  local m = moduleAt(case.module)
  local fn = type(m) == "table" and m[case.fn]
  if type(fn) ~= "function" then return { case.module .. " has no function " .. tostring(case.fn) } end
  local args = table.pack(enc.unpackTree(case.args))
  local returns = table.pack(fn(table.unpack(args, 1, args.n)))
  local got, want = enc.text(enc.encode(returns)), enc.text(case.returns)
  if got == want and case.after ~= nil then
    got, want = enc.text(enc.encode(args)), enc.text(case.after)
  end
  if got ~= want then
    local at = 1
    while at <= #want and got:sub(at, at) == want:sub(at, at) do at = at + 1 end
    local from = math.max(1, at - 60)
    return { "answer differs at character " .. at .. ", wanted ..." .. want:sub(from, at + 60)
      .. "... got ..." .. got:sub(from, at + 60) .. "..." }
  end
  return {}
end

local KINDS = {
  calls = function(case) return runCall(case) end,
  ["filesearch.parse"] = runParse,
  ["filesearch.narrows"] = runNarrows,
  ["rank.order"] = function(case) return runOrder(case) end,
  queryassoc = function(case) return runSteps(case, false) end,
  launcher = function(case) return runSteps(case, true) end,
}

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("a")
  f:close()
  return text
end

local function listFiles(dir)
  local out = {}
  local p = io.popen('find "' .. dir .. '" -type f -name "*.json" | sort')
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end

-- --record writes what the Lua answers now into the expect of every case of every rank.corpus
-- file, in place, one line per case, leaving the rest of the file as it was written. It is for a
-- change to the ranking made on purpose, the way test/goldens.sh --update is, and every changed
-- line is read before it is committed. A rule fixture is never recorded, since its answer is the
-- rule.
local function record(path, file)
  local results = {}
  local rows = {}
  for i, r in ipairs(file.rows) do
    rows[i] = plain(r)
    rows[i]._place = i
  end
  for i, case in ipairs(file.cases) do
    local places = {}
    for j, row in ipairs(rank.apply(rows, case.query, fuzzy)) do places[j] = tostring(row._place) end
    results[i] = "[" .. table.concat(places, ", ") .. "]"
  end
  local out, n = {}, 0
  for line in (readFile(path) .. "\n"):gmatch("(.-)\n") do
    if line:match('^%s*{ "query": .-, "expect": %[[^%]]*%] },?$') then
      n = n + 1
      line = line:gsub('"expect": %[[^%]]*%]', function() return '"expect": ' .. (results[n] or "[]") end)
    end
    out[#out + 1] = line
  end
  if n ~= #file.cases then
    error(path .. " holds " .. #file.cases .. " cases and " .. n .. " one line case(s), so it was not recorded")
  end
  if out[#out] == "" then out[#out] = nil end
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  return n
end

local recording = arg and arg[1] == "--record"
local area = arg and arg[recording and 2 or 1]
local root = here .. "fixtures/" .. (area or "")
local files = listFiles(root)
if #files == 0 then
  print("fixtures, found no fixture under " .. root)
  os.exit(2)
end

local cases, failed = 0, 0
for _, path in ipairs(files) do
  local short = path:sub(#here + 1)
  local ok, file = pcall(json.decode, readFile(path))
  if not ok then
    failed = failed + 1
    print("  FAIL  " .. short .. ", " .. tostring(file))
  elseif file.kind == "rank.corpus" and recording then
    print("  recorded " .. record(path, file) .. " case(s) into " .. short)
  elseif file.kind == "rank.corpus" then
    for _, r in ipairs(runCorpus(file)) do
      cases = cases + 1
      if #r.problems > 0 then
        failed = failed + 1
        print("  FAIL  " .. short .. ", " .. r.name .. ", " .. table.concat(r.problems, "; "))
      end
    end
  elseif KINDS[file.kind] then
    for _, case in ipairs(file.cases or {}) do
      cases = cases + 1
      local okRun, problems = pcall(KINDS[file.kind], case, file)
      if not okRun then problems = { "raised " .. tostring(problems) } end
      if #problems > 0 then
        failed = failed + 1
        print("  FAIL  " .. short .. ", " .. tostring(case.name) .. ", " .. table.concat(problems, "; "))
      end
    end
  else
    failed = failed + 1
    print("  FAIL  " .. short .. ", kind " .. show(file.kind) .. " is not one this runner knows")
  end
end

print(string.format("fixtures, %d case(s) in %d file(s), %d failed", cases, #files, failed))
os.exit(failed == 0 and 0 or 1)
