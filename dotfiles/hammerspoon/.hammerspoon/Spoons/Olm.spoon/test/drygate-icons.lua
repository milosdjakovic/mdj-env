-- The icon declaration checks as pure functions, one for the literal keys a plugin writes in its
-- Lua and one for the coverage of the sources across every declared icon. Pure Lua with no hs,
-- so test/drygate.lua and the plain unit run in test/icons.lua both load it.
--
-- The literal scan is deliberately small. It reads a string key written as icon = "key" on a
-- code line and nothing else, so a key built at runtime, a table spec or a variable is never
-- seen, and a string that is not a plain identifier is an emoji a person wrote and is skipped.

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

--- M.literalKeys(text) -> list of { line = n, key = "name" }
--- Every icon = "key" on a code line whose key is a plain identifier.
function M.literalKeys(text)
  local out = {}
  local n = 0
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = codeOf(l)
    if code then
      for key in code:gmatch("%f[%w_]icon%s*=%s*\"([^\"]*)\"") do
        if key:match("^[%a_][%w_]*$") then out[#out + 1] = { line = n, key = key } end
      end
    end
  end
  return out
end

--- M.sourceNames(paths) -> sorted list of the icon source names, the file names under
--- lib/icons/sources/ in a list of paths, since a source is a file there and nowhere else.
function M.sourceNames(paths)
  local names = {}
  for _, path in ipairs(paths) do
    local name = path:match("lib/icons/sources/([^/]+)%.lua$")
    if name then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

--- M.coverage(declared, sources) -> report
--- declared is a list of { owner = "plugin", key = "name", spec = { emoji = "x", sf = "y" } },
--- the icons tables of every manifest and an identity icon given as a table. A spec with
--- content = true is a glyph that is content and is left out of every count, content never
--- following the set. report.total is the number counted, report.content the number left out,
--- report.covered[source] how many of those have an entry for it, and report.missing[source]
--- the sorted "owner key" lines of the ones that have none.
function M.coverage(declared, sources)
  local report = { total = 0, content = 0, covered = {}, missing = {} }
  for _, source in ipairs(sources) do
    report.covered[source] = 0
    report.missing[source] = {}
  end
  for _, item in ipairs(declared) do
    if item.spec.content == true then
      report.content = report.content + 1
    else
      report.total = report.total + 1
      for _, source in ipairs(sources) do
        local value = item.spec[source]
        if type(value) == "string" and value ~= "" then
          report.covered[source] = report.covered[source] + 1
        else
          report.missing[source][#report.missing[source] + 1] = item.owner .. " " .. item.key
        end
      end
    end
  end
  for _, source in ipairs(sources) do table.sort(report.missing[source]) end
  return report
end

return M
