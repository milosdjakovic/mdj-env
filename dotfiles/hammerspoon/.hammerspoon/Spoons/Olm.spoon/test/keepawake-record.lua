-- Records test/fixtures/keepawake/rows.json from plugins/caffeinate/rows.lua, step 4.4 of
-- docs/PLAN-STANDALONE.md, the way test/windowplan-record.lua records the window plan. Each case is a
-- field and a session at one moment in UTC, and what the Lua answers is written as its expect, so
-- Olm.app's KeepAwakeGrammar is checked against the very words Hammerspoon's list shows. Rerun
-- after a change to rows.lua made on purpose, and read every changed case before committing it.
--
-- "$OLM_LUA" test/keepawake-record.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local Rows = assert(loadfile(here .. "../plugins/caffeinate/rows.lua"))()

-- Saturday 28 November 2026, 14:20 UTC.
local NOW = 1795875600

local OFF = { active = false }
local cases = {}
local function case(name, query, status)
  local row = Rows.line(query, status or OFF, Rows.utcClock(NOW))
  cases[#cases + 1] = { name = name, query = query, status = status or OFF,
    expect = { title = row.title, subtitle = row.subTitle, icon = row.icon, choice = row.item } }
end

case("empty while off", "")
case("spaces while off", "   ")
case("empty while held for good", "", { active = true })
case("empty with five minutes left", "", { active = true, expiry = NOW + 300 })
case("empty with thirty seconds left", "", { active = true, expiry = NOW + 30 })
case("empty with fifty nine minutes left", "", { active = true, expiry = NOW + 3599 })
case("empty with two hours left", "", { active = true, expiry = NOW + 7200 })
case("empty ending tomorrow", "", { active = true, expiry = NOW + 12 * 3600 })
case("empty ending in three days", "", { active = true, expiry = NOW + 3 * 86400 })
case("empty past its end", "", { active = true, expiry = NOW - 5 })
for _, q in ipairs({ "18:45", "9:05", "09:05", "14:20", "14:21", "23:59", "0:00", "24:00", "18:60", "18:", "18:4",
  ":30", "1:2", "123:45" }) do
  case("clock " .. q, q)
end
for _, q in ipairs({ "18", "23", "007", "24", "25", "744", "745", "99999999999999999999" }) do
  case("bare " .. q, q)
end
for _, q in ipairs({ "2h", "90m", "120m", "1h30m", "1h 30m", "2h90m", "2h59m", "18h20h", "20m30m", "30m2h", "0h",
  "0m", "0h0m", "744h", "745h", "44640m", "44641m", "999999m", "9h", "10h", "48h", "h", "m", "1hm", "h30m" }) do
  case("span " .. q, q)
end
for _, q in ipairs({ "abc", "2d", "1.5h", "-2h", "18:45x" }) do
  case("wrong " .. q, q)
end
case("a clock while held", "18:45", { active = true })

local function encode(v)
  local t = type(v)
  if t == "boolean" then return tostring(v) end
  if t == "number" then return string.format("%d", v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '": ' .. encode(v[k]) end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local lines = {}
for i, c in ipairs(cases) do
  lines[i] = '    { "name": ' .. encode(c.name) .. ', "query": ' .. encode(c.query) .. ', "status": ' ..
    encode(c.status) .. ',\n      "expect": ' .. encode(c.expect) .. ' }'
end
local out = '{\n  "kind": "keepawake.rows",\n  "about": "The keep awake row for a field and a session at one moment in UTC, recorded from plugins/caffeinate/rows.lua by test/keepawake-record.lua, step 4.4.",\n  "now": ' ..
  NOW .. ',\n  "cases": [\n' .. table.concat(lines, ",\n") .. '\n  ]\n}\n'
os.execute('mkdir -p "' .. here .. 'fixtures/keepawake"')
local f = assert(io.open(here .. "fixtures/keepawake/rows.json", "wb"))
f:write(out)
f:close()
print("keepawake, recorded " .. #cases .. " case(s)")
