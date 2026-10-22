-- The person's keymap, config/keymap.lua, in plain Lua.
--
-- lib/keymap.lua reads the file through readConfig and lays its keys over the defaults inside
-- build, and both are pure, so these cases drive them with small hand written plans. They pin the
-- chord grammar, every problem an entry can raise, how a person's chord displaces a default, what
-- false frees, the leaders, roles and aliases sections, and which leaders a built keymap puts in
-- use. The offline proof against the real plugins is test/keymap-fixture.lua and its goldens.
--
-- Run it.
--   lua test/keymap-person.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local keymap = assert(loadfile(here .. "../lib/keymap.lua"))()

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local CATALOG = { HYPER = {}, META = {}, SUPER = {} }
local ROLE_WORDS = { "app", "window" }
-- A fake of Hammerspoon's keycode table, name to code and code to name. The three keys the plus
-- sign touches carry the live table's own answers, = on 24, pad+ on 69 and no + at all.
local KEYCODES = {}
do
  local names = { "a", "c", "e", "g", "p", "t", "v", "x", "y", "3", "4", "left", "`" }
  for i, name in ipairs(names) do KEYCODES[name] = i KEYCODES[i] = name end
  KEYCODES["="], KEYCODES[24] = 24, "="
  KEYCODES["pad+"], KEYCODES[69] = 69, "pad+"
end

local function read(config)
  return keymap.readConfig(config, { catalog = CATALOG, roleWords = ROLE_WORDS, keycodes = KEYCODES })
end

local function whys(problems)
  local out = {}
  for _, p in ipairs(problems or {}) do out[#out + 1] = p.where .. " | " .. p.why end
  return table.concat(out, "\n")
end

local function has(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

--------------------------------------------------------------------------------
-- The chord grammar
--------------------------------------------------------------------------------

do
  local leaders = { hyper = true, meta = true, super = true, nav = { "ctrl", "shift" } }
  local function parse(text) return keymap.parseChord(text, leaders, KEYCODES) end

  local c = parse("hyper+E")
  eq(c.leader, "hyper", "a leader chord names its leader")
  eq(c.mods, nil, "and with no modifiers is a catch all, like every default stating none")
  eq(c.key, "e", "the key is lowercased")
  c = parse("HYPER+Shift+4")
  eq(c.leader, "hyper", "a leader is compared without case")
  eq(table.concat(c.mods, "+"), "shift", "a leader chord may carry modifiers")
  eq(c.key, "4", "and the key comes last")
  c = parse("ctrl+alt+C")
  eq(c.leader, nil, "a chord of modifiers alone has no leader")
  eq(table.concat(c.mods, "+"), "alt+ctrl", "its modifiers are sorted to compare")
  c = parse("hyper+pad+")
  eq(c and c.key, "pad+", "a chord ending in pad+ is the keypad plus key")
  eq(c and c.leader, "hyper", "after a leader")
  c = parse("ctrl+alt+PAD+")
  eq(c and c.key, "pad+", "and after modifiers, without case")
  eq(c and table.concat(c.mods, "+"), "alt+ctrl", "keeping them")
  c = parse("hyper+shift+=")
  eq(c and c.key, "=", "the main row plus is written as its unshifted key")
  eq(c and table.concat(c.mods, "+"), "shift", "with shift")
  eq(has(select(2, parse("hyper++")), "names no key"), true, "two plus signs at the end are no plus key")
  eq(has(select(2, parse("pad+")), "neither a leader nor a modifier"), true, "the keypad plus alone is a bare key")
  -- fn on a held leader would bind as a chord stating no modifier, taking the default's chord.
  eq(has(select(2, parse("hyper+fn+4")), "names fn on the held leader hyper"), true, "fn is refused on a held leader")
  eq(parse("ctrl+fn+4") ~= nil, true, "and stays legal in a chord of modifiers alone")
  eq(parse("nav+fn+T") ~= nil, true, "and on a named leader")
  c = parse("nav+T")
  eq(c.leader, "nav", "a named leader opens a chord like a held one")
  c = parse("cmd+fn+left")
  eq(c and table.concat(c.mods, "+"), "cmd+fn", "fn is a modifier a chord may ask for")

  local function why(text) local _, w = parse(text) return w or "" end
  eq(has(why("E"), "neither a leader nor a modifier"), true, "a bare key is refused")
  eq(has(why("hyper+"), "names no key"), true, "a chord ending in a plus sign names no key")
  eq(has(why("hyper++x"), "empty part"), true, "two plus signs in the middle leave an empty part")
  eq(has(why("shift+hyper+E"), "after another part"), true, "a leader opens a chord or not at all")
  eq(has(why("hyper+foo+E"), "neither a leader nor a modifier"), true, "an unknown word is named")
  eq(has(why("hyper+shift+shift+E"), "twice"), true, "a modifier named twice is refused")
  eq(has(why("nav+shift+T"), "already holds"), true, "a modifier the named leader holds is refused")
  eq(has(why("hyper+nosuch"), "no code"), true, "a key the keyboard has no code for is refused")
  eq(parse("hyper+nosuch", nil) == nil, true, "and is not read")
  local stubbed = keymap.parseChord("hyper+nosuch", leaders, setmetatable({}, { __index = function() return {} end }))
  eq(stubbed and stubbed.key, "nosuch", "with no real keycode table a key is only lowercased")
end

--------------------------------------------------------------------------------
-- readConfig, every section and every problem
--------------------------------------------------------------------------------

do
  local empty = read(nil)
  eq(#empty.keys + #empty.leaders + #empty.problems, 0, "no file is no keys and no problems")
  local sections = read({ keys = {}, leaders = {}, roles = {}, aliases = {} })
  eq(#sections.problems, 0, "every section present and empty is no problem")

  eq(has(whys(read("nope").problems), "rather than a table"), true, "a file that is not a table is named")
  local odd = read({ chords = {}, keys = 3 })
  eq(has(whys(odd.problems), "chords | is not a section"), true, "a section Olm does not read is named")
  eq(has(whys(odd.problems), "keys | is a number"), true, "a section that is not a table is named")
end

do
  local r = read({ leaders = {
    nav = { "Shift", "ctrl" },
    hyper = { "shift" },
    shift = { "ctrl" },
    app = { "ctrl" },
    empty = {},
    spacey = { "space" },
    fnny = { "fn" },
    ["1x"] = { "ctrl" },
  } })
  eq(#r.leaders, 1, "one leader of six is read")
  eq(r.leaders[1].name, "nav", "the good one")
  eq(table.concat(r.leaders[1].mods, "+"), "ctrl+shift", "its modifiers lowercased and sorted")
  local text = whys(r.problems)
  eq(has(text, "leaders hyper | is the name of the built in held leader HYPER"), true, "a held leader's name is refused")
  eq(has(text, "leaders shift | is a modifier word"), true, "a modifier word is refused")
  eq(has(text, "leaders app | is a role word"), true, "a role word is refused")
  eq(has(text, "leaders empty | is not a list of modifiers, or an empty one"), true, "an empty list is refused")
  eq(has(text, "leaders spacey | holds 'space'"), true, "a non modifier is refused")
  eq(has(text, "leaders fnny | holds 'fn'"), true, "fn is no part of a leader's own set")
  eq(has(text, "leaders 1x | is not a name"), true, "a name that is not a word is refused")
end

do
  local r = read({ roles = { window = "super", app = "Hyper", foo = "meta", bar = 3 } })
  eq(r.roles.window, "SUPER", "a role moves to the catalog name of a held leader")
  eq(r.roles.app, "HYPER", "named without case")
  local text = whys(r.problems)
  eq(has(text, "roles foo | is not a role"), true, "a role word no default names is refused")
  eq(has(text, "roles bar | is not a role"), true, "and so is any other key")
  local bad = read({ roles = { window = "nav" }, leaders = { nav = { "ctrl" } } })
  eq(bad.roles.window, nil, "a role naming a leader the person named is refused")
  eq(has(whys(bad.problems), "which is no held leader"), true, "since a role moves to a held leader only")
end

do
  local r = read({ aliases = { vpn = { "v", "tunnel" }, broken = { "ok", 3 }, worse = "v" } })
  eq(table.concat(r.aliases.vpn, ","), "v,tunnel", "an alias list is read as it stands")
  eq(r.aliases.broken, nil, "a list holding a non word is refused")
  eq(has(whys(r.problems), "aliases worse | is not a list of words"), true, "and so is a bare word")
end

do
  local r = read({
    leaders = { nav = { "shift", "ctrl" } },
    keys = {
      ["meta+E"] = "vpn.open",
      ["nav+T"] = "tmuxSessions.open",
      ["hyper+3"] = false,
      ["hyper+P"] = true,
      ["hyper+X"] = "vpn",
      ["Q"] = "vpn.open",
    },
  })
  eq(#r.keys, 3, "three entries of six are read")
  local byText = {}
  for _, e in ipairs(r.keys) do byText[e.text] = e end
  eq(byText["meta+E"].owner .. "." .. byText["meta+E"].action, "vpn.open", "an action id splits at its dot")
  eq(byText["nav+T"].leader, "nav", "a chord may open with a leader the same file names")
  eq(byText["hyper+3"].free, true, "false frees a chord")
  local text = whys(r.problems)
  eq(has(text, "keys hyper+P | answers a boolean"), true, "true is neither an action nor false")
  eq(has(text, "keys hyper+X | names 'vpn', which is not an action id"), true, "an id with no dot is refused")
  eq(has(text, "keys Q | has neither a leader nor a modifier"), true, "a chord that does not parse names the entry")
end

--------------------------------------------------------------------------------
-- build, the keys laid over the defaults
--------------------------------------------------------------------------------

local ROLES = { app = "HYPER", window = "META" }

-- A small plan. vpn and clipboard are registered tools, windows a plugin of two window actions
-- with a gate on one, capture a plugin of two actions and a descriptor with no default key, a
-- list with one key, and a toggler whose actions are built from its data, one per app and one per
-- variant, the way the app toggler's are since phase 6 of the keymap plan. Its one key, Safari on
-- a, is its own default.
local function plan()
  return {
    effective = {
      vpn = { leader = "app", description = "VPN", bindings = { { action = "open", key = "P" } } },
      clipboard = { leader = "app", description = "Clipboard", bindings = { { action = "open", key = "X" } } },
      windows = { leader = "window", bindings = {
        { action = "left", key = "left" }, { action = "next", key = "e", when = "multipleDisplays" } } },
      capture = { leader = "app", bindings = { { action = "ocr", key = "3" }, { action = "shot", key = "4" } } },
      toggler = { leader = "app", bindings = { { action = "Safari", key = "a" } } },
    },
    identity = {},
    contexts = { list = { when = "listOpen", bindings = { { action = "close", key = "x" } } } },
    order = { "vpn", "clipboard", "windows", "capture", "toggler" },
  }
end

local runs = {}
local function fn(name) runs[name] = runs[name] or function() end return runs[name] end

local function build(config, extra)
  local cfg = read(config)
  local inputs = {
    plan = plan(), roles = ROLES, keycodes = KEYCODES,
    shortcuts = { { name = "vpn", kind = "leader", fn = fn("vpn") }, { name = "clipboard", kind = "leader", fn = fn("clipboard") } },
    refusedActions = { capture = { broken = true } },
    actions = {
      windows = { left = { run = fn("left"), description = "Left" }, next = { run = fn("next"), description = "Next" } },
      capture = { ocr = { run = fn("ocr") }, shot = { run = fn("shot") }, record = { run = fn("record"), description = "Record" } },
      toggler = {
        Safari = { run = fn("Safari"), app = "com.apple.Safari" },
        Ghostty = { run = fn("Ghostty"), app = "com.mitchellh.ghostty" },
        GhosttyPlaced = { run = fn("GhosttyPlaced"), app = "com.mitchellh.ghostty", description = "Terminal placed" },
      },
    },
    personKeys = cfg.keys,
    modifierLeaders = (function()
      local out = {}
      for _, l in ipairs(cfg.leaders) do out[l.name] = l.mods end
      return out
    end)(),
    known = function(identity) return identity == "offline" end,
  }
  for k, v in pairs(extra or {}) do inputs[k] = v end
  if cfg.roles.window or cfg.roles.app then
    inputs.roles = { app = cfg.roles.app or ROLES.app, window = cfg.roles.window or ROLES.window }
  end
  return keymap.build(inputs), cfg
end

local function rowsOf(result, owner, action)
  local out = {}
  for _, row in ipairs(result.rows) do
    if row.layer == "global" and row.owner == owner and row.action == action then out[#out + 1] = row end
  end
  return out
end

local function chordsOf(result, owner, action)
  local out = {}
  for _, row in ipairs(rowsOf(result, owner, action)) do out[#out + 1] = keymap.chordText(row) end
  table.sort(out)
  return table.concat(out, ",")
end

local function noteText(result) return table.concat(result.notes or {}, "\n") end

-- The empty file changes nothing.
do
  local result = build({ keys = {}, leaders = {}, roles = {}, aliases = {} })
  eq(chordsOf(result, "vpn", "open"), "hyper+p with any modifiers", "with no keys vpn keeps its default")
  eq(#result.problems, 0, "and nothing is a problem")
  eq(#result.notes, 0, "or a note")
end

-- An action named in keys takes exactly the chords listed there and loses its defaults, copying
-- its gate, its label and its function from the row it had.
do
  local result = build({ keys = { ["meta+E"] = "vpn.open", ["meta+shift+E"] = "vpn.open", ["hyper+C"] = "windows.next" } })
  eq(chordsOf(result, "vpn", "open"), "meta+e with any modifiers,meta+shift+e", "vpn takes both its chords and loses hyper+p")
  local row = rowsOf(result, "vpn", "open")[1]
  eq(row.source, "tool", "a moved open row keeps the source of the action it runs")
  eq(row.run, runs.vpn, "and runs the tool's own function")
  eq(row.origin, "user", "and is the person's")
  eq(row.role, "window", "on meta it answers the role meta answers")
  eq(row.entry ~= nil, true, "and names the entry it came from")
  local next = rowsOf(result, "windows", "next")[1]
  eq(keymap.chordText(next), "hyper+c with any modifiers", "a window action may move onto another leader")
  eq(next.when, "multipleDisplays", "keeping its gate")
  eq(next.description, "Next", "and its label")
  eq(next.run, runs.next, "and its function")
  eq(chordsOf(result, "clipboard", "open"), "hyper+x with any modifiers", "an action not named keeps its default")
  eq(#result.problems, 0, "and none of it is a problem")
end

-- A person's chord on a slot a default holds wins it, and the default is dropped with one note.
do
  local result = build({ keys = { ["hyper+X"] = "vpn.open" } })
  eq(chordsOf(result, "clipboard", "open"), "", "the clipboard's default on hyper+x is dropped, not bound beside")
  eq(chordsOf(result, "vpn", "open"), "hyper+x with any modifiers", "vpn takes the slot")
  eq(#result.problems, 0, "displacement is no problem")
  eq(has(noteText(result), "takes hyper+x with any modifiers, so the default clipboard.open is not bound there"), true,
    "one routine note names the displaced action")
  eq(has(whys(result.problems), "no bindings row whose action is open"), false,
    "and a tool left keyless by the person is not reported as missing its key")
end

-- false frees a chord, dropping whatever holds it, with nothing bound there.
do
  local result = build({ keys = { ["hyper+3"] = false, ["hyper+shift+3"] = false } })
  eq(chordsOf(result, "capture", "ocr"), "", "the chord false names is freed")
  eq(chordsOf(result, "capture", "shot"), "hyper+4 with any modifiers", "the plugin's other chords stay")
  eq(has(noteText(result), "'hyper+3' frees the chord, so capture.ocr is not bound there"), true, "said in a note")
  eq(has(noteText(result), "'hyper+shift+3' frees a chord no row holds"), true, "and freeing an empty slot is a note too")
  eq(#result.problems, 0, "neither is a problem")
end

-- Two of the person's own chords on one slot are a problem naming the entries, and so is false
-- beside an entry on its own slot.
do
  local result = build({ keys = { ["meta+E"] = "vpn.open", ["META+e"] = "clipboard.open" } })
  local text = whys(result.problems)
  eq(#result.problems, 1, "two entries on one slot are one problem")
  eq(has(text, "keymap entry 'META+e'") and has(text, "keymap entry 'meta+E'"), true, "naming both entries")
  local freed = build({ keys = { ["hyper+E"] = "vpn.open", ["Hyper+e"] = false } })
  eq(has(whys(freed.problems), "frees a chord the entry 'hyper+E' takes"), true, "false on an entry's own slot is a problem")
  eq(chordsOf(freed, "vpn", "open"), "hyper+e with any modifiers", "and the entry keeps the chord")
  -- An action built from data holds its default slot like any other, so an entry takes it the
  -- same way. config/plugins.lua holds no binding of the person's since phase 7 of the keymap plan.
  local toggle = build({ keys = { ["hyper+A"] = "vpn.open" } })
  eq(#toggle.problems, 0, "an entry on a slot the toggler's default holds is no problem")
  eq(chordsOf(toggle, "toggler", "Safari"), "", "that default's row there is dropped")
  eq(chordsOf(toggle, "vpn", "open"), "hyper+a with any modifiers", "and the entry takes the slot")
  eq(has(noteText(toggle), "takes hyper+a with any modifiers, so the default toggler.Safari is not bound there"), true,
    "said in the routine line a displaced default gets")
end

-- An id naming nothing is a problem, and one naming a plugin not running this load is a note.
do
  local result = build({ keys = {
    ["meta+A"] = "nobody.open", ["meta+C"] = "capture.nothing", ["meta+T"] = "offline.open",
  } })
  local text = whys(result.problems)
  eq(has(text, "keys meta+A | the entry names 'nobody', which is no plugin or host"), true, "an unknown identity is named")
  eq(has(text, "keys meta+C | the entry names the action 'nothing', which 'capture' does not answer"), true, "an unknown action is named")
  eq(has(noteText(result), "names offline, which is not running this load"), true, "a plugin switched off is a note")
  eq(#result.problems, 2, "and is no problem")
end

-- An action with no default chord gets one, a refused one is left unbound in silence, and an
-- action built from data moves like any other.
do
  local result = build({ keys = {
    ["hyper+shift+4"] = "capture.record", ["hyper+shift+3"] = "capture.broken", ["ctrl+alt+A"] = "toggler.Safari",
  } })
  local record = rowsOf(result, "capture", "record")[1]
  eq(record and record.run, runs.record, "a descriptor with no default chord runs from its new one")
  eq(record and record.source, "bindings", "as a binding")
  eq(record and record.description, "Record", "labelled by its descriptor")
  local broken = rowsOf(result, "capture", "broken")[1]
  eq(broken and broken.refused, true, "a refused action's chord is marked refused")
  eq(chordsOf(result, "toggler", "Safari"), "alt+ctrl+a", "an action built from data moves to a plain combo")
  eq(rowsOf(result, "toggler", "Safari")[1].run, runs.Safari, "running its own function")
  eq(rowsOf(result, "toggler", "Safari")[1].app, "com.apple.Safari", "and carrying the app it stands for")
  eq(#result.problems, 0, "none of it is a problem")
end

-- The leaders section. A named leader's chord is its own leader on the row, and its slot is the
-- whole combination, so it meets a plain combo of the same modifiers.
do
  local result = build({ leaders = { nav = { "shift", "ctrl" } }, keys = { ["nav+T"] = "vpn.open" } })
  local row = rowsOf(result, "vpn", "open")[1]
  eq(row.leader, "nav", "the row sits on the named leader")
  eq(row.role, nil, "which answers no role")
  local clash = build({ leaders = { nav = { "shift", "ctrl" } },
    keys = { ["nav+T"] = "vpn.open", ["ctrl+shift+T"] = "clipboard.open" } })
  eq(#clash.problems, 1, "a named leader's chord and the same plain combo are one slot")
end

-- The roles section moves every default on a role at once.
do
  local result = build({ roles = { window = "super" } })
  eq(chordsOf(result, "windows", "left"), "super+left with any modifiers", "a window default lands on super")
  eq(rowsOf(result, "windows", "left")[1].role, "window", "keeping its role")
  eq(chordsOf(result, "vpn", "open"), "hyper+p with any modifiers", "an app default stays")
end

-- Activation, every leader some bound row uses and no other.
do
  local base = keymap.leadersInUse((build({})))
  eq(table.concat(base, ","), "hyper,meta", "the defaults use hyper and meta")
  local moved = keymap.leadersInUse((build({ roles = { window = "super" } })))
  eq(table.concat(moved, ","), "hyper,super", "moving the window role frees meta and claims super")
  local claimed = keymap.leadersInUse((build({ keys = { ["super+V"] = "vpn.open" } })))
  eq(table.concat(claimed, ","), "hyper,meta,super", "one chord on super claims it")
  local named = keymap.leadersInUse((build({ leaders = { nav = { "ctrl" } }, keys = { ["nav+T"] = "vpn.open" } })))
  eq(table.concat(named, ","), "hyper,meta,nav", "a named leader is in use while a chord uses it")
  local refused = keymap.leadersInUse((build({ roles = { window = "super" }, keys = { ["meta+T"] = "capture.broken" } })))
  eq(table.concat(refused, ","), "hyper,super", "a refused row does not put a leader in use")
  local lists = keymap.leadersInUse({ rows = {
    { layer = "list", leader = "hyper" },
    { layer = "global", leader = "meta", quiet = true, run = function() end },
  } })
  eq(table.concat(lists, ","), "hyper", "a list key puts its leader in use and a quiet row does not")
end

-- Two actions for one app, a plain toggle and a placed variant, are two ids since phase 6 of the
-- keymap plan, so each takes its own chord and moving one leaves the other where it is. Until
-- then the two were rows of one id, toggler.Ghostty, and an entry naming it was refused.
do
  local both = build({ keys = { ["hyper+`"] = "toggler.Ghostty", ["alt+`"] = "toggler.GhosttyPlaced" } })
  eq(#both.problems, 0, "a plain toggle and a variant of one app are no problem")
  eq(chordsOf(both, "toggler", "Ghostty"), "hyper+` with any modifiers", "the plain toggle on Hyper and backtick")
  eq(chordsOf(both, "toggler", "GhosttyPlaced"), "alt+`", "the variant on Option and backtick")
  eq(rowsOf(both, "toggler", "Ghostty")[1].run, runs.Ghostty, "each running its own function")
  eq(rowsOf(both, "toggler", "GhosttyPlaced")[1].run, runs.GhosttyPlaced, "the variant included")
  eq(rowsOf(both, "toggler", "GhosttyPlaced")[1].app, rowsOf(both, "toggler", "Ghostty")[1].app,
    "and both stand for the same app")
  local moved = build({ keys = { ["hyper+G"] = "toggler.Ghostty", ["alt+`"] = "toggler.GhosttyPlaced" } })
  eq(#moved.problems, 0, "an entry naming toggler.Ghostty is accepted")
  eq(chordsOf(moved, "toggler", "Ghostty"), "hyper+g with any modifiers", "and moves the plain toggle alone")
  eq(chordsOf(moved, "toggler", "GhosttyPlaced"), "alt+`", "leaving the variant where it is")
end

-- A leader the person named that no chord uses is one routine note, and one in use is not.
do
  local unused = build({ leaders = { nav = { "ctrl" }, side = { "alt", "cmd" } }, keys = { ["nav+T"] = "vpn.open" } })
  eq(has(noteText(unused), "the leader side is named in config/keymap.lua and no chord uses it"), true, "an unused leader is said")
  eq(has(noteText(unused), "the leader nav is named"), false, "a used one is not")
  eq(#unused.problems, 0, "and neither is a problem")
end

-- The fallback when the keymap fails to build, every leader a role names and the leader hosting
-- lists, so lists keep their keys where a role moved the app role off it.
do
  eq(table.concat(keymap.fallbackLeaders({ app = "HYPER", window = "META" }, "hyper"), ","), "hyper,meta",
    "the roles' leaders on this machine")
  eq(table.concat(keymap.fallbackLeaders({ app = "SUPER", window = "META" }, "hyper"), ","), "hyper,meta,super",
    "the leader hosting lists stays in use after the app role moved off it")
  eq(table.concat(keymap.fallbackLeaders({ app = "HYPER" }, nil), ","), "hyper", "with no list leader the roles alone")
end

--------------------------------------------------------------------------------
-- The lists section, the keys live while a list is open, since phase 7 of the keymap plan
--------------------------------------------------------------------------------

-- Two lists built by the real lib/surface.lua on Olm's own all layer, the way the resolver builds
-- them, so every case reads blocks of the true shape. clip has a primary, the move keys, an extra
-- on d, a Command and j extra beside the bare j, a key it lists with chord false, close and the
-- action panel. pane has no move keys and closes on its own key, the way the launcher does.
local surface = assert(loadfile(here .. "../lib/surface.lua"))()
local hints = assert(loadfile(here .. "../lib/hints.lua"))()
local LIST_KEYCODES = {}
do
  local names = { "a", "c", "d", "e", "i", "j", "k", "n", "o", "space", "x", "y", "delete", "p" }
  for i, name in ipairs(names) do LIST_KEYCODES[name] = i LIST_KEYCODES[i] = name end
end

local function lists()
  return {
    clip = assert(surface.context("clip", {
      primary = { action = "insertSelected", description = "Paste" },
      extra = {
        { key = "j", mods = { "cmd" }, action = "scrollDown", description = "Scroll down" },
        { key = "d", action = "deleteSelected", description = "Delete" },
        { key = "delete", action = "leavePage", chord = false, description = "Back" },
      },
    }, nil, keymap.listDefaults)),
    pane = assert(surface.context("pane", {
      primary = { action = "insertSelected", description = "Run" },
      nav = false,
      close = { key = "space" },
    }, nil, keymap.listDefaults)),
  }
end

local function readLists(section)
  return keymap.readConfig({ lists = section },
    { catalog = CATALOG, roleWords = ROLE_WORDS, keycodes = LIST_KEYCODES })
end

local function applied(section, extra)
  local cfg = readLists(section)
  local contexts = lists()
  local opts = { listLeader = "hyper", keycodes = LIST_KEYCODES }
  for k, v in pairs(extra or {}) do opts[k] = v end
  local problems, notes = keymap.applyLists(contexts, cfg.lists, opts)
  for _, p in ipairs(cfg.problems) do problems[#problems + 1] = p end
  return contexts, problems, notes
end

-- The chords a list binds for an action, sorted, the way a person reads them.
local function listKeys(contexts, list, action)
  local out = {}
  for _, b in ipairs(contexts[list].bindings) do
    if b.action == action and b.chord ~= false then
      out[#out + 1] = (b.mods and #b.mods > 0 and (table.concat(b.mods, "+") .. "+") or "") .. b.key
    end
  end
  table.sort(out)
  return table.concat(out, ",")
end

-- Olm's own all layer is what the builder puts the shared verbs on, and lib/surface.lua holds no key.
do
  local contexts = lists()
  eq(listKeys(contexts, "clip", "insertSelected"), "i", "the primary sits on the all layer's key")
  eq(listKeys(contexts, "clip", "selectNext") .. "|" .. listKeys(contexts, "clip", "selectPrev"), "j|k", "the move keys too")
  eq(listKeys(contexts, "clip", "closeChooser") .. "|" .. listKeys(contexts, "clip", "openActionPanel"), "x|o",
    "and close and the action panel")
  eq(listKeys(contexts, "pane", "closeChooser"), "space", "a close key the manifest states wins over the layer's")
  local bare = surface.context("bare", { primary = { action = "insertSelected" } })
  eq(#bare.bindings, 0, "with no all layer handed in no shared verb is bound")
  local scanner = dofile(here .. "drygate-binding.lua")
  eq(#scanner.keyLiterals(assert(io.open(here .. "../lib/surface.lua")):read("a")), 0, "lib/surface.lua writes no key")
  eq(#scanner.keyLiterals('local MOVE = { key = "j", action = "selectNext" }'), 1, "and the dry gate would see one written back")
  eq(#scanner.keyLiterals('local d = { key = close.key or "x" }'), 1, "a literal as a fallback is seen too")
  eq(#scanner.keyLiterals('t["key"] = 4'), 1, "and a number through a quoted field name")
  eq(#scanner.keyLiterals([[log.e("bad, key = 'x' was written")]]), 0, "a key written inside a log message is text")
  eq(#scanner.keyLiterals('local b = { key = keys[1], action = "go" }'), 0, "an index is not a literal")
end

-- An empty section changes nothing.
do
  local contexts, problems, notes = applied({})
  eq(#problems + #notes, 0, "no lists entry is no problem and no note")
  eq(listKeys(contexts, "clip", "selectNext"), "j", "and every key stays where Olm puts it")
end

-- all moves selectNext in every list that answers it, and a list with no move keys is left alone.
do
  local contexts, problems = applied({ all = { ["hyper+n"] = "selectNext" } })
  eq(#problems, 0, "moving a shared verb in all is no problem")
  eq(listKeys(contexts, "clip", "selectNext"), "n", "selectNext takes exactly its new chord")
  eq(listKeys(contexts, "clip", "scrollDown"), "cmd+j", "while Command and j, another slot, stays")
  eq(listKeys(contexts, "pane", "selectNext"), "", "and a list with no move keys gains none")
  local moved
  for _, b in ipairs(contexts.clip.bindings) do if b.action == "selectNext" then moved = b end end
  eq(moved and moved.description, "Move down", "the moved binding keeps its label")
  eq(moved and moved.entry, "all hyper+n", "and names the entry it came from")
  local order = {}
  for _, b in ipairs(contexts.clip.bindings) do order[#order + 1] = b.action end
  eq(table.concat(order, ","), "insertSelected,selectNext,selectPrev,scrollDown,deleteSelected,leavePage,closeChooser,openActionPanel",
    "and the list keeps its order")
  local closed = applied({ all = { ["hyper+c"] = "close" } })
  eq(listKeys(closed, "clip", "closeChooser") .. "|" .. listKeys(closed, "pane", "closeChooser"), "c|space",
    "close in all moves every close on Olm's own key and leaves one the manifest states")
  local named = applied({ pane = { ["hyper+c"] = "close" } })
  eq(listKeys(named, "pane", "closeChooser"), "c", "which moves when the person names that list")
  local freed = applied({ all = { ["hyper+space"] = false } })
  eq(listKeys(freed, "pane", "closeChooser"), "space", "and false in all does not free it either")
  local extra, extraProblems = applied({ all = { ["hyper+e"] = "deleteSelected" } })
  eq(listKeys(extra, "clip", "deleteSelected"), "d", "all does not move a key a manifest states for its own verb")
  eq(has(whys(extraProblems), "which no list answers on a key of Olm's own all layer"), true, "and says so")
end

-- A list's own table goes over all, deciding every action and every slot it names.
do
  local contexts, problems, notes = applied({
    all = { ["hyper+n"] = "selectNext", ["hyper+e"] = "openActionPanel" },
    clip = { ["hyper+p"] = "selectNext", ["hyper+a"] = "selectPrev" },
  })
  eq(#problems, 0, "a per list override is no problem")
  eq(listKeys(contexts, "clip", "selectNext"), "p", "the list's own chord wins over all's for the same action")
  eq(listKeys(contexts, "clip", "selectPrev"), "a", "and its own action moves")
  eq(listKeys(contexts, "clip", "openActionPanel"), "e", "while all still reaches what the list leaves alone")
  eq(#notes, 0, "nothing was displaced")
  local displaced, _, said = applied({ clip = { ["hyper+d"] = "selectPrev" } })
  eq(listKeys(displaced, "clip", "selectPrev"), "d", "a chord on a slot a default holds is the person's")
  eq(listKeys(displaced, "clip", "deleteSelected"), "", "and the default there is dropped, not bound beside it")
  eq(has(table.concat(said, "\n"), "the keymap entry 'lists clip hyper+d' takes d in clip, so the default clip.deleteSelected is not bound there"),
    true, "said in one routine note")
end

-- A list's own table overrides an all entry resolving to the same binding however either names
-- it, a shared verb or the action it runs, so no binding keeps an all chord beside the list's own.
do
  local contexts, problems = applied({ all = { ["hyper+p"] = "primary" }, clip = { ["hyper+y"] = "insertSelected" } })
  eq(#problems, 0, "primary in all and insertSelected in a list are no problem")
  eq(listKeys(contexts, "clip", "insertSelected"), "y", "the list's own chord alone, not all's beside it")
  eq(listKeys(contexts, "pane", "insertSelected"), "p", "while every other list takes all's")
  local closes = applied({ all = { ["hyper+c"] = "closeChooser" }, clip = { ["hyper+y"] = "close" } })
  eq(listKeys(closes, "clip", "closeChooser"), "y", "close in a list overrides closeChooser in all the same way")
end

-- An entry naming an action the list left out for a need this machine lacks is a routine note,
-- since the key is real on a machine that meets it.
do
  local block = assert(surface.context("clip", {
    primary = { action = "insertSelected" },
    extra = { { key = "q", action = "peek", needs = "askedPreview" } },
  }, {}, keymap.listDefaults))
  eq(block.unmet and block.unmet.peek, "askedPreview", "the builder remembers the binding a need dropped")
  local cfg = readLists({ clip = { ["hyper+p"] = "peek" } })
  local problems, notes = keymap.applyLists({ clip = block }, cfg.lists, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  eq(#problems, 0, "naming it is no problem")
  eq(has(table.concat(notes, "\n"), "names peek, which needs askedPreview and this machine lacks it"), true, "but a note")
end

-- false frees a list key, in one list or in all of them.
do
  local contexts, problems, notes = applied({ clip = { ["hyper+o"] = false } })
  eq(#problems, 0, "freeing a list key is no problem")
  eq(listKeys(contexts, "clip", "openActionPanel"), "", "the freed key is not bound in that list")
  eq(listKeys(contexts, "pane", "openActionPanel"), "o", "and stays in every other")
  eq(has(table.concat(notes, "\n"), "frees the chord in clip, so clip.openActionPanel is not bound there"), true, "said in a note")
  local all = applied({ all = { ["hyper+o"] = false } })
  eq(listKeys(all, "clip", "openActionPanel") .. listKeys(all, "pane", "openActionPanel"), "", "false in all frees it in every list")
  local _, _, nothing = applied({ clip = { ["hyper+y"] = false } })
  eq(has(table.concat(nothing, "\n"), "frees a chord no key of the list holds"), true, "freeing an empty slot is a note")
end

-- Two of the person's own chords on one slot of one table are refused together, one problem and
-- neither applied, and two defaults on one slot of a list are named by the keymap's collision check.
do
  local contexts, problems = applied({ clip = { ["hyper+n"] = "selectNext", ["hyper+N"] = "selectPrev" } })
  eq(#problems, 1, "two entries on one slot of a list are one problem")
  eq(has(whys(problems), "'hyper+N' and 'hyper+n' are two of the person's own chords on one slot of clip"), true,
    "naming both entries")
  eq(listKeys(contexts, "clip", "selectNext") .. "|" .. listKeys(contexts, "clip", "selectPrev"), "j|k", "and neither is applied")

  local clash = lists()
  table.insert(clash.clip.bindings, 2, { key = "d", action = "other", description = "Other" })
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = clash }, roles = ROLES,
    keycodes = LIST_KEYCODES, listLeader = "hyper" })
  eq(#result.problems, 1, "two defaults on one slot of a list are reported")
  eq(has(whys(result.problems), "in the clip layer"), true, "in that list's own layer")
end

-- A list chord may shadow a global chord while its list is open, since the layers never meet.
do
  local contexts, problems = applied({ clip = { ["hyper+e"] = "deleteSelected" } })
  local result = keymap.build({
    plan = { effective = { finder = { leader = "app", bindings = { { action = "go", key = "e" } } } },
      identity = {}, contexts = contexts, order = { "finder" } },
    roles = ROLES, keycodes = LIST_KEYCODES, listLeader = "hyper",
    actions = { finder = { go = { run = function() end } } },
  })
  eq(#problems + #result.problems, 0, "a list chord on a global chord's slot is accepted")
  local layers = {}
  for _, row in ipairs(result.rows) do
    if row.key == "e" then layers[#layers + 1] = row.layer .. ":" .. tostring(row.origin) end
  end
  table.sort(layers)
  eq(table.concat(layers, ","), "clip:user,global:default", "both bind, the list's marked the person's")
end

-- Problems an entry can raise, each named, with every other entry still read.
do
  local _, problems, notes = applied({
    all = { ["hyper+y"] = "nothing" },
    clip = { ["meta+n"] = "selectNext", ["ctrl+alt+n"] = "selectNext", ["hyper+c"] = "leavePage", ["hyper+e"] = "missing" },
    gone = { ["hyper+n"] = "selectNext" },
    away = { ["hyper+n"] = "selectNext" },
    [3] = {},
  }, { known = function(name) return name == "away" end })
  local text = whys(problems)
  eq(has(text, "lists all hyper+y | the entry names the action 'nothing', which no list answers"), false,
    "an all entry is worded as the section it sits in")
  eq(has(text, "lists all hyper+y | names the action 'nothing', which no list answers"), true, "an all action no list answers is named")
  eq(has(text, "lists clip meta+n | opens with meta, and a list key opens with a held leader, hyper"), true,
    "a chord on a leader that is not a held leader this load is named")
  eq(has(text, "lists clip ctrl+alt+n | opens with no leader"), true, "and so is a chord of modifiers alone")
  eq(has(text, "lists clip hyper+c | names leavePage, which the list lists with chord false"), true,
    "a key the list reads for itself is no person setting")
  eq(has(text, "lists clip hyper+e | names the action 'missing', which the list clip does not answer"), true,
    "an action the list does not answer is named")
  eq(has(text, "lists gone | names no list in this load"), true, "a section naming no list is named")
  eq(has(text, "lists away"), false, "and one naming a list not loaded this time is not a problem")
  eq(has(table.concat(notes, "\n"), "the keymap lists section 'away' names a list that is not loaded this time"), true,
    "but a routine note")
  eq(has(text, "lists 3 | is not a list name"), true, "a section key that is not a name is named")
  local bad = readLists({ clip = { ["hyper+n"] = 3, ["hyper+zz"] = "selectNext" } })
  eq(has(whys(bad.problems), "lists clip hyper+n | answers a number"), true, "a value that is no action name is named")
  eq(#bad.lists.clip, 0, "and neither unreadable entry is kept")
end

-- The hint bar and the action panel read the bindings the lists section left, so a moved key shows
-- its new chord there too.
do
  local contexts = applied({ clip = { ["hyper+e"] = "deleteSelected" }, all = { ["hyper+n"] = "selectNext" } })
  local plan = { contexts = contexts, effective = {}, order = {}, identity = {} }
  local deps = { chordLabel = function(leader, key, mods)
    return leader .. " " .. ((mods and #mods > 0) and (table.concat(mods, "+") .. "+") or "") .. key
  end, leaderName = "Hyper" }
  local bar = {}
  for _, h in ipairs(hints.footerFor("clip", plan, deps)) do bar[h.action] = h.badges[1] end
  eq(bar.deleteSelected, "Hyper e", "the hint bar spells the moved verb on its new chord")
  eq(bar.selectNext, "Hyper n", "and the moved shared verb too")
  local panel = {}
  for _, row in ipairs(hints.rowsFor("clip", plan, deps)) do panel[row.action or row.title] = row.chord end
  eq(panel.deleteSelected, "Hyper e", "the action panel shows the same chord")
  eq(panel.selectNext, nil, "and lists no navigation verb")
  local kinds = hints.actionKinds({ contexts = applied({ clip = { ["hyper+i"] = false } }) })
  eq(kinds.scrollDown, "verb", "a freed primary leaves an extra a verb")
end

--------------------------------------------------------------------------------
-- List keys on any leader, phase A of the list keys addendum
--------------------------------------------------------------------------------

local HELD = { hyper = true, meta = true, super = true }

-- The list role moves every default list key at once. readConfig takes list as a role word, and
-- applyLists places every default binding on the leader the role lands on, so the keymap's list
-- rows, the leaders in use and the hint bar all read that leader.
do
  local cfg = keymap.readConfig({ roles = { list = "meta" } },
    { catalog = CATALOG, roleWords = { "app", "window", keymap.LIST_ROLE }, keycodes = LIST_KEYCODES })
  eq(#cfg.problems, 0, "list role: list is a role word")
  eq(cfg.roles.list, "META", "list role: it names the held leader it moves to")
  local contexts = lists()
  local problems = keymap.applyLists(contexts, {}, { listLeader = "meta", heldLeaders = HELD, keycodes = LIST_KEYCODES })
  eq(#problems, 0, "list role: placing the defaults is no problem")
  local onMeta, listedOnly = 0, nil
  for _, b in ipairs(contexts.clip.bindings) do
    if b.chord == false then listedOnly = b.leader
    elseif b.leader == "meta" then onMeta = onMeta + 1 end
  end
  eq(onMeta, #contexts.clip.bindings - 1, "list role: every bound default of the list sits on meta")
  eq(listedOnly, nil, "list role: a key the list reads for itself is placed on no leader")
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = contexts, order = {} },
    roles = ROLES, keycodes = LIST_KEYCODES, listLeader = "meta" })
  local leaders = {}
  for _, row in ipairs(result.rows) do if row.layer ~= "global" then leaders[row.leader] = true end end
  eq(leaders.meta and not leaders.hyper, true, "list role: every list row names meta")
  eq(table.concat(keymap.leadersInUse(result), ","), "meta", "list role: so meta is in use and hyper is not")
  local deps = { chordLabel = function(leader, key) return leader .. " " .. key end,
    leaderNames = { hyper = "Hyper", meta = "Meta" }, leaderName = "Hyper" }
  local bar = {}
  for _, h in ipairs(hints.footerFor("clip", { contexts = contexts }, deps)) do bar[h.action] = h.badges[1] end
  eq(bar.selectNext, "Meta j", "list role: the hint bar spells the binding's own leader")
end

-- An explicit chord moves only itself, onto whichever held leader it names, and the rest stay on
-- the list role's leader. Its slot carries its leader, so hyper and n and meta and n are two.
do
  local cfg = readLists({ clip = { ["meta+n"] = "selectNext", ["super+e"] = "deleteSelected", ["hyper+n"] = "selectPrev" } })
  local contexts = lists()
  local problems = keymap.applyLists(contexts, cfg.lists, { listLeader = "hyper", heldLeaders = HELD, keycodes = LIST_KEYCODES })
  eq(#problems, 0, "explicit: chords on three held leaders are accepted")
  local at = {}
  for _, b in ipairs(contexts.clip.bindings) do at[b.action] = tostring(b.leader) .. "+" .. tostring(b.key) end
  eq(at.selectNext, "meta+n", "explicit: selectNext lands on meta")
  eq(at.deleteSelected, "super+e", "explicit: deleteSelected lands on super")
  eq(at.selectPrev, "hyper+n", "explicit: hyper and n is a slot of its own beside meta and n")
  eq(at.insertSelected, "hyper+i", "explicit: every other key stays on the list role's leader")
  eq(at.closeChooser, "hyper+x", "explicit: close too")
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = contexts, order = {} },
    roles = ROLES, keycodes = LIST_KEYCODES, listLeader = "hyper" })
  eq(#result.problems, 0, "explicit: no collision between hyper and n and meta and n in one list")
  eq(table.concat(keymap.leadersInUse(result), ","), "hyper,meta,super", "explicit: every leader a list row names is in use")
end

-- Two rows of one list on one slot of a leader that is not hyper are a collision, named with that
-- leader, and the same pair of the person's own in one table is refused together.
do
  local contexts = { clash = { when = "clashOpen", priority = 100, bindings = {
    { action = "selectNext", key = "j", leader = "meta" },
    { action = "scrollDown", key = "j", leader = "meta" },
    { action = "selectPrev", key = "j", leader = "super" },
  } } }
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = contexts, order = {} },
    roles = ROLES, keycodes = LIST_KEYCODES, listLeader = "hyper" })
  eq(#result.problems, 1, "collision: two rows on meta and j in one list are one problem")
  eq(has(whys(result.problems), "meta+j with any modifiers in clash"), true, "collision: named with its leader")
  local _, problems = applied({ clip = { ["meta+n"] = "selectNext", ["META+N"] = "selectPrev" } },
    { heldLeaders = HELD })
  eq(has(whys(problems), "are two of the person's own chords on one slot of clip"), true,
    "collision: two of the person's own on one meta slot are refused together")
end

--------------------------------------------------------------------------------
-- List keys the open list's own field answers, phase B of the list keys addendum
--------------------------------------------------------------------------------

-- A fake of the default chooser's own answer, the field reading Ctrl and A and the down arrow.
local function fieldUses(key, mods)
  local text = table.concat(mods, "+")
  if key == "a" and text == "ctrl" then return "the field's own moveToStart" end
  if key == "down" then return "the arrow moves the highlight" end
  return nil
end
local FIELD_KEYCODES = {}
do
  local names = { "a", "c", "d", "e", "i", "j", "k", "n", "o", "space", "x", "y", "delete", "p", "down", "tab", "pad1" }
  for i, name in ipairs(names) do FIELD_KEYCODES[name] = i FIELD_KEYCODES[i] = name end
end
local NAMED = { nav = { "ctrl", "shift" } }

local function fieldApplied(section)
  local cfg = keymap.readConfig({ leaders = { nav = { "shift", "ctrl" } }, lists = section },
    { catalog = CATALOG, roleWords = ROLE_WORDS, keycodes = FIELD_KEYCODES })
  local contexts = lists()
  local problems, notes = keymap.applyLists(contexts, cfg.lists, { listLeader = "hyper", heldLeaders = HELD,
    modifierLeaders = NAMED, fieldUses = fieldUses, keycodes = FIELD_KEYCODES })
  for _, p in ipairs(cfg.problems) do problems[#problems + 1] = p end
  return contexts, problems, notes
end

-- What the field may answer and what it refuses, each refusal naming why.
do
  local contexts, problems = fieldApplied({ clip = {
    ["ctrl+j"] = "selectNext", ["nav+k"] = "selectPrev", ["tab"] = "deleteSelected",
    ["y"] = "insertSelected", ["shift+p"] = "insertSelected", ["pad1"] = "insertSelected",
    ["ctrl+a"] = "insertSelected", ["alt+down"] = "insertSelected",
  } })
  local text = whys(problems)
  eq(has(text, "lists clip y | names a key that types a character into the list's field"), true, "field: a printable bare key is refused")
  eq(has(text, "lists clip shift+p | names a key that types a character"), true, "field: Shift alone on a printable key is refused")
  eq(has(text, "lists clip pad1 | names a key that types a character"), true, "field: a keypad digit types too")
  eq(has(text, "lists clip ctrl+a | names a chord the list's field already reads, the field's own moveToStart"), true,
    "field: a chord the field already reads is refused naming what reads it")
  eq(has(text, "lists clip alt+down | names a chord the list's field already reads, the arrow moves the highlight"), true,
    "field: an arrow the chooser reads is refused with modifiers too")
  eq(#problems, 5, "field: and nothing else is refused")
  local at = {}
  for _, b in ipairs(contexts.clip.bindings) do at[b.action] = b end
  eq(at.selectNext.leader, false, "field: a chord of modifiers alone binds on no leader")
  eq(table.concat(at.selectNext.mods, "+"), "ctrl", "field: with its own modifiers")
  eq(at.selectPrev.leader, "nav", "field: a chord on a named leader keeps the leader's name")
  eq(at.deleteSelected.leader, false, "field: a bare key the field does not read is accepted")
  eq(at.insertSelected.leader, "hyper", "field: every refused entry leaves its default where it was")

  -- The keymap's rows for field keys, which put no leader in use and collide by the whole
  -- combination with no leader, so nav and k is ctrl and shift and k.
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = contexts, order = {} },
    roles = ROLES, keycodes = FIELD_KEYCODES, listLeader = "hyper", modifierLeaders = NAMED })
  local rows = {}
  for _, row in ipairs(result.rows) do if row.layer == "clip" then rows[row.action] = row end end
  eq(rows.selectNext.field, true, "field rows: a field key's row says field")
  eq(rows.selectNext.leader, nil, "field rows: modifiers alone name no leader")
  eq(rows.selectPrev.leader, "nav", "field rows: a named leader's chord names it")
  eq(table.concat(keymap.leadersInUse(result), ","), "hyper", "field rows: no field key puts a leader in use")
  local _, clash = fieldApplied({ clip = { ["nav+k"] = "selectPrev", ["ctrl+shift+k"] = "scrollDown" } })
  eq(has(whys(clash), "are two of the person's own chords on one slot of clip"), true,
    "field rows: nav and k and ctrl, shift and k are one slot")

  -- Spelling, the glyph and modifiers alone for no leader, the leader's word for a named one.
  local deps = { chordLabel = function(leader, key, mods) return leader .. " " .. key end,
    glyphFor = function(key, mods) return table.concat(mods or {}, "+") .. "+" .. key end,
    leaderNames = { hyper = "Hyper", nav = "Nav" }, leaderName = "Hyper" }
  local bar = {}
  for _, h in ipairs(hints.footerFor("clip", { contexts = contexts }, deps)) do bar[h.action] = h.badges[1] end
  eq(bar.selectNext, "ctrl+j", "field spelling: modifiers alone read as the glyph and modifiers")
  eq(bar.selectPrev, "Nav k", "field spelling: a named leader reads as its word")
end

-- The watcher the field asks, and the field asking it. It runs a field key only while its list's
-- context is live and only on its exact modifiers, and the field claims the key it took and types
-- nothing, while a key it did not take goes on to the field as before.
do
  local nav = assert(loadfile(here .. "../lib/nav.lua"))()
  local input = assert(loadfile(here .. "../lib/chooser/providers/default/field/input.lua"))()
  local contexts = fieldApplied({ clip = { ["ctrl+j"] = "selectNext", ["nav+k"] = "selectPrev" } })
  local ran = {}
  for _, b in ipairs(contexts.clip.bindings) do
    local action = b.action
    b.fn = function() ran[#ran + 1] = action end
  end
  local open = false
  contexts.clip.when = "clipOpen"
  local watch, keys = nav.fieldKeys(contexts, { keycodes = FIELD_KEYCODES, modifierLeaders = NAMED,
    predicates = { clipOpen = function() return open end } })
  eq(#keys, 2, "watcher: two field keys are listed")
  local function ev(key, flags, chars)
    return { getKeyCode = function() return FIELD_KEYCODES[key] end, getFlags = function() return flags end,
      getCharacters = function() return chars end }
  end
  eq(watch(ev("j", { ctrl = true })), false, "watcher: with its list closed a field key is not taken")
  open = true
  eq(watch(ev("j", { ctrl = true })), true, "watcher: with its list open Ctrl and J is taken")
  eq(ran[#ran], "selectNext", "watcher: and runs that list's binding")
  eq(watch(ev("j", { ctrl = true, alt = true })), false, "watcher: other modifiers are not the chord")
  eq(watch(ev("k", { ctrl = true, shift = true })), true, "watcher: a named leader's key is its whole set")
  eq(ran[#ran], "selectPrev", "watcher: and runs selectPrev")

  local f = input.Field.new({ listKeys = watch })
  eq(f:_handle(ev("j", { ctrl = true }, "j")), true, "field: a key the watcher took is claimed")
  eq(f:getState().text, "", "field: and nothing is typed")
  local before = #ran
  eq(f:_handle(ev("j", {}, "j")), true, "field: a plain J is not the watcher's")
  eq(f:getState().text, "j", "field: so it types as before")
  eq(#ran, before, "field: and runs nothing")
  open = false
  local g = input.Field.new({ listKeys = watch })
  g:_handle(ev("j", { ctrl = true }, "j"))
  eq(#ran, before, "field: with the list's context gone the chord runs nothing")
end

-- The fix round on phase B. fn is refused in a field chord, since the watcher compares only the
-- four real modifiers and fn and J would act on a plain J. Option on a printable key is kept with a
-- routine note. A held key's autorepeat runs only a repeating action and is swallowed otherwise, a
-- binding that raises still claims the key, and a list naming no predicate the watcher can ask is
-- warned about once.
do
  local contexts, problems, notes = fieldApplied({ clip = { ["fn+j"] = "selectNext", ["alt+d"] = "deleteSelected" } })
  eq(has(whys(problems), "lists clip fn+j | names fn, which the list's field does not compare"), true, "fix: fn in a field chord is refused")
  local noteText = table.concat(notes, "\n")
  eq(has(noteText, "lists clip alt+d' takes a chord that types a character into the field"), true,
    "fix: Option on a printable key is accepted with a routine note")
  local at = {}
  for _, b in ipairs(contexts.clip.bindings) do at[b.action] = b end
  eq(at.deleteSelected.leader, false, "fix: and binds for the field")
  eq(at.selectNext.leader, "hyper", "fix: the refused fn entry leaves selectNext where it was")

  local warnings = {}
  local saved = hs
  hs = { logger = { new = function() return {
    w = function(m) warnings[#warnings + 1] = m end, e = function(m) warnings[#warnings + 1] = m end,
    i = function() end } end } }
  local nav = assert(loadfile(here .. "../lib/nav.lua"))()
  hs = saved
  local held = fieldApplied({ clip = { ["ctrl+j"] = "selectNext", ["ctrl+d"] = "deleteSelected", ["ctrl+e"] = "scrollDown" } })
  held.clip.when = "clipOpen"
  local ran = {}
  for _, b in ipairs(held.clip.bindings) do
    local action = b.action
    b.fn = function() ran[#ran + 1] = action end
    if action == "scrollDown" then b.fn = function() error("boom") end end
  end
  local repeating = false
  local watch = nav.fieldKeys(held, { keycodes = FIELD_KEYCODES, predicates = { clipOpen = function() return true end },
    repeats = { selectNext = true }, isRepeat = function() return repeating end })
  local function ev(key, flags)
    return { getKeyCode = function() return FIELD_KEYCODES[key] end, getFlags = function() return flags end }
  end
  repeating = true
  eq(watch(ev("j", { ctrl = true })), true, "repeat: a repeat of a repeating action is taken")
  eq(ran[#ran], "selectNext", "repeat: and runs it")
  local before = #ran
  eq(watch(ev("d", { ctrl = true })), true, "repeat: a repeat of an action that does not repeat is still claimed")
  eq(#ran, before, "repeat: and runs nothing, so a held delete deletes once")
  repeating = false
  eq(watch(ev("d", { ctrl = true })), true, "repeat: the first press runs it")
  eq(ran[#ran], "deleteSelected", "repeat: as deleteSelected")
  local warned = #warnings
  eq(watch(ev("e", { ctrl = true })), true, "raise: a binding that raises still claims the key")
  eq(#warnings, warned + 1, "raise: and is reported")

  local blind = fieldApplied({ clip = { ["ctrl+j"] = "selectNext" } })
  blind.clip.when = "nothingAnswers"
  for _, b in ipairs(blind.clip.bindings) do b.fn = function() end end
  local blindWatch = nav.fieldKeys(blind, { keycodes = FIELD_KEYCODES, predicates = {} })
  warned = #warnings
  eq(blindWatch(ev("j", { ctrl = true })), false, "predicate: a list no predicate answers takes no key")
  blindWatch(ev("j", { ctrl = true }))
  eq(#warnings, warned + 1, "predicate: and says so once")
end

if failures > 0 then
  print(string.format("keymap person, %d check(s), %d failure(s)", checks, failures))
  os.exit(1)
end
print(string.format("keymap person, %d check(s), 0 failure(s)", checks))
