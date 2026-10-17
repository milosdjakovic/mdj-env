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

check("lib/chooser is not read", scanner.applies("lib/chooser/rank.lua") == false)
check("the spoon's test directory is not read", scanner.applies("test/ranking.lua") == false)
check("a plugin's own test directory is not read", scanner.applies("plugins/browsertabs/test/agent.lua") == false)
check("a plugin and a host are read", scanner.applies("plugins/x/init.lua") and scanner.applies("host/launcher/init.lua"))
