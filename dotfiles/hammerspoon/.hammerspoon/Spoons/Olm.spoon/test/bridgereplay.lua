-- Replays a bridge transcript, a case of kind bridge.transcript under test/fixtures/bridge, against
-- host/bridge's rpc.lua and serve.lua over the fake launcher the case describes, step 2.2 of
-- docs/PLAN-STANDALONE.md. fixtures.lua runs every such case and test/bridgeserve.lua beside it
-- uses the same writer. Plain Lua, no Hammerspoon.
--
-- M.replay(case) -> a list of problems, empty when every step answered as the case expects.
-- M.encode(value) -> JSON text, an empty table written as an array, as hs.json writes one.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local host = here .. "../host/bridge/"
local json = assert(loadfile(here .. "json.lua"))()
local frame = assert(loadfile(host .. "frame.lua"))()
local rpc = assert(loadfile(host .. "rpc.lua"))()
local serve = assert(loadfile(host .. "serve.lua"))()

local M = { json = json, frame = frame, rpc = rpc, serve = serve }

function M.encode(v)
  local t = type(v)
  if v == nil or v == json.null or (type(v) == "table" and getmetatable(v) ~= nil and tostring(v) == "null") then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if math.type(v) == "integer" or v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  if #v > 0 or next(v) == nil then
    local parts = {}
    for i = 1, #v do parts[i] = M.encode(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = M.encode(k) .. ":" .. M.encode(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

M.JSON = { encode = M.encode, decode = json.decode }

--- M.memoryKey(item), the launcher's recencyKey, the rule host/launcher/init.lua keeps
function M.memoryKey(item)
  if type(item) ~= "table" or item.kind == "calc" or item.kind == "scope" or item.remember == false then return nil end
  if item.kind == "app" then return "app:" .. tostring(item.bundleID) end
  return item.kind .. ":" .. tostring(item.key or item.name)
end

-- json.null, from this module's reader or a caller's own copy of it, fixtures.lua loading one.
local function isNull(v)
  return v == json.null or (type(v) == "table" and getmetatable(v) ~= nil and tostring(v) == "null")
end

-- Whether got holds want, an array element for element, null meaning absent.
local function holds(got, want, path)
  if isNull(want) then return got == nil, path .. " should be absent" end
  if type(want) ~= "table" then
    if got ~= want then return false, path .. " is " .. tostring(got) .. ", wanted " .. tostring(want) end
    return true
  end
  if type(got) ~= "table" then return false, path .. " is " .. tostring(got) .. ", wanted a table" end
  if #want > 0 and #got ~= #want then return false, path .. " has " .. #got .. " entries, wanted " .. #want end
  for k, v in pairs(want) do
    local fine, why = holds(got[k], v, path .. "." .. tostring(k))
    if not fine then return false, why end
  end
  return true
end

function M.replay(case)
  local problems = {}
  local fake = case.launcher or {}
  local claimed, replaces, ran, laters = {}, {}, {}, {}
  for _, word in ipairs(fake.claimed or {}) do claimed[word] = true end
  for _, name in ipairs(fake.replaces or {}) do replaces[name] = true end
  local service = serve.new({ rpc = rpc, clean = frame.clean, version = "test",
    -- The fallback fires only where a step says fallback, so a case can tell hidden from it.
    later = function(_, fn) laters[#laters + 1] = fn end,
    launcher = {
      rows = function(query)
        if claimed[query] then return fake.claimedRows or {}, true end
        return (fake.rows or {})[query] or {}, false
      end,
      memoryKey = M.memoryKey,
      memory = function() return fake.memory or {} end,
      placeholder = function() return fake.placeholder or "" end,
      -- Return on a row, as Launcher:bridgeChoose answers. A row named in replaces is unserved, and
      -- any other hides and leaves its run, recorded in ran by its memory key or its kind.
      choose = function(item, query)
        if replaces[item.name] then return { { unserved = { name = item.name } } } end
        return { { hide = {} } }, function() ran[#ran + 1] = (M.memoryKey(item) or item.kind) .. "@" .. query end
      end,
    },
    icons = function(owner) return (case.icons or {})[owner] end })
  local out, queued = {}, {}
  local session = rpc.new({ json = M.JSON, send = function(t) out[#out + 1] = t end,
    defer = function(fn) queued[#queued + 1] = fn end, methods = service.methods })
  for i, step in ipairs(case.steps or {}) do
    out = {}
    session:receive(M.encode(step.send))
    while #queued > 0 do table.remove(queued, 1)() end
    if step.fallback then
      local fire = laters
      laters = {}
      for _, fn in ipairs(fire) do fn() end
    end
    local name = "step " .. i .. " " .. tostring(step.send.method) .. " " .. tostring(step.send.id or "")
    -- ran expects every run so far, in order, the work Return left waiting once it ran.
    if step.ran ~= nil then
      local fine, why = holds(ran, step.ran, "ran")
      if not fine or #ran ~= #step.ran then
        problems[#problems + 1] = name .. ", " .. tostring(why or ("ran " .. #ran .. " wanted " .. #step.ran))
      end
    end
    if #out ~= #step.expect then
      problems[#problems + 1] = name .. " answered " .. #out .. " message(s), wanted " .. #step.expect
    end
    for j, want in ipairs(step.expect) do
      local got = out[j] and json.decode(out[j])
      local fine, why = holds(got, want, "answer")
      if not fine then problems[#problems + 1] = name .. ", " .. tostring(why) end
    end
  end
  return problems
end

return M
