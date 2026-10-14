-- How a tab is shown. A tab is expanded to the next multiple of WIDTH columns, counted in
-- characters, so a tab after three characters adds one space and after four adds four. It lives
-- in its own file because two units need the same answer, the code block that draws a line and
-- the measurer that decides where a line breaks, and a wrap measured with one tab width and a
-- draw with another would count lines the canvas never shows. Plain Lua, no hs.

local M = {}

M.width = 4

--- M.expand(line) -> the line with every tab replaced by spaces, and the same string when it
--- holds none.
function M.expand(line)
  if not line:find("\t", 1, true) then return line end
  local out, col = {}, 0
  for ch in line:gmatch(utf8.charpattern) do
    if ch == "\t" then
      local n = M.width - (col % M.width)
      out[#out + 1] = string.rep(" ", n)
      col = col + n
    else
      out[#out + 1] = ch
      col = col + 1
    end
  end
  return table.concat(out)
end

return M
