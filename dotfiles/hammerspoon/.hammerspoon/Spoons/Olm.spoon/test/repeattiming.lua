-- The chord engine's repeat timing, fixture 0.3f of docs/PLAN-STANDALONE.md, recorded from
-- lib/chordkey.lua's own driven repeat, _startRepeat, on a virtual clock, for Olm.app's port to
-- answer the same, step 5.3 of docs/DESIGN-APP-KEYS.md. A case is the two beats, how long the key is
-- held and how long the handler takes, and its answer is every run, when it starts and its depth,
-- the press at 0 with depth 0 included.
--
-- It needs no Hammerspoon and no lock. With --record it writes test/fixtures/keys/repeat.json, and
-- without it checks the file still says what the engine does.
--
-- Run it.
--   lua test/repeattiming.lua [--record]

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local FILE = here .. "fixtures/keys/repeat.json"

local run = assert(loadfile(here .. "repeatclock.lua"))().run

local CASES = {
  { name = "a short tap runs once", delay = 0.5, interval = 0.1, hold = 0.2, handler = 0 },
  { name = "a hold past the delay repeats on the interval", delay = 0.5, interval = 0.1, hold = 0.95, handler = 0 },
  { name = "the machine's slowest beats", delay = 2.0, interval = 2.0, hold = 6.5, handler = 0 },
  { name = "a slow handler repeats slower, never in a burst", delay = 0.3, interval = 0.05, hold = 0.8, handler = 0.12 },
  { name = "a handler slower than the delay delays the first repeat by nothing", delay = 0.2, interval = 0.1, hold = 0.6, handler = 0.25 },
}

local function round(x) return math.floor(x * 1000 + 0.5) / 1000 end

local ABOUT = "Recorded from lib/chordkey.lua's driven repeat by test/repeattiming.lua, fixture 0.3f, "
  .. "each run of a hold, its start and its depth. Run by test/repeattiming.lua and by olm-keys-check, "
  .. "the app's port, KeyRepeat. Record it again with --record after a change made on purpose."

local function encode(cases)
  local out = { "{", '  "kind": "keys.repeat",', '  "about": "' .. ABOUT .. '",', '  "cases": [' }
  for i, c in ipairs(cases) do
    local runs = {}
    for _, r in ipairs(c.runs) do runs[#runs + 1] = string.format('{"at":%s,"depth":%d}', round(r.at), r.depth) end
    out[#out + 1] = string.format('    {"name":"%s","delay":%s,"interval":%s,"hold":%s,"handler":%s,"runs":[%s]}%s',
      c.name, c.delay, c.interval, c.hold, c.handler, table.concat(runs, ","), i < #cases and "," or "")
  end
  out[#out + 1] = "  ]"
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

for _, c in ipairs(CASES) do c.runs = run(c) end
local text = encode(CASES)
if arg[1] == "--record" then
  local f = assert(io.open(FILE, "w"))
  f:write(text)
  f:close()
  print("repeattiming, recorded " .. #CASES .. " cases")
  return
end
local f = io.open(FILE, "r")
local held = f and f:read("a") or ""
if f then f:close() end
if held ~= text then
  print("repeattiming, FAILED, test/fixtures/keys/repeat.json no longer says what lib/chordkey.lua does, record it again with --record")
  os.exit(1)
end
print("repeattiming, " .. #CASES .. " cases match the engine")
