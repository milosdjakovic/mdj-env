-- The rename proof. Core must behave the same whatever its plugins are called, so this runs the
-- composition root twice, once over the spoon as it is and once over a copy where every plugin
-- carries a scrambled name, and reports every difference between what the two runs decided.
--
-- WHY A RUN AND NOT ONLY A SCAN. test/drygate-leaks.lua reads the source, so it sees a name only
-- in the shapes it was taught, a string, a path, a field, a key, a concatenation of literals or
-- a format of literals. A name can reach core by routes no token pattern sees, a string reversed
-- or upper cased, a table built from a list, a lookup by position. Behaviour sees every route,
-- since a core that does anything different for one particular name does it differently once
-- that name is gone. This is also the one place root/compose.lua runs outside a live
-- Hammerspoon, so a regression where core starts depending on a plugin through the root stays
-- red here.
--
-- THE SCRAMBLE. Each letter is swapped for another by one fixed table, keeping its case, so a
-- directory and an identity that differ only by case, browsertabs and browserTabs, still differ
-- only by case afterwards, and every name keeps its length, so a report that pads a column by
-- name length pads it the same. A plugin is renamed where its identity lives, its directory on
-- disk, which drygate.sh copied for this, and through test/drygate-composerun.lua its manifest
-- name, its surface context, every sibling need that names it, and the person's config keys.
-- Nothing inside a plugin's own code is touched, so a plugin that spells its own name keeps
-- spelling it the old way, which is the plugin's business, and only a difference in what core
-- decided is reported.
--
-- THE COMPARISON. Each run prints a sorted snapshot, see test/drygate-composerun.lua. The
-- scrambled one has every scrambled name turned back, a name counting only where it stands as
-- a word of its own or the head of a camel case word, then the two are compared as counted
-- sets of lines. Order is not compared, since a core that sorts plugins by name is generic and
-- sorting a renamed set gives another order. A line one run has and the other lacks is a
-- finding. The table is chosen so no scrambled name is already a word in the original
-- snapshot, and the run refuses to compare when that cannot be met, rather than turning an
-- unrelated word into a plugin name.
--
-- Usage
--   lua drygate-rename.lua <spoon dir> <config dir> <copy of the spoon> <sandbox dir> <manifest.lua path>...
-- Prints one line per finding and nothing on a clean tree, then a last line "rename proof, ..."
-- with the counts. drygate.sh hands the output to test/drygate.lua, which reports each line.

local scriptDir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoonDir, hsRoot, copyDir, sandbox = arg[1], arg[2], arg[3], arg[4]
if not (spoonDir and hsRoot and copyDir and sandbox) then
  io.stderr:write("usage: lua drygate-rename.lua <spoon dir> <config dir> <copy> <sandbox> <manifest>...\n")
  os.exit(2)
end
if spoonDir:sub(-1) ~= "/" then spoonDir = spoonDir .. "/" end
if copyDir:sub(-1) ~= "/" then copyDir = copyDir .. "/" end

-- Every plugin's directory and identity, from the manifests under plugins/. A host is core and
-- keeps its name, since core may name core.
local names = {}
for i = 5, #arg do
  local path = arg[i]
  local dir = path:match("/plugins/([^/]+)/manifest%.lua$")
  if dir then
    names[dir] = true
    local chunk = loadfile(path)
    local ok, m = pcall(chunk or error)
    if ok and type(m) == "table" and type(m.name) == "string" then names[m.name] = true end
  end
end

local function cipher(word, shift)
  return (word:gsub("%a", function(c)
    local base = c:match("%l") and 97 or 65
    return string.char((c:byte() - base + shift) % 26 + base)
  end))
end

local function run(dir, mapPath)
  local cmd = string.format("lua %q %q %q %q %q", scriptDir .. "drygate-composerun.lua", dir, hsRoot, sandbox, mapPath or "")
  return io.popen(cmd)
end

-- A word stands alone when nothing alphanumeric sits before it and nothing lower case or
-- numeric after it, so "zfo" is found in plugins/zfo/init.lua and in zfoHistory, never inside
-- another word.
local function frontier(word)
  return "%f[%w]" .. word:gsub("%p", "%%%0") .. "%f[^%l%d]"
end

-- The original run starts first, and the copy is renamed while it runs.
local originalPipe = run(spoonDir)

local sorted = {}
for n in pairs(names) do sorted[#sorted + 1] = n end
table.sort(sorted)

local originalText = originalPipe:read("a")
originalPipe:close()

-- Choose the first shift whose scrambled names are new words everywhere, never a plugin or
-- host name and never a word already in the original snapshot.
local shift, scrambled
for candidate = 7, 25 do
  local clash = false
  local out = {}
  for _, n in ipairs(sorted) do
    local s = cipher(n, candidate)
    out[n] = s
    if names[s] or originalText:find(frontier(s)) then clash = true break end
  end
  if not clash then shift, scrambled = candidate, out break end
end
if not shift then
  print("dry gate refused the rename proof, every scramble collides with a word the original run already prints, so the two runs cannot be compared")
  print("rename proof, could not compare")
  os.exit(0)
end

-- Rename every plugin directory in the copy, then write the map the second run reads.
for dir in io.popen('ls "' .. copyDir .. 'plugins"'):lines() do
  if scrambled[dir] then
    assert(os.rename(copyDir .. "plugins/" .. dir, copyDir .. "plugins/" .. scrambled[dir]))
  end
end
local mapPath = sandbox .. "/rename.map"
local mapFile = assert(io.open(mapPath, "w"))
for _, n in ipairs(sorted) do mapFile:write(n, " ", scrambled[n], "\n") end
mapFile:close()

local renamedPipe = run(copyDir, mapPath)
local renamedText = renamedPipe:read("a")
renamedPipe:close()

-- Every scrambled name must have reached core, or the second run proved nothing about it. A
-- name the renamed run never printed means the rename did not take, a manifest field core
-- reads that this proof does not rename, or a snapshot that no longer shows the plan.
local unreached = {}
for _, n in ipairs(sorted) do
  if not renamedText:find(frontier(scrambled[n])) then unreached[#unreached + 1] = n end
end
for _, n in ipairs(unreached) do
  print(string.format("dry gate refused the rename proof, the scrambled name for '%s' never reached core, so the proof says nothing about it", n))
end

-- Turn every scrambled name back, the longest first so no shorter name eats part of a longer.
local back = {}
for n, s in pairs(scrambled) do back[#back + 1] = { from = s, to = n } end
table.sort(back, function(a, b) return #a.from > #b.from end)
local function unscramble(line)
  for _, pair in ipairs(back) do
    line = line:gsub(frontier(pair.from), (pair.to:gsub("%%", "%%%%")))
  end
  return line
end

-- A line is compared by its canonical form, the words it holds sorted, a word being what lies
-- between spaces, commas, quotes and brackets, with "and" dropped. Core joins a list of plugins
-- in the order their names sort, the dependency summary does, and a renamed set sorts in
-- another order, so the same words come out in another order and, where the list is written
-- as English, with the "and" on another item. That is generic, a difference that is only that
-- order depends on no one name. A snapshot line is mostly one path and one value, so its words
-- keep their meaning, and what a leak changes is which words a line holds or which lines exist.
local function canonical(line)
  local words = {}
  for word in line:gmatch('[^%s,"()]+') do
    if word ~= "and" then words[#words + 1] = word end
  end
  table.sort(words)
  return table.concat(words, " ")
end

local function counted(text, map)
  local set = {}
  for raw in text:gmatch("[^\n]+") do
    local line = map and map(raw) or raw
    local key = canonical(line)
    local entry = set[key] or { n = 0, line = line }
    entry.n = entry.n + 1
    set[key] = entry
  end
  return set
end
local original = counted(originalText)
local renamed = counted(renamedText, unscramble)

local function only(a, b, out)
  for key, entry in pairs(a) do
    local m = b[key] and b[key].n or 0
    if entry.n > m then
      out[#out + 1] = entry.line .. (entry.n - m > 1 and string.format(" (x%d)", entry.n - m) or "")
    end
  end
end
local onlyOriginal, onlyRenamed = {}, {}
only(original, renamed, onlyOriginal)
only(renamed, original, onlyRenamed)
table.sort(onlyOriginal)
table.sort(onlyRenamed)

local SHOWN = 12
local function report(list, which)
  for i, line in ipairs(list) do
    if i > SHOWN then
      print(string.format("dry gate refused the rename proof, %d more line(s) only %s", #list - SHOWN, which))
      break
    end
    print(string.format("dry gate refused the rename proof, core decided differently once the plugins were renamed, only %s, %s", which, line))
  end
end
report(onlyOriginal, "with the real names")
report(onlyRenamed, "with the scrambled names")

local total = 0
for _ in pairs(original) do total = total + 1 end
local raised = originalText:match("\nraised [^\n]*") or originalText:match("^raised [^\n]*")
if raised then
  print("dry gate, the rename proof is weak, the composition root raised under the stub before it finished, " .. raised:gsub("^\n", ""))
end
print(string.format("rename proof, %d plugin name(s) scrambled by %d, %d distinct snapshot line(s), %d difference(s)",
  #sorted, shift, total, #onlyOriginal + #onlyRenamed))
