-- Lifts fixtures out of an existing plain Lua test by recording every call it makes into a module,
-- for the 0.3 steps of docs/PLAN-STANDALONE.md. The test runs unchanged, and each top level call
-- into a watched function of a watched module is written down as its arguments, as they were
-- before the call, and what it answered, so the fixture holds exactly the calls the test checks.
-- fixtures.lua replays them as kind calls.
--
-- A function handed in as an argument, a dependency the module asks, is recorded too, every call
-- it received and what it answered, and the replay hands back the same answers, so a module that
-- asks questions is pinned by its dialogue. A value the encoding cannot carry, a userdata or a
-- table that holds itself, drops the case, counted on the last line.
--
-- Run it, one test at a time, from the spoon.
--   lua test/fixtures-record.lua OUT.json TEST.lua MODULE=fn,fn [MODULE=fn ...] [-- TEST ARGS]   * for every function
--   lua test/fixtures-record.lua test/fixtures/keys/remap.json test/keyremap.lua lib/keyremap.lua=allocate

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoon = here .. "../"
local json = assert(loadfile(here .. "json.lua"))()
local enc = assert(loadfile(here .. "fixtures-encode.lua"))()

local out, testPath = arg[1], arg[2]
local watch, testArgs = {}, {}
local split = #arg + 1
for i = 3, #arg do if arg[i] == "--" then split = i break end end
for i = split + 1, #arg do testArgs[#testArgs + 1] = arg[i] end
for i = 3, split - 1 do
  local modulePath, names = arg[i]:match("^([^=]+)=(.+)$")
  local set = {}
  for n in names:gmatch("[^,]+") do set[n] = true end
  watch[modulePath] = set
end

local cases, seen, dropped, depth = {}, {}, 0, 0

local function wrap(modulePath, name, fn)
  return function(...)
    if depth > 0 then return fn(...) end
    local args = table.pack(...)
    local recorders = {}
    local okPrep, call, before, swaps = pcall(enc.prepare, args, recorders)
    if not okPrep then
      dropped = dropped + 1
      io.stderr:write("dropped " .. modulePath .. " " .. name .. ", " .. tostring(call) .. "\n")
      return fn(...)
    end
    -- The arguments as they stand before the call, functions opaque, to tell whether it changed them.
    local okBefore, beforeText = pcall(function() return enc.text(enc.encode(call)) end)
    depth = depth + 1
    local results = table.pack(pcall(fn, table.unpack(call, 1, call.n)))
    depth = depth - 1
    enc.restore(swaps)
    if not results[1] then error(results[2], 0) end
    local returns = { n = results.n - 1 }
    for i = 2, results.n do returns[i - 1] = results[i] end
    local okArgs, argsDoc = pcall(enc.finish, before, recorders)
    local okRet, retDoc = pcall(enc.encode, returns)
    local okAfter, afterDoc = pcall(enc.encode, args)
    if okBefore and okArgs and okRet and okAfter then
      local case = { module = modulePath, fn = name, args = argsDoc, returns = retDoc }
      -- after is kept only when the call changed what it was handed.
      if enc.text(afterDoc) ~= beforeText then case.after = afterDoc end
      local sig = enc.signature(case)
      if not seen[sig] then
        seen[sig] = true
        cases[#cases + 1] = case
      end
    else
      dropped = dropped + 1
      io.stderr:write("dropped " .. modulePath .. " " .. name .. ", "
        .. tostring((not okBefore and beforeText) or (not okArgs and argsDoc) or (not okRet and retDoc) or afterDoc) .. "\n")
    end
    -- The test reads the real answers, given back exactly as the module gave them.
    return table.unpack(returns, 1, returns.n)
  end
end

-- Every loadfile of a watched module answers a chunk whose module has its watched functions
-- wrapped, so the test reaches them through its own loadfile as it always does.
local realLoadfile = loadfile
loadfile = function(path, ...)
  local chunk, err = realLoadfile(path, ...)
  if not chunk then return chunk, err end
  for modulePath, names in pairs(watch) do
    if path:sub(-#modulePath) == modulePath then
      return function(...)
        local m = chunk(...)
        if type(m) == "table" then
          for name, fn in pairs(m) do
            if type(fn) == "function" and (names[name] or names["*"]) then m[name] = wrap(modulePath, name, fn) end
          end
        end
        return m
      end
    end
  end
  return chunk, err
end

-- The output is written with io.open as it was before the test ran, since the dry gate's own run
-- puts a sandbox around io.open.
local realOpen = io.open

-- dofile reaches the same hook, since a test may load its module either way.
dofile = function(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

local function flush()
  local f = assert(realOpen(out, "wb"))
  f:write(enc.document(testPath, cases))
  f:close()
  io.stderr:write(string.format("recorded %d call(s) into %s, %d dropped\n", #cases, out, dropped))
end

local realExit = os.exit
os.exit = function(code, ...)
  flush()
  return realExit(code, ...)
end
arg = { [0] = testPath, table.unpack(testArgs) }
assert(realLoadfile(testPath))()
flush()
