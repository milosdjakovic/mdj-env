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
  local odd = read({ lists = {}, keys = 3 })
  eq(has(whys(odd.problems), "lists | is not a section"), true, "a section Olm does not read is named")
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
-- a, is a bindings override the person wrote in config/plugins.lua, so it is the person's own.
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
    identity = {}, provenance = { toggler = { bindings = "user" } },
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
  -- A keymap entry ranks above every other source of the person's, so it takes the slot of a
  -- binding the person wrote in config/plugins.lua.
  local toggle = build({ keys = { ["hyper+A"] = "vpn.open" } })
  eq(#toggle.problems, 0, "an entry on a slot the person's own binding holds is no problem")
  eq(chordsOf(toggle, "toggler", "Safari"), "", "that binding's row there is dropped")
  eq(chordsOf(toggle, "vpn", "open"), "hyper+a with any modifiers", "and the entry takes the slot")
  eq(has(noteText(toggle), "takes hyper+a with any modifiers, so the person's own toggler.Safari is not bound there"), true,
    "said in the same routine line a displaced default gets")
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

if failures > 0 then
  print(string.format("keymap person, %d check(s), %d failure(s)", checks, failures))
  os.exit(1)
end
print(string.format("keymap person, %d check(s), 0 failure(s)", checks))
