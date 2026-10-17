-- The one search rule as a scan, docs/PLAN-UNIFIED-SEARCH.md phase four. Every chooser list is
-- searched by lib/chooser/match.lua and ranked by lib/chooser/rank.lua, and no plugin or host
-- matches, filters or orders rows by the query itself, Milos's decision of 2026-10-17 that search
-- never differs per list. This file finds the shapes a list has opted out with before, so a new
-- one is a finding rather than a surprise in a live test. It is a static scan of one file at a
-- time, so it catches the shapes below and nothing else, and review catches the rest.
--
-- WHAT IS READ. The code of a file with every comment gone, block comments included, every long
-- string emptied, and every short string emptied after an index written as a quoted name is read
-- as a field, so `t["matcher"]` reads as `t.matcher` and `rank["apply"]` as `rank.apply`. A call
-- whose arguments run onto later lines is joined to them first.
--
-- WHAT COUNTS.
--
-- 1. A `matcher = false`, anywhere the scan reads, which stands the shared search down for that
--    field.
-- 2. In a file under plugins/ or host/, a matcher declared as anything but absent, nil or false,
--    a strategy name, a function or a name holding one, on a table field, a field assignment or
--    an index written as a quoted name, since the search is never chosen per list. A table as the
--    value is a dependency request and is not hit. A line starting with `matcher =` counts as a
--    field unless the file declared a local or a parameter of that name earlier.
-- 3. A call of a matcher. A call of anything whose name ends in matcher with arguments, a matcher
--    handed to pcall, a strategy called through match or matchers, a bare fuzzy call, and a call
--    of a local that aliases one of those, a local assigned from a name ending in matcher, from a
--    `:matcher()` read, or from a strategy of match or matchers, followed through further locals
--    in the same file. Reading the instance's matcher with no arguments, setMatcher, resolving a
--    matcher by name and passing one as an argument are not calls of one.
-- 4. A use of rank.apply, rank.score or rank.before, through any name ending in rank, through a
--    local holding the rank module or one of those three, or through an index written as a
--    quoted name. rank.apply is allowed in three hosts, see ALLOWED_RANK below, and score and
--    before nowhere outside lib/chooser.
-- 5. In a file under plugins/ or host/, a plain self filter, a `:find(` or `string.find(` whose
--    pattern is a variable named query, q, text, rest, word or w, a field path through one, or a
--    lowered one, used as a truth value, in an if, a while, after not, and, or or return, or
--    compared, on something that is not itself one of those names. Typed text searched for a
--    word of a vocabulary is a grammar parse and is not hit, and neither is a position kept in a
--    local, which is how a value parse reads.
-- 6. A table.sort whose comparator orders by a query, calls a matcher or the engine, or reads a
--    score while the function around the sort reads a query or calls a matcher. A sort by load,
--    by date, by frecency or by a stored query's strength reads no typed query and is not hit.
--    A named comparator is followed to its definition in the same file.
--
-- WHAT IT CANNOT SEE, so review has to. A comparator or a filter defined in another module and
-- handed in, a precomputed weight or score table built from the query, a matcher or the rank
-- module reached through a table of strategies indexed by a variable, through a function's
-- parameter or through a value returned by a call, a self filter through `:match(`, `:gmatch(`,
-- a loop over bytes or a pattern argument with any other name, a helper that keeps a position
-- from find and tests it later, and a supplier that drops rows by any rule the scan has no
-- pattern for. lib/ui is not in the set drygate.sh hands over at all.
--
-- WHERE. Every file drygate.sh hands over in DRYGATE_SOURCES except lib/chooser, which is the
-- engine, and any test directory, which drives the engine on purpose. drygate.lua applies the
-- path rule through M.applies, so a unit case can scan text directly.
--
-- AN EXEMPTION, one syntax everywhere. A line comment starting with `search-exempt, ` and the
-- reason, on the line or on a comment line directly above it. A field that is input rather than
-- a search, a confirm, a source narrowing its own external request. A search-exempt with no
-- comma or no reason is a finding, and so is one that marks a line nothing here hits, read by
-- the same parser, so a stale exemption cannot outlive the code it excused.
--
-- Pure Lua with no hs, so test/drygate.lua and a unit case both load it.

local M = {}

-- Which hosts may call rank.apply, each ranking rows it does not own on behalf of the list
-- that does. The stage ranks a presentation's rows for its highlight hold, the query scope
-- ranks a scope's rows, and the action panel ranks its own verbs. The providers rank too and
-- sit in lib/chooser. Nothing outside lib/chooser calls rank.score or rank.before since phase
-- four removed the launcher's own ordering, their last caller.
local ALLOWED_RANK = { "host/stage/", "host/queryscope/", "host/actionpanel/" }

-- The names typed text goes by in this tree, for the self filter rule.
local QUERY_NAMES = { query = true, q = true, text = true, rest = true, word = true, w = true }

local RANK_VERBS = { apply = true, score = true, before = true }

--- M.applies(rel) -> whether the rule reads the file at this spoon relative path.
function M.applies(rel)
  if rel:sub(1, 12) == "lib/chooser/" then return false end
  if rel:sub(1, 5) == "test/" or rel:find("/test/", 1, true) then return false end
  return true
end

-- Whether a file is one that builds lists, where a declared strategy and a self filter are read.
-- Outside them, in root and lib, a matcher is wiring, the root's default resolved and handed on.
local function authors(rel)
  return rel:sub(1, 8) == "plugins/" or rel:sub(1, 5) == "host/"
end

-- The text split into lines, the code of each line with every comment gone and every long string
-- replaced by an empty short string, and the line comment each line carries. Short strings are
-- kept whole here, since an index written as a quoted name is read before strings are emptied.
local function lex(text)
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  local codes, comments = {}, {}
  local buf, ln = {}, 1
  local i, n = 1, #text
  local function flush()
    codes[ln] = table.concat(buf)
    buf = {}
    ln = ln + 1
  end
  -- Skips a long bracket body from position at, flushing a line for each newline inside, and
  -- answers the position after its close, or past the end when it never closes.
  local function skipLong(at, eq)
    local _, e = text:find("]" .. eq .. "]", at, true)
    e = e or n
    for _ in text:sub(at, e):gmatch("\n") do flush() end
    return e + 1
  end
  while i <= n do
    local ch = text:sub(i, i)
    if ch == "\n" then
      flush()
      i = i + 1
    elseif ch == "-" and text:sub(i + 1, i + 1) == "-" then
      local eq = text:match("^%[(=*)%[", i + 2)
      if eq then
        i = skipLong(i + 4 + #eq, eq)
      else
        local e = text:find("\n", i, true) or (n + 1)
        comments[ln] = text:sub(i + 2, e - 1)
        i = e
      end
    elseif ch == "[" and text:match("^%[=*%[", i) then
      local eq = text:match("^%[(=*)%[", i)
      buf[#buf + 1] = "\"\""
      i = skipLong(i + 2 + #eq, eq)
    elseif ch == "\"" or ch == "'" then
      local j = i + 1
      while j <= n do
        local c = text:sub(j, j)
        if c == "\\" and text:sub(j + 1, j + 1) ~= "\n" then
          j = j + 2
        elseif c == ch or c == "\n" then
          break
        else
          j = j + 1
        end
      end
      if text:sub(j, j) == ch then
        buf[#buf + 1] = text:sub(i, j)
        i = j + 1
      else
        buf[#buf + 1] = text:sub(i, j - 1) .. ch
        i = j
      end
    else
      buf[#buf + 1] = ch
      i = i + 1
    end
  end
  flush()
  return lines, codes, comments
end

-- The code with an index written as a quoted name read as a field and every short string
-- emptied, so a word inside a message never reads as code.
local function normalized(code)
  code = code:gsub("%[%s*\"([%a_][%w_]*)\"%s*%]", ".%1"):gsub("%[%s*'([%a_][%w_]*)'%s*%]", ".%1")
  local out, i, n = {}, 1, #code
  while i <= n do
    local ch = code:sub(i, i)
    if ch == "\"" or ch == "'" then
      local j = i + 1
      while j <= n and code:sub(j, j) ~= ch do
        if code:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      out[#out + 1] = ch .. ch
      i = j + 1
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end

local function blank(c)
  return c == nil or not c:find("%S")
end

-- The line from n with every later line its open parentheses run onto, so a call split across
-- lines reads as one. The length of line n's own part comes back too, so a rule only reports a
-- call that starts on line n.
local function joinedFrom(cs, n)
  local c = cs[n]
  local depth = 0
  for ch in c:gmatch("[()]") do depth = depth + (ch == "(" and 1 or -1) end
  if depth <= 0 then return c, #c end
  local parts = { c }
  for j = n + 1, math.min(#cs, n + 30) do
    local more = cs[j] or ""
    parts[#parts + 1] = more
    for ch in more:gmatch("[()]") do depth = depth + (ch == "(" and 1 or -1) end
    if depth <= 0 then break end
  end
  return table.concat(parts, "\n"), #c
end

local function standsDown(c)
  return c:find("%f[%w_]matcher%s*=%s*false%f[^%w_]") ~= nil
end

-- Whether a line declares a matcher as anything but absent, nil, false or a table. The key must
-- be a field, after an open brace, a comma or a dot, or at the start of the line when the file
-- has no local of that name.
local function declaresStrategy(c, localMatcher)
  for at, value in c:gmatch("()%f[%w_]matcher%s*=%s*([^=%s][^\n]*)") do
    local before = c:sub(1, at - 1):match("(%S)%s*$")
    local field = before == "{" or before == "," or before == "." or (before == nil and not localMatcher)
    local absent = value:match("^false%f[^%w_]") or value:match("^nil%f[^%w_]") or value:sub(1, 1) == "{"
    if field and not absent then return true end
  end
  return false
end

-- Whether text carries a call, starting within its first limit characters, of anything whose
-- last name ends in matcher, with arguments, that is not a setter, a resolver or a definition.
local function callsMatcherName(text, limit)
  for at, name, args in text:gmatch("()([%w_]*[Mm]atcher)%s*(%b())") do
    if at <= limit then
      local lower = name:lower()
      local verb = lower:sub(1, 3) == "set" or lower:find("^_?resolve") ~= nil
      local defined = text:find("function%s+[%w_%.:]*" .. name .. "%s*%(") ~= nil
      if not verb and not defined and args:find("[^%s()]") then return true end
    end
  end
  return false
end

local function callsMatcher(c, joined, limit)
  if callsMatcherName(joined or c, limit or #c) then return true end
  if c:find("pcall%s*%(%s*[%w_%.:]*[Mm]atcher%s*,") then return true end
  if c:find("[Mm]atch%s*%.%s*fuzzy%s*%(") or c:find("[Mm]atch%s*%.%s*substring%s*%(")
    or c:find("[Mm]atch%s*%.%s*words%s*%(") then return true end
  if c:find("[Mm]atchers%s*%.%s*[%w_]+%s*%(") then return true end
  if c:find("%f[%w_]fuzzy%s*%(") then return true end
  return false
end

-- Which engine function a line reaches, apply, score or before, or nil, through a name ending in
-- rank or through a local holding the rank module.
local function rankCall(c, aliases)
  for verb in c:gmatch("[%w_]*[Rr]ank%s*%.%s*([%a]+)%f[^%w_]") do
    if RANK_VERBS[verb] then return verb end
  end
  for name, kind in pairs(aliases or {}) do
    if kind == "rank" then
      for at, verb in c:gmatch("()%f[%w_]" .. name .. "%s*%.%s*([%a]+)%f[^%w_]") do
        local prev = c:sub(at - 1, at - 1)
        if prev ~= "." and prev ~= ":" and RANK_VERBS[verb] then return verb end
      end
    end
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

-- What a plain name path stands for, a matcher, the rank module, one of its verbs as rank.verb,
-- or nil, the aliases already known followed for a bare name.
local function kindOfPath(path, aliases)
  if path:find("[Mm]atch%.fuzzy$") or path:find("[Mm]atch%.substring$") or path:find("[Mm]atch%.words$")
    or path:find("[Mm]atchers%.[%w_]+$") then return "matcher" end
  local last = path:match("([%w_]+)$") or path
  if last:find("[Mm]atcher$") and not last:lower():find("^set") then return "matcher" end
  local verb = path:match("[Rr]ank%.([%a]+)$")
  if verb and RANK_VERBS[verb] then return "rank." .. verb end
  if last == "rank" or last == "_rank" then return "rank" end
  if not path:find("[%.:]") and aliases[path] then return aliases[path] end
  local head, tail = path:match("^([%a_][%w_]*)%.([%a]+)$")
  if head and aliases[head] == "rank" and RANK_VERBS[tail] then return "rank." .. tail end
  return nil
end

-- What the value of a local assignment aliases, by its operands joined with and or or, each a
-- plain name path or a `:matcher()` read, so `type(m) == "function" and opts.matcher or nil`
-- aliases opts.matcher.
local function aliasOf(rhs, aliases)
  local s = (" " .. rhs .. " "):gsub("%s+and%s+", "\1"):gsub("%s+or%s+", "\1")
  for operand in (s .. "\1"):gmatch("([^\1]*)\1") do
    local o = operand:match("^%s*(.-)%s*$")
    if o:find("^[%a_][%w_%.:]*:%s*matcher%s*%(%s*%)$") then return "matcher" end
    if o:find("^[%a_][%w_%.]*$") then
      local kind = kindOfPath(o, aliases)
      if kind then return kind end
    end
  end
  return nil
end

-- Updates the aliases from a line that binds a local, a local function or a function name, so a
-- name bound again to something else stops counting from that line on.
local function bind(c, aliases)
  local fname = c:match("^%s*local%s+function%s+([%a_][%w_]*)") or c:match("^%s*function%s+([%a_][%w_]*)%s*%(")
  if fname then aliases[fname] = nil end
  local names, rhs = c:match("^%s*local%s+([%a_][%w_%s,]*)=%s*([^=].*)$")
  if not names then return end
  local first = true
  for name in names:gmatch("[%a_][%w_]*") do
    if first then
      aliases[name] = aliasOf(rhs, aliases)
      first = false
    else
      aliases[name] = nil
    end
  end
end

-- Which kind of alias text calls, by name with arguments or through pcall, starting within its
-- first limit characters, "matcher" or "rank.verb", or nil.
local function aliasCall(text, limit, aliases)
  for name, kind in pairs(aliases) do
    if kind ~= "rank" then
      local hit = false
      for at, args in text:gmatch("()%f[%w_]" .. name .. "%s*(%b())") do
        local prev = text:sub(at - 1, at - 1)
        local defined = text:sub(1, at - 1):find("function%s*$") ~= nil
        if at <= limit and prev ~= "." and prev ~= ":" and not defined and args:find("[^%s()]") then
          hit = true
        end
      end
      if text:sub(1, limit):find("pcall%s*%(%s*" .. name .. "%s*,") then hit = true end
      if hit then return kind end
    end
  end
  return nil
end

-- Whether an expression is typed text, a name of QUERY_NAMES or a field path through one,
-- optionally lowered.
local function isQueryExpr(e)
  e = e:match("^%s*(.-)%s*$")
  e = e:gsub("%s*:%s*lower%s*%(%s*%)$", "")
  e = e:match("^string%.lower%s*%((.*)%)$") or e
  e = e:match("^%s*(.-)%s*$")
  if not e:find("^[%a_][%w_%.]*$") then return false end
  for seg in e:gmatch("[%a_][%w_]*") do
    if QUERY_NAMES[seg] then return true end
  end
  return false
end

-- The arguments inside a balanced argument list, split at its top level commas.
local function argsOf(list)
  local inner = list:sub(2, -2)
  local out, depth, start = {}, 0, 1
  for i = 1, #inner do
    local ch = inner:sub(i, i)
    if ch == "(" or ch == "{" or ch == "[" then
      depth = depth + 1
    elseif ch == ")" or ch == "}" or ch == "]" then
      depth = depth - 1
    elseif ch == "," and depth == 0 then
      out[#out + 1] = inner:sub(start, i - 1)
      start = i + 1
    end
  end
  out[#out + 1] = inner:sub(start)
  return out
end

-- The receiver of a method call whose colon sits at position at, a name path or a call on one,
-- read backwards over balanced parentheses, and where it starts.
local function receiverBefore(text, at)
  local i = at - 1
  while i > 0 and text:sub(i, i):match("%s") do i = i - 1 end
  local stop = i
  while i > 0 do
    local ch = text:sub(i, i)
    if ch:match("[%w_%.:]") then
      i = i - 1
    elseif ch == ")" then
      local depth = 0
      while i > 0 do
        local d = text:sub(i, i)
        if d == ")" then depth = depth + 1 elseif d == "(" then depth = depth - 1 end
        i = i - 1
        if depth == 0 then break end
      end
    else
      break
    end
  end
  return text:sub(i + 1, stop), i + 1
end

-- Whether a call spanning from start to stop in text is read as a truth value.
local function truthUse(text, start, stop)
  local pre = text:sub(1, start - 1):match("^(.-)%s*$")
  local post = text:sub(stop + 1):match("^%s*(.*)$")
  for _, word in ipairs({ "if", "elseif", "while", "until", "not", "and", "or", "return" }) do
    if pre:find("%f[%w_]" .. word .. "$") then return true end
  end
  if post:find("^[~=<>]=") or post:find("^then%f[^%w_]") or post:find("^and%f[^%w_]")
    or post:find("^or%f[^%w_]") or post:find("^do%f[^%w_]") then return true end
  return false
end

-- Whether text, from its first limit characters, holds a plain self filter, see rule 5.
local function selfFilters(text, limit)
  for at, list in text:gmatch("():%s*find%s*(%b())") do
    if at <= limit then
      local recv, rstart = receiverBefore(text, at)
      local args = argsOf(list)
      local stop = at + #text:sub(at):match("^:%s*find%s*") + #list - 1
      if recv ~= "" and not isQueryExpr(recv) and args[1] and isQueryExpr(args[1])
        and truthUse(text, rstart, stop) then return true end
    end
  end
  for at, list in text:gmatch("()string%s*%.%s*find%s*(%b())") do
    if at <= limit then
      local args = argsOf(list)
      local stop = at + #text:sub(at):match("^string%s*%.%s*find%s*") + #list - 1
      if args[2] and not isQueryExpr(args[1]) and isQueryExpr(args[2]) and truthUse(text, at, stop) then
        return true
      end
    end
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
local function comparatorOf(cs, lines, n)
  local parts, depth, started = {}, 0, false
  local from = cs[n]:find("table%.sort")
  for i = n, math.min(#lines, n + 80) do
    local code = cs[i] or ""
    if i == n then code = code:sub(from) end
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
        local code = cs[i] or ""
        if code:find("function%s+" .. short .. "%s*%(") or code:find("%f[%w_]" .. short .. "%s*=%s*function") then
          local own = indentOf(line)
          local b = {}
          for j = i, math.min(#lines, i + 80) do
            b[#b + 1] = cs[j] or ""
            if j > i and indentOf(lines[j]) == own and (cs[j] or ""):match("^%s*end") then break end
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
local function enclosingOf(cs, lines, n)
  local own = indentOf(lines[n])
  local start = 1
  for i = n - 1, 1, -1 do
    local code = cs[i] or ""
    if code:find("%f[%w_]function%f[^%w_]") and indentOf(lines[i]) < own then
      start = i
      break
    end
  end
  local parts = {}
  for i = start, n do parts[#parts + 1] = cs[i] or "" end
  return table.concat(parts, "\n")
end

local function engineIn(text, aliases)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if callsMatcher(line) or rankCall(line, aliases) or aliasCall(line, #line, aliases) then return true end
  end
  return false
end

local function sortsByQuery(cs, lines, n, aliases)
  local body, params = comparatorOf(cs, lines, n)
  if readsQuery(body, params) then return true end
  if engineIn(body, aliases) then return true end
  if readsScore(body) then
    local around = enclosingOf(cs, lines, n)
    if readsQuery(around, {}) then return true end
    if engineIn(around, aliases) then return true end
  end
  return false
end

--- M.exemption(comment) -> nil when a line comment is not a search-exempt, else a table with
--- reason, the text after the comma, and comma, whether the comma is there. The scan and the
--- stale check both read a marker through this, so the two never disagree on what one is. A
--- marker starts the comment, so prose naming search-exempt further in is not one.
function M.exemption(comment)
  if not comment then return nil end
  local body = comment:match("^%-*%s*search%-exempt(.*)$")
  if not body then return nil end
  if body ~= "" and not body:match("^[%s,]") then return nil end
  local reason = body:match("^%s*,%s*(.-)%s*$")
  if reason then return { reason = reason, comma = true } end
  return { reason = body:match("^%s*(.-)%s*$"), comma = false }
end

-- The marker excusing line n, on the line or on a comment only line directly above, and the line
-- that carries it.
local function exemptionFor(cs, comments, n)
  local own = M.exemption(comments[n])
  if own then return own, n end
  if n > 1 and blank(cs[n - 1]) then
    local above = M.exemption(comments[n - 1])
    if above then return above, n - 1 end
  end
  return nil
end

--- M.scan(text, rel) -> a list of { line = n, what = "...", exempt = reason or nil, source }
--- one per offending line, a line named once for the first rule it breaks, rel being the spoon
--- relative path, which decides where rank.apply is allowed and whether rules 2 and 5 read the
--- file. An exempt line carries its reason, an exemption with no comma or no reason is a finding,
--- and so is a search-exempt that marks no hit.
function M.scan(text, rel)
  rel = rel or ""
  local lines, codes, comments = lex(text)
  local cs = {}
  for n = 1, #lines do cs[n] = normalized(codes[n] or "") end
  local authoring = authors(rel)
  local out, used = {}, {}
  local aliases = {}
  local localMatcher = false
  for n, line in ipairs(lines) do
    local c = cs[n]
    if not blank(c) then
      local joined, limit = joinedFrom(cs, n)
      local what
      local verb = rankCall(c, aliases)
      local aliased = aliasCall(joined, limit, aliases)
      if aliased and aliased:sub(1, 5) == "rank." then
        verb = verb or aliased:sub(6)
        aliased = nil
      end
      if standsDown(c) then
        what = "matcher = false, which stands the shared search down"
      elseif authoring and declaresStrategy(c, localMatcher) then
        what = "a matcher declared other than absent or false, which picks a search for one list"
      elseif callsMatcher(c, joined, limit) then
        what = "a call of a matcher, which matches rows outside the shared search"
      elseif aliased then
        what = "a call of a local holding a matcher, which matches rows outside the shared search"
      elseif verb and not rankAllowed(rel, verb) then
        what = "a use of rank." .. verb .. ", which ranks rows outside the stage, the providers, the query scope and the action panel"
      elseif authoring and selfFilters(joined, limit) then
        what = "a find of the typed text deciding a row, which filters rows outside the shared search"
      elseif c:find("table%.sort%s*%(") and sortsByQuery(cs, lines, n, aliases) then
        what = "a sort by a query or a match score, which orders rows outside the shared search"
      end
      if what then
        local mark, at = exemptionFor(cs, comments, n)
        local entry = { line = n, what = what, source = line:match("^%s*(.-)%s*$") }
        if mark then used[at] = true end
        if not mark then
          entry.exempt = nil
        elseif not mark.comma then
          entry.what = entry.what .. ", with a search-exempt missing its comma, write search-exempt, then the reason"
        elseif mark.reason == "" then
          entry.what = entry.what .. ", with a search-exempt that gives no reason"
        else
          entry.exempt = mark.reason
        end
        out[#out + 1] = entry
      end
      bind(c, aliases)
      if c:find("^%s*local%s+[%w_%s,]*%f[%w_]matcher%f[^%w_]")
        or c:find("function[%w_%s%.:]*%([^)]*%f[%w_]matcher%f[^%w_]") then
        localMatcher = true
      end
    end
  end
  -- A search-exempt that excused nothing this run, read by the same parser as above.
  for n, line in ipairs(lines) do
    if M.exemption(comments[n]) and not used[n] then
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
