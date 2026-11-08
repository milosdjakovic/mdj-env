-- Records test/fixtures/chooser/pane.json, the file search preview pane laid out by the Lua code for
-- a handful of rows, step 1.4a of docs/PLAN-STANDALONE.md. It runs inside the live Hammerspoon,
-- since only there do the fonts measure as they draw, and it is read only. It loads this checkout's
-- own files in an environment of its own through test/panefixture.lua, asks the running Olm's
-- measurer for every width and font metric the layout needs, writes each answer into the fixture
-- with what the layout made of it, and shows nothing, reloads nothing and changes nothing the
-- running config holds beyond the measurer's own cache.
--
-- Each case is also laid out with the full live tokens rather than the part Olm.app is handed,
-- lib/chooser/providers/swift/pane.lua's tokens, and a difference is said, since it would mean the
-- app is handed too little to draw the pane.
--
-- Run it through hs with the spoon and the file to write, from a script of one line,
--   return dofile(SPOON .. "test/fixtures-pane-record.lua").record(SPOON, OUT)
-- and copy OUT over the fixture once it says it recorded, reading every changed line.

local M = {}

local HOME = "/Users/fixture"
local NOW = 1800000000
local DAY = 86400

local function file(size, changed, added, blob)
  return { attrs = { mode = "file", size = size, modification = NOW - changed, creation = NOW - added }, blob = blob }
end

local function folder(changed, scanned, truncated, names)
  local entries = {}
  for i, name in ipairs(names) do entries[i] = { name = name, at = NOW - i * 60 } end
  return { attrs = { mode = "directory", size = 4096, modification = NOW - changed, creation = NOW - 40 * DAY },
    folder = { scanned = scanned, truncated = truncated, entries = entries } }
end

local function repeated(unit, bytes)
  local parts, n = {}, 0
  while n < bytes do
    parts[#parts + 1] = unit
    n = n + #unit
  end
  return table.concat(parts):sub(1, bytes)
end

local NOTES = table.concat({
  "# Notes",
  "\tindented with a tab, and\ttwo",
  "a very long line of words that goes on and on past the width of the pane so it has to wrap more than once before it ends",
  "averyveryverylongwordwithoutanyspacesthatmustbebrokenbycharacterbecauseitiswiderthanthepanewidthofthisfixture",
  "trailing spaces   ",
  "crlf line\r",
  "",
  "last line",
}, "\n")

local function longLog()
  local lines = {}
  for i = 1, 450 do lines[i] = "line " .. i end
  return table.concat(lines, "\n") .. "\n"
end

local READ_CAP = 8192

M.cases = {
  { name = "a text file with long lines, tabs, a long word, a carriage return and no last newline",
    path = HOME .. "/code/notes.txt", seen = file(#NOTES, 30, 3 * DAY, NOTES) },
  { name = "the same text file on the light half", half = "light",
    path = HOME .. "/code/notes.txt", seen = file(#NOTES, 30, 3 * DAY, NOTES) },
  { name = "a text file past its budget and slack, the file larger than the read",
    path = HOME .. "/logs/build.log", seen = file(#longLog() + 5000, 7200, 5 * DAY, longLog()) },
  { name = "a file the read cap cut, its last line dropped",
    path = HOME .. "/data/table.dat", seen = file(50000, 300, 2 * DAY, repeated("0123456789 abc\n", READ_CAP)) },
  { name = "a minified file the read cap cut in its only line",
    path = HOME .. "/web/bundle.min.js", seen = file(3 * 1024 * 1024 + 1, 4000, 9 * DAY, repeated("var a=1;b=2 ", READ_CAP)) },
  { name = "an empty file", path = HOME .. "/empty.txt", seen = file(0, 59, 61, "") },
  { name = "a folder with entries and a truncated count", path = HOME .. "/Downloads", isDir = true,
    seen = folder(3600, 2000, true, { "sub/", "report.pdf", "\tweird name", "notes.txt" }) },
  { name = "an empty folder", path = HOME .. "/Empty", isDir = true, seen = folder(90 * DAY, 0, false, {}) },
  { name = "a folder of one", path = HOME .. "/One", isDir = true, seen = folder(0, 1, false, { "only.txt" }) },
  { name = "an application bundle", path = "/Applications/Safari.app", isDir = true,
    seen = folder(20 * DAY, 1, false, { "Contents/" }) },
  { name = "a path that is gone", path = HOME .. "/gone.md", seen = {} },
  { name = "a picture type, which has no picture before step 1.4b", path = HOME .. "/Pictures/photo.png",
    seen = file(2 * 1024 * 1024, 120, 400 * DAY, "") },
  { name = "a document type Quick Look draws", path = HOME .. "/doc.pdf", seen = file(1536, -100, 10, "%PDF") },
  { name = "a binary with a NUL byte", path = HOME .. "/bin/tool", seen = file(5000, 86399, 86400, "ab\0cd") },
  { name = "a read that never answered", path = HOME .. "/slow.txt" },
  { name = "a dotfile at the root, with no folder line", path = "/.zshrc", seen = file(500, 10, 10, "export X=1\n") },
  { name = "a long name and a deep folder that wraps",
    path = HOME .. "/a/very/deep/folder/structure/that/keeps/going/and/going/beyond/the/width/of/the/pane/"
      .. "a-file-with-a-rather-long-name-that-will-not-fit.json",
    seen = file(9, 30, 30, '{"a": 1}\n') },
  { name = "no row, the empty state" },
  { name = "no row on the light half", half = "light" },
}

-- The fixture's frame, a pane as wide as the list on a screen that holds every row, with the bar
-- spanning under it, the layout `~/.olm/run/chooser.json` held on 2026-11-08.
M.frame = { x = 0, y = 0, w = 480, h = 559.1, under = 56 }
M.limits = { readCap = READ_CAP, headLines = 400, headSlack = 20, folderEntries = 100 }
M.emptyText = "Highlight a file to preview it"

local function sizeKey(font, size) return tostring(font) .. "|" .. string.format("%g", size) end
M.sizeKey = sizeKey

function M.record(spoon, out)
  local harness = dofile(spoon .. "test/panefixture.lua")
  local enc = dofile(spoon .. "test/fixtures-encode.lua")
  local SwiftPane = dofile(spoon .. "lib/chooser/providers/swift/pane.lua")
  local ui = spoon and _G.spoon.Olm.lib.ui
  local live = ui.measure
  local sizes, fonts = {}, {}
  local measured = {
    size = function(str, style)
      local w
      if utf8.len(str) == 1 then w = live:width(str, style.font, style.size) else w = live:exact(str, style.font, style.size) end
      local k = sizeKey(style.font, style.size)
      sizes[k] = sizes[k] or {}
      sizes[k][str] = w
      return { w = w, h = 0 }
    end,
    info = function(f)
      local m = live:metrics(f.name, f.size)
      fonts[sizeKey(f.name, f.size)] = { ascender = m.ascender, descender = m.descender, capHeight = m.capHeight }
      return m
    end,
  }
  local runner = harness.new(spoon, measured, { home = HOME, now = NOW })
  local interior = ui.interior(100, 100)
  local tokens = { dark = SwiftPane.tokens(ui.tokensFor("dark"), interior),
                   light = SwiftPane.tokens(ui.tokensFor("light"), interior) }
  local spec = { frame = M.frame, limits = M.limits, emptyText = M.emptyText }
  local lines, notes = {}, {}
  for i, case in ipairs(M.cases) do
    local half = case.half or "dark"
    local got = runner.run(case, tokens[half], spec)
    local full = ui.tokensFor(half)
    local copy = {}
    for k, v in pairs(full) do copy[k] = v end
    copy.interior = tokens[half].interior
    local fullGot = runner.run(case, copy, spec)
    local diff = harness.compare(fullGot, got)
    if #diff > 0 then notes[#notes + 1] = case.name .. ": " .. table.concat(diff, "; ") end
    local els = {}
    for j, el in ipairs(got.elements) do els[j] = "        " .. enc.text(el) end
    lines[#lines + 1] = "    { \"name\": " .. enc.text(case.name) .. ", \"half\": " .. enc.text(half)
      .. ", \"path\": " .. enc.text(case.path) .. ", \"isDir\": " .. enc.text(case.isDir == true)
      .. ", \"seen\": " .. enc.text(case.seen) .. ",\n      \"expect\": { \"height\": " .. enc.text(got.height)
      .. ", \"reset\": " .. enc.text(got.reset) .. ", \"elements\": [\n" .. table.concat(els, ",\n")
      .. " ] } }" .. (i < #M.cases and "," or "")
  end
  local about = "The file search preview pane, plugins/filesearch/viewers/sidepanel.lua under lib/previewpane.lua's "
    .. "native scroll path, which Olm.app ports, step 1.4a of docs/PLAN-STANDALONE.md. A case is a row, its path "
    .. "and whether the index calls it a folder, or no row for the empty state, and what the helper's peek found, "
    .. "as sources/index.lua's parsePeek shapes it, or null for a read that never answered. The tokens are each "
    .. "half's as lib/chooser/providers/swift/pane.lua hands them to the app, measured holds every width and font "
    .. "metric the layout asked the system for, and the elements expected are what the Lua layout drew, all "
    .. "recorded from the live Hammerspoon on " .. os.date("%Y-%m-%d") .. " by test/fixtures-pane-record.lua. "
    .. "test/fixtures.lua lays every case out again over the measured answers, and olm-fixtures lays it out "
    .. "with the app's own measurer, frames within half a point."
  local doc = table.concat({
    "{",
    "  \"kind\": \"chooser.pane\",",
    "  \"about\": " .. enc.text(about) .. ",",
    "  \"home\": " .. enc.text(HOME) .. ", \"now\": " .. enc.text(NOW) .. ",",
    "  \"frame\": " .. enc.text(M.frame) .. ",",
    "  \"limits\": " .. enc.text(M.limits) .. ",",
    "  \"emptyText\": " .. enc.text(M.emptyText) .. ",",
    "  \"tokens\": " .. enc.text(tokens) .. ",",
    "  \"measured\": { \"sizes\": " .. enc.text(sizes) .. ",",
    "    \"fonts\": " .. enc.text(fonts) .. " },",
    "  \"cases\": [",
    table.concat(lines, "\n"),
    "  ]",
    "}",
  }, "\n") .. "\n"
  local f = assert(io.open(out, "wb"))
  f:write(doc)
  f:close()
  return "recorded " .. #M.cases .. " case(s)" .. (#notes > 0 and (", the full tokens differ: " .. table.concat(notes, " | ")) or "")
end

return M
