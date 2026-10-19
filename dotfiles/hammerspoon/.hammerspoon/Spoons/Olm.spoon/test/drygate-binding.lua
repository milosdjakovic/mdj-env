-- The binding rule as a scan. Olm binds every key, from the keymap, through lib/binder.lua, so a
-- file under plugins/ or host/ that binds one itself is a key the keymap never sees, outside the
-- collision check, the cheat sheets and the hint bar. Three shapes are refused there.
--
--   hs.hotkey.bind   a plain combo bound by the plugin, the shape the app toggler and the
--                    clipboard used before the keymap bound them.
--   hs.hotkey.new    the same combo made and enabled by hand.
--   a bind call      a call of a method or field named bind, the way a leader engine is bound,
--                    engine:bind(...) or engine.bind(...).
--
-- A plugin says what it can run through provides.actions and which keys it would like through
-- defaults.bindings, and Olm binds them, so none of these has a legitimate use under those two
-- directories. Each hit is one finding naming the file and the line. A comment is not code, so a
-- line that only mentions one is not a hit.
--
-- What it cannot see. A bind reached through a local alias, local b = hs.hotkey.bind, is seen
-- only at the alias, and a call built from a string is not seen at all. A review reads for those.
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
  { pattern = "hs%.hotkey%.bind", what = "binds a plain combo through hs.hotkey.bind" },
  { pattern = "hs%.hotkey%.new", what = "makes a plain combo through hs.hotkey.new" },
  { pattern = "[:.]bind%s*%(", what = "calls a bind function, the way a leader engine is bound" },
}

--- M.applies(rel) -> boolean. Whether a spoon relative path is one this rule reads.
function M.applies(rel)
  return rel:sub(1, 8) == "plugins/" or rel:sub(1, 5) == "host/"
end

--- M.scan(text) -> list of { line, what, source }, one per hit, at most one per line.
function M.scan(text)
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

--- M.scanFile(path) -> the same answer for one file, and false when it cannot be read.
function M.scanFile(path)
  local f = io.open(path, "r")
  if not f then return false end
  local text = f:read("a")
  f:close()
  return M.scan(text)
end

return M
