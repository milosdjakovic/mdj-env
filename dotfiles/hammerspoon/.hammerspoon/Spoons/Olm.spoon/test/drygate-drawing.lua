-- The icon drawing rule as a scan. Olm draws every row icon, so a plugin that creates a canvas
-- and snapshots it with imageFromCanvas is drawing an icon of its own, the drift the icon
-- engine in lib/icons exists to end. A file that does both, in code and not in a comment, is a
-- finding, one per file.
--
-- A canvas shown on screen, a pane or a preview, never calls imageFromCanvas, so it is not
-- caught. A drawing that is genuinely content, a thumbnail or a colour swatch, or a drawing
-- the engine cannot express, a tinted nerd font glyph, is declared once in
-- test/drygate-accepted.txt with its reason, the gate's one place for an exemption.
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

--- M.scan(text) -> line or nil. The line of the first imageFromCanvas call when the same file
--- also creates a canvas with canvas.new, nil when it does not do both.
function M.scan(text)
  local makesCanvas, snapshotLine = false, nil
  local n = 0
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = codeOf(l)
    if code then
      if code:find("canvas%.new") then makesCanvas = true end
      if not snapshotLine and code:find("imageFromCanvas") then snapshotLine = n end
    end
  end
  if makesCanvas then return snapshotLine end
  return nil
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
