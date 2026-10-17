-- The one search rule as a scan, docs/PLAN-UNIFIED-SEARCH.md phase four. Every chooser list is
-- searched by lib/chooser/match.lua and ranked by lib/chooser/rank.lua, and no plugin or host
-- matches or ranks rows itself, Milos's decision of 2026-10-17 that search never differs per
-- list. This file finds the three ways a list has opted out before, so a new one is a finding
-- rather than a surprise in a live test.
--
-- WHAT COUNTS, on the code part of a line, a comment never counting.
--
-- 1. A presentation, level or scope declaring `matcher = false`, which stands the shared search
--    down for that field.
-- 2. A call to a matcher or to the rank engine. A call to anything whose name ends in matcher
--    with arguments, a matcher handed to pcall, a strategy called through match or matchers,
--    or rank.apply, rank.score or rank.before. Reading the instance's matcher with no
--    arguments, setMatcher and resolving a matcher by name are not calls of one. rank.apply is
--    allowed in three hosts, see ALLOWED_RANK below, and score and before nowhere outside
--    lib/chooser.
-- 3. A table.sort whose comparator orders by a query, calls a matcher or the engine, or reads a
--    score while the function around the sort reads a query or calls a matcher. A sort by load,
--    by date, by frecency or by a stored query's strength reads no typed query and is not hit.
--    A named comparator is followed to its definition in the same file.
--
-- WHERE. Every file drygate.sh hands over in DRYGATE_SOURCES except lib/chooser, which is the
-- engine, and any test directory, which drives the engine on purpose. drygate.lua applies the
-- path rule through M.applies, so a unit case can scan text directly.
--
-- AN EXEMPTION, the form type-exempt already has. The line, or the comment line directly above
-- it, says search-exempt, a comma, and the reason. A field that is input rather than a search,
-- a confirm, a source narrowing its own external request. An exemption with no reason is a
-- finding, and so is one that marks a line nothing here hits, so a stale exemption cannot
-- outlive the code it excused.
--
-- Pure Lua with no hs, so test/drygate.lua and a unit case both load it.

local M = {}

-- Which hosts may call rank.apply, each ranking rows it does not own on behalf of the list
-- that does. The stage ranks a presentation's rows for its highlight hold, the query scope
-- ranks a scope's rows, and the action panel ranks its own verbs. The providers rank too and
-- sit in lib/chooser. Nothing outside lib/chooser calls rank.score or rank.before since phase
-- four removed the launcher's own ordering, their last caller.
local ALLOWED_RANK = { "host/stage/", "host/queryscope/", "host/actionpanel/" }

--- M.applies(rel) -> whether the rule reads the file at this spoon relative path.
function M.applies(rel)
  if rel:sub(1, 12) == "lib/chooser/" then return false end
  if rel:sub(1, 5) == "test/" or rel:find("/test/", 1, true) then return false end
  return true
end

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

-- The code with every quoted string emptied, so a word inside a message never reads as code.
local function unquoted(code)
  return (code:gsub("\"[^\"]*\"", "\"\""):gsub("'[^']*'", "''"))
end

local function standsDown(c)
  return c:find("%f[%w_]matcher%s*=%s*false%f[^%w_]") ~= nil
end

-- A call of a matcher. The callee's last name ends in matcher or Matcher, its argument list is
-- not empty, and it is not a setter, a resolver or a definition.
local function callsMatcher(c)
  for name, args in c:gmatch("([%w_]*[Mm]atcher)%s*(%b())") do
    local lower = name:lower()
    local verb = lower:sub(1, 3) == "set" or lower:find("^_?resolve") ~= nil
    local defined = c:find("function%s+[%w_%.:]*" .. name .. "%s*%(") ~= nil
    if not verb and not defined and args:find("[^%s()]") then return true end
  end
  if c:find("pcall%s*%(%s*[%w_%.:]*[Mm]atcher%s*,") then return true end
  if c:find("[Mm]atch%s*%.%s*fuzzy%s*%(") or c:find("[Mm]atch%s*%.%s*substring%s*%(")
    or c:find("[Mm]atch%s*%.%s*words%s*%(") then return true end
  if c:find("[Mm]atchers%s*%.%s*[%w_]+%s*%(") or c:find("[Mm]atchers%s*%b[]%s*%(") then return true end
  if c:find("%f[%w_]fuzzy%s*%(") then return true end
  return false
end

-- Which engine function a line reaches, apply, score or before, or nil.
local function rankCall(c)
  for verb in c:gmatch("[%w_]*[Rr]ank%s*%.%s*([%a]+)%f[^%w_]") do
    if verb == "apply" or verb == "score" or verb == "before" then return verb end
  end
  return nil
end

local function rankAllowed(rel, verb)
  if verb ~= "apply" then return false end
  for _, prefix in ipairs(ALLOWED_RANK) do
    if rel:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- Whether a text reads a query, any name holding query, except a field of one of the
-- comparator's own two parameters, which is a stored record's key and not what was typed.
local function readsQuery(text, params)
  for at in text:gmatch("()%f[%w_][%w_]*[Qq]uery") do
    local owner = text:sub(1, at - 1):match("([%w_]+)%s*[%.:]%s*$")
    if not (owner and params[owner]) then return true end
  end
  return false
end

local function readsScore(text)
  return text:find("[Ss]core") ~= nil
end

local function indentOf(line)
  return #(line:match("^(%s*)") or "")
end

-- The comparator text of a table.sort starting at line n, with the call's own text, and the
-- comparator's two parameter names. A named comparator is followed to its definition in the
-- same file.
local function comparatorOf(codes, lines, n)
  local parts, depth, started = {}, 0, false
  local first = codes[n]
  local from = first:find("table%.sort")
  for i = n, math.min(#lines, n + 80) do
    local code = codes[i] or ""
    if i == n then code = code:sub(from) end
    code = unquoted(code)
    parts[#parts + 1] = code
    for ch in code:gmatch("[()]") do
      if ch == "(" then depth = depth + 1; started = true else depth = depth - 1 end
    end
    if started and depth <= 0 then break end
  end
  local call = table.concat(parts, "\n")
  local body = call
  if not call:find("function") then
    local name = call:match("table%.sort%s*(%b())")
    name = name and name:match(",%s*([%w_%.:]+)%s*%)$")
    body = ""
    if name then
      local short = name:match("([%w_]+)$")
      for i, line in ipairs(lines) do
        local code = codes[i]
        if code and (code:find("function%s+" .. short .. "%s*%(") or code:find("%f[%w_]" .. short .. "%s*=%s*function")) then
          local own = indentOf(line)
          local b = {}
          for j = i, math.min(#lines, i + 80) do
            b[#b + 1] = unquoted(codes[j] or "")
            if j > i and indentOf(lines[j]) == own and (codes[j] or ""):match("^%s*end") then break end
          end
          body = table.concat(b, "\n")
          break
        end
      end
    end
  end
  local params = {}
  local a, b = body:match("function%s*[%w_%.:]*%s*%(%s*([%w_]+)%s*,%s*([%w_]+)%s*%)")
  if a then params[a] = true; params[b] = true end
  return body, params
end

-- The function around line n, from the nearest earlier line opening a function less indented
-- than line n, through line n. The whole file above when there is none.
local function enclosingOf(codes, lines, n)
  local own = indentOf(lines[n])
  local start = 1
  for i = n - 1, 1, -1 do
    local code = codes[i]
    if code and code:find("%f[%w_]function%f[^%w_]") and indentOf(lines[i]) < own then
      start = i
      break
    end
  end
  local parts = {}
  for i = start, n do parts[#parts + 1] = unquoted(codes[i] or "") end
  return table.concat(parts, "\n")
end

local function sortsByQuery(codes, lines, n)
  local body, params = comparatorOf(codes, lines, n)
  if readsQuery(body, params) then return true end
  for line in (body .. "\n"):gmatch("(.-)\n") do
    if callsMatcher(line) or rankCall(line) then return true end
  end
  if readsScore(body) then
    local around = enclosingOf(codes, lines, n)
    if readsQuery(around, {}) then return true end
    for line in (around .. "\n"):gmatch("(.-)\n") do
      if callsMatcher(line) or rankCall(line) then return true end
    end
  end
  return false
end

local EXEMPT = "search%-exempt"

-- What the exemption on a line says and which line carries it, nil for none, "" for no reason.
local function exemptionOf(lines, n)
  local function reasonIn(text)
    if not text or not text:find(EXEMPT) then return nil end
    return text:match(EXEMPT .. "%s*,?%s*(.-)%s*$") or ""
  end
  local own = reasonIn(lines[n])
  if own ~= nil then return own, n end
  local above = lines[n - 1]
  if above and above:match("^%s*%-%-") then
    local r = reasonIn(above)
    if r ~= nil then return r, n - 1 end
  end
  return nil
end

--- M.scan(text, rel) -> a list of { line = n, what = "...", exempt = reason or nil, source }
--- one per offending line, a line named once for the first rule it breaks, rel being the spoon
--- relative path, which decides where rank.apply is allowed. An exempt line carries its reason,
--- an exemption with no reason is a finding, and so is a search-exempt that marks no hit.
function M.scan(text, rel)
  rel = rel or ""
  local lines, codes = {}, {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  for n, line in ipairs(lines) do codes[n] = codeOf(line) end
  local out, used = {}, {}
  for n, line in ipairs(lines) do
    local code = codes[n]
    if code then
      local c = unquoted(code)
      local what
      local verb = rankCall(c)
      if standsDown(c) then
        what = "matcher = false, which stands the shared search down"
      elseif callsMatcher(c) then
        what = "a call of a matcher, which matches rows outside the shared search"
      elseif verb and not rankAllowed(rel, verb) then
        what = "a call of rank." .. verb .. ", which ranks rows outside the stage, the providers, the query scope and the action panel"
      elseif c:find("table%.sort%s*%(") and sortsByQuery(codes, lines, n) then
        what = "a sort by a query or a match score, which orders rows outside the shared search"
      end
      if what then
        local reason, at = exemptionOf(lines, n)
        local entry = { line = n, what = what, source = line:match("^%s*(.-)%s*$") }
        if reason == nil then
          -- not exempt, a plain finding
        elseif reason == "" then
          entry.what = entry.what .. ", with a search-exempt that gives no reason"
          used[at] = true
        else
          entry.exempt = reason
          used[at] = true
        end
        out[#out + 1] = entry
      end
    end
  end
  -- A search-exempt that excused nothing this run.
  for n, line in ipairs(lines) do
    local comment = line:match("%-%-(.*)$")
    if comment and comment:find(EXEMPT .. "%s*,") and not used[n] then
      out[#out + 1] = { line = n, what = "a search-exempt that marks no search, remove it",
                        source = line:match("^%s*(.-)%s*$") }
    end
  end
  table.sort(out, function(x, y) return x.line < y.line end)
  return out
end

--- M.scanFile(path, rel) -> the same list for one file, nil when it cannot be read.
function M.scanFile(path, rel)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return M.scan(text, rel)
end

return M
