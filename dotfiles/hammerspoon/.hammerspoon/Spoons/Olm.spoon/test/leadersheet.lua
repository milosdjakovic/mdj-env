-- The leader sheet host and the policy fields that lay it out, in plain Lua.
--
-- Phase 4 of the keymap plan replaced a Hyper sheet host and a window sheet host with one host that
-- draws whichever held leader asks. This pins what that host does with the rows it is given, how it
-- files a row under a group, how a row whose when is false is hidden, what it hands the renderer
-- and what a leader's layout may say, so a change to any of them fails here and not on a key hold.
--
-- It needs no Hammerspoon and no lock. The host touches hs only for a logger, which records what it
-- warned so the unknown predicate rule can be counted.
--
-- Run it.
--   lua test/leadersheet.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local warnings = {}
hs = {
  logger = {
    new = function()
      return setmetatable({
        w = function(message) warnings[#warnings + 1] = message end,
      }, { __index = function() return function() end end })
    end,
  },
}

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local function fresh()
  local host = assert(loadfile(here .. "../host/leadersheet/init.lua"))()
  host:init()
  return host
end
local leader = assert(loadfile(here .. "../lib/leader.lua"))()

-- A badge spelled as the key and its modifiers joined, so a row compares as one plain string.
local function glyphFor(key, mods)
  local m = {}
  for _, x in ipairs(mods or {}) do m[#m + 1] = x end
  return (#m > 0 and table.concat(m, "+") .. "+" or "") .. tostring(key):upper()
end

-- A renderer that records every model it is shown and whether it was hidden.
local function renderer()
  local r = { shown = {}, hidden = 0, up = false, glyphFor = glyphFor }
  function r:show(model) self.shown[#self.shown + 1] = model self.up = true end
  function r:hide() self.hidden = self.hidden + 1 self.up = false end
  function r:isShowing() return self.up end
  return r
end

local LAYOUT = { title = "ACTIONS", columns = 4, colWidth = 215, iconSize = 32, gap = 10, groupGap = 20 }
local function titles(sections)
  local out = {}
  for _, s in ipairs(sections) do out[#out + 1] = s.title end
  return table.concat(out, ",")
end
local function badges(section)
  local out = {}
  for _, r in ipairs(section.rows) do out[#out + 1] = r.badge end
  return table.concat(out, ",")
end

-- Rows become one section under the layout's title, spelled by the glyph helper, in order.
do
  local host = fresh()
  local entries = host.ownSections({
    { key = "a", description = "Alpha" },
    { key = "b", mods = { "shift" }, action = "betaThing" },
    { key = "c" },
  }, { glyphFor = glyphFor, layout = LAYOUT })
  eq(#entries, 1, "model: rows with no group make one section")
  eq(entries[1].title, "ACTIONS", "model: it wears the layout's title")
  eq(badges(entries[1]), "A,shift+B,C", "model: each badge is spelled by the glyph helper, in the order given")
  eq(entries[1].rows[1].label, "Alpha", "model: a row wears its description")
  eq(entries[1].rows[2].label, "Beta Thing", "model: a row with none wears its action in words")
  eq(entries[1].rows[3].label, "c", "model: and the key where it has no action either")
  eq(entries[1].alpha, 1.0, "model: the section is fully opaque")
  eq(entries[1].columns, 4, "model: a plain section keeps the leader's own columns")
  eq(entries[1].colWidth, 215, "model: and its column width")
  eq(entries[1].iconSize, 0, "model: and draws no icon gutter")
  eq(#host.ownSections({}, { glyphFor = glyphFor, layout = LAYOUT }), 0, "model: no rows make no section")
  eq(#host.ownSections({ { description = "no key" }, "text" }, { glyphFor = glyphFor, layout = LAYOUT }), 0,
    "model: a row with no key and a row that is no table are skipped")
end

-- A descriptor's group files its row under a section of that name, in first appearance order.
do
  local host = fresh()
  local entries = host.ownSections({
    { key = "a", description = "A" },
    { key = "b", description = "B", group = "Capture" },
    { key = "c", description = "C" },
    { key = "d", description = "D", group = "Capture" },
    { key = "e", description = "E", group = "Other" },
  }, { glyphFor = glyphFor, layout = LAYOUT })
  eq(titles(entries), "ACTIONS,Capture,Other", "groups: a section appears where its title first appears")
  eq(badges(entries[1]), "A,C", "groups: rows with no group share the default section")
  eq(badges(entries[2]), "B,D", "groups: rows of one group share a section")
end

-- A group that is a function makes the whole block one supplier, asked again on every show.
do
  local host = fresh()
  local word = "First"
  local entries = host.ownSections({
    { key = "a", description = "A", group = function() return word end },
    { key = "b", description = "B" },
    { key = "c", description = "C", group = function() error("broken") end },
    { key = "d", description = "D", group = function() return 7 end },
  }, { glyphFor = glyphFor, layout = LAYOUT })
  eq(#entries, 1, "dynamic groups: the block is one entry")
  eq(type(entries[1]), "function", "dynamic groups: and it is a supplier")
  eq(titles(entries[1]()), "First,ACTIONS", "dynamic groups: a failure or a non word files the row under the title")
  word = "Second"
  eq(titles(entries[1]()), "Second,ACTIONS", "dynamic groups: the answer is asked again on every call")
end

-- The gate. A row whose when is false is hidden at every show and a section left empty stays an
-- empty section for the renderer to drop, and a sheet whose every row is hidden is not drawn.
do
  local host = fresh()
  local open = true
  local r = renderer()
  local entries = host.ownSections({
    { key = "a", description = "A" },
    { key = "b", description = "B", when = "gate" },
  }, { glyphFor = glyphFor, layout = LAYOUT })
  host:configure({ cheatSheet = r, predicates = { gate = function() return open end },
    sheets = { { name = "hyper", keyCode = 79, layout = LAYOUT, entries = entries } } })
  host:show(79)
  eq(#r.shown, 1, "gate: a sheet with rows is drawn")
  eq(badges(r.shown[1].sections[1]), "A,B", "gate: a row whose when is true is shown")
  open = false
  host:show(79)
  eq(badges(r.shown[2].sections[1]), "A", "gate: a row whose when is false is hidden, asked again on this show")
  eq(entries[1].rows[2].badge, "B", "gate: and the stored row is untouched, so the next show can restore it")
  open = true
  host:show(79)
  eq(badges(r.shown[3].sections[1]), "A,B", "gate: the row returns the moment its predicate is true again")

  local only = fresh()
  local r2 = renderer()
  local gated = only.ownSections({ { key = "a", when = "gate" } }, { glyphFor = glyphFor, layout = LAYOUT })
  only:configure({ cheatSheet = r2, predicates = { gate = function() return false end },
    sheets = { { name = "meta", keyCode = 80, layout = LAYOUT, entries = gated } } })
  only:show(80)
  eq(#r2.shown, 0, "gate: a sheet whose every row is hidden is not drawn at all")

  warnings = {}
  local unknown = fresh()
  local r3 = renderer()
  local typo = unknown.ownSections({ { key = "a", when = "nope" } }, { glyphFor = glyphFor, layout = LAYOUT })
  unknown:configure({ cheatSheet = r3, predicates = {},
    sheets = { { name = "meta", keyCode = 80, layout = LAYOUT, entries = typo } } })
  unknown:show(80)
  eq(#r3.shown, 1, "gate: an unknown predicate name leaves the row shown, so a typo fails visibly")
  eq(#warnings, 1, "gate: and says so")
  unknown:show(80)
  unknown:show(80)
  eq(#warnings, 1, "gate: once per name, not on every show")
end

-- What the renderer is handed, and what a supplier's sections are checked against.
do
  local host = fresh()
  local r = renderer()
  local supplier = function()
    return {
      { title = "RUNNING", alpha = 1.0, icons = true, rows = { { key = "a", label = "App", icon = "img" } } },
      { title = "PLAIN", rows = { { badge = "X", label = "Own badge" }, { key = "q", mods = { "ctrl" }, label = "Chord" } } },
      "not a table",
      { title = "MIXED", rows = { { label = "no badge and no key" }, "text", { key = "z", label = "Z" } } },
    }
  end
  local own = host.ownSections({ { key = "b", description = "B" } }, { glyphFor = glyphFor, layout = LAYOUT })
  host:configure({ cheatSheet = r, sheets = { { name = "hyper", keyCode = 79, layout = LAYOUT,
    entries = { supplier, own[1] } } } })
  host:show(79)
  local model = r.shown[1]
  eq(titles(model.sections), "RUNNING,PLAIN,MIXED,ACTIONS", "renderer: suppliers lead where the entries put them and a section that is no table is dropped")
  eq(model.sections[1].iconSize, nil, "renderer: a section asking for icons keeps the panel's icon grid")
  eq(model.sections[1].rows[1].badge, "A", "renderer: a supplied row with a key is spelled by the glyph helper")
  eq(model.sections[2].iconSize, 0, "renderer: a supplied section asking for none loses the icon gutter")
  eq(model.sections[2].columns, 4, "renderer: and takes the leader's columns")
  eq(model.sections[2].rows[1].badge, "X", "renderer: a row that states its own badge keeps it")
  eq(model.sections[2].rows[2].badge, "ctrl+Q", "renderer: any other row is spelled with its modifiers")
  eq(#model.sections[3].rows, 1, "renderer: a supplied row with neither a badge nor a key is dropped")
  eq(model.columns, 4, "renderer: the leader's columns reach the show")
  eq(model.colWidth, 215, "renderer: and its column width")
  eq(model.iconSize, 32, "renderer: and its icon size")
  eq(model.gap, 10, "renderer: and its gap")
  eq(model.groupGap, 20, "renderer: and its group gap")
  eq(model.badgeWidth, nil, "renderer: a field the layout does not state is left to the renderer")

  local broken = fresh()
  local r2 = renderer()
  broken:configure({ cheatSheet = r2, sheets = { { name = "hyper", keyCode = 79, layout = LAYOUT,
    entries = { function() return "not a list" end, own[1] } } } })
  broken:show(79)
  eq(titles(r2.shown[1].sections), "ACTIONS", "renderer: a supplier answering something that is no list costs only itself")
end

-- Two leaders in one host, each drawn with its own layout and nothing of the other's.
do
  local host = fresh()
  local r = renderer()
  local window = { title = "WINDOW", columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 }
  host:configure({ cheatSheet = r, sheets = {
    { name = "hyper", keyCode = 79, layout = LAYOUT,
      entries = host.ownSections({ { key = "a", description = "A" } }, { glyphFor = glyphFor, layout = LAYOUT }) },
    { name = "meta", keyCode = 80, layout = window,
      entries = host.ownSections({ { key = "left", description = "Left" } }, { glyphFor = glyphFor, layout = window }) },
  } })
  host:show(80)
  eq(titles(r.shown[1].sections), "WINDOW", "leaders: the keycode picks the leader's own sheet")
  eq(r.shown[1].columns, 2, "leaders: and its own columns")
  eq(r.shown[1].badgeWidth, 44, "leaders: and its own badge width")
  eq(r.shown[1].iconSize, nil, "leaders: and nothing of the other leader's icon size")
  host:show(79)
  eq(titles(r.shown[2].sections), "ACTIONS", "leaders: the other keycode picks the other sheet")
  host:show(99)
  eq(#r.shown, 2, "leaders: a keycode the host holds nothing for draws nothing")
  eq(host:modelNamed("meta").keyCode, 80, "leaders: a record is found by the leader's name")
  eq(host:models()[1].name, "hyper", "leaders: records keep the order the root gave them")
  host:hide()
  eq(r.hidden, 1, "leaders: hide takes the one overlay down")
  eq(host:isShowing(), false, "leaders: and the host answers from the renderer")

  local before = fresh()
  local r2 = renderer()
  before:configure({ cheatSheet = r2 })
  before:show(79)
  eq(#r2.shown, 0, "leaders: a host configured with the renderer alone holds no sheet")
  before:configure({ sheets = { { name = "hyper", keyCode = 79, layout = LAYOUT,
    entries = before.ownSections({ { key = "a" } }, { glyphFor = glyphFor, layout = LAYOUT }) } } })
  before:show(79)
  eq(#r2.shown, 1, "leaders: a second configure keeps the renderer the first gave it")
end

-- The policy. A sheet is a boolean, its layout a table beside it, and a leader with none draws the
-- defaults.
do
  local clean, problems = leader.checkPolicy("META", { sheet = true,
    sheetLayout = { title = "WINDOW", columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 } })
  eq(#problems, 0, "policy: a sheet and a full layout are accepted")
  eq(clean.sheet, true, "policy: the sheet is kept")
  eq(clean.sheetLayout.badgeWidth, 44, "policy: and every layout field")

  clean, problems = leader.checkPolicy("META", { sheet = "windowcheatsheet" })
  eq(#problems, 1, "policy: a sheet that is a word is named, since it is a boolean now")
  eq(clean.sheet, nil, "policy: and left at its default")

  clean, problems = leader.checkPolicy("X", { sheet = true, sheetLayout = "wide" })
  eq(#problems, 1, "policy: a layout that is no table is named")
  eq(clean.sheetLayout, nil, "policy: and left out")

  clean, problems = leader.checkPolicy("X", { sheet = true,
    sheetLayout = { columns = 0, colWidth = -1, gap = "wide", title = 3, typo = true, groupGap = 5 } })
  eq(#problems, 5, "policy: every bad layout field is its own problem line")
  eq(clean.sheetLayout.groupGap, 5, "policy: a good field beside bad ones is kept")
  eq(clean.sheetLayout.columns, nil, "policy: a column count of zero is left out")
  eq(clean.sheetLayout.colWidth, nil, "policy: a negative size is left out")
  eq(clean.sheetLayout.gap, nil, "policy: a size that is a word is left out")
  eq(clean.sheetLayout.title, nil, "policy: a title that is a number is left out")

  clean, problems = leader.checkPolicy("X", { sheet = true, sheetLayout = { columns = 2.5 } })
  eq(#problems, 1, "policy: a fractional column count is named")

  clean, problems = leader.checkPolicy("X", { sheetLayout = { columns = 2 } })
  eq(#problems, 1, "policy: a layout with no sheet is named, since a hold reveals nothing")
  eq(clean.sheetLayout, nil, "policy: and the layout is dropped")

  clean, problems = leader.checkPolicy("X", { sheet = false, sheetLayout = false })
  eq(#problems, 0, "policy: false is the same as absent for both")

  -- A person's sheet = false merged over the shipped layout is legitimate and says nothing.
  clean, problems = leader.checkPolicy("META", { sheet = false,
    sheetLayout = { title = "WINDOW", columns = 2 }, drivenRepeat = true })
  eq(#problems, 0, "policy: sheet false beside a merged shipped layout is not a problem")
  eq(clean.sheetLayout, nil, "policy: and the layout is dropped")
  eq(clean.drivenRepeat, true, "policy: the rest of the policy is kept")

  local renderer = { columns = 3, colWidth = 111, gap = 7, iconSize = 0 }
  local defaults = leader.sheetLayout({ sheet = true }, renderer)
  eq(defaults.title, "SHORTCUTS", "defaults: a leader with no layout is headed plainly")
  eq(defaults.columns, 3, "defaults: in the renderer's own columns, read from it")
  eq(defaults.colWidth, 111, "defaults: and its own column width")
  eq(defaults.gap, 7, "defaults: and its gap")
  eq(defaults.iconSize, nil, "defaults: with no icon size stated, so none is drawn")
  local merged = leader.sheetLayout({ sheet = true, sheetLayout = { columns = 4, title = "ACTIONS" } }, renderer)
  eq(merged.columns, 4, "defaults: a stated field wins")
  eq(merged.colWidth, 111, "defaults: and a field it does not state keeps the default")
  eq(merged.title, "ACTIONS", "defaults: the title included")
end

-- Which suppliers reach which sheet. Each leader's sheet asks for its own role, and a supplier no
-- sheet reaches is named once, not once for every sheet that did not take it.
do
  local contributions = assert(loadfile(here .. "../lib/contributions.lua"))()
  local plan = {
    sets = { leadersheet = { cheatSheetSections = { "toggler", "mover", "drifter", "nowhere" } } },
    effective = {
      toggler = { leader = "app" }, mover = { leader = "window" }, drifter = { leader = "extra" }, nowhere = {},
    },
  }
  local function ask(role)
    return contributions.sheetSections({
      host = "leadersheet", role = role, plan = plan, manifests = {},
      modules = {}, registrar = {}, own = { { title = "OWN", rows = {} } }, ownOrder = 50,
    })
  end
  local both = contributions.sheetSections({ host = "leadersheet", roles = { "app", "window" }, plan = plan,
    manifests = {}, modules = {}, registrar = {}, own = { { title = "OWN", rows = {} } }, ownOrder = 50 })
  eq(#both, 1, "suppliers: a leader answering two roles asks for both, and an absent module adds nothing")
  local reached = {}
  contributions.unreachedSheetSections({ host = "leadersheet", roles = { "app", "window" }, plan = plan,
    log = function(m) reached[#reached + 1] = m end })
  eq(#reached, 2, "suppliers: every role a leader answers counts as revealed")
  eq(#ask("app"), 1, "suppliers: a supplier whose module is absent adds nothing and the leader's own block stays")
  local said = {}
  contributions.unreachedSheetSections({ host = "leadersheet", roles = { "app", "window" }, plan = plan,
    log = function(message) said[#said + 1] = message end })
  eq(#said, 2, "suppliers: a supplier on a role no sheet reveals is named, and so is one stating none")
  eq(said[1]:match("'drifter'") ~= nil and said[2]:match("'nowhere'") ~= nil, true, "suppliers: each by its identity")
end

-- Provided rows, provides.bindings, reach a sheet unless their plugin supplies sections for it.
do
  local hints = assert(loadfile(here .. "../lib/hints.lua"))()
  local keymapLib = assert(loadfile(here .. "../lib/keymap.lua"))()
  local plan = {
    effective = { toggler = { leader = "app" }, other = { leader = "app" } },
    identity = {}, contexts = {}, order = { "toggler", "other" },
  }
  local fn = function() end
  local result = keymapLib.build({ plan = plan, roles = { app = "HYPER", window = "META" },
    provided = { toggler = { { action = "Safari", key = "s", leader = "app", fn = fn } },
      other = { { action = "openMail", key = "m", leader = "app", fn = fn, description = "Mail" } } } })
  local rows = hints.sheetRows(result, plan, "hyper", {})
  eq(#rows, 2, "provided: a provided row reaches the sheet")
  eq(rows[1].description, "Safari", "provided: wearing its action when it states no description")
  eq(rows[2].description, "Mail", "provided: or its own description")
  rows = hints.sheetRows(result, plan, "hyper", { supplied = { toggler = true } })
  eq(#rows, 1, "provided: a plugin supplying sections for the leader is not listed twice")
  eq(rows[1].action, "openMail", "provided: and another plugin's row stays")
end

print(string.format("leadersheet: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
