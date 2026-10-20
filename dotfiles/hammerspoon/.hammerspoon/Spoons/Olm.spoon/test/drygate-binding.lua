-- The binding rule as a scan. Olm binds every key, from the keymap, through lib/binder.lua, so a
-- file under plugins/ or host/ that binds one itself is a key the keymap never sees, outside the
-- collision check, the cheat sheets and the hint bar. Four shapes are refused there.
--
--   hs.hotkey.bind   a plain combo bound by the plugin, the shape the app toggler and the
--                    clipboard used before the keymap bound them.
--   hs.hotkey.new    the same combo made and enabled by hand.
--   hs.hotkey.modal  a modal of the plugin's own, hs.hotkey.modal.new and its binds, a leader
--                    in all but name.
--   a bind call      a call of a method or field named bind, the way a leader engine is bound,
--                    engine:bind(...) or engine.bind(...).
--
-- A plugin says what it can run through provides.actions and which keys it would like through
-- defaults.bindings, and Olm binds them, so none of these has a legitimate use under those two
-- directories. Each hit is one finding naming the file and the line. A comment is not code, a
-- line comment or a block comment opened with two dashes and long brackets, so a line that only
-- mentions one there is not a hit.
--
-- What it cannot see. A bind reached through a local alias, local b = hs.hotkey.bind, is seen
-- only at the alias, and a call built from a string is not seen at all. A review reads for those.
--
-- A second rule lives here because it is the same kind of scan. lib/surface.lua builds every
-- list's shared verbs and holds no key since phase 7 of the keymap plan, the keys being Olm's own
-- all layer in lib/keymap.lua and the person's lists section in config/keymap.lua. A key written
-- there again, key = "j" or a number, would be a second place a list key is set, so a key literal
-- in that file is a finding too, M.keyLiterals below.
--
-- Pure Lua with no hs, so test/drygate.lua and a unit case both load it.

local M = {}

-- The code part of a line, with a whole line comment gone and a trailing comment cut off where
-- a double dash sits outside a quoted string. nil for a line that is only a comment or blank.
local function codeOf(line)
  if line:match("^%s*%-%-") or line:match("^%s*$") then return nil end
  local quote
  local i, n = 1, #line
  while i <= n do
    local ch = line:sub(i, i)
    if quote then
      if ch == "\\" then i = i + 1 elseif ch == quote then quote = nil end
    elseif ch == "\"" or ch == "'" then
      quote = ch
    elseif ch == "-" and line:sub(i, i + 1) == "--" then
      return line:sub(1, i - 1)
    end
    i = i + 1
  end
  return line
end

local SHAPES = {
  { pattern = "hs%.hotkey%.modal", what = "makes a modal of its own through hs.hotkey.modal" },
  { pattern = "hs%.hotkey%.bind", what = "binds a plain combo through hs.hotkey.bind" },
  { pattern = "hs%.hotkey%.new", what = "makes a plain combo through hs.hotkey.new" },
  { pattern = "[:.]bind%s*%(", what = "calls a bind function, the way a leader engine is bound" },
}

--- M.applies(rel) -> boolean. Whether a spoon relative path is one this rule reads.
function M.applies(rel)
  return rel:sub(1, 8) == "plugins/" or rel:sub(1, 5) == "host/"
end

-- The text with every block comment blanked, its newlines kept so line numbers still agree. A
-- block comment opens with two dashes and a long bracket, any number of equals signs between the
-- two square brackets, and closes on the matching bracket. A long bracket inside a string is rare
-- enough in this tree that it is not told apart here.
local function blankBlockComments(text)
  local out, pos = {}, 1
  while true do
    local s, e, eq = text:find("%-%-%[(=*)%[", pos)
    if not s then break end
    out[#out + 1] = text:sub(pos, s - 1)
    local close = "]" .. eq .. "]"
    local cs, ce = text:find(close, e + 1, true)
    local stop = ce or #text
    out[#out + 1] = (text:sub(s, stop):gsub("[^\n]", " "))
    pos = stop + 1
  end
  out[#out + 1] = text:sub(pos)
  return table.concat(out)
end

--- M.scan(text) -> list of { line, what, source }, one per hit, at most one per line.
function M.scan(text)
  text = blankBlockComments(text)
  local hits = {}
  local n = 0
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = codeOf(l)
    if code then
      for _, shape in ipairs(SHAPES) do
        if code:find(shape.pattern) then
          hits[#hits + 1] = { line = n, what = shape.what, source = code:match("^%s*(.-)%s*$") }
          break
        end
      end
    end
  end
  return hits
end

--- M.keyLiteralFiles, the spoon relative files that must hold no key literal.
M.keyLiteralFiles = { ["lib/surface.lua"] = true }

--- M.keyLiterals(text) -> list of { line, what, source }, one per line that writes a key as a
--- literal, a field named key, key = or ["key"] =, whose value holds a quoted string or a bare
--- number at its own level up to the next comma or brace, so a fallback such as close.key or "x"
--- is caught as well as "x" alone. Every quoted string is set aside before the line is read, so
--- key = 'x' inside a log message is text and not a field, and an index such as keys[1] or a call
--- such as pick(2) is not a literal. Comments are not counted.
---
--- What it cannot see. A key reached through a local, local k = "j" and then key = k, and a value
--- that starts on the next line after key =, are both read as no literal. A review reads for those.

-- The line with every quoted string replaced by a marker holding its index, and the strings.
local function maskStrings(code)
  local out, strings = {}, {}
  local i, n = 1, #code
  while i <= n do
    local ch = code:sub(i, i)
    if ch == "\"" or ch == "'" then
      local j, buf = i + 1, {}
      while j <= n and code:sub(j, j) ~= ch do
        if code:sub(j, j) == "\\" then buf[#buf + 1] = code:sub(j, j + 1) j = j + 2
        else buf[#buf + 1] = code:sub(j, j) j = j + 1 end
      end
      strings[#strings + 1] = table.concat(buf)
      out[#out + 1] = "\1" .. #strings .. "\2"
      i = j + 1
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out), strings
end

local function literalValue(value)
  value = value:gsub("%b[]", ""):gsub("%b()", "")
  value = value:match("^[^,}]*") or ""
  return value:find("\1") ~= nil or value:find("%f[%w_.]%d+%f[^%w_.]") ~= nil
end

function M.keyLiterals(text)
  text = blankBlockComments(text)
  local hits = {}
  local n = 0
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = codeOf(l)
    local hit = false
    if code then
      local masked, strings = maskStrings(code)
      for value in masked:gmatch("%f[%w_]key%s*=%f[^=](.*)") do
        if literalValue(value) then hit = true end
      end
      for index, value in masked:gmatch("%[%s*\1(%d+)\2%s*%]%s*=%f[^=](.*)") do
        if strings[tonumber(index)] == "key" and literalValue(value) then hit = true end
      end
    end
    if hit then
      hits[#hits + 1] = { line = n, what = "writes a key as a literal", source = code:match("^%s*(.-)%s*$") }
    end
  end
  return hits
end

--- M.scanFile(path) -> the same answer for one file, and false when it cannot be read.
function M.scanFile(path)
  local f = io.open(path, "r")
  if not f then return false end
  local text = f:read("a")
  f:close()
  return M.scan(text)
end

return M
