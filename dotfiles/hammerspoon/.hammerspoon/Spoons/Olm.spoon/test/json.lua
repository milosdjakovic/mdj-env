-- A JSON reader in plain Lua, for the fixtures, see fixtures.lua beside it. The dry gate runs
-- with no Hammerspoon, so hs.json is not there, and the fixtures are JSON so that Olm.app's own
-- tests read the very same files.
--
-- It reads what RFC 8259 allows and refuses the rest with the byte offset, since a fixture
-- that half parses would pin nothing. An object becomes a table keyed by its names, an array a
-- sequence, and null becomes M.null, a sentinel, so a case can say a value is expected to be
-- absent and a missing field stays nil.
--
-- M.decode(text) -> value, or raises "json: <reason> at <offset>".

local M = {}

M.null = setmetatable({}, { __tostring = function() return "null" end })

local function fail(reason, at)
  error(string.format("json: %s at %d", reason, at), 0)
end

local function skip(s, i)
  return (s:find("[^ \t\r\n]", i)) or (#s + 1)
end

local function utf8char(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then
    return string.char(0xC0 | (code >> 6), 0x80 | (code & 0x3F))
  end
  if code < 0x10000 then
    return string.char(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
  end
  return string.char(0xF0 | (code >> 18), 0x80 | ((code >> 12) & 0x3F),
    0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
end

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local value

local function str(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == "" then fail("unterminated string", i) end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local e = s:sub(j + 1, j + 1)
      if e == "u" then
        local hex = s:sub(j + 2, j + 5)
        if not hex:match("^%x%x%x%x$") then fail("bad unicode escape", j) end
        local code = tonumber(hex, 16)
        j = j + 6
        if code >= 0xD800 and code <= 0xDBFF then
          local low = s:sub(j, j + 5):match("^\\u(%x%x%x%x)$")
          if not low then fail("lone high surrogate", j) end
          code = 0x10000 + ((code - 0xD800) << 10) + (tonumber(low, 16) - 0xDC00)
          j = j + 6
        end
        out[#out + 1] = utf8char(code)
      elseif ESCAPES[e] then
        out[#out + 1] = ESCAPES[e]
        j = j + 2
      else
        fail("bad escape", j)
      end
    elseif c:byte() < 0x20 then
      fail("control character in string", j)
    else
      local k = s:find('["\\%c]', j) or (#s + 1)
      out[#out + 1] = s:sub(j, k - 1)
      j = k
    end
  end
end

local function num(s, i)
  local text = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
  if not text or not text:match("^-?%d") then fail("bad number", i) end
  if text:match("^-?0%d") then fail("leading zero", i) end
  local n = math.tointeger(tonumber(text)) or tonumber(text)
  if n == nil then fail("bad number", i) end
  return n, i + #text
end

function value(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local out = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return out, i + 1 end
    while true do
      if s:sub(i, i) ~= '"' then fail("expected a name", i) end
      local key
      key, i = str(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ":" then fail("expected a colon", i) end
      out[key], i = value(s, i + 1)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "}" then return out, i + 1 end
      if d ~= "," then fail("expected a comma or a brace", i) end
      i = skip(s, i + 1)
    end
  elseif c == "[" then
    local out = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return out, i + 1 end
    while true do
      out[#out + 1], i = value(s, i)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "]" then return out, i + 1 end
      if d ~= "," then fail("expected a comma or a bracket", i) end
      i = i + 1
    end
  elseif c == '"' then
    return str(s, i)
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return M.null, i + 4
  elseif c == "-" or c:match("%d") then
    return num(s, i)
  end
  fail("unexpected " .. (c == "" and "end" or ("'" .. c .. "'")), i)
end

function M.decode(text)
  local v, i = value(text, 1)
  i = skip(text, i)
  if i <= #text then fail("trailing text", i) end
  return v
end

return M
