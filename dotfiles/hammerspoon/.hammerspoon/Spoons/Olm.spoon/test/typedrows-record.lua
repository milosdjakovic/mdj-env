-- Records the fixtures of the typed rows in the app, docs/PLAN-STANDALONE.md stage 6, from the Lua
-- sources the launcher asks, the way test/keepawake-record.lua records keep awake.
--
-- test/fixtures/arithmetic/rows.json holds what plugins/arithmetic answers for each query, the row's
-- title or nothing, which Olm.app's Arithmetic answers too.
--
-- test/fixtures/launcher/typedgate.json holds, for each query, whether a source other than the
-- calculator answers it, the query scope over a fixed set of words, plugins/convert and
-- plugins/windowsize, so Olm.app's TypedGate asks Hammerspoon for every one of them, and whether
-- the query is plain words that nothing could answer, which the gate must not ask about.
--
-- test/fixtures/convert/parts.json holds whether plugins/convert takes each query as a conversion,
-- which Olm.app's Convert.parts answers too.
--
-- Rerun after a change to one of those sources made on purpose, and read every changed case.
--
-- "$OLM_LUA" test/typedrows-record.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local Sources = assert(loadfile(here .. "typedrows-sources.lua"))()

local SUMS = {
  "1+2", "2*3", "10/4", "7/7", "2^10", "2^0.5", "-2^2", "2^-1", "(-2)^2", "- -3", "-(3)", "7%3", "-7%3",
  "7%-3", "7.5%2", "5%0", "5.0%0", "5//0", "7//2", "-7//2", "7.0//2", "1/0", "-1/0", "0/0", "1/3", "2/3",
  "100*10%", "2+2%", "2%+5%", "10%^2", "(2+2)%", "50%", "12%3", "1%2%", "1e5+1", "1E3*2", "1e+2+0", "1e-2*3",
  "1e", "1e+", "e", "e+1", "1+e", "2e3e", "5e", ".5+.5", "5.+1", "1.2.3+1", "..1", "1..2", "5--3", "5- -3",
  "= 2+2", "=3*3", "=", "  4 * 5  ", "\t6-1\n", "3", "-3", "+3", "3+", "*3", "()", "(1)(2)", "2(3)", "((1+2))*3",
  "1+2)", "(1+2", "9223372036854775807+1", "9223372036854775808+0", "-9223372036854775808//-1",
  "9223372036854775807*2", "2^63", "2^53+1", "1e15+0", "999999999999999+0", "999999999999999.5*1",
  "1000000000000000+0", "123456789*987654321", "0.1+0.2", "1/7", "-0.0*1", "0*-1", "3.14159*2", "1e300*1e10",
  "1e308*10", "128 * 4", "2 ^ 10", "45-", "4 5", "%5", "5%", "2^3^2", "2*3+4*5", "10-2-3", "2/2/2", "100//7*7",
  "1+2e", "1.e5", "1.5e3", "0.5e-3*2", "12.5%", "50%*4", "200*10%", "1.5%+1", "1%.5", "20%%3", "3**2", "3//",
  "x+1", "1+2,3", "1 + 2 + 3", "007+1", "00.5*2", "1+(-1)", "-(-(-1))", "2*(3+(4-1))^2",
}

local GATE = {
  "", "safari", "Visual Studio Code", "1password", "intellij", "notion", "k 2h", "K 30m", "k", "k ", "kk 2h",
  "v ", "vpn de", "t github", "/ report", "= 2+2", " k 2h", "k\t2h", "10 km to miles", "10 KM TO MILES",
  "5 ft->cm", "100 eur to usd", "to", "km to miles", "10 to", "10 to ", "x to 5", "1920x1080", "1920 x 1080",
  "1920X1080", "1920×1080", "19x1080", "x1080", "1920x", "box 3", "3 boxes", "abc", "2+2", "12%3", "hex 255",
  "255 to hex", "0x1f", "into 5", "token 5", "1 into 2", "5 tons", "v2", "wifi 2", "mail", "ma", "a", "s", "w",
  "w left", "?", "? ", "3d", "macOS 27", "iPhone 15 Pro",
}

local CONVERSIONS = {
  "10 km to miles", "10 KM TO MILES", "10 km TO miles", "10 eur to rsd", "5 ft->cm", "5 ft -> cm", "255 to hex",
  "km to miles", "10 to", "10 to ", " 10 km to miles ", "10 km to", "to 5", "x to 5", "10 km into miles",
  "1 token 5", "5 in to cm", "10 in to cm to mm", "2 -> 3 -> 4", "1 to 2", "10km to mi", "10 km  to  mi",
  "10\tkm to mi", "10 km\tto mi", "abc", "", "5", "1->", "->5", "1 ->", "-40 celsius to fahrenheit",
}

local WORDS = { "k", "awake", "v", "vpn", "t", "/", "w", "s", "a", "?", "e" }

local function encode(v)
  local t = type(v)
  if v == nil then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  if #v > 0 or next(v) == nil then
    local parts = {}
    for i, x in ipairs(v) do parts[i] = encode(x) end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '": ' .. encode(v[k]) end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function write(dir, name, kind, about, extra, cases)
  local lines = {}
  for i, c in ipairs(cases) do lines[i] = "    " .. encode(c) end
  local out = '{\n  "kind": ' .. encode(kind) .. ',\n  "about": ' .. encode(about) .. ',\n' .. extra ..
    '  "cases": [\n' .. table.concat(lines, ",\n") .. '\n  ]\n}\n'
  os.execute('mkdir -p "' .. here .. "fixtures/" .. dir .. '"')
  local f = assert(io.open(here .. "fixtures/" .. dir .. "/" .. name, "wb"))
  f:write(out)
  f:close()
  print(kind .. ", recorded " .. #cases .. " case(s)")
end

local sums = {}
for i, q in ipairs(SUMS) do sums[i] = { name = q, query = q, expect = Sources.sum(q) } end
write("arithmetic", "rows.json", "arithmetic.rows",
  "The calculator's row title for each query, nothing for none, recorded from plugins/arithmetic by test/typedrows-record.lua.",
  "", sums)

local conversions = {}
for i, q in ipairs(CONVERSIONS) do
  conversions[i] = { name = q == "" and "empty" or q, query = q, converts = Sources.converts(q) }
end
write("convert", "parts.json", "convert.parts",
  "Whether plugins/convert takes each query as a conversion, recorded by test/typedrows-record.lua.", "", conversions)

local gate = {}
for i, q in ipairs(GATE) do
  local answers, quiet = Sources.gate(q, WORDS)
  gate[i] = { name = q == "" and "empty" or q, query = q, answers = answers, quiet = quiet }
end
write("launcher", "typedgate.json", "launcher.typedgate",
  "Whether a typed source other than the calculator answers each query, the scope over the file's words, convert and window size, and whether it is plain words nothing answers, recorded by test/typedrows-record.lua.",
  '  "words": ' .. encode(WORDS) .. ',\n  "sources": ' .. encode({ "arithmetic", "convert", "windowsize" }) .. ',\n', gate)
