-- How fast the one search is over long bodies, against the words strategy it replaces there,
-- docs/PLAN-UNIFIED-SEARCH.md phase one. It reports and asserts nothing, since a timing depends
-- on the machine and on what else it is doing, and a threshold here would fail for reasons that
-- have nothing to do with the code. It exists so the number in decisions/olm-unified-search.md
-- can be measured again rather than trusted.
--
-- Run it.
--   lua test/search-timing.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local match = assert(loadfile(here .. "../lib/chooser/match.lua"))()
local clock = os.clock

-- Text built from a fixed word list with a seeded generator, so two runs search the same bodies.
local WORDS = { "The", "quick", "brown", "Fox", "jumps", "over", "lazy", "dog", "function",
  "return", "local", "table", "Insert", "string", "format", "value", "https://example.com/path",
  "config", "Hammerspoon", "chooser" }
local function body(len, seed)
  math.randomseed(seed)
  local parts, n = {}, 0
  while n < len do
    local w = WORDS[math.random(#WORDS)]
    parts[#parts + 1] = w
    n = n + #w + 1
  end
  return table.concat(parts, " "):sub(1, len)
end

local function time(label, iterations, fn)
  local started = clock()
  for i = 1, iterations do fn(i) end
  print(string.format("  %-52s %8.2f microseconds a call", label, (clock() - started) / iterations * 1e6))
end

print("the subsequence scorer by haystack length, an eight letter word with a typo")
for _, m in ipairs({ 64, 128, 256 }) do
  local h = body(m, m)
  time(m .. " bytes", 2000, function() match.fuzzy("settigns", h) end)
end

print("a thousand bodies of four kilobytes, the cost of one body")
local bodies, lowered = {}, {}
for i = 1, 1000 do
  bodies[i] = body(4000, i) .. " " .. i
  lowered[i] = bodies[i]:lower()
end
-- The first search ever lowers every body once, and every later one finds the copy kept.
time("fuzzy, the first search, lowering each body", 1000, function(i) match.fuzzy("settings", bodies[i]) end)
-- ump sits only inside words, so every occurrence is tried for a word start before the first
-- is kept, the worst case of choosing the best occurrence.
for _, q in ipairs({ "settings", "hello there", "chooser", "zebra", "ump" }) do
  print(" query " .. q)
  time("words over a body the caller lowered", 1000, function(i) match.words(q, lowered[i]) end)
  time("fuzzy over the body as the row holds it", 1000, function(i) match.fuzzy(q, bodies[i]) end)
end
