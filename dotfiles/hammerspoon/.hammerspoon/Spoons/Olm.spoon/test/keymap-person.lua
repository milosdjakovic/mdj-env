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
-- The allow list and the allocation are lib/keyremap.lua's, handed to the reader the way the root
-- hands them, so this file keeps no list of keys of its own. The remap needs only a logger.
hs = { logger = { new = function() return setmetatable({}, { __index = function() return function() end end }) end } }
local KeyRemap = assert(loadfile(here .. "../lib/keyremap.lua"))()

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

-- The leaders Olm ships, in the shape root/compose.lua's SHIPPED_LEADERS has, and the keys
-- lib/keyremap.lua allows.
local SHIPPED = {
  hyper = { key = "capsLock", ranked = true, sheet = true,
    sheetLayout = { columns = 4, colWidth = 215 } },
  meta = { key = "rightOption", drivenRepeat = true, sheet = true, sheetLayout = { columns = 2 } },
  super = { key = "rightCommand", drivenRepeat = true },
}
local SOURCES = KeyRemap.sources()
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
  return keymap.readConfig(config, { leaders = SHIPPED, sources = SOURCES, allocate = KeyRemap.allocate,
    roleWords = ROLE_WORDS, keycodes = KEYCODES })
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
  eq(#empty.keys + #empty.problems, 0, "no file is no keys and no problems")
  eq(#empty.leaders, 3, "and the shipped leaders alone")
  local sections = read({ keys = {}, leaders = {}, roles = {}, aliases = {} })
  eq(#sections.problems, 0, "every section present and empty is no problem")

  eq(has(whys(read("nope").problems), "rather than a table"), true, "a file that is not a table is named")
  local odd = read({ chords = {}, keys = 3 })
  eq(has(whys(odd.problems), "chords | is not a section"), true, "a section Olm does not read is named")
  eq(has(whys(odd.problems), "keys | is a number"), true, "a section that is not a table is named")
end

-- Every leader of a read, by name.
local function byName(r)
  local out = {}
  for _, l in ipairs(r.leaders) do out[l.name] = l end
  return out
end

do
  local r = read({ leaders = {
    nav = { "Shift", "ctrl" },
    shift = { "ctrl" },
    app = { "ctrl" },
    empty = {},
    spacey = { "space" },
    fnny = { "fn" },
    ["1x"] = { "ctrl" },
  } })
  local by = byName(r)
  eq(#r.leaders, 4, "the three shipped leaders and the one good one are read")
  eq(table.concat(by.nav.mods, "+"), "ctrl+shift", "the good one, its modifiers lowercased and sorted")
  local text = whys(r.problems)
  eq(has(text, "leaders shift | is a modifier word"), true, "a modifier word is refused")
  eq(has(text, "leaders app | is a role word"), true, "a role word is refused")
  eq(has(text, "leaders empty | states neither mods nor key"), true, "an empty entry is refused")
  eq(has(text, "leaders spacey | is a modifier word") or has(text, "leaders spacey | has mods holding 'space'"), true, "a non modifier is refused")
  eq(has(text, "leaders fnny | has mods holding 'fn'"), true, "fn is no part of a leader's own set")
  eq(has(text, "leaders 1x | is not a name"), true, "a name that is not a word is refused")
  eq(has(text, "hyper"), false, "no shipped name is refused as reserved")
end

-- The leaders section laid over the shipped table, phase 1 of the leaders plan.
do
  -- An empty section and no section answer the shipped leaders exactly, behaviour included.
  for _, config in ipairs({ {}, { leaders = {} } }) do
    local r = read(config)
    local by = byName(r)
    eq(#r.problems, 0, "shipped: an empty section is no problem")
    eq(#r.notes, 0, "shipped: and no note")
    eq(table.concat({ r.leaders[1].name, r.leaders[2].name, r.leaders[3].name }, ","), "hyper,meta,super",
      "shipped: the held leaders come in name order")
    eq(by.hyper.key, "capsLock", "shipped: hyper is Caps Lock")
    eq(by.hyper.mods, nil, "shipped: a held leader has no mods")
    eq(by.hyper.policy.ranked, true, "shipped: hyper keeps its behaviour")
    eq(by.hyper.policy.sheetLayout.columns, 4, "shipped: and its sheet layout")
    eq(by.meta.policy.drivenRepeat, true, "shipped: meta drives its repeats")
    eq(by.super.key, "rightCommand", "shipped: super is Right Command")
  end
  -- Shipping must not be edited by a read.
  eq(SHIPPED.hyper.sheetLayout.columns, 4, "shipped: the shipped table is left as it was")

  -- A behaviour field merges over the shipped entry, one field at a time.
  local r = read({ leaders = { hyper = { ranked = false, sheetLayout = { columns = 3 } }, meta = { sheet = false } } })
  local by = byName(r)
  eq(#r.problems, 0, "merge: behaviour fields alone are no problem")
  eq(by.hyper.key, "capsLock", "merge: the trigger stays the shipped one")
  eq(by.hyper.policy.ranked, false, "merge: a stated field wins")
  eq(by.hyper.policy.sheet, true, "merge: an unstated field keeps the shipped value")
  eq(by.hyper.policy.sheetLayout.columns, 3, "merge: a layout field is laid over")
  eq(by.hyper.policy.sheetLayout.colWidth, 215, "merge: and the other layout fields are kept")
  eq(by.meta.policy.sheet, false, "merge: a sheet is switched off by stating false")
  eq(by.meta.policy.drivenRepeat, true, "merge: beside the shipped repeat")
  eq(SHIPPED.hyper.sheetLayout.columns, 4, "merge: the shipped layout is not shared with the result")

  -- A key replaces the trigger as one and keeps the behaviour.
  r = read({ leaders = { hyper = { key = "rightControl" }, meta = { key = "f13", drivenRepeat = false } } })
  by = byName(r)
  eq(#r.problems, 0, "key: a known source is no problem")
  eq(by.hyper.key, "rightControl", "key: the trigger is replaced")
  eq(by.hyper.policy.ranked, true, "key: the behaviour stays")
  eq(by.meta.key, "f13", "key: another leader likewise")
  eq(by.meta.policy.drivenRepeat, false, "key: with its own field stated")

  -- A new name starts with every behaviour off, whichever kind.
  r = read({ leaders = { pedal = { key = "rightControl", sheet = true }, nav = { mods = { "shift", "ctrl" } } } })
  by = byName(r)
  eq(#r.problems, 0, "new: a held and a modifier leader read")
  eq(by.pedal.key, "rightControl", "new: a held leader names its key")
  eq(by.pedal.policy.sheet, true, "new: and states its own behaviour")
  eq(by.pedal.policy.ranked, nil, "new: every other behaviour is off")
  eq(by.pedal.shipped, nil, "new: and it is not a shipped leader")
  eq(table.concat(by.nav.mods, "+"), "ctrl+shift", "new: a modifier leader names its mods")
  eq(next(by.nav.policy), nil, "new: with no behaviour")
  eq(table.concat({ r.leaders[1].name, r.leaders[2].name, r.leaders[3].name, r.leaders[4].name, r.leaders[5].name }, ","),
    "hyper,meta,pedal,super,nav", "new: held leaders come first and then the modifier ones")
  r = read({ roles = { window = "pedal" }, leaders = { pedal = { key = "rightControl" } } })
  eq(r.roles.window, "PEDAL", "new: a role may land on a new held leader")

  -- Today's form, a bare list, is read as mods with a routine note and no problem.
  r = read({ leaders = { nav = { "shift", "ctrl" } } })
  eq(#r.problems, 0, "bare: a bare list is no problem")
  eq(table.concat(byName(r).nav.mods, "+"), "ctrl+shift", "bare: it is read as mods")
  eq(#r.notes, 1, "bare: and said once")
  eq(has(r.notes[1], "write mods = { ... }") or has(r.notes[1], "mods = { ... }"), true, "bare: the note says what to write")
  eq(has(r.notes[1], "leaders nav"), true, "bare: and names the entry")

  -- Both fields or neither is a problem and the leader keeps its shipped default.
  r = read({ leaders = { hyper = { mods = { "shift" }, key = "capsLock", ranked = false },
    pedal = { mods = { "ctrl" }, key = "capsLock" }, bare = { sheet = true } } })
  by = byName(r)
  local text = whys(r.problems)
  eq(has(text, "leaders hyper | states both mods and key"), true, "both: said for a shipped name")
  eq(has(text, "so the shipped default is kept"), true, "both: the shipped default is kept")
  eq(by.hyper.policy.ranked, true, "both: and none of its fields applied")
  eq(by.pedal, nil, "both: a new name is ignored")
  eq(has(text, "leaders bare | states neither mods nor key"), true, "neither: said, and the entry ignored")
  eq(by.bare, nil, "neither: a new name is ignored")

  -- A shipped name may change kind. Hyper written as the four modifiers leaves the held leaders,
  -- the trigger replaces whole and the shipped behaviour stays unless the entry says otherwise.
  r = read({ leaders = { hyper = { mods = { "shift", "ctrl", "alt", "cmd" }, sheet = false } } })
  by = byName(r)
  eq(#r.problems, 0, "kind: a modifier Hyper is no problem")
  eq(table.concat(by.hyper.mods, "+"), "alt+cmd+ctrl+shift", "kind: hyper holds the four modifiers")
  eq(by.hyper.key, nil, "kind: the shipped key is dropped with the trigger")
  eq(by.hyper.remapTo, nil, "kind: and no remap is asked for")
  eq(by.hyper.policy.ranked, true, "kind: the shipped behaviour merges")
  eq(by.hyper.policy.sheet, false, "kind: and the entry's own field wins")
  eq(by.hyper.policy.sheetLayout.columns, 4, "kind: the layout stays")
  eq(r.allocation.leaders.hyper, nil, "kind: a leader of modifiers takes no function key")
  eq(r.leaders[#r.leaders].name, "hyper", "kind: it is listed among the modifier leaders, after the held ones")
  r = read({ leaders = { hyper = { mods = { "shift" } } } })
  eq(table.concat(byName(r).hyper.mods, "+"), "shift", "kind: a bare list on a shipped name is read as mods")
  -- The other way round, a name that ships mods may take a key.
  local MODS_SHIPPED = { hyper = { mods = { "ctrl", "alt" }, ranked = true }, meta = SHIPPED.meta }
  r = keymap.readConfig({ leaders = { hyper = { key = "capsLock" } } }, { leaders = MODS_SHIPPED, sources = SOURCES,
    allocate = KeyRemap.allocate, roleWords = ROLE_WORDS, keycodes = KEYCODES })
  by = byName(r)
  eq(#r.problems, 0, "kind: a shipped modifier leader may take a key")
  eq(by.hyper.key, "capsLock", "kind: the key replaces the mods")
  eq(by.hyper.mods, nil, "kind: and the mods are dropped")
  eq(by.hyper.policy.ranked, true, "kind: with the behaviour kept")
  -- A conflict the allocation refuses restores the shipped trigger of whichever kind it was.
  r = keymap.readConfig({ leaders = { hyper = { key = "rightOption" } } }, { leaders = MODS_SHIPPED, sources = SOURCES,
    allocate = KeyRemap.allocate, roleWords = ROLE_WORDS, keycodes = KEYCODES })
  by = byName(r)
  eq(has(whys(r.problems), "leaders hyper"), true, "kind: two leaders on one key are said")
  eq(table.concat(by.hyper.mods or {}, "+"), "alt+ctrl", "kind: the shipped mods come back")
  eq(by.hyper.key, nil, "kind: and no key stays")

  -- A key off the allow list is a problem line naming the keys it allows.
  r = read({ leaders = { hyper = { key = "space" }, pedal = { key = "a" }, odd = { key = 3 }, low = { key = "f12" },
    left = { key = "leftCommand" } } })
  by = byName(r)
  text = whys(r.problems)
  eq(has(text, "leaders hyper | has a key of 'space', which is not a key Olm can make a leader"), true, "allow: a key off the list is named")
  eq(has(text, "capsLock, f13, f14, f15, f16, f17, f18, f19, f20, rightCommand, rightControl, rightOption"), true,
    "allow: with the keys it allows, from keyremap")
  eq(has(text, "leaders low | has a key of 'f12'"), true, "allow: F12 carries brightness and is refused")
  eq(has(text, "leaders left | has a key of 'leftCommand'"), true, "allow: a left modifier is refused")
  eq(by.hyper.key, "capsLock", "allow: a shipped leader keeps its key")
  eq(by.pedal, nil, "allow: a new name is ignored")
  eq(by.odd, nil, "allow: a key that is no word is ignored")
  eq(by.low, nil, "allow: F12 is ignored")
  for _, name in ipairs({ "capsLock", "rightCommand", "rightOption", "rightControl", "f13", "f14", "f15", "f16",
    "f17", "f18", "f19", "f20" }) do
    r = read({ leaders = { pedal = { key = name } } })
    if name == "capsLock" or name == "rightCommand" or name == "rightOption" then
      eq(byName(r).pedal, nil, "allow: " .. name .. " is a shipped leader's key, so a new one on it is refused")
    else
      eq(byName(r).pedal ~= nil and #r.problems == 0, true, "allow: " .. name .. " is admitted")
    end
  end

  -- remapTo is a trigger field, read beside key.
  r = read({ leaders = { hyper = { key = "capsLock", remapTo = "f19" } } })
  by = byName(r)
  eq(#r.problems, 0, "remapTo: a pin on a remapped key is no problem")
  eq(by.hyper.remapTo, "f19", "remapTo: it is kept on the entry")
  eq(r.allocation.leaders.hyper.fkey, "f19", "remapTo: and the allocation honours it")
  eq(r.allocation.leaders.meta.fkey, "f16", "remapTo: the others keep their keys")
  -- It replaces together with key, so a later key on the entry drops it, and behaviour alone keeps the shipped one.
  r = read({ leaders = { hyper = { key = "rightControl" } } })
  eq(byName(r).hyper.remapTo, nil, "remapTo: a key stated without it states none")
  r = read({ leaders = { hyper = { remapTo = "f19" } } })
  text = whys(r.problems)
  eq(has(text, "leaders hyper | states remapTo without a key"), true, "remapTo: alone it is refused")
  eq(has(text, "so the shipped default is kept"), true, "remapTo: and the shipped default is kept")
  eq(byName(r).hyper.remapTo, nil, "remapTo: so it is not set")
  r = read({ leaders = { nav = { mods = { "ctrl" }, remapTo = "f19" } } })
  eq(has(whys(r.problems), "leaders nav | states remapTo beside mods"), true, "remapTo: beside mods is refused")
  eq(byName(r).nav, nil, "remapTo: and the new leader is ignored")
  r = read({ leaders = { hyper = { key = "capsLock", remapTo = "f12" }, pedal = { key = "f13", remapTo = "f14" } } })
  by = byName(r)
  text = whys(r.problems)
  eq(has(text, "leaders hyper | has a remapTo of 'f12', which is not one of f13 to f20, so the shipped default is kept"), true,
    "remapTo: a key off F13 to F20 is refused and the shipped default kept")
  eq(by.hyper.key, "capsLock", "remapTo: Hyper is back on Caps Lock")
  eq(by.hyper.remapTo, nil, "remapTo: with no pin")
  eq(has(text, "leaders pedal | has a remapTo beside the key f13, which is a function key already and is not remapped, so it is ignored"), true,
    "remapTo: beside a function key is refused and the new leader ignored")
  eq(by.pedal, nil, "remapTo: so the pedal is not read")
  eq(r.allocation.leaders.hyper.fkey, "f18", "remapTo: and the allocation is the shipped one")

  -- Two leaders on one physical key, or one function key, drop both person entries.
  r = read({ leaders = { pedal = { key = "f13" }, foot = { key = "f13" } } })
  by = byName(r)
  text = whys(r.problems)
  eq(has(text, "leaders foot | shares the key f13 with foot, pedal"), true, "conflict: two pedals on F13, the first named")
  eq(has(text, "leaders pedal | shares the key f13 with foot, pedal"), true, "conflict: and the second")
  eq(by.pedal == nil and by.foot == nil, true, "conflict: both new leaders are dropped")
  r = read({ leaders = { hyper = { key = "rightOption" } } })
  by = byName(r)
  eq(has(whys(r.problems), "leaders hyper | shares the key rightOption with hyper, meta, and a key is one leader's, so the shipped default is kept"), true,
    "conflict: Hyper on the key Meta ships on is refused")
  eq(by.hyper.key, "capsLock", "conflict: Hyper keeps Caps Lock")
  eq(by.meta.key, "rightOption", "conflict: and Meta keeps what it ships")
  eq(has(whys(r.problems), "leaders meta"), false, "conflict: the shipped leader gets no line of its own")
  r = read({ leaders = { hyper = { key = "rightControl" }, meta = { key = "rightControl" } } })
  by = byName(r)
  eq(by.hyper.key .. "," .. by.meta.key, "capsLock,rightOption", "conflict: both shipped leaders go back to their defaults")
  eq(#r.problems, 2, "conflict: one line each")
  r = read({ leaders = { hyper = { key = "capsLock", remapTo = "f19" }, meta = { key = "rightOption", remapTo = "f19" } } })
  eq(has(whys(r.problems), "leaders hyper | has a remapTo of f19, which hyper, meta all name"), true, "conflict: two pins on F19")
  eq(byName(r).hyper.remapTo == nil and byName(r).meta.remapTo == nil, true, "conflict: both pins dropped")
  r = read({ leaders = { pedal = { key = "f13" }, hyper = { key = "capsLock", remapTo = "f13" } } })
  by = byName(r)
  text = whys(r.problems)
  eq(has(text, "leaders hyper | has a remapTo of f13, which leader pedal uses directly"), true, "conflict: a pin on a direct key, the pin")
  eq(has(text, "leaders pedal | uses f13 directly, which leader hyper names as its remapTo"), true, "conflict: and the pedal")
  eq(by.pedal == nil and by.hyper.remapTo == nil, true, "conflict: both entries dropped")
  -- A dropped entry can bring a shipped default back onto another person's key, which is dropped in turn.
  r = read({ leaders = { hyper = { key = "f13" }, meta = { key = "f13" }, extra = { key = "capsLock" } } })
  by = byName(r)
  eq(by.hyper.key .. "," .. by.meta.key, "capsLock,rightOption", "chain: the shipped defaults come back")
  eq(by.extra, nil, "chain: and a new leader on a key that came back is dropped")
  eq(#r.problems, 3, "chain: one line each")

  -- The allocation notes reach the reader's notes, and the tap field is retired.
  r = read({ leaders = { hyper = { key = "capsLock", remapTo = "f16" } } })
  eq(#r.notes, 1, "note: a taken preferred target is one note")
  eq(has(r.notes[1], "leader meta on rightOption prefers f16, which is in use, so it takes f13"), true, "note: it names the fallback")
  r = read({ leaders = { hyper = { tapTogglesCapsLock = true, ranked = false }, pedal = { key = "f13", tapTogglesCapsLock = true } } })
  by = byName(r)
  text = whys(r.problems)
  eq(has(text, "leaders hyper | has tapTogglesCapsLock, which is retired"), true, "tap: the retired field is one problem line")
  eq(has(text, "a quick tap toggles Caps Lock when the key is capsLock"), true, "tap: saying the tap follows the key")
  eq(#r.problems, 2, "tap: one line per entry stating it")
  eq(by.hyper.policy.tapTogglesCapsLock, nil, "tap: the field is ignored")
  eq(by.hyper.policy.ranked, false, "tap: and the rest of the entry is read")
  eq(by.pedal.policy.tapTogglesCapsLock, nil, "tap: on a new leader too")

  -- No name is reserved, a built in name is only a name when it is not shipped.
  r = keymap.readConfig({ leaders = { hyper = { key = "capsLock" }, super = { mods = { "ctrl" } }, Nav = { mods = { "ctrl" } },
    nav = { mods = { "alt" } } } }, { leaders = {}, sources = SOURCES, roleWords = ROLE_WORDS, keycodes = KEYCODES })
  by = byName(r)
  eq(by.hyper.key, "capsLock", "names: hyper is an ordinary name when nothing ships it")
  eq(table.concat(by.super.mods, "+"), "ctrl", "names: so is super")
  eq(has(whys(r.problems), "leaders nav | names a leader already named in another case"), true, "names: the same name in two cases is refused")
  eq(by.Nav, nil, "names: and kept lowercase")
  eq(by.nav ~= nil or by.Nav ~= nil, true, "names: one of the two is read")
  eq(has(whys(r.problems), "reserved"), false, "names: nothing is reserved")
end

do
  local r = read({ roles = { window = "super", app = "Hyper", foo = "meta", bar = 3 } })
  eq(r.roles.window, "SUPER", "a role moves to the catalog name of a held leader")
  eq(r.roles.app, "HYPER", "named without case")
  local text = whys(r.problems)
  eq(has(text, "roles foo | is not a role"), true, "a role word no default names is refused")
  eq(has(text, "roles bar | is not a role"), true, "and so is any other key")
  local ok = keymap.readConfig({ roles = { window = "nav", list = "hyper" }, leaders = { nav = { mods = { "ctrl" } },
    hyper = { mods = { "shift", "ctrl", "alt", "cmd" } } } }, { leaders = SHIPPED, sources = SOURCES,
    allocate = KeyRemap.allocate, roleWords = { "app", "window", "list" }, keycodes = KEYCODES })
  eq(ok.roles.window, "NAV", "a role may name a leader of modifiers, by the same upper cased name")
  eq(ok.roles.list, "HYPER", "the list role lands on a modifier Hyper, known by the name a held one has")
  eq(#ok.problems, 0, "and that is no problem")
  local bad = read({ roles = { window = "nobody" } })
  eq(bad.roles.window, nil, "a role naming no leader is refused")
  eq(has(whys(bad.problems), "which is no leader"), true, "since a role moves to a leader that exists")
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
local labelsLib = assert(loadfile(here .. "../lib/labels.lua"))()
local LIST_KEYCODES = {}
do
  local names = { "a", "c", "d", "e", "i", "j", "k", "n", "o", "space", "x", "y", "delete", "p", "/" }
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
    { leaders = SHIPPED, sources = SOURCES, roleWords = ROLE_WORDS, keycodes = LIST_KEYCODES })
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
  eq(table.concat(order, ","), "insertSelected,selectNext,selectPrev,scrollDown,deleteSelected,leavePage,closeChooser,openActionPanel,showKeys",
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

-- The action bar's key panel and the action panel read the bindings the lists section left, so a
-- moved key shows its new chord there too.
do
  local contexts = applied({ clip = { ["hyper+e"] = "deleteSelected" }, all = { ["hyper+n"] = "selectNext" } })
  local plan = { contexts = contexts, effective = {}, order = {}, identity = {} }
  local deps = { chordLabel = function(leader, key, mods)
    return leader .. " " .. ((mods and #mods > 0) and (table.concat(mods, "+") .. "+") or "") .. key
  end, leaderName = "Hyper" }
  local bar = {}
  for _, h in ipairs(hints.footerModel("clip", plan, deps).keys) do if h.action then bar[h.action] = h.badges[1] end end
  eq(bar.deleteSelected, "Hyper e", "the key panel spells the moved verb on its new chord")
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
-- rows, the leaders in use and the key panel all read that leader.
do
  local cfg = keymap.readConfig({ roles = { list = "meta" } },
    { leaders = SHIPPED, sources = SOURCES, roleWords = { "app", "window", keymap.LIST_ROLE }, keycodes = LIST_KEYCODES })
  eq(#cfg.problems, 0, "list role: list is a role word")
  eq(cfg.roles.list, "META", "list role: it names the held leader it moves to")
  local contexts = lists()
  local problems = keymap.applyLists(contexts, {}, { listLeader = "meta", heldLeaders = HELD, keycodes = LIST_KEYCODES })
  eq(#problems, 0, "list role: placing the defaults is no problem")
  local onMeta, listedOnly, onField = 0, nil, 0
  for _, b in ipairs(contexts.clip.bindings) do
    if b.chord == false then listedOnly = b.leader
    elseif b.leader == false then onField = onField + 1
    elseif b.leader == "meta" then onMeta = onMeta + 1 end
  end
  eq(onMeta, #contexts.clip.bindings - 1 - onField, "list role: every bound default of the list sits on meta, the field's own keys apart")
  eq(onField, 1, "list role: showKeys is the one default the field answers on no leader")
  eq(listedOnly, nil, "list role: a key the list reads for itself is placed on no leader")
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = contexts, order = {} },
    roles = ROLES, keycodes = LIST_KEYCODES, listLeader = "meta" })
  local leaders = {}
  for _, row in ipairs(result.rows) do if row.layer ~= "global" and row.leader then leaders[row.leader] = true end end
  eq(leaders.meta and not leaders.hyper, true, "list role: every list row names meta")
  eq(table.concat(keymap.leadersInUse(result), ","), "meta", "list role: so meta is in use and hyper is not")
  local deps = { chordLabel = function(leader, key) return leader .. " " .. key end,
    leaderNames = { hyper = "Hyper", meta = "Meta" }, leaderName = "Hyper" }
  local bar = {}
  for _, h in ipairs(hints.footerModel("clip", { contexts = contexts }, deps).keys) do if h.action then bar[h.action] = h.badges[1] end end
  eq(bar.selectNext, "Meta j", "list role: the key panel spells the binding's own leader")
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
    { leaders = SHIPPED, sources = SOURCES, roleWords = ROLE_WORDS, keycodes = FIELD_KEYCODES })
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
  for _, h in ipairs(hints.footerModel("clip", { contexts = contexts }, deps).keys) do if h.action then bar[h.action] = h.badges[1] end end
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

-- A leader on two triggers, phase 1 of docs/PLAN-MACHINES.md. Hyper and META ship on a held key and
-- a set of modifiers at once, written as triggers, and the reader holds such a leader as one with
-- both a key and mods, among the held leaders.
do
  local BOTH = {
    hyper = { triggers = { { key = "capsLock" }, { mods = { "shift", "ctrl", "alt", "cmd" } } }, ranked = true },
    meta = { triggers = { { key = "rightOption" }, { mods = { "shift", "ctrl", "alt" } } }, drivenRepeat = true },
    super = { key = "rightCommand" },
  }
  local function readBoth(config)
    return keymap.readConfig(config, { leaders = BOTH, sources = SOURCES, allocate = KeyRemap.allocate,
      roleWords = ROLE_WORDS, keycodes = KEYCODES })
  end
  local r = readBoth({})
  local by = byName(r)
  eq(#r.problems, 0, "triggers: the shipped pair is no problem")
  eq(by.hyper.key, "capsLock", "triggers: hyper keeps its key")
  eq(table.concat(by.hyper.mods, "+"), "alt+cmd+ctrl+shift", "triggers: beside its four modifiers")
  eq(table.concat(by.meta.mods, "+"), "alt+ctrl+shift", "triggers: and meta its three")
  eq(by.hyper.policy.triggers, nil, "triggers: the list is no behaviour field")
  eq(by.hyper.policy.ranked, true, "triggers: the behaviour stays beside it")
  eq(r.allocation.leaders.hyper.fkey, "f18", "triggers: the held half is placed on its function key as before")
  eq(r.allocation.leaders.meta.fkey, "f16", "triggers: meta's too")
  eq(table.concat({ r.leaders[1].name, r.leaders[2].name, r.leaders[3].name }, ","), "hyper,meta,super",
    "triggers: a leader on both is listed among the held leaders")
  local chord = keymap.parseChord("hyper+shift+4", { hyper = true }, KEYCODES)
  eq(chord and chord.leader, "hyper", "triggers: a chord on it still reads as a held leader's")

  -- key or mods alone replaces both halves, and triggers replaces both with its list.
  r = readBoth({ leaders = { hyper = { key = "capsLock" }, meta = { mods = { "shift", "ctrl", "alt" } } } })
  by = byName(r)
  eq(#r.problems, 0, "triggers: a single form is no problem")
  eq(by.hyper.mods, nil, "triggers: key alone drops the modifier half")
  eq(by.meta.key, nil, "triggers: mods alone drops the held half")
  eq(r.allocation.leaders.meta, nil, "triggers: and leaves the allocation")
  r = readBoth({ leaders = { super = { triggers = { { key = "rightCommand", remapTo = "f19" }, { mods = { "ctrl", "cmd" } } } },
    hyper = { triggers = { { mods = { "shift", "ctrl", "alt", "cmd" } } } } } })
  by = byName(r)
  eq(#r.problems, 0, "triggers: a person's list is no problem")
  eq(by.super.key, "rightCommand", "triggers: it states the held half")
  eq(table.concat(by.super.mods, "+"), "cmd+ctrl", "triggers: and the modifier half")
  eq(r.allocation.leaders.super.fkey, "f19", "triggers: a remapTo inside the key trigger is honoured")
  eq(by.hyper.key, nil, "triggers: a list of one replaces both with that one")
  eq(table.concat(by.hyper.mods, "+"), "alt+cmd+ctrl+shift", "triggers: the modifiers")

  -- Malformed lists are refused and the shipped default is kept.
  r = readBoth({ leaders = {
    hyper = { triggers = { { key = "capsLock" }, { key = "rightControl" } } },
    meta = { triggers = { { mods = { "shift" } }, { mods = { "ctrl" } } } },
    super = { triggers = { { key = "rightCommand" }, { mods = { "ctrl" } }, { key = "f13" } } },
    pedal = { triggers = { { key = "f13", mods = { "ctrl" } } } },
    nav = { triggers = { mods = { "ctrl" } } },
    odd = { triggers = "capsLock" },
    side = { triggers = { { key = "f14" } }, key = "f14" },
    far = { triggers = { { key = "f15" } }, remapTo = "f19" },
    soft = { triggers = { { mods = { "ctrl" }, remapTo = "f19" } } },
    typo = { triggers = { { keys = "f13" } } },
    low = { triggers = { { key = "f12" }, { mods = { "fn" } } } },
  } })
  by = byName(r)
  local text = whys(r.problems)
  eq(has(text, "leaders hyper | has two triggers of key"), true, "malformed: two keys are refused")
  eq(by.hyper.key, "capsLock", "malformed: and hyper keeps its shipped key")
  eq(by.hyper.mods ~= nil, true, "malformed: and its shipped modifiers")
  eq(has(text, "leaders meta | has two triggers of mods"), true, "malformed: two sets of mods are refused")
  eq(has(text, "leaders super | has more than two triggers"), true, "malformed: three triggers are refused")
  eq(has(text, "leaders pedal | has a trigger, number 1, that states both mods and key"), true,
    "malformed: one trigger holding both is refused")
  eq(by.pedal, nil, "malformed: and a new name is ignored")
  eq(has(text, "leaders nav | has triggers that are not a list"), true, "malformed: a table that is no list is refused")
  eq(has(text, "leaders odd | has triggers that are not a list"), true, "malformed: a string is refused")
  eq(has(text, "leaders side | states triggers beside mods, key or remapTo"), true, "malformed: triggers beside key is refused")
  eq(has(text, "leaders far | states triggers beside mods, key or remapTo"), true, "malformed: remapTo outside the list is refused")
  eq(has(text, "leaders soft | has a trigger, number 1, that states remapTo beside mods"), true,
    "malformed: remapTo inside a mods trigger is refused")
  eq(has(text, "leaders typo | has a trigger, number 1, that states 'keys'"), true, "malformed: an unknown field is refused")
  eq(has(text, "leaders low | has a key of 'f12'"), true, "malformed: a key off the allow list is refused inside the list")
  eq(#r.problems, 11, "malformed: one problem per entry")
end

-- The collision check once a leader listens on modifiers too. A meta row adding cmd and a hyper row
-- on the same key are one physical combination when both leaders listen on modifiers, and so are a
-- hyper row and a plain combo of the four, while a row the modifier half leaves to the held key
-- claims nothing there.
do
  local COMPOSITE = { hyper = { "alt", "cmd", "ctrl", "shift" }, meta = { "alt", "ctrl", "shift" } }
  local function row(leader, key, mods, owner, extra)
    local list, anyMods = keymap.mods(mods)
    local r = { layer = "global", leader = leader, key = key, mods = list, anyMods = anyMods, owner = owner, action = "open" }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local problems = keymap.collisions({ row("hyper", "k", nil, "kitty"), row("meta", "k", { "cmd" }, "keep") }, {}, COMPOSITE)
  eq(#problems, 1, "physical: a meta row adding cmd and a hyper row on one key are one problem")
  eq(has(whys(problems), "'kitty' action 'open' on hyper+k with any modifiers and 'keep' action 'open' on meta+cmd+k both claim alt+cmd+ctrl+shift+k"),
    true, "physical: naming both rows and the combination")
  eq(#keymap.collisions({ row("hyper", "k", nil, "kitty"), row("meta", "k", { "cmd" }, "keep") }, {}, {}), 0,
    "physical: with no leader on modifiers the two never meet")
  problems = keymap.collisions({ row("hyper", "k", {}, "kitty"), row(nil, "k", { "shift", "ctrl", "alt", "cmd" }, "plain") }, {}, COMPOSITE)
  eq(#problems, 1, "physical: a hyper row and a plain combo of the four are one problem")
  problems = keymap.collisions({ row("hyper", "k", { "cmd" }, "preview"), row("meta", "k", { "cmd" }, "keep") }, {}, COMPOSITE)
  eq(#problems, 0, "physical: a hyper row asking for cmd is left to the held key and claims nothing on modifiers")
  problems = keymap.collisions({ row("hyper", "k", nil, "kitty"), row("hyper", "k", {}, "other") }, {}, COMPOSITE)
  eq(#problems, 0, "physical: a catch all and an exact row on one leader are no pair, the resolver picks between them")
  problems = keymap.collisions({ row("hyper", "k", nil, "kitty"), row("nav", "k", { "cmd" }, "keep") },
    { nav = { "alt", "ctrl", "shift" } }, COMPOSITE)
  eq(#problems, 1, "physical: a modifier leader's row on the same combination is one problem")
  problems = keymap.collisions({ row("hyper", "k", nil, "kitty", { entry = "hyper+k" }), row("meta", "k", { "cmd" }, "keep", { entry = "meta+cmd+k" }) }, {}, COMPOSITE)
  eq(has(whys(problems), "config/keymap.lua keys meta+cmd+k |"), true, "physical: a person's row is named by its entry")
end

--------------------------------------------------------------------------------
-- The action bar, docs/PLAN-ACTION-BAR.md, the secondary, showKeys and the footer model
--------------------------------------------------------------------------------

-- A list declaring a secondary gets it right after the primary on Olm's own Command and Return, a
-- field key on no leader, and every list gets showKeys on the list role. applyLists leaves the
-- secondary on no leader, and the keymap reads it as a field row.
local function barList(decl)
  return assert(surface.context("bar", decl, nil, keymap.listDefaults))
end
do
  local block = barList({
    primary = { action = "insertSelected", description = "Choose Files" },
    secondary = { action = "uninstall", description = "Uninstall" },
    extra = { { key = "d", action = "deleteSelected", description = "Delete" } },
  })
  local order = {}
  for _, b in ipairs(block.bindings) do order[#order + 1] = b.action end
  eq(table.concat(order, ","), "insertSelected,uninstall,uninstall,selectNext,selectPrev,deleteSelected,closeChooser,openActionPanel,showKeys",
    "bar: the secondary sits right after the primary, on two keys, and showKeys comes last")
  local secondary, padSecondary, show
  for _, b in ipairs(block.bindings) do
    if b.shared == "secondary" then
      if secondary then padSecondary = b else secondary = b end
    end
    if b.shared == "showKeys" then show = b end
  end
  eq(secondary and secondary.key, "return", "bar: the secondary sits on Return")
  eq(padSecondary and padSecondary.key, "padenter", "bar: and on keypad Enter, which chooses the row as Return does")
  eq(padSecondary and table.concat(padSecondary.mods, "+") .. tostring(padSecondary.leader), "cmdfalse",
    "bar: also with Command and on no leader")
  eq(secondary and table.concat(secondary.mods, "+"), "cmd", "bar: with Command")
  eq(secondary and secondary.leader, false, "bar: on no leader, a key the field answers")
  eq(secondary and secondary.layerKey, true, "bar: from Olm's own all layer, so all moves it")
  eq(show and show.key, "/", "bar: showKeys sits on slash")
  eq(show and table.concat(show.mods, "+") .. tostring(show.leader), "cmd+shiftfalse",
    "bar: with Command and Shift on no leader, a key the field answers")
  keymap.applyLists({ bar = block }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  eq(secondary.leader, false, "bar: applyLists leaves the secondary on no leader")
  eq(show.leader, false, "bar: and leaves showKeys on no leader too")
  local nav = assert(loadfile(here .. "../lib/nav.lua"))()
  local _, fieldList = nav.fieldKeys({ bar = block }, { keycodes = { ["return"] = 36, padenter = 76, d = 2 } })
  eq(#fieldList, 2, "bar: the field answers exactly the two secondary keys")
  eq(fieldList[1] and (fieldList[1].key .. "+" .. table.concat(fieldList[1].mods, "+")), "return+cmd",
    "bar: Command and Return")

  local none = barList({ primary = { action = "insertSelected" } })
  local fieldNone = select(2, nav.fieldKeys({ bar = none }, { keycodes = { ["return"] = 36 } }))
  eq(#fieldNone, 0, "bar: a list with no secondary binds nothing on Command and Return, so it keeps choosing the row")
  local moved = { bar = barList({ primary = { action = "insertSelected" }, secondary = { action = "uninstall" } }) }
  local cfg = readLists({ all = { ["hyper+y"] = "secondary" } })
  keymap.applyLists(moved, cfg.lists, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  eq(listKeys(moved, "bar", "uninstall"), "y", "bar: the person's all moves the secondary, both keys at once, like any shared verb")
end

-- A secondary is checked the way a primary is, and names no key.
do
  local ok, why = surface.validate("bar", { primary = { action = "open" }, secondary = { description = "x" } })
  eq(ok, false, "secondary: one naming no action is refused")
  eq(has(why, "secondary names no action"), true, "secondary: saying so")
  ok, why = surface.validate("bar", { primary = { action = "open" }, secondary = { action = "go", key = "u" } })
  eq(ok, false, "secondary: one naming a key is refused")
  eq(has(why, "secondary.key is not a field a secondary takes"), true, "secondary: naming the field")
  ok, why = surface.validate("bar", { primary = { action = "open" }, secondary = { action = "go", chord = false } })
  eq(ok, false, "secondary: chord false is refused, since the bar would name a key nothing binds")
  eq(has(why, "secondary.chord is not a field a secondary takes"), true, "secondary: naming chord")
  eq(surface.validate("bar", { primary = { action = "open" }, secondary = { action = "go", needs = "x", repeats = false } }),
    true, "secondary: needs and repeats are allowed")
  local block = assert(surface.context("bar", { primary = { action = "open" }, secondary = { action = "go", needs = "x" } },
    {}, keymap.listDefaults))
  eq(block.unmet and block.unmet.go, "x", "secondary: a need this machine lacks drops it like any binding")
end

-- The footer model reads the bindings, the gates and the labels rowsFor reads. The right side is
-- the primary on Return, the secondary on its chord and the action panel, and the key panel every
-- other key and the field's own two.
do
  local gate = { open = true }
  local block = barList({
    primary = { action = "insertSelected", description = "Choose Files" },
    secondary = { action = "uninstall", description = "Uninstall" },
    extra = {
      { key = "d", action = "deleteSelected", description = "Delete" },
      { key = "p", action = "peek", when = "peekable" },
    },
  })
  keymap.applyLists({ bar = block }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  local plan = { contexts = { bar = block }, effective = {}, order = {}, identity = {} }
  local labels = nil
  local deps = {
    chordLabel = function(leader, key, mods) return leader .. " " .. key end,
    glyphFor = function(key, mods) return ((mods and #mods > 0) and (table.concat(mods, "+") .. "+") or "") .. key end,
    leaderNames = { hyper = "Hyper" }, leaderName = "Hyper",
    predicates = { peekable = function() return gate.open end },
    labelsFor = function(name) return name == "bar" and labels or nil end,
  }
  local model = hints.footerModel("bar", plan, deps)
  local right = {}
  for _, r in ipairs(model.right) do right[#right + 1] = r.label .. " " .. r.chord end
  eq(table.concat(right, " | "), "Choose Files return | Uninstall cmd+return | Actions Hyper o",
    "footer: primary on Return, the secondary on its chord, then Actions")
  local keys = {}
  for _, k in ipairs(model.keys) do keys[#keys + 1] = table.concat(k.badges, "+") .. " " .. k.label end
  eq(table.concat(keys, " | "),
    "return Choose Files | Hyper j+down Move down | Hyper k+up Move up | Hyper d Delete | Hyper p Peek | Hyper x+escape Close | cmd+shift+/ Keys | cmd+1+cmd+9 Choose a visible row",
    "footer: every other key in declaration order, the primary reading Return alone, then Command with a digit, and no Back on a level Backspace does not leave")
  local before = model.state
  gate.open = false
  local gated = hints.footerModel("bar", plan, deps)
  eq(gated.state ~= before, true, "footer: a gate closing changes the state")
  local peek = false
  for _, k in ipairs(gated.keys) do if k.action == "peek" then peek = true end end
  eq(peek, false, "footer: and drops the gated key")

  labels = { primary = "Choose 4 Files", secondary = "Uninstall 4" }
  local live = hints.footerModel("bar", plan, deps)
  eq(live.right[1].label, "Choose 4 Files", "footer: the level's labels word the primary")
  eq(live.right[2].label, "Uninstall 4", "footer: and the secondary")
  eq(live.state ~= gated.state, true, "footer: and a label changing changes the state")
  local panel = {}
  for _, row in ipairs(hints.rowsFor("bar", plan, deps)) do panel[#panel + 1] = tostring(row.action) .. "=" .. row.title end
  eq(table.concat(panel, ","), "nil=Back,insertSelected=Choose 4 Files,uninstall=Uninstall 4,deleteSelected=Delete",
    "action panel: Back, the primary and the secondary with their live labels, then the verbs")
  labels = { secondary = "" }
  eq(hints.footerModel("bar", plan, deps).right[2].label, "Uninstall", "footer: an empty label falls back to the description")

  local bare = barList({ primary = { action = "open" } })
  keymap.applyLists({ bare = bare }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  local plain = hints.footerModel("bare", { contexts = { bare = bare } }, deps)
  eq(plain.right[1].label, "Open", "footer: a primary with no description reads Open")
  eq(#plain.right, 2, "footer: and with no secondary the right side is the primary and Actions")
  eq(hints.footerModel("nothing", { contexts = {} }, deps).right[1].label, "Open",
    "footer: a list no surface describes still chooses on Return")
  eq(hints.labelFor({ action = "deleteSelected" }, "bar"), "Delete Selected", "labels: an action with no words is spelled out")
end

-- Back is listed only where Backspace on an empty field leaves a level, and never beside a list's
-- own binding on Backspace. The action panel open over a list changes what the bar says, and the
-- secondary is listed once in the action panel although it sits on two keys.
do
  local backs, openRow = false, nil
  local deps = {
    chordLabel = function(leader, key) return leader .. " " .. key end,
    glyphFor = function(key, mods) return ((mods and #mods > 0) and (table.concat(mods, "+") .. "+") or "") .. key end,
    leaderNames = { hyper = "Hyper" }, leaderName = "Hyper",
    predicates = { paged = function() return true end },
    backs = function() return backs end,
    actionPanel = function() return openRow end,
    panelOwner = "panel",
  }
  local function keyLabels(model)
    local out = {}
    for _, k in ipairs(model.keys) do out[#out + 1] = k.label end
    return table.concat(out, ",")
  end
  local block = barList({
    primary = { action = "insertSelected", description = "Paste" },
    secondary = { action = "uninstall", description = "Uninstall" },
    extra = { { key = "d", action = "deleteSelected", description = "Delete" } },
  })
  keymap.applyLists({ bar = block }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  local plan = { contexts = { bar = block }, effective = {}, order = {}, identity = {} }
  eq(has(keyLabels(hints.footerModel("bar", plan, deps)), "Back"), false, "back: none at the bottom of the stack")
  backs = true
  eq(has(keyLabels(hints.footerModel("bar", plan, deps)), "Back"), true, "back: listed on a pushed level")
  local paged = barList({
    primary = { action = "insertSelected" },
    extra = { { key = "delete", action = "leavePage", chord = false, when = "paged", description = "Back to history" } },
  })
  keymap.applyLists({ paged = paged }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  local pagedModel = hints.footerModel("paged", { contexts = { paged = paged } }, deps)
  local backCount = 0
  for _, k in ipairs(pagedModel.keys) do if k.badges[1] == "delete" then backCount = backCount + 1 end end
  eq(backCount, 1, "back: a list listing its own Backspace binding gets no second Back")

  openRow = { action = "deleteSelected", title = "Delete" }
  local panel = hints.footerModel("bar", plan, deps)
  eq(panel.right[1].label, "Delete", "panel: Return reads the highlighted panel row's title")
  eq(#panel.right, 2, "panel: no secondary, only Return and the action panel's chord")
  eq(panel.right[2].action, "openActionPanel", "panel: the second entry closes the panel")
  eq(keyLabels(panel), "Move down,Move up,Close,Back,Choose a visible row",
    "panel: the key panel lists the shared held keys and Back, not the list's own verbs or its inert field keys")
  openRow = {}
  eq(hints.footerModel("bar", plan, deps).right[1].label, "Run", "panel: Run when no row is highlighted")
  openRow = nil

  local rows = {}
  for _, row in ipairs(hints.rowsFor("bar", plan, deps)) do rows[#rows + 1] = tostring(row.action) end
  eq(table.concat(rows, ","), "nil,insertSelected,uninstall,deleteSelected", "panel rows: the secondary is listed once")
  local spelled = {}
  for _, row in ipairs(hints.rowsFor("bar", plan, deps)) do
    spelled[#spelled + 1] = tostring(row.chord) .. "/" .. tostring(row.icon) .. "/" .. tostring(row.owner)
  end
  eq(table.concat(spelled, ","), "delete/back/panel,return/primary/panel,cmd+return/secondary/panel,Hyper d/nil/nil",
    "panel rows: the primary reads Return, the secondary Command and Return, and both take Olm's own icons")
  local mine = barList({ primary = { action = "insertSelected", icon = "paste" },
    secondary = { action = "uninstall", icon = "trash" } })
  keymap.applyLists({ mine = mine }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  local ownIcons = {}
  for _, row in ipairs(hints.rowsFor("mine", { contexts = { mine = mine } },
    { glyphFor = deps.glyphFor, chordLabel = deps.chordLabel, leaderName = "Hyper", panelOwner = "panel",
      owners = { mine = "minePlugin" } })) do
    ownIcons[#ownIcons + 1] = tostring(row.icon) .. "/" .. tostring(row.owner)
  end
  eq(table.concat(ownIcons, ","), "back/panel,paste/minePlugin,trash/minePlugin",
    "panel rows: an icon the surface names is read against the plugin that owns the list")
  eq(surface.validate("bar", { primary = { action = "open", icon = 3 } }), false, "icons: a primary icon that is no key is refused")
  eq(surface.validate("bar", { primary = { action = "open" }, secondary = { action = "go", icon = "trash" } }), true,
    "icons: a secondary may name an icon")
end

-- A shared binding never shadows another list's verb. One list's secondary named like another
-- list's extra verb leaves that verb a verb, in its action panel, and records no conflict.
do
  local one = barList({ primary = { action = "insertSelected" }, secondary = { action = "reveal" } })
  local two = barList({ primary = { action = "insertSelected" }, extra = { { key = "r", action = "reveal", description = "Reveal" } } })
  local kinds, conflicts = hints.actionKinds({ contexts = { one = one, two = two } })
  eq(kinds.reveal, "verb", "kinds: the extra verb stays a verb")
  eq(#conflicts, 0, "kinds: and no conflict is recorded")
  eq(kinds.insertSelected, "navigation", "kinds: a shared action no binding claims is navigation")
  eq(kinds.showKeys, "navigation", "kinds: showKeys too")
  local rows = {}
  for _, row in ipairs(hints.rowsFor("two", { contexts = { one = one, two = two } }, { leaderName = "Hyper",
    chordLabel = function(l, k) return l .. " " .. k end })) do rows[#rows + 1] = tostring(row.action) end
  eq(table.concat(rows, ","), "nil,insertSelected,reveal", "kinds: the other list's panel lists its verb")
end

-- Every handler in the dispatch table tells onAction first, routed and exception alike, which is
-- where the root closes the key panel for every list key that acts.
do
  local nav = assert(loadfile(here .. "../lib/nav.lua"))()
  local told, ran = {}, {}
  local block = barList({ primary = { action = "insertSelected" } })
  local surfaceStub = { isShowing = function() return true end, selectNext = function() ran[#ran + 1] = "selectNext" end }
  local built = nav.actions({ contexts = { bar = block } }, {
    surfaces = { surfaceStub },
    exceptions = { showKeys = function() ran[#ran + 1] = "showKeys" end },
    onAction = function(name) told[#told + 1] = name end,
  })
  built.selectNext()
  built.showKeys()
  eq(table.concat(told, ","), "selectNext,showKeys", "dispatch: onAction hears a routed action and an exception")
  eq(table.concat(ran, ","), "selectNext,showKeys", "dispatch: and each still runs")
  local stamped
  for _, b in ipairs(block.bindings) do if b.action == "selectNext" then stamped = b.fn end end
  told = {}
  stamped()
  eq(told[1], "selectNext", "dispatch: the handler stamped on a binding, what a key runs, tells it too")
end

-- showKeys is Command and ?, slash with Command and Shift, a key the open list's field answers on
-- no leader, since macOS takes Hyper with slash before any tap. The shared speller folds Shift and
-- slash into a question mark, so it reads ⌘? wherever it is spelled, and a person moves and frees
-- it like any field key.
do
  local glyph = assert(loadfile(here .. "../lib/cheatsheet.lua"))().glyphFor
  eq(glyph("/", { "shift" }), "?", "showKeys: the speller reads Shift and slash as a question mark")
  eq(glyph("/", { "cmd", "shift" }), "\u{2318}?", "showKeys: and Command, Shift and slash as Command and ?")
  eq(glyph("/", { "shift", "cmd" }), "\u{2318}?", "showKeys: in either order the keymap sorts them")
  eq(glyph("/"), "/", "showKeys: and plain slash as itself")
  local block = barList({ primary = { action = "insertSelected" } })
  local show
  for _, b in ipairs(block.bindings) do if b.shared == "showKeys" then show = b end end
  keymap.applyLists({ bar = block }, {}, { listLeader = "hyper", keycodes = LIST_KEYCODES })
  local deps = { chordLabel = labelsLib.chordLabel(glyph), leaderNames = { hyper = "Hyper" }, leaderName = "Hyper", glyphFor = glyph }
  eq(hints.chordFor(show, deps), "\u{2318}?", "showKeys: spelled Command and ?")
  local keyPanel
  for _, k in ipairs(hints.footerModel("bar", { contexts = { bar = block } }, deps).keys) do
    if k.action == "showKeys" then keyPanel = k.badges[1] end
  end
  eq(keyPanel, "\u{2318}?", "showKeys: the key panel row spells it the same way")
  local result = keymap.build({ plan = { effective = {}, identity = {}, contexts = { bar = block }, order = {} },
    roles = ROLES, keycodes = LIST_KEYCODES, listLeader = "hyper" })
  local row
  for _, r in ipairs(result.rows) do if r.layer == "bar" and r.action == "showKeys" then row = r end end
  eq(row and row.field, true, "showKeys: the keymap row is a field key")
  eq(row and glyph(row.key, row.shownMods), "\u{2318}?", "showKeys: and the keys page spells it Command and ?")
  -- The default chooser reads nothing on Command, Shift and slash or on Control and Y.
  local function fieldUses() return nil end
  local accepted = keymap.applyLists({ bar = barList({ primary = { action = "insertSelected" } }) },
    readLists({ bar = { ["cmd+shift+/"] = "showKeys" } }).lists,
    { listLeader = "hyper", keycodes = LIST_KEYCODES, fieldUses = fieldUses })
  eq(#accepted, 0, "showKeys: applyLists accepts Command, Shift and slash as a field chord")

  local moved = { bar = barList({ primary = { action = "insertSelected" } }) }
  local movedProblems = keymap.applyLists(moved, readLists({ all = { ["ctrl+y"] = "showKeys" } }).lists,
    { listLeader = "hyper", keycodes = LIST_KEYCODES, fieldUses = fieldUses })
  eq(#movedProblems, 0, "showKeys: a person may move it to another field chord")
  eq(listKeys(moved, "bar", "showKeys"), "ctrl+y", "showKeys: and it takes exactly that chord")
  local freed = { bar = barList({ primary = { action = "insertSelected" } }) }
  keymap.applyLists(freed, readLists({ all = { ["cmd+shift+/"] = false } }).lists,
    { listLeader = "hyper", keycodes = LIST_KEYCODES, fieldUses = fieldUses })
  eq(listKeys(freed, "bar", "showKeys"), "", "showKeys: and freeing Command and ? leaves it unbound")
end

if failures > 0 then
  print(string.format("keymap person, %d check(s), %d failure(s)", checks, failures))
  os.exit(1)
end
print(string.format("keymap person, %d check(s), 0 failure(s)", checks))
