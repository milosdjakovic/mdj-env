-- How a recorded call is written as JSON and read back, shared by fixtures-record.lua, which writes
-- them, and fixtures.lua, which replays them. Plain JSON carries most of a Lua value, and four tagged
-- objects carry the rest, so a second implementation reading a calls fixture needs only these.
--
--   {"$map": [[key, value], ...]}   a table whose keys are not all strings, the pairs sorted, a key
--                                   that is a number staying a number, a two way keycode table
--   {"$bytes": "hex"}               a string that is not valid UTF-8
--   {"$num": "nan" | "inf" | "-inf"} a number JSON has no word for
--   {"$fn": {"calls": [...]}}       a function handed in, every call it received in order, each
--                                   {"args": [...], "returns": [...]}, or "raises" in place of
--                                   returns for a call that raised, which the replay raises again
--   {"$fn": "opaque"}               a function in an answer, compared only as being a function
--   {"$key": {"name","glyph","kind","symbol"}}  a key of lib/kbd.lua, read back by its name, a
--                                   leader through kbd.leader with its glyph as the word
--   {"$chord": [key, ...]}          a chord of lib/kbd.lua, its keys in order
--   {"$lazy": value}                a table whose __index is a function, its own keys alone, which
--                                   the replay gives an __index that raises, so a call that read
--                                   past its own keys fails rather than passing on a guess
--
-- An argument list or an answer is {"n": count, "values": [...]}, null standing for nil, so a
-- trailing nil is kept. after is the argument list once the call returned, for a module that
-- changes what it is handed in place, its functions opaque. A table whose keys are 1 to n is an array, one whose keys are all strings
-- and none starting with $ is an object, an empty table is []. A table that holds itself raises,
-- and the recorder drops that case.

local M = {}

local json -- set by M.use, the reader json.lua answers, for its null.
local kbd -- set by M.use, lib/kbd.lua, which rebuilds a key or a chord on the way back.

function M.use(reader, keys)
  json = reader
  kbd = keys
end

local function isUTF8(s)
  return utf8.len(s) ~= nil
end

local function isSequence(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do if t[i] == nil then return false end end
  return n > 0
end

local function keyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  if ta == "number" or ta == "string" then return a < b end
  return tostring(a) < tostring(b)
end

-- A table as the module reads it, its own keys over whatever a table __index chain gives it, since
-- a table that inherits, lib/keycodes.lua's keycodes over the system's, is read through the chain.
-- An __index that is a function answers keys nobody can list, so such a table is carried as lazy,
-- its own keys alone, and the replay raises if anything asks it for another, see $lazy above.
local function flatten(v)
  local mt = getmetatable(v)
  if not mt or mt.__index == nil or mt.__object then return v end
  if type(mt.__index) ~= "table" then return v, true end
  local out, chain, depth = {}, {}, 0
  local t = v
  while t do
    depth = depth + 1
    if depth > 16 then error("an __index chain too deep to carry", 0) end
    chain[#chain + 1] = t
    local m = getmetatable(t)
    local up = m and m.__index
    if up ~= nil and type(up) ~= "table" then error("an __index chain ending in a function", 0) end
    t = up
  end
  for i = #chain, 1, -1 do for k, x in pairs(chain[i]) do out[k] = x end end
  return out
end

-- value to tree. onFunction(fn) answers the tree for a function met on the way.
local function tree(v, onFunction, seen)
  local t = type(v)
  if v == nil then return nil end
  if t == "boolean" then return v end
  if t == "number" then
    if v ~= v then return { ["$num"] = "nan" } end
    if v == math.huge then return { ["$num"] = "inf" } end
    if v == -math.huge then return { ["$num"] = "-inf" } end
    return v
  end
  if t == "string" then
    if isUTF8(v) then return v end
    return { ["$bytes"] = (v:gsub(".", function(c) return string.format("%02x", c:byte()) end)) }
  end
  if t == "function" then return onFunction(v) end
  if t ~= "table" then error("cannot carry a " .. t, 0) end
  local mt = getmetatable(v)
  if type(mt) == "table" and mt.__name == "kbd.key" then
    return { ["$key"] = setmetatable({ name = v.name, glyph = v.glyph, kind = v.kind, symbol = v.symbol }, { __object = true }) }
  end
  if type(mt) == "table" and mt.__name == "kbd.chord" then
    local keys = {}
    for i, k in ipairs(v.keys) do keys[i] = tree(k, onFunction, seen) end
    return { ["$chord"] = keys }
  end
  if seen[v] then error("a table that holds itself", 0) end
  seen[v] = true
  local original = v
  local lazy
  v, lazy = flatten(v)
  if lazy then
    local own = {}
    for k, x in pairs(v) do own[k] = x end
    seen[original] = nil
    return { ["$lazy"] = tree(own, onFunction, seen) }
  end
  local out
  if next(v) == nil then
    out = {}
  elseif isSequence(v) then
    out = {}
    for i = 1, #v do out[i] = tree(v[i], onFunction, seen) end
  else
    local plainObject = true
    for k in pairs(v) do
      if type(k) ~= "string" or k:sub(1, 1) == "$" then plainObject = false break end
    end
    if plainObject then
      out = {}
      for k, x in pairs(v) do out[k] = tree(x, onFunction, seen) end
      setmetatable(out, { __object = true })
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, keyOrder)
      local pairsOut = {}
      for i, k in ipairs(keys) do pairsOut[i] = { tree(k, onFunction, seen), tree(v[k], onFunction, seen) } end
      out = { ["$map"] = pairsOut }
    end
  end
  seen[original] = nil
  return out
end

local function packTree(packed, onFunction)
  local values = {}
  for i = 1, packed.n do
    local x = tree(packed[i], onFunction, {})
    values[i] = x == nil and "\0nil" or x
  end
  return { n = packed.n, values = values }
end

local function opaque() return { ["$fn"] = "opaque" } end

--- M.encode(packed) -> tree of a packed list, a function in it opaque.
function M.encode(packed) return packTree(packed, opaque) end

-- A recorder stands in for a function handed to the module. It calls the real one and writes down
-- the call. recorders maps each stand in to its record.
local function recorderFor(fn, recorders)
  local r = { calls = {} }
  local stand = function(...)
    local args = M.encode(table.pack(...))
    local results = table.pack(pcall(fn, ...))
    if not results[1] then
      r.calls[#r.calls + 1] = { args = args, raises = tostring(results[2]) }
      error(results[2], 0)
    end
    local returns = table.pack(table.unpack(results, 2, results.n))
    r.calls[#r.calls + 1] = { args = args, returns = M.encode(returns) }
    return table.unpack(returns, 1, returns.n)
  end
  recorders[stand] = r
  return stand
end

-- Puts a recorder in place of every function inside v, in the tables themselves, and notes each
-- swap so M.restore can put the originals back. The module is called with the real tables, since
-- it may change them in place and the run after it depends on that.
local function swapIn(v, recorders, swaps, seen)
  if type(v) ~= "table" or seen[v] then return end
  seen[v] = true
  local found = {}
  for k, x in pairs(v) do found[#found + 1] = { k, x } end
  for _, kx in ipairs(found) do
    local k, x = kx[1], kx[2]
    if type(x) == "function" then
      local stand = recorderFor(x, recorders)
      rawset(v, k, stand)
      swaps[#swaps + 1] = { t = v, k = k, stand = stand, fn = x }
    else
      swapIn(x, recorders, swaps, seen)
    end
  end
end

--- M.prepare(packed, recorders) -> the packed list to call with, the tree of it before the call,
--- and the swaps to undo. A function argument is replaced in the list, a function inside a table
--- in the table.
function M.prepare(packed, recorders)
  local swaps, seen = {}, {}
  local call = { n = packed.n }
  for i = 1, packed.n do
    local x = packed[i]
    if type(x) == "function" then
      call[i] = recorderFor(x, recorders)
    else
      call[i] = x
      swapIn(x, recorders, swaps, seen)
    end
  end
  local ok, before = pcall(packTree, call, function(fn) return { ["\0stand"] = fn } end)
  if not ok then
    M.restore(swaps)
    error(before, 0)
  end
  return call, before, swaps
end

--- M.restore(swaps) puts every swapped function back where its recorder still stands.
function M.restore(swaps)
  for i = #swaps, 1, -1 do
    local sw = swaps[i]
    if rawget(sw.t, sw.k) == sw.stand then rawset(sw.t, sw.k, sw.fn) end
  end
end

--- M.finish(before, recorders) -> the tree with each recorder replaced by what it was asked.
function M.finish(before, recorders)
  local function fill(t)
    if type(t) ~= "table" then return t end
    if t["\0stand"] then
      local r = recorders[t["\0stand"]]
      return { ["$fn"] = { calls = r and r.calls or {} } }
    end
    local out = {}
    for k, x in pairs(t) do out[k] = fill(x) end
    return setmetatable(out, getmetatable(t))
  end
  return fill(before)
end

-- Canonical text of a tree, sorted keys, so two trees compare as strings.
local function text(t, buf)
  local ty = type(t)
  if t == nil or t == "\0nil" or (json and t == json.null) then buf[#buf + 1] = "null"
  elseif ty == "boolean" then buf[#buf + 1] = t and "true" or "false"
  elseif ty == "number" then
    if math.type(t) == "integer" then buf[#buf + 1] = tostring(t)
    else buf[#buf + 1] = string.format("%.17g", t) end
  elseif ty == "string" then
    buf[#buf + 1] = '"' .. t:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
      return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif ty == "table" then
    local isArray = getmetatable(t) == nil and (next(t) == nil or isSequence(t))
    if t.values ~= nil and t.n ~= nil then isArray = false end
    if isArray then
      buf[#buf + 1] = "["
      for i = 1, #t do
        if i > 1 then buf[#buf + 1] = "," end
        text(t[i], buf)
      end
      buf[#buf + 1] = "]"
    else
      local keys = {}
      for k in pairs(t) do keys[#keys + 1] = k end
      table.sort(keys)
      buf[#buf + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then buf[#buf + 1] = "," end
        text(k, buf)
        buf[#buf + 1] = ":"
        text(t[k], buf)
      end
      buf[#buf + 1] = "}"
    end
  else
    error("cannot write a " .. ty, 0)
  end
  return buf
end

function M.text(t) return table.concat(text(t, {})) end

function M.signature(case)
  return case.module .. "\0" .. case.fn .. "\0" .. M.text(case.args)
end

--- M.document(source, cases) -> the JSON text of a calls fixture, one case per line.
function M.document(source, cases)
  local lines = {
    "{",
    '  "kind": "calls",',
    '  "about": ' .. M.text("Recorded from " .. source:match("[^/]+/[^/]+$") .. " by test/fixtures-record.lua, every call it made into the module named on each case, with the arguments it passed and what the module answered, which that test's own assertions checked. Record it again after a change made on purpose, and read every changed line.") .. ",",
    '  "cases": [',
  }
  for i, c in ipairs(cases) do
    lines[#lines + 1] = "    " .. M.text({ module = c.module, fn = c.fn, args = c.args, returns = c.returns, after = c.after })
      .. (i < #cases and "," or "")
  end
  lines[#lines + 1] = "  ]"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

--------------------------------------------------------------------------------
-- Reading back, for the replay.
--------------------------------------------------------------------------------

local value

-- A stub answering a function's recorded calls, in order where they match, and raising on a
-- question the test never asked.
local function stub(calls)
  local used = {}
  return function(...)
    local asked = M.text(M.encode(table.pack(...)))
    local fallback
    for i, c in ipairs(calls) do
      if M.text(c.args) == asked then
        if not used[i] then
          used[i] = true
          if c.raises then error(c.raises, 0) end
          return M.unpackTree(c.returns)
        end
        fallback = fallback or c
      end
    end
    if fallback then
      if fallback.raises then error(fallback.raises, 0) end
      return M.unpackTree(fallback.returns)
    end
    error("the module asked a dependency something the recording never answered, " .. asked, 0)
  end
end

function value(t)
  if t == nil or (json and t == json.null) then return nil end
  if type(t) ~= "table" then return t end
  if t["$map"] then
    local out = {}
    for _, kv in ipairs(t["$map"]) do out[value(kv[1])] = value(kv[2]) end
    return out
  end
  if t["$bytes"] then return (t["$bytes"]:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
  if t["$num"] then return ({ nan = 0 / 0, inf = math.huge, ["-inf"] = -math.huge })[t["$num"]] end
  if t["$key"] then
    local k = t["$key"]
    if k.kind == "leader" then return kbd.leader(k.name, k.glyph) end
    return kbd.named(k.name)
  end
  if t["$chord"] then
    local keys = {}
    for i, k in ipairs(t["$chord"]) do keys[i] = value(k) end
    return kbd.chord(keys)
  end
  if t["$lazy"] then
    local own = value(t["$lazy"]) or {}
    return setmetatable(own, { __index = function(_, k)
      error("the recording holds no answer for key " .. tostring(k) .. " of a table that answered through a function", 0)
    end })
  end
  if t["$fn"] then
    if type(t["$fn"]) == "table" then return stub(t["$fn"].calls or {}) end
    return function() end
  end
  local out = {}
  for k, x in pairs(t) do out[k] = value(x) end
  return out
end

M.value = value

--- M.unpackTree(tree) -> the values of a packed tree.
function M.unpackTree(t)
  local out = { n = t.n }
  for i = 1, t.n do out[i] = value(t.values[i]) end
  return table.unpack(out, 1, out.n)
end

return M
