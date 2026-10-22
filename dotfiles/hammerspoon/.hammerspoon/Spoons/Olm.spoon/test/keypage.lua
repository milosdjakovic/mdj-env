-- The OLM keys page, in plain Lua. lib/hints.lua's keyEntries turns the keymap the root built into
-- words, and lib/keypage.lua turns those words into the presentation the launcher's OLM keys row
-- pushes. This builds a small keymap through the real lib/keymap.lua and pins both halves, which
-- keys are listed and in what order, how a chord, a description and an owner are spelled, and
-- that a row does nothing when chosen while Back pops.
--
-- It needs no Hammerspoon and no lock.
--
-- Run it.
--   lua test/keypage.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local keymapLib = assert(loadfile(here .. "../lib/keymap.lua"))()
local hints = assert(loadfile(here .. "../lib/hints.lua"))()
local labels = assert(loadfile(here .. "../lib/labels.lua"))()
local binder = assert(loadfile(here .. "../lib/binder.lua"))()
local keyPage = assert(loadfile(here .. "../lib/keypage.lua"))()

local MOD_GLYPH = { shift = "⇧", ctrl = "⌃", alt = "⌥", cmd = "⌘" }
local function glyphFor(key, mods)
  local prefix = ""
  for _, m in ipairs(mods or {}) do prefix = prefix .. (MOD_GLYPH[m] or "") end
  return prefix .. tostring(key):upper()
end
local KEYCODES = { a = 0, b = 1, g = 2, j = 3, k = 4, l = 5, t = 6, x = 7, z = 8, d = 9, y = 10,
  [0] = "a", [1] = "b", [2] = "g", [3] = "j", [4] = "k", [5] = "l", [6] = "t", [7] = "x", [8] = "z",
  [9] = "d", [10] = "y" }

-- Four plugins and a list. tool opens on Hyper and T, mover has a window key and an app key,
-- toggler stands for an app on Hyper and A and on a plain combination, and picker owns a list
-- with a move key and a delete. The person moves the toggle's app key to Meta and B and frees
-- mover's Hyper G.
local fn = function() end
local plan = {
  effective = {
    tool = { leader = "app", description = "Tool", bindings = { { action = "open", key = "t" } } },
    mover = { leader = "window", bindings = { { action = "left", key = "l" },
      { action = "grow", key = "g", leader = "app" } } },
    toggler = { leader = "app", bindings = { { action = "openSafari", key = "a" },
      { action = "Placed", key = "z", leader = false, mods = { "alt" } } } },
    picker = { leader = "app", description = "Picker", bindings = {} },
  },
  identity = {}, order = { "tool", "mover", "toggler", "picker" },
  contexts = { pick = { when = "pickOpen", priority = 100, bindings = {
    { action = "insertSelected", key = "i", shared = "primary", description = "Choose" },
    { action = "selectNext", key = "j", shared = "selectNext", description = "Move down" },
    { action = "deleteEntry", key = "d", mods = { "shift" }, description = "Delete" },
  } } },
}
local manifests = {
  tool = { about = { title = "The Tool" } },
  mover = { about = { title = "Window Mover" } },
  toggler = {},
  picker = { surface = { context = "pick" } },
}
local person = keymapLib.readConfig({ keys = { ["meta+B"] = "toggler.openSafari", ["hyper+G"] = false } },
  { catalog = { HYPER = true, META = true }, roleWords = { "app", "window" }, keycodes = KEYCODES })
eq(#person.problems, 0, "setup: the person's keymap reads")
local keymap = keymapLib.build({
  plan = plan, roles = { app = "HYPER", window = "META" }, keycodes = KEYCODES,
  shortcuts = { { name = "tool", kind = "leader", fn = fn } },
  actions = {
    mover = { left = { run = fn, description = "Left half" }, grow = { run = fn } },
    toggler = { openSafari = { run = fn, app = "com.s" }, Placed = { run = fn, app = "com.s", description = "Safari placed" } },
  },
  personKeys = person.keys, listLeader = "hyper",
})
eq(#keymap.problems, 0, "setup: the keymap builds")

local entries = hints.keyEntries(keymap, plan, {
  bindable = binder.bindable,
  leaders = { "hyper", "meta" },
  leaderNames = { hyper = "Hyper", meta = "Meta" },
  chordLabel = labels.chordLabel(glyphFor),
  glyphFor = glyphFor,
  manifests = manifests,
  appName = function(bundleID) return bundleID == "com.s" and "Safari" or nil end,
})

local function line(e)
  return table.concat({ e.chord, e.description, e.owner, e.list or "-" }, " | ")
end
local want = {
  "Hyper T | Tool | Tool | -",
  "Meta L | Left half | Window Mover | -",
  "Meta B | Safari | toggler | -",
  "⌥Z | Safari placed | toggler | -",
  "Hyper I | Choose | Picker | Picker",
  "Hyper J | Move down | Picker | Picker",
  "Hyper ⇧D | Delete | Picker | Picker",
}
eq(#entries, #want, "entries: every bound chord and nothing freed")
for i, w in ipairs(want) do eq(entries[i] and line(entries[i]), w, "entries: row " .. i) end

-- A refused or quiet row is not bound, so it is not listed, and a leader not asked for is left out.
do
  local marked = { bound = {}, rows = keymap.rows, roles = keymap.roles }
  for _, row in ipairs(keymap.bound) do
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    if copy.action == "left" then copy.refused = true copy.run = nil end
    -- A row whose source answered no function and was neither refused nor quiet, which the binder
    -- reports and leaves unbound, is not listed either.
    if copy.action == "open" then copy.run = nil end
    marked.bound[#marked.bound + 1] = copy
  end
  local some = hints.keyEntries(marked, plan, { bindable = binder.bindable, leaders = { "hyper" }, leaderNames = { hyper = "Hyper" },
    chordLabel = labels.chordLabel(glyphFor), glyphFor = glyphFor, manifests = manifests })
  local chords = {}
  for _, e in ipairs(some) do chords[#chords + 1] = e.chord end
  eq(table.concat(chords, ","), "⌥Z,Hyper I,Hyper J,Hyper ⇧D", "entries: a refused row, a row with no function and an unlisted leader are left out")
  local unnamed = hints.keyEntries(keymap, plan, { bindable = binder.bindable, leaders = { "meta" }, leaderNames = { meta = "Meta" },
    chordLabel = labels.chordLabel(glyphFor), glyphFor = glyphFor, manifests = manifests })
  eq(unnamed[2] and unnamed[2].description, "Open Safari", "entries: an app row with no app name reads as its action")
  eq(#hints.keyEntries(nil, plan, { bindable = binder.bindable }), 0, "entries: no keymap lists nothing")
  eq(pcall(hints.keyEntries, keymap, plan, {}), false, "entries: with no bindable test it refuses rather than guess")
end

-- The page's rows, Back first and then one per entry.
local rows = keyPage.rows(entries)
eq(#rows, #entries + 1, "rows: Back and one per entry")
eq(rows[1].title, "Back", "rows: Back leads")
eq(rows[1].pinned, true, "rows: and is pinned so a search never drops it")
eq(rows[2].title, "Tool", "rows: titled by what the key does")
eq(rows[2].subTitle, "Hyper T", "rows: an owner the title already says is not said twice")
eq(rows[3].subTitle, "Meta L · Window Mover", "rows: a global key reads its chord and owner")
eq(rows[3].keywords, "Window Mover", "rows: the owner is a keyword")
eq(rows[2].keywords, nil, "rows: and not where it is the title")
eq(rows[6].subTitle, "Hyper I in Picker", "rows: a list key reads its chord in its list")
eq(rows[2].filterText, nil, "rows: the subtitle stays searchable, the chord is what is looked up")
eq(rows[2].icon, keyPage.ICON_KEY, "rows: every key wears the keys icon")

-- The presentation. Rows are built once per show, a key row stays and Back pops.
do
  local asked, popped = 0, 0
  local p = keyPage.presentation({ name = "launcher",
    catalog = function() asked = asked + 1 return entries end,
    pop = function() popped = popped + 1 end })
  eq(p.name, "launcher", "presentation: named for the list it is pushed over")
  eq(type(p.onSelect), "function", "presentation: answers the required onSelect")
  local first = p.rows()
  eq(p.rows(), first, "presentation: a rebuild hands back the same rows")
  eq(asked, 1, "presentation: the catalog is asked once per show")
  eq(p.intercept(first[2].item), "stay", "presentation: choosing a key stays and does nothing")
  eq(popped, 0, "presentation: and pops nothing")
  eq(p.intercept(first[1].item), true, "presentation: Back is handled")
  eq(popped, 1, "presentation: by popping back to the launcher")
  local again = keyPage.presentation({ name = "launcher", catalog = function() asked = asked + 1 return entries end })
  again.rows()
  eq(asked, 2, "presentation: a new push builds its rows afresh")
end

print(string.format("keypage: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
