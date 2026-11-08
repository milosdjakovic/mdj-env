-- Reads the three timings of docs/PLAN-STANDALONE.md, step 1.3f, from `~/.olm/log/timings.jsonl`,
-- which the swift chooser's panel writes in either process while `~/.olm/run/timings` exists,
-- native/Timings.swift in lib/chooser/providers/swift. It prints one row per process and list, the
-- median, the 95th percentile and the worst of each, so Hammerspoon's Lua file search and Olm.app's
-- read side by side. It changes nothing.
--
--   "$OLM_LUA" test/timings.lua [log] [since]
--
-- since is an ISO time, so a trial reads only its own lines.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local json = dofile(here .. "json.lua")

local path = arg[1] or (os.getenv("HOME") .. "/.olm/log/timings.jsonl")
local since = arg[2] or ""

local file = io.open(path, "r")
if not file then
  print("no timings at " .. path)
  os.exit(1)
end

local groups, order = {}, {}
for line in file:lines() do
  local ok, doc = pcall(json.decode, line)
  if ok and type(doc) == "table" and (doc.at or "") >= since then
    local name = (doc.process or "?") .. " | " .. (doc.list or "")
    local g = groups[name]
    if not g then
      g = { opens = 0, echo = {}, rows = {}, settled = {}, stall = {} }
      groups[name] = g
      order[#order + 1] = name
    end
    g.opens = g.opens + 1
    for _, field in ipairs({ "echo", "rows", "settled" }) do
      for _, v in ipairs(doc[field] or {}) do g[field][#g[field] + 1] = v end
    end
    g.stall[#g.stall + 1] = doc.stallMs or 0
  end
end
file:close()

local function stats(list)
  if #list == 0 then return "-" end
  table.sort(list)
  local function at(p) return list[math.max(1, math.ceil(#list * p))] end
  return string.format("%.1f / %.1f / %.1f (%d)", at(0.5), at(0.95), list[#list], #list)
end

print("median / 95th / worst ms (samples)")
for _, name in ipairs(order) do
  local g = groups[name]
  print(string.format("%s, %d opens", name, g.opens))
  print("  echo     " .. stats(g.echo))
  print("  rows     " .. stats(g.rows))
  print("  settled  " .. stats(g.settled))
  print("  stall    " .. stats(g.stall))
end
