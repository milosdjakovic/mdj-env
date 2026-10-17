-- Unit case for the dry gate's search rule, Olm.spoon/test/drygate-search.lua, docs/PLAN-UNIFIED-SEARCH.md
-- phase four. Plain Lua over text, no hs. Each check states one thing the rule must hit or must
-- leave alone, the second half mattering as much, since a sort by load or by date is ordinary
-- code and a gate that flags it would be exempted into noise.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local scanner = dofile(caseDir .. "/../../Spoons/Olm.spoon/test/drygate-search.lua")

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function hits(text, rel)
  local plain, exempt = 0, 0
  local whats = {}
  for _, h in ipairs(scanner.scan(text, rel or "plugins/x/init.lua")) do
    if h.exempt then exempt = exempt + 1 else plain = plain + 1 end
    whats[#whats + 1] = h.line .. " " .. h.what
  end
  return plain, exempt, table.concat(whats, "; ")
end

local p, e, w = hits("local child = {\n  matcher = false,\n}\n")
check("matcher false is a finding", p == 1 and e == 0, w)

p, e, w = hits("local child = {\n  -- search-exempt, the field is a name being typed\n  matcher = false,\n}\n")
check("a search-exempt with a reason on the line above is accepted", p == 0 and e == 1, w)

p, e, w = hits("local child = { matcher = false } -- search-exempt, a confirm\n")
check("a search-exempt on the line itself is accepted", p == 0 and e == 1, w)

p, e, w = hits("local child = {\n  -- search-exempt,\n  matcher = false,\n}\n")
check("a search-exempt with no reason is a finding", p == 1 and w:find("gives no reason") ~= nil, w)

p, e, w = hits("-- search-exempt, nothing here\nlocal x = 1\n")
check("a search-exempt that marks nothing is a finding", p == 1 and w:find("marks no search") ~= nil, w)

p, e, w = hits("-- matcher = false is what this used to say\nlocal s = \"matcher = false\"\n")
check("a comment or a string saying matcher false is not a finding", p == 0, w)

p, e, w = hits("local ok = matcher(query, row.title) ~= nil\n")
check("calling a matcher is a finding", p == 1, w)

p, e, w = hits("local ok, s = pcall(matcher, w, hay)\n")
check("handing a matcher to pcall is a finding", p == 1, w)

p, e, w = hits("local s = match.fuzzy(q, hay)\nlocal t = matchers.substring(q, hay)\n")
check("calling a strategy through match or matchers is a finding", p == 2, w)

p, e, w = hits("local m, s = instance:matcher()\ninstance:setMatcher(m, nil)\nlocal f = self:_resolveMatcher(p.matcher)\n")
check("reading, setting or resolving a matcher is not a finding", p == 0, w)

p, e, w = hits("local out = self._rank.apply(rows, q, m)\n", "host/stage/init.lua")
check("rank.apply in the stage is allowed", p == 0, w)
p, e, w = hits("local out = self._rank.apply(rows, q, m)\n", "host/queryscope/init.lua")
check("rank.apply in the query scope is allowed", p == 0, w)
p, e, w = hits("local out = self._rank.apply(rows, q, m)\n", "host/actionpanel/init.lua")
check("rank.apply in the action panel is allowed", p == 0, w)
p, e, w = hits("local out = rank.apply(rows, q, m)\n", "plugins/x/init.lua")
check("rank.apply in a plugin is a finding", p == 1, w)
p, e, w = hits("local s = rank.score(rows, q, m)\n", "host/stage/init.lua")
check("rank.score is a finding even in the stage", p == 1, w)
p, e, w = hits("table.sort(xs, rank.before)\n", "host/launcher/init.lua")
check("rank.before handed to a sort is a finding", p == 1, w)

p, e, w = hits([[
function M.sortByLoad()
  local score = {}
  table.sort(rows, function(a, b)
    if score[a] ~= score[b] then return score[a] > score[b] end
    return order[a] < order[b]
  end)
end
]])
check("a sort by a load score with no query in sight is not a finding", p == 0, w)

p, e, w = hits([[
local function trim(s, now)
  table.sort(ranked, function(a, b) return a.score > b.score end)
end
]])
check("a sort by a stored frecency score is not a finding", p == 0, w)

p, e, w = hits([[
local function cap()
  table.sort(ranked, function(a, b)
    if a.best ~= b.best then return a.best > b.best end
    return a.query < b.query
  end)
end
]])
check("a sort breaking a tie on a stored record's query field is not a finding", p == 0, w)

p, e, w = hits([[
local function rows(query)
  local scored = {}
  for _, r in ipairs(all) do scored[#scored + 1] = { row = r, score = mine(query, r) } end
  table.sort(scored, function(a, b) return a.score > b.score end)
end
]])
check("a sort by a score inside a function reading the query is a finding", p == 1, w)

p, e, w = hits([[
local function byQuery(a, b)
  return a.title:find(currentQuery) and not b.title:find(currentQuery)
end
local function rows()
  table.sort(all, byQuery)
end
]])
check("a named comparator reading the query is followed and is a finding", p == 1, w)

p, e, w = hits("table.sort(list, function(a, b) return a.at > b.at end)\n")
check("a sort by date is not a finding", p == 0, w)

--------------------------------------------------------------------------------
-- A matcher declared as anything but absent or false, rule 2.
--------------------------------------------------------------------------------

p, e, w = hits("local presentation = {\n  matcher = \"substring\",\n}\n")
check("a strategy name on a presentation is a finding", p == 1 and w:find("other than absent") ~= nil, w)
p, e, w = hits("local scope = { title = \"x\", matcher = match.words }\n")
check("a strategy on a scope is a finding", p == 1, w)
p, e, w = hits("presentation.matcher = myStrategy\n")
check("a strategy assigned to a field is a finding", p == 1, w)
p, e, w = hits("p[\"matcher\"] = \"fuzzy\"\n")
check("a strategy through a quoted index is a finding", p == 1, w)
p, e, w = hits("local child = { [\"matcher\"] = false }\n")
check("a quoted matcher false index counts like matcher false", p == 1 and w:find("stands the shared search down") ~= nil, w)
p, e, w = hits("local child = { matcher = nil }\n")
check("matcher nil is absent and not a finding", p == 0, w)
p, e, w = hits("local needs = {\n  matcher = { source = \"root\", policy = \"optional\" },\n}\n", "host/queryscope/manifest.lua")
check("a matcher dependency request is not a finding", p == 0, w)
p, e, w = hits("local matcher = scope.matcher\nif matcher == nil then matcher = self._matcher end\n", "host/queryscope/init.lua")
check("a local holding a scope's matcher is not a declaration", p == 0, w)
p, e, w = hits("local function f(matcher)\nmatcher = matcher or other\nend\n")
check("a line start assignment to a local named matcher is not a declaration", p == 0, w)
p, e, w = hits("local policy = {\n  matcher = \"fuzzy\",\n}\nlocal o = { matcher = chooserAtom.matchers[policy.matcher] }\n", "root/compose.lua")
check("the root's default and its wiring are not findings", p == 0, w)

--------------------------------------------------------------------------------
-- Aliases and quoted indexes, rules 3 and 4.
--------------------------------------------------------------------------------

p, e, w = hits("local f = opts.matcher\nlocal ok = f(q, hay)\n")
check("a call of a local aliasing opts.matcher is a finding", p == 1 and w:find("^2 ") ~= nil, w)
p, e, w = hits("local m = stage:matcher()\nif m(q, hay) then keep() end\n")
check("a call of a local holding a :matcher() read is a finding", p == 1, w)
p, e, w = hits("local fz = match.fuzzy\nreturn fz(q, row.title)\n")
check("a call of a local aliasing match.fuzzy is a finding", p == 1, w)
p, e, w = hits("local f = opts.matcher\nlocal g = f\nlocal ok, s = pcall(g, q, hay)\n")
check("an alias of an alias handed to pcall is a finding", p == 1, w)
p, e, w = hits("local m = instance:matcher()\ninstance:setMatcher(m, nil)\nlocal out = take(m)\n")
check("passing an aliased matcher as an argument is not a finding", p == 0, w)
p, e, w = hits("local f = opts.matcher\nlocal f = math.max\nlocal n = f(1, 2)\n")
check("a local bound again to something else stops being an alias", p == 0, w)
p, e, w = hits("local ap = rank.apply\nlocal out = ap(rows, q, m)\n")
check("rank.apply reached under another name is a finding twice in a plugin", p == 2, w)
p, e, w = hits("local r = self._rank\nreturn r.apply(rows, q, m)\n")
check("rank.apply through a local holding the rank module is a finding in a plugin", p == 1, w)
p, e, w = hits("local r = self._rank\nreturn r.apply(rows, q, m)\n", "host/stage/init.lua")
check("the same alias in the stage is allowed", p == 0, w)
p, e, w = hits("local out = rank[\"apply\"](rows, q, m)\n")
check("rank.apply through a quoted index is a finding", p == 1, w)
p, e, w = hits("local s = rank['score'](rows, q, m)\n", "host/stage/init.lua")
check("rank.score through a quoted index is a finding even in the stage", p == 1, w)

--------------------------------------------------------------------------------
-- A call split across lines, rule 3.
--------------------------------------------------------------------------------

p, e, w = hits("local s = opts.matcher(\n  q,\n  hay\n)\n")
check("a matcher call with its arguments on later lines is one finding on its first line",
  p == 1 and w:find("^1 ") ~= nil, w)
p, e, w = hits("local f = opts.matcher\nlocal s = f(\n  q, hay)\n")
check("an aliased call split across lines is a finding", p == 1, w)
p, e, w = hits("local m = instance:matcher(\n)\n")
check("a split read with no arguments is not a finding", p == 0, w)

--------------------------------------------------------------------------------
-- A plain self filter, rule 5.
--------------------------------------------------------------------------------

p, e, w = hits("for _, w in ipairs(words) do\n  if not name:find(w:lower(), 1, true) then all = false break end\nend\n")
check("a find of a lowered typed word deciding a row is a finding", p == 1 and w:find("find of the typed text") ~= nil, w)
p, e, w = hits("local function has(low, w)\n  return low:find(w, 1, true) ~= nil\nend\n")
check("a returned find of a typed word is a finding", p == 1, w)
p, e, w = hits("if row.title:lower():find(query, 1, true) then out[#out + 1] = row end\n", "host/x/init.lua")
check("a find of the query on a lowered row field in a host is a finding", p == 1, w)
p, e, w = hits("if string.find(name, parsed.text, 1, true) then keep = true end\n")
check("string.find with a field path through text is a finding", p == 1, w)
p, e, w = hits("local s = name:find(\n  w, 1, true) and 1 or 0\n")
check("a self filter split across lines is a finding", p == 1, w)
p, e, w = hits("if text:find(word, 1, true) == 1 then kind = word end\n")
check("typed text searched for a vocabulary word is a grammar parse, not a finding", p == 0, w)
p, e, w = hits("local s, e2 = text:find(\"^%d+\")\nlocal pos = name:find(w, 1, true)\n")
check("a value parse and a position kept in a local are not findings", p == 0, w)
p, e, w = hits("local hit = aliases[word]\nif hit then return hit end\n")
check("an exact alias lookup is not a finding", p == 0, w)
p, e, w = hits("if name:find(needle, 1, true) then return rule end\n")
check("a find of a pattern with another name is not a finding", p == 0, w)
p, e, w = hits("if not name:find(w, 1, true) then return false end\n", "lib/registrar.lua")
check("a self filter outside plugins and hosts is not read", p == 0, w)

--------------------------------------------------------------------------------
-- Block comments and long strings, never read.
--------------------------------------------------------------------------------

p, e, w = hits("--[[\nmatcher = false\nlocal s = rank.score(rows, q, m)\n]]\nlocal x = 1\n")
check("a block comment is never read", p == 0, w)
p, e, w = hits("local doc = [[\nmatcher = false\nopts.matcher(q, hay)\n]]\n")
check("a long string is never read", p == 0, w)
p, e, w = hits("local doc = [==[ ]] matcher = false ]==]\n")
check("a long string with a level is never read", p == 0, w)
p, e, w = hits("--[==[\n\n]==]\nlocal child = { matcher = false }\n")
check("lines after a block comment keep their numbers", p == 1 and w:find("^4 ") ~= nil, w)

--------------------------------------------------------------------------------
-- One exemption syntax.
--------------------------------------------------------------------------------

p, e, w = hits("local child = {\n  -- search-exempt the field is a name being typed\n  matcher = false,\n}\n")
check("a search-exempt with no comma above is a finding", p == 1 and e == 0 and w:find("missing its comma") ~= nil, w)
p, e, w = hits("local child = { matcher = false } -- search-exempt a confirm\n")
check("a search-exempt with no comma on the line is a finding", p == 1 and e == 0 and w:find("missing its comma") ~= nil, w)
p, e, w = hits("-- search-exempt nothing here\nlocal x = 1\n")
check("a stale search-exempt with no comma is a finding", p == 1 and w:find("marks no search") ~= nil, w)
p, e, w = hits("local s = \"-- search-exempt, inside a string\"\n-- see the search-exempt, rule\nlocal x = 1\n")
check("a marker inside a string or further into prose is not a marker", p == 0, w)
check("the parser reads a marker with a comma",
  scanner.exemption(" search-exempt, input").comma == true and scanner.exemption(" search-exempt, input").reason == "input")
check("the parser reads a commaless marker as one", scanner.exemption(" search-exempt input").comma == false)
check("the parser leaves other comments alone", scanner.exemption(" search-exemptions are listed") == nil)

check("lib/chooser is not read", scanner.applies("lib/chooser/rank.lua") == false)
check("the spoon's test directory is not read", scanner.applies("test/ranking.lua") == false)
check("a plugin's own test directory is not read", scanner.applies("plugins/browsertabs/test/agent.lua") == false)
check("a plugin and a host are read", scanner.applies("plugins/x/init.lua") and scanner.applies("host/launcher/init.lua"))
