-- The keymap, one read model of every chord Olm binds.
--
-- Every key Olm binds comes from one of three sources, a tool's or a host's open row, a plugin's
-- own bindings, a host's included, and every list's context bindings, and then the person's own
-- keymap, config/keymap.lua, is laid over them. An action a plugin builds from its own data, an
-- app the toggler serves, is an ordinary descriptor reached the same way. A tool's open key is
-- not a field of its own
-- any more. It is the bindings row whose action is open, so one list in the manifest suggests
-- every key a plugin has, and this module tells an open row of a tool from one of a host. This module reads
-- the declarations behind all of them and writes them down as one list of rows in one spelling,
-- then checks that list for two rows on the same chord. Each global row also carries the
-- function its source answers, and a second list holds the global rows in the order the engines
-- receive them, so lib/binder.lua binds that list as it stands and nothing else binds a global
-- key. This module itself binds nothing.
--
-- It is pure Lua. It touches no hs global, and the keycode table it spells keys with and every
-- function a row carries arrive through its inputs, so a plain test can drive it with small
-- fakes. It names no plugin and no leader. A leader is whatever word the roles table maps a role
-- to, a name the leader catalog carries or a name the person gave a set of modifiers, and a plugin
-- is whatever the plan's identity table calls its directory.
--
-- THE PERSON'S KEYMAP. readConfig reads config/keymap.lua, which reaches Olm as cfg.keymap and no
-- plugin ever reads, into its five sections, keys, leaders, roles, aliases and lists. applyLists
-- lays the lists section over every list's bindings before anything reads them, and build lays
-- the keys section over the defaults by three rules. An action the person names takes exactly the
-- chords listed for it and loses every row it had. A row the person set wins a slot a default
-- holds, and the default row on that slot is dropped with one routine note naming it, never bound
-- beside it. And false frees a chord, dropping whatever default holds it with nothing bound there.
-- The notes come back beside the problems for the root to log. applyLists follows the same three
-- rules inside each list.
--
-- The row.
--
--   layer       the word global for a key live whenever its leader is held, or always for a plain
--               combo, otherwise the name of the list the key is live in while that list is open,
--               on whichever leader the row names.
--   leader      the catalog name lowercased, or nil for a plain combo with no leader at all.
--   role        the role word the leader answers, app or window, or nil for a plain combo. A
--               surface that names a leader to a person asks the root what the role is called,
--               so it reads this rather than the catalog name.
--   key         one spelling, the name the keycode table gives the key, lowercase.
--   mods        the required modifiers, sorted, spelled cmd, ctrl, alt and shift.
--   shownMods   the same modifiers in the order a Mac spells them, control, option, shift,
--               command, or nil for a catch all. Every surface spelling a chord to a person
--               reads this one, since the sorted list is for comparing and reads wrong.
--   anyMods     true when the binding states no modifiers at all and fires whatever extra
--               modifiers are held. That is a different binding from one that states an empty
--               list, which demands no modifier, and the two never collide with each other.
--   owner       the identity of the plugin or host that declared the chord. For a list's own
--               keys it is the list's name.
--   action      what the chord does, open for a tool's or a host's open row, and the binding's
--               own action name for everything else.
--   source      one word naming the path, tool, host, bindings or context. A row the
--               person's keymap set keeps the source of the action it runs, so every reader
--               treats it as it treats that action's own default.
--   when        the predicate gating the chord, where there is one.
--   priority    the context priority, where there is one.
--   description the declared label, the binding's own, else the descriptor's, else for an open
--               row the plugin's own description.
--   group       the section a cheat sheet files the row under, the descriptor's own group, a word,
--               a table with a title, or a function answering either, or nil for the sheet's
--               default section.
--   app         the bundle id the descriptor behind the row stands for, which a sheet draws the
--               row with, or nil.
--   origin      default when the plugin shipped the chord and user when the person set it.
--   entry       the chord as the person wrote it in config/keymap.lua, for a row that file set,
--               so a problem or a note about the row names the entry to look at.
--   repeats     whether the action keeps firing while its key is held, where the source says.
--   afterRelease true when the descriptor behind the chord asks to run only once the leader that
--               fired it is released, which the leader honours.
--   run         the function the chord calls, or nil where the source answers none. A list's
--               own keys carry none, since the root binds those through its contexts.
--   refused     true when the action behind a binding was declared and refused, or the plugin's
--               whole actions member failed, so the binder leaves the row unbound without a
--               second line about it.
--   quiet       true for a host whose key has nothing to show, which is left unbound in silence
--               the way it always was.
--   field       true for a list key the open list's own field answers, one opening with no held
--               leader, which binds on no leader and puts none in use.
--
-- The lines this module can name are problems. A problem is a table with where, the chord, and
-- why, one sentence, so the root can hand each straight to the wiring report.

local obj = {}

local GLOBAL = "global"

--- obj.LIST_ROLE
--- The role every default list key rides, Olm's own all layer and every manifest's surface keys,
--- which the roles section of config/keymap.lua may move to any leader as it moves app
--- and window. A list key the person writes names its own leader and rides no role.
obj.LIST_ROLE = "list"

--------------------------------------------------------------------------------
-- Spelling, one way to write a key and a set of modifiers
--------------------------------------------------------------------------------

local MOD_ALIASES = {
  shift = "shift", ctrl = "ctrl", control = "ctrl", alt = "alt", option = "alt", opt = "alt",
  cmd = "cmd", command = "cmd",
}

-- The keycode a key spelling stands for, or nil where the table does not know it. A number is
-- already a keycode. The table is Hammerspoon's own, name to code and code to name in one
-- table, and anything that does not answer a number is treated as not knowing the key.
local function codeOf(key, keycodes)
  if type(key) == "number" then return key end
  if type(key) ~= "string" or type(keycodes) ~= "table" then return nil end
  local code = keycodes[key:lower()]
  if type(code) == "number" then return code end
  return nil
end

--- obj.keyCode(key, keycodes) -> number or nil
--- The keycode a key stands for in the given table, whatever case or alias it was written in.
function obj.keyCode(key, keycodes)
  return codeOf(key, keycodes)
end

--- obj.keyName(key, keycodes) -> string
--- One spelling for a key. A key the table knows takes the name the table gives its code, so
--- two aliases of one key agree. A key it does not know is lowercased, which is the best
--- spelling there is, and a number with no name is written code followed by the number.
function obj.keyName(key, keycodes)
  local code = codeOf(key, keycodes)
  if code then
    local name = type(keycodes) == "table" and keycodes[code]
    if type(name) == "string" then return name end
    return "code" .. tostring(code)
  end
  if type(key) == "string" then return key:lower() end
  return tostring(key)
end

--- obj.mods(mods) -> list, anyMods
--- The modifiers sorted and spelled one way, plus whether the binding was a catch all. Nil
--- means a catch all, which fires whatever extra modifiers are held. An empty list means no
--- modifier at all, a different binding, so the two are told apart here and nowhere later.
function obj.mods(mods)
  if mods == nil then return {}, true end
  local seen, list = {}, {}
  for _, m in ipairs(mods) do
    local canon = MOD_ALIASES[tostring(m):lower()] or tostring(m):lower()
    if not seen[canon] then
      seen[canon] = true
      list[#list + 1] = canon
    end
  end
  table.sort(list)
  return list, false
end

--- obj.modsText(mods) -> string
--- The same answer as one word, any for a catch all, none for no modifier, otherwise the sorted
--- list joined with a plus. This is how the probe's golden file spells it.
function obj.modsText(mods)
  local list, anyMods = obj.mods(mods)
  if anyMods then return "any" end
  if #list == 0 then return "none" end
  return table.concat(list, "+")
end

-- The order a Mac spells modifiers in, which is what a person reads on a badge or a subtitle.
local MAC_ORDER = { ctrl = 1, alt = 2, shift = 3, cmd = 4 }

--- obj.shownMods(mods, anyMods) -> list or nil
--- The modifiers in the order a Mac spells them, or nil for a catch all.
function obj.shownMods(mods, anyMods)
  if anyMods or type(mods) ~= "table" then return nil end
  local out = {}
  for _, m in ipairs(mods) do out[#out + 1] = m end
  table.sort(out, function(a, b)
    local ra, rb = MAC_ORDER[a] or 9, MAC_ORDER[b] or 9
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return out
end

local function rowModsText(row)
  if row.anyMods then return "any" end
  if #row.mods == 0 then return "none" end
  return table.concat(row.mods, "+")
end

-- The slot a row claims, the one thing two rows must not share. Layer, leader, key and modifiers,
-- except on a leader the person named from a set of modifiers. That leader is claimed through
-- hs.hotkey on its own set plus the row's, so its slot is that whole combination with no leader,
-- the same slot a plain combo of those modifiers takes, since the two are one physical chord.
-- modifierLeaders maps such a leader's name to its set, and is empty when the person named none.
local function slotOf(row, modifierLeaders)
  local base = row.leader and (modifierLeaders or {})[row.leader]
  if base then
    local union = {}
    for _, m in ipairs(base) do union[#union + 1] = m end
    for _, m in ipairs(row.mods or {}) do union[#union + 1] = m end
    local list = obj.mods(union)
    return table.concat({ row.layer, "", row.key, table.concat(list, "+") }, "\0")
  end
  return table.concat({ row.layer, row.leader or "", row.key, rowModsText(row) }, "\0")
end

--------------------------------------------------------------------------------
-- Collecting the rows
--------------------------------------------------------------------------------

local function sortedKeys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- A value copied one level down, so a merged leader never shares a layout table with the shipped one.
local function copyValue(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = v end
  return copy
end

--------------------------------------------------------------------------------
-- The person's keymap, config/keymap.lua, read into one shape
--------------------------------------------------------------------------------

-- The sections the file may hold.
local SECTIONS = { "keys", "leaders", "roles", "aliases", "lists" }
local SECTION = {}
for _, name in ipairs(SECTIONS) do SECTION[name] = true end

-- The modifier words a chord may carry, and the four a named leader may hold. fn is a modifier a
-- chord may ask for, and never part of a leader's own set, since the modifier trigger compares the
-- four real modifiers alone and an fn in the set would be dropped in silence.
local CHORD_MODS = { shift = true, ctrl = true, alt = true, cmd = true, fn = true }
local LEADER_MODS = { shift = true, ctrl = true, alt = true, cmd = true }

-- Whether a keycode table is a real one, rather than the stand in a stubbed run answers, so a key
-- the keyboard has no code for is named only where the answer means something.
local function realKeycodes(keycodes)
  return type(keycodes) == "table" and codeOf("a", keycodes) ~= nil
end

local function splitPlus(text)
  local parts, start = {}, 1
  while true do
    local at = text:find("+", start, true)
    if not at then
      parts[#parts + 1] = text:sub(start)
      return parts
    end
    parts[#parts + 1] = text:sub(start, at - 1)
    start = at + 1
  end
end

--- obj.parseChord(text, leaders, keycodes, allowBare, standalone) -> chord or nil, why
--- One chord as the person writes it, a leader or modifiers joined by a plus and the key last.
--- leaders maps every leader name a chord may open with, lowercased, to true for a held leader or
--- to the list of modifiers a named leader holds. A chord ending in pad+ names the keypad plus key,
--- the one key whose name holds a plus sign, and the plus on the main row is written as the key it
--- shares, shift and =, since the keycode table has no + of its own. fn is refused on a chord that
--- opens with a held leader, since a held leader compares only shift, ctrl, alt and cmd and would
--- bind the chord as one stating no modifier, taking the chord from the default with none. It
--- stays legal in a chord of modifiers alone and in a named leader's chord. Leader and modifier words are compared without case, and the key is compared without
--- case and spelled the way the keycode table spells it. The answer is the leader, nil for a chord
--- of modifiers alone, the modifiers, nil for a leader chord stating none, which is a catch all
--- like every default row stating none, and the key. Anything else answers nil and the reason.
---
--- With allowBare true a chord of a key alone is read too, leader and modifiers both absent and the
--- modifiers an empty list, which only a list chord asks for, since a list's own field decides
--- whether a bare key is one it can answer without typing it.
---
--- standalone is lib/keycodes.lua's answer to whether a key is one no app reads as typing, the
--- Globe key. Such a key alone is read as a chord of no modifier, the same rule placeOfRow keeps
--- for a plugin's row, so a person may move a binding onto it or free it like any other chord.
function obj.parseChord(text, leaders, keycodes, allowBare, standalone)
  if type(text) ~= "string" or text == "" then return nil, "is not a chord" end
  local parts, key
  local lower = text:lower()
  if #lower > 4 and lower:sub(-5) == "+pad+" then
    key = "pad+"
    parts = splitPlus(text:sub(1, -6))
  elseif lower == "pad+" then
    key = "pad+"
    parts = {}
  else
    parts = splitPlus(text)
    key = table.remove(parts)
  end
  if key == "" then return nil, "names no key, the key comes last after a plus sign" end
  local leader, mods, seen = nil, {}, {}
  for i, part in ipairs(parts) do
    local word = part:lower()
    if word == "" then
      return nil, "has an empty part between two plus signs"
    elseif CHORD_MODS[word] then
      if seen[word] then return nil, "names the modifier " .. word .. " twice" end
      seen[word] = true
      mods[#mods + 1] = word
    elseif (leaders or {})[word] ~= nil then
      if i ~= 1 then return nil, "names the leader " .. word .. " after another part, and a chord opens with its leader" end
      leader = word
    else
      return nil, "names '" .. part .. "', which is neither a leader nor a modifier"
    end
  end
  if not leader and #mods == 0 and not allowBare and not (standalone and standalone(key)) then
    return nil, "has neither a leader nor a modifier, and a bare key would be taken from every app"
  end
  local base = leader and leaders[leader]
  if leader and base == true and seen.fn then
    return nil, "names fn on the held leader " .. leader .. ", which compares only shift, ctrl, alt and cmd, so the chord would bind as one stating no modifier"
  end
  if type(base) == "table" then
    for _, m in ipairs(base) do
      if seen[m] then return nil, "names " .. m .. ", which the leader " .. leader .. " already holds" end
    end
  end
  if realKeycodes(keycodes) and codeOf(key, keycodes) == nil then
    return nil, "names the key '" .. key .. "', which the keyboard has no code for"
  end
  local list = nil
  if not leader or #mods > 0 then list = obj.mods(mods) end
  return { leader = leader, mods = list, key = obj.keyName(key, keycodes) }
end

local function isWordList(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n ~= #t then return false end
  for _, v in ipairs(t) do
    if type(v) ~= "string" or v == "" then return false end
  end
  return true
end

-- The fields of an entry that say what physically means the leader, every other field being
-- behaviour.
local TRIGGER_FIELDS = { key = true, mods = true, remapTo = true, triggers = true }

-- The shipped leaders as the reader holds them, lowercase name to { name, key, mods, policy,
-- shipped }, the trigger split from the behaviour fields so a person's entry can replace one half
-- and merge over the other. A shipped entry states key, mods, or triggers holding one of each, and
-- a leader on both holds both key and mods, which the root reads as a leader on two triggers.
local function shippedLeaders(shipped)
  local merged = {}
  for name, entry in pairs(shipped or {}) do
    local lower = tostring(name):lower()
    local policy = {}
    for field, value in pairs(entry) do
      if not TRIGGER_FIELDS[field] then policy[field] = copyValue(value) end
    end
    local key, mods = entry.key, entry.mods
    for _, t in ipairs(entry.triggers or {}) do
      if t.key ~= nil then key = t.key end
      if t.mods ~= nil then mods = t.mods end
    end
    if mods ~= nil then mods = obj.mods(mods) end
    merged[lower] = { name = lower, key = key, mods = mods, policy = policy, shipped = true,
      shippedKey = key, shippedMods = mods }
  end
  return merged
end

-- Puts the merged leaders into out.leaders, the held ones first and then the modifier ones, each
-- in name order, and answers every leader's name, to the name it is known by upper cased, held or
-- modifier alike, which is the one identity a role resolves to, and what a chord may open with,
-- true for a held leader or the modifiers a named one holds.
local function listLeaders(merged, out)
  local identities, chordLeaders = {}, {}
  for _, lower in ipairs(sortedKeys(merged)) do
    local entry = merged[lower]
    identities[lower] = lower:upper()
    if entry.key ~= nil then
      chordLeaders[lower] = true
      out.leaders[#out.leaders + 1] = entry
    end
  end
  for _, lower in ipairs(sortedKeys(merged)) do
    local entry = merged[lower]
    if entry.key == nil then
      chordLeaders[lower] = entry.mods
      out.leaders[#out.leaders + 1] = entry
    end
  end
  return identities, chordLeaders
end

--- obj.readConfig(config, opts) -> { keys, leaders, roles, aliases, lists, allocation, problems, notes }
--- config/keymap.lua as one shape, every entry checked here so the rest of Olm reads clean data.
---   opts.leaders    the leaders Olm ships, lowercase name to an entry in the shape of the leaders
---                   section, a key or mods beside any behaviour fields. The person's section is
---                   laid over it, so an empty section answers exactly these.
---   opts.sources    the set of key names a held leader may name, the allow list lib/keyremap.lua
---                   keeps, or nil to take any name. This file holds no list of its own.
---   opts.allocate   function taking the held leaders as a list of { name, key, remapTo } and
---                   answering { leaders, remaps, issues, notes }, lib/keyremap.lua's allocate. It
---                   decides which function key each held leader listens on and which leaders
---                   cannot be placed, and the person's trigger of each of those is dropped here,
---                   so the leaders returned are the ones it could place. Nil skips the check.
---   opts.roleWords  the role words a default may name, app and window.
---   opts.keycodes   the keycode table a key is spelled with, or nil.
---   opts.standalone function answering whether a key is one no app reads as typing, which a
---                   chord may name alone, lib/keycodes.lua's standalone, or nil to allow none.
---
--- leaders is every leader in use, shipped and named, as a list of { name, key or mods or both,
--- remapTo, policy, shipped }, the held ones first and then the modifier ones, each sorted by name.
--- A leader holding both a key and mods listens on both, and counts among the held ones. policy is the
--- leader's behaviour fields as written, laid over the shipped entry's field by field, and the
--- root checks their types. roles maps a role word to the name, upper cased, of the leader it
--- moves to, held or modifier, which is the one identity every reader of a role compares.
--- allocation is the last answer opts.allocate gave, nil when none was handed. notes are routine
--- lines for the root to log. aliases maps a plugin or host identity to its words, the identity
--- checked by the caller, which knows the plugins. keys is a list, sorted by the chord as written, of { text, leader, mods, key, free,
--- owner, action }, free true for an entry answering false. lists maps a list's context name, or
--- all, to a list sorted by the chord as written of { text, leader, mods, key, free, action }, the
--- action a surface action name rather than an id, since a list key acts on whichever list is
--- open, and every list section is read whether or not a list of that name loads, applyLists
--- answering that. Every entry that cannot be read is one problem naming the entry and is left
--- out, and every other entry is still read.
function obj.readConfig(config, opts)
  opts = opts or {}
  local out = { keys = {}, leaders = {}, roles = {}, aliases = {}, lists = {}, problems = {}, notes = {} }
  local function problem(where, why)
    out.problems[#out.problems + 1] = { where = "config/keymap.lua " .. where, why = why }
  end
  -- The shipped leaders and the person's entries laid over them, built below. The two early
  -- answers still hold the shipped leaders, since an empty file means exactly those.
  local merged = shippedLeaders(opts.leaders)
  if config == nil then
    listLeaders(merged, out)
    return out
  end
  if type(config) ~= "table" then
    problem("itself", "answers a " .. type(config) .. " rather than a table, so every key keeps its default")
    listLeaders(merged, out)
    return out
  end
  for _, name in ipairs(sortedKeys(config)) do
    if not SECTION[name] then
      problem(tostring(name), "is not a section Olm reads, which are " .. table.concat(SECTIONS, ", ")
        .. ", so it is ignored")
    elseif type(config[name]) ~= "table" then
      problem(tostring(name), "is a " .. type(config[name]) .. " rather than a table, so the section is ignored")
    end
  end
  local function section(name)
    return type(config[name]) == "table" and config[name] or {}
  end

  local roleWord = {}
  for _, word in ipairs(opts.roleWords or {}) do roleWord[word] = true end

  -- The leaders, the shipped ones first and then the person's entry for each name laid over them
  -- in two halves. The trigger, mods, key or triggers, is replaced as one, so an entry writing key
  -- alone on a leader that ships on a key and on modifiers leaves it on that key alone, and one
  -- writing triggers replaces both with its list. triggers holds at most one key and one set of
  -- mods, a held key and a set of modifiers being the only pair a leader listens on at once, so
  -- three triggers or two of one kind are refused. The behaviour fields merge one by one over the
  -- shipped entry of the same name, so a person changing one keeps the rest. A name the person
  -- adds starts with every behaviour off.
  -- No name is reserved, a name is refused only when a chord could not tell it from a modifier or
  -- a role, or when it is not a word at all. A shipped name may change kind, hyper written
  -- with mods is a modifier leader and leaves the held allocation, and the behaviour fields it
  -- ships stay unless the entry says otherwise.
  local leaders = section("leaders")
  local named = {}
  -- One set of modifiers as a leader holds it, sorted, or nil and why it is refused.
  local function leaderMods(given)
    if type(given) ~= "table" or #given == 0 then
      return nil, "has mods that are not a list of modifiers, or an empty one"
    end
    local list = {}
    for _, m in ipairs(given) do
      local word = tostring(m):lower()
      if not LEADER_MODS[word] then
        return nil, "has mods holding '" .. tostring(m) .. "', and a leader holds only shift, ctrl, alt and cmd"
      end
      list[#list + 1] = word
    end
    return (obj.mods(list))
  end
  -- Why a held key is refused, or nil when it is one the allow list holds.
  local function badKey(key)
    if type(key) == "string" and not (opts.sources and not opts.sources[key]) then return nil end
    local known = {}
    for source in pairs(opts.sources or {}) do known[#known + 1] = source end
    table.sort(known)
    return "has a key of '" .. tostring(key) .. "', which is not a key Olm can make a leader"
      .. (#known > 0 and ", the keys it knows are " .. table.concat(known, ", ") or "")
  end
  -- The triggers list, answering the key, its remapTo and the mods it holds, or the reason the
  -- whole list is refused.
  local function readTriggers(list)
    if type(list) ~= "table" or #list == 0 or #list ~= #sortedKeys(list) then
      return nil, nil, nil, "has triggers that are not a list of { key = ... } and { mods = ... } entries"
    end
    if #list > 2 then
      return nil, nil, nil, "has more than two triggers, and a leader listens on at most one key and one set of modifiers"
    end
    local key, remapTo, mods = nil, nil, nil
    for i, t in ipairs(list) do
      local where = "has a trigger, number " .. i .. ", that "
      if type(t) ~= "table" then
        return nil, nil, nil, where .. "is a " .. type(t) .. " rather than a table of key or mods"
      end
      for field in pairs(t) do
        if field ~= "key" and field ~= "mods" and field ~= "remapTo" then
          return nil, nil, nil, where .. "states '" .. tostring(field) .. "', and a trigger holds only key, remapTo or mods"
        end
      end
      if t.key ~= nil and t.mods ~= nil then
        return nil, nil, nil, where .. "states both mods and key, and one trigger is one or the other"
      elseif t.mods ~= nil then
        if t.remapTo ~= nil then return nil, nil, nil, where .. "states remapTo beside mods, and only a held key is remapped" end
        if mods ~= nil then
          return nil, nil, nil, "has two triggers of mods, and a leader listens on at most one key and one set of modifiers"
        end
        local why
        mods, why = leaderMods(t.mods)
        if not mods then return nil, nil, nil, why end
      elseif t.key ~= nil then
        if key ~= nil then
          return nil, nil, nil, "has two triggers of key, and a leader listens on at most one key and one set of modifiers"
        end
        local why = badKey(t.key)
        if why then return nil, nil, nil, why end
        key, remapTo = t.key, t.remapTo
      else
        return nil, nil, nil, where .. "states neither mods nor key"
      end
    end
    return key, remapTo, mods
  end
  for _, name in ipairs(sortedKeys(leaders)) do
    local where = "leaders " .. tostring(name)
    local set = leaders[name]
    local lower = type(name) == "string" and name:lower() or nil
    if not lower or not lower:match("^%a%w*$") then
      problem(where, "is not a name, a leader is one word of letters and digits, so it is ignored")
    elseif CHORD_MODS[lower] then
      problem(where, "is a modifier word, so a chord could not tell the two apart, and it is ignored")
    elseif roleWord[lower] then
      problem(where, "is a role word, " .. tostring(lower) .. ", which the roles section moves, so a chord could not tell the two apart and it is ignored")
    elseif named[lower] then
      problem(where, "names a leader already named in another case, so it is ignored")
    else
      named[lower] = true
      local isNew = merged[lower] == nil
      local fields = set
      if type(set) == "table" and set.mods == nil and set.key == nil and set.triggers == nil and #set > 0 then
        -- Today's form, a bare list of modifiers, is still read as mods for now.
        fields = { mods = set }
        out.notes[#out.notes + 1] = "leaders " .. name .. " is a bare list of modifiers, read as mods, "
          .. "so write mods = { ... } instead"
      end
      local mods, key, remapTo, bad = nil, nil, nil, nil
      if type(fields) ~= "table" then
        bad = "is a " .. type(set) .. " rather than a table of mods or key and behaviour fields"
      elseif fields.triggers ~= nil and (fields.mods ~= nil or fields.key ~= nil or fields.remapTo ~= nil) then
        bad = "states triggers beside mods, key or remapTo, and triggers holds them all, a remapTo inside its key trigger"
      elseif fields.triggers ~= nil then
        key, remapTo, mods, bad = readTriggers(fields.triggers)
      elseif fields.mods ~= nil and fields.key ~= nil then
        bad = "states both mods and key, and a leader is one or the other"
      elseif fields.mods ~= nil and fields.remapTo ~= nil then
        bad = "states remapTo beside mods, and only a held key is remapped"
      elseif fields.mods == nil and fields.key == nil and fields.remapTo ~= nil then
        bad = "states remapTo without a key, and the two replace together, so write the key beside it"
      elseif fields.mods == nil and fields.key == nil then
        -- A shipped leader written with behaviour fields alone keeps the kind it ships, a new name
        -- has none to keep.
        if isNew then bad = "states neither mods nor key, and a leader is one or the other" end
      elseif fields.mods ~= nil then
        mods, bad = leaderMods(fields.mods)
      else
        key, remapTo = fields.key, fields.remapTo
        bad = badKey(key)
      end
      if bad then
        problem(where, bad .. ", so " .. (isNew and "it is ignored" or "the shipped default is kept"))
      else
        local entry = merged[lower] or { name = lower, policy = {} }
        merged[lower] = entry
        if mods or key then
          entry.mods, entry.key, entry.remapTo, entry.person = mods, key, remapTo, true
        end
        for _, field in ipairs(sortedKeys(fields)) do
          if field == "tapTogglesCapsLock" then
            problem(where, "has tapTogglesCapsLock, which is retired, a quick tap toggles Caps Lock when the key is "
              .. "capsLock and does nothing for any other key, so the field is ignored")
          elseif not TRIGGER_FIELDS[field] and type(field) ~= "number" then
            local value, was = fields[field], entry.policy[field]
            if type(value) == "table" and type(was) == "table" then
              local both = copyValue(was)
              for k, v in pairs(value) do both[k] = v end
              value = both
            end
            entry.policy[field] = value
          end
        end
      end
    end
  end
  -- The held leaders placed on function keys, and the check the allocation makes across leaders,
  -- which no single entry can make. A leader it cannot place loses the trigger the person wrote,
  -- every one of the conflicting entries together, and goes back to the shipped one or, for a new
  -- name, is dropped. The check runs again on what is left, since a shipped default coming back may
  -- meet another entry, and it ends because each pass drops at least one person entry.
  if opts.allocate then
    local result
    repeat
      local rows = {}
      for _, lower in ipairs(sortedKeys(merged)) do
        local entry = merged[lower]
        if entry.key ~= nil then rows[#rows + 1] = { name = lower, key = entry.key, remapTo = entry.remapTo } end
      end
      result = opts.allocate(rows)
      local dropped = false
      for _, issue in ipairs(result.issues) do
        local entry = merged[issue.name]
        if entry and entry.person then
          problem("leaders " .. issue.name, issue.why .. ", so "
            .. (entry.shipped and "the shipped default is kept" or "it is ignored"))
          if entry.shipped then
            -- Both halves go back, since the person's entry may have changed the kind.
            entry.key, entry.mods, entry.remapTo, entry.person = entry.shippedKey, entry.shippedMods, nil, nil
          else
            merged[issue.name] = nil
          end
          dropped = true
        end
      end
    until not dropped
    -- What is left is shipped entries alone, a defect in what Olm ships and not in the person's file.
    for _, issue in ipairs(result.issues) do problem("leaders " .. issue.name, issue.why) end
    for _, note in ipairs(result.notes) do out.notes[#out.notes + 1] = note end
    out.allocation = result
  end
  local identities, chordLeaders = listLeaders(merged, out)

  local roles = section("roles")
  for _, role in ipairs(sortedKeys(roles)) do
    local where = "roles " .. tostring(role)
    local value = roles[role]
    if not roleWord[role] then
      problem(where, "is not a role the roles section moves, which are "
        .. table.concat(opts.roleWords or {}, ", ") .. ", so it is ignored")
    elseif type(value) ~= "string" or not identities[value:lower()] then
      problem(where, "names '" .. tostring(value) .. "', which is no leader, so the role keeps its default")
    else
      out.roles[role] = identities[value:lower()]
    end
  end

  local aliases = section("aliases")
  for _, identity in ipairs(sortedKeys(aliases)) do
    local words = aliases[identity]
    if type(identity) ~= "string" or not isWordList(words) then
      problem("aliases " .. tostring(identity), "is not a list of words, so the plugin keeps its own aliases")
    else
      local copy = {}
      for i, w in ipairs(words) do copy[i] = w end
      out.aliases[identity] = copy
    end
  end

  local keys = section("keys")
  for _, text in ipairs(sortedKeys(keys)) do
    local where = "keys " .. tostring(text)
    local value = keys[text]
    if value ~= false and type(value) ~= "string" then
      problem(where, "answers a " .. type(value) .. ", where a chord takes an action id such as vpn.open, or false to free it, so the entry is ignored")
    else
      local chord, why = obj.parseChord(text, chordLeaders, opts.keycodes, false, opts.standalone)
      if not chord then
        problem(where, why .. ", so the entry is ignored")
      else
        local entry = { text = text, leader = chord.leader, mods = chord.mods, key = chord.key, free = value == false }
        if value ~= false then
          local owner, action = value:match("^([^.]+)%.(.+)$")
          if not owner then
            problem(where, "names '" .. value .. "', which is not an action id, the plugin or host identity, a dot and the action, so the entry is ignored")
            entry = nil
          else
            entry.owner, entry.action = owner, action
          end
        end
        if entry then out.keys[#out.keys + 1] = entry end
      end
    end
  end

  -- The lists section, one table per list keyed by its context name and all for every list, each a
  -- chord to the surface action it runs there or false. Whether the chord sits on the leader that
  -- hosts lists, and whether the list and the action exist, is applyLists' question, since only
  -- the root knows the leader and the lists, so this reads the grammar alone.
  local lists = section("lists")
  for _, name in ipairs(sortedKeys(lists)) do
    local layer = lists[name]
    if type(name) ~= "string" or name == "" then
      problem("lists " .. tostring(name), "is not a list name, so the section is ignored")
    elseif type(layer) ~= "table" then
      problem("lists " .. name, "is a " .. type(layer) .. " rather than a table of chords, so it is ignored")
    else
      local entries = {}
      for _, text in ipairs(sortedKeys(layer)) do
        local where = "lists " .. name .. " " .. tostring(text)
        local value = layer[text]
        if value ~= false and (type(value) ~= "string" or value == "") then
          problem(where, "answers a " .. type(value) .. ", where a list chord takes the name of a surface action such as selectNext, or false to free it, so the entry is ignored")
        else
          local chord, why = obj.parseChord(text, chordLeaders, opts.keycodes, true)
          if not chord then
            problem(where, why .. ", so the entry is ignored")
          else
            entries[#entries + 1] = { text = text, leader = chord.leader, mods = chord.mods, key = chord.key,
              free = value == false, action = value ~= false and value or nil }
          end
        end
      end
      out.lists[name] = entries
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Keys inside a list, Olm's own all layer and the person's lists section
--------------------------------------------------------------------------------

--- obj.listDefaults
--- Olm's own all layer, the key every list's shared verbs sit on unless that list's manifest
--- states its own, the launcher's close for one, or the person moves it in the lists section of
--- config/keymap.lua. A shared verb is named by what it does, primary for the list's own primary
--- action, secondary for its second one, close for its close, and the action names of the rest,
--- and lib/surface.lua builds each on the key named here. This is a core default rather than a
--- plugin's, and the one place these keys are written.
---
--- An entry takes one of three shapes. A bare key name is a key on the list role, LIST_ROLE, which
--- applyLists turns into a leader, and every held list key takes it. A table holding key, mods and
--- leader false is a key the open list's own field answers with modifiers alone, the same three
--- fields a person's list chord with no held leader carries once applyLists has read it, so
--- lib/surface.lua copies them onto the binding and applyLists, which places only a binding whose
--- leader is nil, leaves it on no leader. A list of such tables puts one verb on several keys.
--- secondary takes that last shape, Command and Return and Command and keypad Enter, since plain
--- keypad Enter chooses the row as plain Return does, and the field asks the list keys for both
--- before its own Return handling. A list declaring no secondary builds no binding there, so both
--- keep choosing the row. A person naming secondary in the lists section moves both at once, since
--- an action named takes exactly the chords listed for it. showKeys is Command and ?, slash with
--- Command and Shift, and Command and slash beside it, so a press with or without Shift opens the
--- key panel, two field keys on no leader like the secondary's. The first is the one spelled, ⌘?
--- through the shared glyph speller. It is not a held list key because macOS takes Hyper and slash, and Hyper with other
--- punctuation, before any event tap sees it, see decisions/olm-chooser-keys.md. It reaches a list
--- only where the system's Show Help menu shortcut is off, which src/setup-macos-shortcuts.sh sees to. showKeys sits on slash
--- on the list role, shadowing a global slash only while a list is open, which a list key may do
--- since collisions are checked per layer.
obj.listDefaults = {
  primary = "i", selectNext = "j", selectPrev = "k", close = "x", openActionPanel = "o",
  secondary = {
    { key = "return", mods = { "cmd" }, leader = false },
    { key = "padenter", mods = { "cmd" }, leader = false },
  },
  showKeys = {
    { key = "/", mods = { "cmd", "shift" }, leader = false },
    { key = "/", mods = { "cmd" }, leader = false },
  },
}

-- Whether a key types a character into a text field when pressed with no modifier or with Shift
-- alone, a key whose name is one character, space, or a keypad key that is not Enter or Clear.
-- Read from the name alone, which is how the keycode table spells every such key.
local function typesCharacter(key)
  if type(key) ~= "string" then return false end
  if #key == 1 or key == "space" then return true end
  return key:match("^pad") ~= nil and key ~= "padenter" and key ~= "padclear"
end
obj.typesCharacter = typesCharacter

-- Whether a list binding or entry belongs to the open list's own field rather than to a held
-- leader, which is any that opens with no held leader, false or nil for modifiers alone and a
-- leader the person named from modifiers. heldLeaders is the set of held leader names.
local function isFieldLeader(leader, heldLeaders)
  if leader == false or leader == nil then return true end
  return not (heldLeaders or {})[leader]
end

--- obj.fieldMods(leader, mods, modifierLeaders) -> sorted list
--- The modifiers a list key the field answers is pressed with, a named leader's own set joined
--- with the chord's, sorted and spelled one way.
function obj.fieldMods(leader, mods, modifierLeaders)
  local union = {}
  for _, m in ipairs((type(leader) == "string" and (modifierLeaders or {})[leader]) or {}) do union[#union + 1] = m end
  for _, m in ipairs(mods or {}) do union[#union + 1] = m end
  return (obj.mods(union))
end

-- The slot one list key claims inside its list, its leader, its key and its modifiers, a catch
-- all apart from an exact set, the same comparison collisions makes, with no layer since that is
-- the list's. hyper and J and meta and J are two slots of one list.
local function listSlot(leader, key, mods, keycodes)
  local text
  if mods == nil then text = "any"
  else
    local list = obj.mods(mods)
    text = #list == 0 and "none" or table.concat(list, "+")
  end
  return tostring(leader or "") .. "\0" .. obj.keyName(key, keycodes) .. "\0" .. text
end

-- Whether a binding answers a name a list entry gives, its own action or the shared verb it was
-- built for, so close reaches the launcher's close and closeChooser reaches it too.
local function answers(b, name)
  return b.action == name or (b.shared ~= nil and b.shared == name)
end

-- Whether an entry reaches a binding at all. An entry of the list's own table reaches every binding
-- answering its name. An all entry reaches only a binding whose key came from Olm's own all layer,
-- layerKey, so a list whose manifest states its own key for a shared verb, the launcher closing
-- on the key that also opens it, keeps that key unless the person names that list.
local function reaches(held, b)
  if held.section == "all" and not b.layerKey then return false end
  return true
end

--- obj.applyLists(contexts, lists, opts) -> problems, notes
--- The person's lists section laid over every list's built bindings, in place, so the action bar,
--- the action panel, the keymap's rows and the contexts the root binds all read the one answer.
--- First every default binding, one naming no leader, is placed on the leader the list role lands
--- on, opts.listLeader, so every reader after this reads a binding's own leader. Then all is laid
--- and each list's own table over it. A list's own table decides every binding
--- its entries resolve to and every slot it names, so an all entry resolving to one of the same
--- bindings, by action or by shared verb, or on one of those slots, is not applied in that list.
--- all moves and frees only keys that came from Olm's own all layer, so a key a manifest states
--- for a shared verb stays unless the list's own table names it. The
--- rules are the keys section's, inside one list. An action named takes exactly the chords
--- listed for it and loses its default key, copying its gate, label and repeat from the binding
--- it had. A chord landing on a slot a default holds drops that default, one routine note. false
--- frees a slot. Two entries of one table on one slot are refused together, one problem, so no
--- winner is picked, and two defaults on one slot stay for the keymap's collision check to name.
--- A binding listed with chord false is a key the list reads for itself, a manifest fact, so an
--- entry naming it is a problem and it is never a slot.
---   opts.listLeader  the leader the list role lands on, the name a chord spells it with, hyper
---                    unless the roles section moves it, which every default binding is placed on.
---   opts.heldLeaders optional, the held leaders a list chord may open with, a name to true, the
---                    list role's leader alone when absent.
---   opts.modifierLeaders optional, a leader the person named to its set of modifiers.
---   opts.fieldUses   optional, a function from a key name and a sorted list of modifiers to a
---                    word naming what the list's own field already does with that chord, or nil.
---                    It is how a chord opening with no held leader is checked, since such a chord
---                    belongs to the open list's field. Absent, every such chord is refused, so a
---                    caller with no field to answer them binds none.
--- A chord opening with no held leader, modifiers alone or a leader the person named, is a key the
--- open list's own field answers while it is up, phase B of the list keys addendum. It is refused
--- when it would type into the field, no modifier or Shift alone on a key that types a character,
--- and when the field already reads it, and otherwise kept with leader false for modifiers alone or
--- the named leader's name, its slot being the whole combination with no leader.
---   opts.keycodes    the keycode table a key is spelled with, or nil.
---   opts.known       optional, answering whether a list name belongs to a plugin that exists and
---                    is not loaded this time, so its section is a note rather than a problem.
--- An entry naming an action the list left out for a need this machine lacks, the block's unmet,
--- is a routine note, since the key exists on a machine that meets the need.
--- Every problem is a table with where and why, and every note a line, the same shapes build gives.
function obj.applyLists(contexts, lists, opts)
  opts = opts or {}
  contexts = contexts or {}
  local keycodes = opts.keycodes
  local problems, notes = {}, {}
  local function problem(where, why)
    problems[#problems + 1] = { where = "config/keymap.lua lists " .. where, why = why }
  end
  local heldLeaders = opts.heldLeaders
  if heldLeaders == nil then
    heldLeaders = {}
    if opts.listLeader then heldLeaders[opts.listLeader] = true end
  end

  -- Every default binding rides the list role, so it is placed on that role's leader before a
  -- slot is compared, and a key a list reads for itself, chord false, binds on no leader at all.
  for _, block in pairs(contexts) do
    for _, b in ipairs(block.bindings or {}) do
      if b.chord ~= false and b.leader == nil then b.leader = opts.listLeader end
    end
  end

  -- Each section's readable entries, with a chord on another leader and two entries of the one
  -- table on one slot refused here, once, rather than once per list they would reach.
  local sections = {}
  for _, name in ipairs(sortedKeys(lists or {})) do
    local valid, bySlot = {}, {}
    for _, e in ipairs(lists[name]) do
      local where = name .. " " .. tostring(e.text)
      local field = isFieldLeader(e.leader, heldLeaders)
      local fieldMods = field and obj.fieldMods(e.leader, e.mods, opts.modifierLeaders) or nil
      local refusal = nil
      if field then
        local onlyShift = #fieldMods == 0 or (#fieldMods == 1 and fieldMods[1] == "shift")
        local hasFn = false
        for _, m in ipairs(fieldMods) do if m == "fn" then hasFn = true end end
        if not opts.fieldUses then
          local names = {}
          for name in pairs(heldLeaders) do names[#names + 1] = name end
          table.sort(names)
          refusal = "opens with " .. tostring(e.leader or "no leader") .. ", and a list key opens with a held leader, "
            .. (#names > 0 and table.concat(names, ", ") or "of which this load has none") .. ", so the entry is ignored"
        elseif hasFn then
          refusal = "names fn, which the list's field does not compare, so the chord would act on the "
            .. "key without it, and the entry is ignored"
        elseif onlyShift and typesCharacter(e.key) then
          refusal = "names a key that types a character into the list's field, so the entry is ignored, a key "
            .. "the field answers needs a modifier other than shift"
        else
          local use = opts.fieldUses(e.key, fieldMods)
          if use then
            refusal = "names a chord the list's field already reads, " .. tostring(use) .. ", so the entry is ignored"
          end
        end
      end
      if refusal then
        problem(where, refusal)
      else
        if field and typesCharacter(e.key) then
          local typing = true
          for _, m in ipairs(fieldMods) do
            if m == "ctrl" or m == "cmd" then typing = false end
          end
          if typing then
            notes[#notes + 1] = "the keymap entry 'lists " .. where .. "' takes a chord that types a character "
              .. "into the field, Option on a printable key, so in that list the chord acts and the character is not typed"
          end
        end
        local slot = field and listSlot("", e.key, fieldMods, keycodes) or listSlot(e.leader, e.key, e.mods, keycodes)
        local held = { entry = e, slot = slot, section = name, where = where }
        if bySlot[slot] then
          bySlot[slot].clash = bySlot[slot].clash or {}
          table.insert(bySlot[slot].clash, held)
        else
          bySlot[slot] = held
          valid[#valid + 1] = held
        end
      end
    end
    local kept = {}
    for _, held in ipairs(valid) do
      if held.clash then
        local texts = { "'" .. tostring(held.entry.text) .. "'" }
        for _, other in ipairs(held.clash) do texts[#texts + 1] = "'" .. tostring(other.entry.text) .. "'" end
        problem(held.where, "the entries " .. table.concat(texts, " and ") .. " are two of the person's own chords on one slot of "
          .. name .. ", so neither is applied")
      else
        kept[#kept + 1] = held
      end
    end
    sections[name] = kept
  end

  for _, name in ipairs(sortedKeys(sections)) do
    if name ~= "all" and contexts[name] == nil then
      if opts.known and opts.known(name) then
        notes[#notes + 1] = "the keymap lists section '" .. name .. "' names a list that is not loaded this time, so it binds nothing"
      else
        problem(name, "names no list in this load, a list is named by its manifest's surface context, so the section is ignored")
      end
    end
  end

  -- Which all entries some list answered or freed something in, so an entry that reached nothing
  -- anywhere is said once rather than once per list.
  local reached = {}

  for _, listName in ipairs(sortedKeys(contexts)) do
    local block = contexts[listName]
    local own = sections[listName] or {}
    local bindings = block.bindings or {}
    -- The bindings the list's own table resolves to, by action or by shared verb, so an all entry
    -- naming the same binding another way, primary for insertSelected or close for closeChooser,
    -- is overridden just as one spelling it the same way is.
    local ownSlot, ownBinding = {}, {}
    for _, held in ipairs(own) do
      ownSlot[held.slot] = true
      if not held.entry.free then
        for _, b in ipairs(bindings) do
          if answers(b, held.entry.action) then ownBinding[b] = true end
        end
      end
    end
    local function overridden(held)
      if ownSlot[held.slot] then return true end
      if held.entry.free then return false end
      for _, b in ipairs(bindings) do
        if ownBinding[b] and answers(b, held.entry.action) then return true end
      end
      return false
    end
    local layer = {}
    for _, held in ipairs(sections.all or {}) do
      if not overridden(held) then
        layer[#layer + 1] = held
      else
        -- The list's own table overrode the entry here, which is still a list the entry reached,
        -- so it is not said to reach none below.
        reached[held] = true
      end
    end
    for _, held in ipairs(own) do layer[#layer + 1] = held end

    -- What each entry moves, the first binding answering its action and every one answering it,
    -- which all lose their key and give way to the entry's chords.
    local moved, chordsFor, template = {}, {}, {}
    for _, held in ipairs(layer) do
      local e = held.entry
      if not e.free then
        local first, listedOnly = nil, false
        for _, b in ipairs(bindings) do
          if answers(b, e.action) and reaches(held, b) then
            if b.chord == false then listedOnly = true
            else
              first = first or b
              moved[b] = true
            end
          end
        end
        if first then
          reached[held] = true
          template[first] = template[first] or first
          chordsFor[first] = chordsFor[first] or {}
          table.insert(chordsFor[first], held)
        elseif held.section ~= "all" then
          local need = (block.unmet or {})[e.action]
          if need ~= nil then
            notes[#notes + 1] = "the keymap entry 'lists " .. listName .. " " .. tostring(e.text) .. "' names "
              .. e.action .. ", which needs " .. tostring(need) .. " and this machine lacks it, so it binds nothing"
          elseif listedOnly then
            problem(held.where, "names " .. e.action .. ", which the list lists with chord false, a key it reads for itself, so it is no person setting and the entry is ignored")
          else
            problem(held.where, "names the action '" .. e.action .. "', which the list " .. listName .. " does not answer, so the entry is ignored")
          end
        end
      end
    end

    -- The moved bindings give way, in place, to one copy per chord, so the order a list's keys
    -- are listed in stays its manifest's. A binding answering an action named that is not the
    -- first is dropped, since the action takes exactly the chords listed.
    local rebuilt = {}
    for _, b in ipairs(bindings) do
      if not moved[b] then
        rebuilt[#rebuilt + 1] = b
      elseif chordsFor[b] then
        for _, held in ipairs(chordsFor[b]) do
          local copy = {}
          for k, v in pairs(b) do copy[k] = v end
          copy.leader, copy.key, copy.mods = held.entry.leader or false, held.entry.key, held.entry.mods
          copy.fn, copy.layerKey = nil, nil
          copy.entry = held.section .. " " .. tostring(held.entry.text)
          rebuilt[#rebuilt + 1] = copy
        end
      end
    end

    -- false frees a slot, and a person's chord takes a slot from the default holding it. Both drop
    -- default bindings only, the bound ones, since a key listed with chord false holds no slot.
    local function slotOfBinding(b)
      if isFieldLeader(b.leader, heldLeaders) then
        return listSlot("", b.key, obj.fieldMods(b.leader, b.mods, opts.modifierLeaders), keycodes)
      end
      return listSlot(b.leader, b.key, b.mods, keycodes)
    end
    local takenBy = {}
    for _, b in ipairs(rebuilt) do
      if b.entry then takenBy[slotOfBinding(b)] = takenBy[slotOfBinding(b)] or b end
    end
    local frees = {}
    for _, held in ipairs(layer) do
      if held.entry.free then frees[held.slot] = held end
    end
    local final = {}
    for _, b in ipairs(rebuilt) do
      local slot = (not b.entry and b.chord ~= false) and slotOfBinding(b) or nil
      local free = slot and frees[slot]
      if free and not reaches(free, b) then free = nil end
      local winner = slot and takenBy[slot]
      if free then
        reached[free] = true
        notes[#notes + 1] = "the keymap entry 'lists " .. free.section .. " " .. tostring(free.entry.text)
          .. "' frees the chord in " .. listName .. ", so " .. listName .. "." .. tostring(b.action) .. " is not bound there"
      elseif winner then
        notes[#notes + 1] = "the keymap entry 'lists " .. winner.entry .. "' takes " .. tostring(b.key) .. " in "
          .. listName .. ", so the default " .. listName .. "." .. tostring(b.action) .. " is not bound there"
      else
        final[#final + 1] = b
      end
    end
    -- false on a slot one of the person's own chords in this list takes is two of the person's on
    -- one slot, which the section check above already refused within one table, so here it is
    -- only ever an all entry the list's own table overrode, and the list's own wins in silence.
    block.bindings = final
  end

  for _, held in ipairs(sections.all or {}) do
    if not reached[held] then
      if held.entry.free then
        notes[#notes + 1] = "the keymap entry 'lists all " .. tostring(held.entry.text) .. "' frees a chord no list holds"
      else
        problem(held.where, "names the action '" .. tostring(held.entry.action) .. "', which no list answers on a key of Olm's own all layer, and all moves only those, so the entry is ignored, a list's own key is moved in that list's table")
      end
    end
  end
  for _, name in ipairs(sortedKeys(sections)) do
    if name ~= "all" and contexts[name] then
      for _, held in ipairs(sections[name]) do
        if held.entry.free and not reached[held] then
          notes[#notes + 1] = "the keymap entry 'lists " .. name .. " " .. tostring(held.entry.text) .. "' frees a chord no key of the list holds"
        end
      end
    end
  end
  return problems, notes
end

--- obj.retiredPluginFields
--- The fields config/plugins.lua refuses since phase 7 of the keymap plan, each a key, a list key
--- or an alias a person once set per plugin, all of which config/keymap.lua holds now.
obj.retiredPluginFields = { "key", "mods", "leader", "bindings", "surface", "aliases" }

--- obj.refusePluginKeys(entries) -> entries, problems
--- The person's config/plugins.lua entries with every retired key field taken out, and one
--- problem per field naming config/keymap.lua. The entries are copied where a field is taken, so
--- the person's own table is untouched, and every other field, data and global among them, is
--- kept as it was. Only an entry's own top level fields are read, so a key or an aliases field
--- inside its data is the plugin's data and never refused. A false entry and an entry holding none
--- of the fields come back as they were. An entry left with nothing comes back nil, since an empty
--- table is read by lib/defaults.lua's merge as an empty list replacing every default, which would
--- leave a plugin with no open row, leader, aliases or description.
function obj.refusePluginKeys(entries)
  local out, problems = {}, {}
  local retired = {}
  for _, field in ipairs(obj.retiredPluginFields) do retired[field] = true end
  for _, identity in ipairs(sortedKeys(entries or {})) do
    local entry = entries[identity]
    if type(entry) == "table" then
      local copy, refused = {}, false
      for field, value in pairs(entry) do
        if retired[field] then refused = true else copy[field] = value end
      end
      if refused then
        for _, field in ipairs(obj.retiredPluginFields) do
          if entry[field] ~= nil then
            problems[#problems + 1] = { where = "config/plugins.lua " .. tostring(identity) .. " " .. field,
              why = "is retired, every key, list key and alias a person sets is written in config/keymap.lua, so the field is ignored" }
          end
        end
        if next(copy) ~= nil then out[identity] = copy end
      else
        out[identity] = entry
      end
    else
      out[identity] = entry
    end
  end
  return out, problems
end

--- obj.build(inputs) -> { rows = list, bound = list, problems = list, notes = list, roles = table }
--- rows is every row sorted by chord, the read model. bound is the global rows again in the
--- order the engines receive them, which is the order the paths bound in before the binder
--- existed, since two rows on one key are resolved by that order and only by that order.
--- notes are routine lines, a default a person's chord displaced or a chord false freed, which
--- the root logs and never reports as problems. roles is the roles table it was built with.
--- Reads declarations and nothing else.
---
---   plan        the root's plan, its effective, contexts, identity and order.
---   roles       the role word to leader catalog name table, app and window at least.
---   keycodes    Hammerspoon's keycode table, or nil, in which case a key is only lowercased.
---   shortcuts   what the registry holds as shortcuts, in registration order, entries with a
---               name, a kind and the fn the chord calls.
---   actions     the action descriptors each plugin answered, by directory, already validated.
---   refusedActions the action names each plugin declared and had refused, by directory, or
---               true for a plugin whose whole actions member failed.
---   hostRun     a function from a host's directory to the function its key calls, or nil.
---   cycleRun    a function from an identity and the keycode its cycle row binds to the function
---               that key calls, the stage cycling that identity's presentation, or nil for an
---               identity with none, which refuses the row. Absent, no cycle row binds.
---   standalone  a function answering whether a key, by name, is one no app reads as typing,
---               which a row may bind with neither a leader nor a modifier, or nil for none.
---   personKeys  the keys section readConfig read from config/keymap.lua, or nil.
---   modifierLeaders the leaders the person named, name to its sorted set of modifiers, or nil.
---   compositeLeaders the held leaders that also listen on a set of modifiers, name to that sorted
---               set, or nil. Their rows are checked against every other leader's once the set is
---               counted, see collisions.
---   listLeader  the leader the list role lands on, which a list binding naming no leader binds
---               on, or nil for the app role's leader.
---   known       optional, a function answering whether an identity is a plugin or host at all,
---               so an entry naming one that is switched off this load is a note, not a problem.
---
function obj.build(inputs)
  local plan = assert(inputs and inputs.plan, "keymap needs a plan")
  local roles = assert(inputs.roles, "keymap needs the roles")
  assert(roles.app, "keymap needs the app role")
  local keycodes = inputs.keycodes
  local identityOf = plan.identity or {}
  local rows = {}

  -- The order the engines receive the global rows in, one number per row. The paths this list
  -- replaced bound in three passes, every plugin's own bindings in plan order, then every
  -- registered shortcut in registration order, then the hosts' keys, and
  -- each phase keeps that order so an engine meets two rows on one key exactly as it did.
  local position = {}
  for i, directory in ipairs(plan.order or {}) do position[directory] = i end
  -- Kept beside the rows rather than on them, since the number is a place in the plan's own
  -- order and says nothing a reader of a row needs.
  local placeOf = {}
  local function orderOf(phase, major, minor)
    return phase * 1000000 + (major or 0) * 1000 + (minor or 0)
  end
  local actions = inputs.actions or {}
  local refusedActions = inputs.refusedActions or {}

  -- Any role word the roles table does not know falls back to the app leader, since that is
  -- where the root binds a key that names no other.
  local function leaderOf(role)
    local name = roles[role or "app"] or roles.app
    return tostring(name):lower()
  end
  -- The role a leader answers, the first in word order whose leader it is, or nil for a leader no
  -- role names, a held one a person's chord reached directly or one the person named.
  local roleWords = sortedKeys(roles)
  local function roleOfLeader(name)
    for _, role in ipairs(roleWords) do
      if leaderOf(role) == name then return role end
    end
    return nil
  end
  local modifierLeaders = inputs.modifierLeaders or {}
  local listLeader = inputs.listLeader or leaderOf("app")

  local function add(spec)
    local mods, anyMods = obj.mods(spec.mods)
    -- A plain combination is bound by hs.hotkey, which has no catch all, so one stating no
    -- modifiers is bound demanding none, lib/binder.lua, and its row says so rather than any.
    if anyMods and spec.leader == nil and (spec.layer or GLOBAL) == GLOBAL then
      anyMods = false
    end
    local row = {
      layer = spec.layer or GLOBAL,
      leader = spec.leader,
      role = spec.role,
      key = obj.keyName(spec.key, keycodes),
      mods = mods,
      shownMods = obj.shownMods(mods, anyMods),
      anyMods = anyMods,
      owner = spec.owner,
      action = spec.action,
      source = spec.source,
      when = spec.when,
      priority = spec.priority,
      description = spec.description,
      group = spec.group,
      app = spec.app,
      origin = spec.origin or "default",
      repeats = spec.repeats,
      afterRelease = spec.afterRelease,
      run = spec.run,
      refused = spec.refused,
      quiet = spec.quiet,
      entry = spec.entry,
      field = spec.field,
    }
    rows[#rows + 1] = row
    placeOf[row] = { order = spec.order or math.huge, index = #rows }
  end

  -- The registered tools, by identity, so a chord of a tool is told from a chord of a host. Each
  -- shortcut entry carries the function its chord calls and its place in registration order.
  local registered, kindOf, shortcutOf, shortcutAt = {}, {}, {}, {}
  for i, entry in ipairs(inputs.shortcuts or {}) do
    if type(entry) == "table" and entry.name then
      registered[entry.name] = true
      kindOf[entry.name] = entry.kind
      shortcutOf[entry.name] = entry
      shortcutAt[entry.name] = i
    end
  end

  -- Each source is read on its own. A raise inside one drops the rows that source added, with
  -- one problem naming it, and every other source still builds and binds, so one defect costs
  -- its own keys rather than every global key. The root's pcall around the whole build stays as
  -- the last line of defence.
  local sourceProblems = {}
  local function source(name, read)
    local mark = #rows
    local ok, err = pcall(read)
    if not ok then
      for i = #rows, mark + 1, -1 do
        placeOf[rows[i]] = nil
        rows[i] = nil
      end
      sourceProblems[#sourceProblems + 1] = { where = "the " .. name .. " source",
        why = "reading it raised, " .. tostring(err) .. ", so its keys are left out and every other source still binds" }
    end
  end

  -- Where one bindings row sits. A row names a role of its own, or false for a plain combo with
  -- no leader at all, and a row naming neither inherits the plugin's defaults.leader, which is
  -- what that field is now, the role every row of the plugin takes unless it says otherwise. A
  -- row with no leader must state its modifiers, since a bare key with neither would be taken
  -- from every app, a leader of any other shape is a typo, and so is a role word the roles table
  -- does not know, which used to fall back to the app leader in silence. Each is a problem naming
  -- the word, and the row is not read.
  local function placeOfRow(b, eff)
    if b.leader == false then
      -- A standalone key, the Globe key, is read by no app, so binding it bare takes nothing.
      local bare = inputs.standalone and inputs.standalone(b.key) == true
      if (type(b.mods) ~= "table" or #b.mods == 0) and not bare then
        return nil, "states leader false and no mods, and a key with neither a leader nor a modifier would be taken from every app"
      end
      return { leader = nil, role = nil }
    end
    if b.leader ~= nil and type(b.leader) ~= "string" then
      return nil, "names a leader that is a " .. type(b.leader) .. ", where a row takes a role word or false"
    end
    local role = b.leader or eff.leader or "app"
    if type(role) ~= "string" or not roles[role] then
      return nil, "names the leader role '" .. tostring(role) .. "', which no leader answers"
    end
    return { leader = leaderOf(role), role = role }
  end
  local rowProblems = {}
  local function badRow(owner, b, why)
    rowProblems[#rowProblems + 1] = { where = tostring(owner) .. " " .. tostring(b.action),
      why = "the bindings row " .. why .. ", so it is not bound" }
  end

  -- An open row belongs to the open keys source, unless the plugin answers a descriptor named
  -- open of its own, in which case it is an ordinary binding running that descriptor. A cycle row
  -- is the same, the other way the core shows a tool's list.
  local function isOpenRow(directory, b)
    return (b.action == "open" or b.action == "cycle") and not (actions[directory] or {})[b.action]
  end

  -- What a cycle row of a tool calls, the stage cycling that tool's list, or nil and why. The
  -- root answers nil for an identity with no presentation, a host or a plugin with no list.
  local function cycleOf(owner, key)
    local run = inputs.cycleRun and inputs.cycleRun(owner, obj.keyCode(key, keycodes)) or nil
    if not run then return nil, "names cycle, which needs a presentation the stage can show, and this plugin declares none" end
    return run
  end

  source("open keys", function()
    for hostIndex, directory in ipairs(sortedKeys(plan.effective)) do
      local eff = plan.effective[directory]
      local owner = identityOf[directory] or directory

      -- The open row of a tool, or of a host that is not a tool. A tool's key sits on whatever
      -- leader its row names, the window leader included, and a tool registered with a global
      -- shortcut is a plain combo. A host's key calls whatever the root answers for it. Every row
      -- here is the manifest's, since config/plugins.lua holds no key since phase 7 of the keymap
      -- plan, so a row is the person's only when config/keymap.lua set it, below.
      for _, b in ipairs(eff.bindings or {}) do
        if isOpenRow(directory, b) then
          local place, why = placeOfRow(b, eff)
          local entry = shortcutOf[owner]
          local origin = "default"
          if not place then
            badRow(owner, b, why)
          elseif b.action == "cycle" then
            -- A cycle row binds on the leader it names like an open row, and calls the stage
            -- cycling the tool's list rather than opening it.
            local run, cycleWhy = cycleOf(owner, b.key)
            if not run then
              badRow(owner, b, cycleWhy)
            else
              add({
                leader = place.leader, role = place.role, key = b.key, mods = b.mods, owner = owner,
                action = "cycle", source = "cycle",
                description = b.description or eff.description, origin = origin,
                run = run, order = orderOf(2, shortcutAt[owner], 1),
              })
            end
          elseif entry then
            local global = kindOf[owner] == "global"
            add({
              leader = not global and place.leader or nil, role = not global and place.role or nil,
              key = b.key, mods = b.mods, owner = owner,
              action = "open", source = "tool",
              description = b.description or eff.description, origin = origin,
              run = entry.fn, order = orderOf(2, shortcutAt[owner]),
            })
          else
            -- A host with a key and no way to be shown, or no leader, was skipped in silence
            -- before the binder existed, so its row is kept for the collision check and left
            -- unbound without a line.
            local run = inputs.hostRun and inputs.hostRun(directory) or nil
            add({
              leader = place.leader, role = place.role, key = b.key, mods = b.mods, owner = owner,
              action = "open", source = "host",
              description = b.description or eff.description, origin = origin,
              run = run, quiet = run == nil,
              order = orderOf(3, hostIndex),
            })
          end
        end
      end
    end
  end)

  source("bindings", function()
    for _, directory in ipairs(sortedKeys(plan.effective)) do
      local eff = plan.effective[directory]
      local owner = identityOf[directory] or directory
      -- A plugin's own bindings, each with its own key, modifiers and gate, each running the
      -- descriptor its action names. The binding's own gate, repeat and label win, and the
      -- descriptor's answer them where the binding is silent.
      local answered = actions[directory] or {}
      -- true when the plugin's whole provides.actions member failed, which that failure has
      -- already said once, otherwise the set of action names that were refused one by one.
      local refusedHere = refusedActions[directory]
      for i, b in ipairs(eff.bindings or {}) do
        if not isOpenRow(directory, b) then
          local place, why = placeOfRow(b, eff)
          if not place then
            badRow(owner, b, why)
          else
            local descriptor = answered[b.action]
            local repeats = b.repeats
            if repeats == nil and descriptor then repeats = descriptor.repeats end
            add({
              leader = place.leader, role = place.role, key = b.key, mods = b.mods, owner = owner,
              action = b.action, source = "bindings", when = b.when or (descriptor and descriptor.when),
              priority = b.priority,
              description = b.description or (descriptor and descriptor.description),
              group = descriptor and descriptor.group or nil,
              app = descriptor and descriptor.app or nil,
              origin = "default",
              repeats = repeats, run = descriptor and descriptor.run or nil,
              afterRelease = descriptor and descriptor.afterRelease or nil,
              refused = refusedHere == true
                or (type(refusedHere) == "table" and refusedHere[b.action] == true),
              order = orderOf(1, position[directory], i),
            })
          end
        end
      end
    end
  end)

  -- Every list's context bindings, live only while that list is open. Each binds on the leader it
  -- names, which applyLists placed every default on, the list role's leader, and falls back to
  -- listLeader for a block that never went through it, under the context's own gate and priority.
  -- A binding that says chord is false is listed for reading and never bound as a key. The
  -- person's lists section is already laid over them by applyLists, so a binding it moved names
  -- its entry and is the person's.
  source("list keys", function()
    for _, name in ipairs(sortedKeys(plan.contexts)) do
      local block = plan.contexts[name]
      for _, b in ipairs(block.bindings or {}) do
        if b.chord ~= false then
          -- A binding the open list's field answers, leader false for modifiers alone or a leader
          -- the person named, binds on no held leader, so its row names that named leader or none
          -- and marks field.
          local field = b.leader == false or (b.leader ~= nil and modifierLeaders[b.leader] ~= nil)
          local leader
          if b.leader == false then leader = nil else leader = b.leader or listLeader end
          add({
            layer = name, leader = leader, role = not field and roleOfLeader(leader) or nil, key = b.key,
            mods = (field and b.leader == false) and (b.mods or {}) or b.mods, owner = name, field = field or nil,
            action = b.action, source = "context", when = block.when, priority = block.priority,
            description = b.description, origin = b.entry and "user" or "default", entry = b.entry,
          })
        end
      end
    end
  end)

  -- The person's keymap, laid over every default above. Read after the sources, since an entry
  -- may name any action any of them answers and takes its gate, its repeat and its label from
  -- the row that action had, so a moved action behaves exactly as it did on its old chord.
  local notes = {}
  local function idOf(row) return tostring(row.owner) .. "." .. tostring(row.action) end
  -- Tools whose open row the person moved, freed or displaced, which the check for a tool with
  -- no key below leaves alone, since the person asked for that.
  local touchedOpen = {}
  local function drop(test)
    local kept, dropped = {}, {}
    for _, row in ipairs(rows) do
      if test(row) then
        dropped[#dropped + 1] = row
        placeOf[row] = nil
        if row.source == "tool" then touchedOpen[row.owner] = true end
      else
        kept[#kept + 1] = row
      end
    end
    rows = kept
    return dropped
  end

  local person = inputs.personKeys or {}
  if #person > 0 then
    local dirOf, hostIndexOf = {}, {}
    for i, directory in ipairs(sortedKeys(plan.effective)) do
      dirOf[identityOf[directory] or directory] = directory
      hostIndexOf[directory] = i
    end
    -- The first global row each action holds before the person's keys, in binding order, which a
    -- moved action copies everything but its chord from.
    local template = {}
    for _, row in ipairs(rows) do
      if row.layer == GLOBAL then
        local id = idOf(row)
        local held = template[id]
        if not held or placeOf[row].order < placeOf[held].order then template[id] = row end
      end
    end

    -- What one action id names, the row it had, else a descriptor, a refused descriptor, or a
    -- tool's or a host's open, each with the place in binding order
    -- that action's own rows would take, or nil and why for an id naming nothing.
    local function resolveTarget(entry)
      local directory = dirOf[entry.owner]
      if not directory then
        -- A plugin that exists and is switched off this load, or left out for a missing tool,
        -- takes its keys with it, which is what switching it off asks for, so its entry is a
        -- routine note rather than a problem.
        if inputs.known and inputs.known(entry.owner) then
          return nil, nil, "the keymap entry '" .. tostring(entry.text) .. "' names " .. entry.owner
            .. ", which is not running this load, so it binds nothing"
        end
        return nil, "names '" .. entry.owner .. "', which is no plugin or host in this load"
      end
      local id = entry.owner .. "." .. entry.action
      local held = template[id]
      if held then
        local copy = {}
        for k, v in pairs(held) do copy[k] = v end
        copy.order = placeOf[held].order
        return copy
      end
      local eff = plan.effective[directory] or {}
      local descriptor = (actions[directory] or {})[entry.action]
      local refusedHere = refusedActions[directory]
      local tail = orderOf(1, position[directory], 900)
      if descriptor then
        return { source = "bindings", run = descriptor.run, when = descriptor.when,
          description = descriptor.description, group = descriptor.group, app = descriptor.app,
          repeats = descriptor.repeats, afterRelease = descriptor.afterRelease, order = tail }
      end
      if refusedHere == true or (type(refusedHere) == "table" and refusedHere[entry.action]) then
        return { source = "bindings", refused = true, order = tail }
      end
      if entry.action == "cycle" then
        local run, why = cycleOf(entry.owner, entry.key)
        if not run then return nil, why end
        return { source = "cycle", run = run, description = eff.description,
          order = orderOf(2, shortcutAt[entry.owner], 1) }
      end
      if entry.action == "open" then
        local shortcut = shortcutOf[entry.owner]
        if shortcut then
          return { source = "tool", run = shortcut.fn, description = eff.description,
            order = orderOf(2, shortcutAt[entry.owner]) }
        end
        local run = inputs.hostRun and inputs.hostRun(directory) or nil
        if run then
          return { source = "host", run = run, description = eff.description,
            order = orderOf(3, hostIndexOf[directory]) }
        end
      end
      return nil, "names the action '" .. entry.action .. "', which '" .. entry.owner .. "' does not answer"
    end

    local wanted, frees, named = {}, {}, {}
    for _, entry in ipairs(person) do
      if entry.free then
        frees[#frees + 1] = entry
      else
        local target, why, note = resolveTarget(entry)
        if note then
          notes[#notes + 1] = note
        elseif not target then
          rowProblems[#rowProblems + 1] = { where = "config/keymap.lua keys " .. tostring(entry.text),
            why = "the entry " .. why .. ", so the entry is ignored" }
        else
          wanted[#wanted + 1] = { entry = entry, target = target }
          named[entry.owner .. "." .. entry.action] = true
        end
      end
    end

    -- An action the person named takes exactly the chords listed for it, so every row it had goes.
    drop(function(row) return row.layer == GLOBAL and named[idOf(row)] == true end)
    for _, w in ipairs(wanted) do
      local e, t = w.entry, w.target
      add({
        leader = e.leader, role = e.leader and roleOfLeader(e.leader) or nil,
        key = e.key, mods = e.mods, owner = e.owner, action = e.action, source = t.source,
        when = t.when, priority = t.priority, description = t.description, group = t.group,
        app = t.app, origin = "user", repeats = t.repeats, afterRelease = t.afterRelease, run = t.run,
        refused = t.refused, quiet = t.quiet, order = t.order, entry = e.text,
      })
    end

    -- false frees a chord. Whatever row holds it is dropped and nothing is bound there, said in one
    -- routine line, and a chord another of the person's own entries takes is that entry's, which
    -- is two of the person's own chords on one slot and one problem.
    for _, e in ipairs(frees) do
      local mods, anyMods = obj.mods(e.mods)
      local slot = slotOf({ layer = GLOBAL, leader = e.leader, key = e.key, mods = mods, anyMods = anyMods }, modifierLeaders)
      local taken = nil
      for _, row in ipairs(rows) do
        if row.entry and slotOf(row, modifierLeaders) == slot then taken = row break end
      end
      if taken then
        rowProblems[#rowProblems + 1] = { where = "config/keymap.lua keys " .. tostring(e.text),
          why = "the entry frees a chord the entry '" .. tostring(taken.entry) .. "' takes, two of the person's own chords on one slot, so the chord stays bound to " .. idOf(taken) }
      else
        local dropped = drop(function(row) return row.layer == GLOBAL and slotOf(row, modifierLeaders) == slot end)
        if #dropped == 0 then
          notes[#notes + 1] = "the keymap entry '" .. tostring(e.text) .. "' frees a chord no row holds"
        end
        for _, row in ipairs(dropped) do
          notes[#notes + 1] = "the keymap entry '" .. tostring(e.text) .. "' frees the chord, so "
            .. idOf(row) .. " is not bound there"
        end
      end
    end
  end

  -- A row the person set wins its slot over a shipped default, which is dropped rather than bound
  -- beside it, with one routine line naming what was displaced, so a default never meets a
  -- person's row in the collision check below. The person's rows are the keymap's entries, the one
  -- file a person writes keys in, since config/plugins.lua refuses every key field.
  local userSlot = {}
  for _, row in ipairs(rows) do
    if row.layer == GLOBAL and row.origin == "user" then
      local slot = slotOf(row, modifierLeaders)
      userSlot[slot] = userSlot[slot] or row
    end
  end
  for _, row in ipairs(drop(function(row)
    return row.layer == GLOBAL and row.origin ~= "user" and userSlot[slotOf(row, modifierLeaders)] ~= nil
  end)) do
    local winner = userSlot[slotOf(row, modifierLeaders)]
    notes[#notes + 1] = "the keymap entry '" .. tostring(winner.entry) .. "' takes " .. obj.chordText(row) .. ", so the default "
      .. idOf(row) .. " is not bound there"
  end

  -- A leader the person named that no row uses is said once, a routine line, since a name nothing
  -- reaches is most often a chord that was meant for it and spelled another way.
  local usedLeader = {}
  for _, row in ipairs(rows) do
    if row.leader then usedLeader[row.leader] = true end
  end
  for _, name in ipairs(sortedKeys(modifierLeaders)) do
    if not usedLeader[name] then
      notes[#notes + 1] = "the leader " .. tostring(name) .. " is named in config/keymap.lua and no chord uses it"
    end
  end

  -- A registered tool with a leader shortcut and no open row has no key, which a manifest without
  -- one never means. Said once per tool, and quiet where the person's keymap moved, freed or
  -- displaced its open row, since the person asked for that.
  local hasOpen = {}
  for _, row in ipairs(rows) do
    if row.source == "tool" then hasOpen[row.owner] = true end
  end
  for _, entry in ipairs(inputs.shortcuts or {}) do
    if type(entry) == "table" and entry.kind == "leader" and not hasOpen[entry.name] and not touchedOpen[entry.name] then
      rowProblems[#rowProblems + 1] = { where = tostring(entry.name) .. " open",
        why = "the registered tool has a leader shortcut and no bindings row whose action is open, so it has no key" }
    end
  end

  local bound = {}
  for _, row in ipairs(rows) do
    if row.layer == GLOBAL then bound[#bound + 1] = row end
  end
  table.sort(bound, function(a, b)
    local pa, pb = placeOf[a], placeOf[b]
    if pa.order ~= pb.order then return pa.order < pb.order end
    return pa.index < pb.index
  end)

  table.sort(rows, function(a, b)
    local ka = table.concat({ a.layer, a.leader or "", a.key, rowModsText(a), a.action or "", a.owner or "" }, "\0")
    local kb = table.concat({ b.layer, b.leader or "", b.key, rowModsText(b), b.action or "", b.owner or "" }, "\0")
    return ka < kb
  end)

  local problems = obj.collisions(rows, modifierLeaders, inputs.compositeLeaders)
  for _, problem in ipairs(rowProblems) do problems[#problems + 1] = problem end
  for _, problem in ipairs(sourceProblems) do problems[#problems + 1] = problem end
  return { rows = rows, bound = bound, problems = problems, notes = notes, roles = roles }
end

--------------------------------------------------------------------------------
-- Collisions
--------------------------------------------------------------------------------

--- obj.chordText(row) -> string
--- The chord the way a person reads it, the leader, the modifiers, then the key, joined with a
--- plus. A catch all says so after it, since it is a different binding from the bare chord.
function obj.chordText(row)
  local parts = {}
  if row.leader then parts[#parts + 1] = row.leader end
  for _, m in ipairs(row.mods) do parts[#parts + 1] = m end
  parts[#parts + 1] = row.key
  local text = table.concat(parts, "+")
  if row.anyMods then text = text .. " with any modifiers" end
  return text
end

--- obj.collisions(rows, modifierLeaders) -> list of problems
--- Two rows collide when they claim one slot, layer, leader, key and modifiers, where a leader
--- the person named from a set of modifiers claims the whole combination with no leader, see
--- slotOf. A catch all and an exact modifier row on one key are different slots, since every
--- resolver prefers the exact one, and rows in different layers never meet, which is how a global
--- key and a list key share a chord on purpose.
---
--- By the time this runs a shipped default never meets a row the person set, since build drops the
--- default on a slot the person took. That replaced the one exemption the old check kept, where the
--- pair was left to bind side by side unreported. So every pair still here is reported, two
--- defaults, a fact about the repository the same on every machine, and two of the person's own,
--- each named by the keymap entry where the keymap set it. Nothing here picks a winner, the pair is
--- named and the fix is left to a person.
function obj.collisions(rows, modifierLeaders, compositeLeaders)
  local first, order, extra = {}, {}, {}
  for _, row in ipairs(rows) do
    local id = slotOf(row, modifierLeaders)
    if not first[id] then
      first[id] = row
      order[#order + 1] = id
    else
      extra[id] = extra[id] or {}
      table.insert(extra[id], row)
    end
  end

  local function named(row)
    local text = "'" .. tostring(row.owner) .. "' action '" .. tostring(row.action) .. "'"
    if row.entry then text = text .. " from the keymap entry '" .. tostring(row.entry) .. "'" end
    return text
  end
  local problems = {}
  for _, id in ipairs(order) do
    local a = first[id]
    for _, b in ipairs(extra[id] or {}) do
      local where = obj.chordText(b) .. " in " .. b.layer
      if b.entry then
        where = "config/keymap.lua " .. (b.layer == GLOBAL and "keys " or "lists ") .. tostring(b.entry)
      end
      problems[#problems + 1] = {
        where = where,
        why = named(a) .. " and " .. named(b) .. " both bind "
          .. obj.chordText(b) .. " in the " .. b.layer .. " layer, so one of them can never be reached by it",
      }
    end
  end

  -- A held leader that also listens on a set of modifiers claims each of its global rows a second
  -- time, as that set united with the row's own modifiers, except a row asking for a modifier the
  -- set already holds, which its modifier half leaves to the held key. So a meta row adding cmd and
  -- a hyper row on the same key, once both listen on modifiers, are one physical combination, and
  -- so are such a row and a plain combo or a modifier leader's row on that same combination. Each
  -- such pair on different leaders is one problem naming both. A pair two leaders of modifiers
  -- alone would make is the check above, so only a pair holding a composite row is said here.
  local physical, physicalOrder = {}, {}
  local function claimPhysical(row, mods, composite)
    local spelled = table.concat(mods, "+")
    local slot = table.concat({ GLOBAL, row.key, spelled }, "\0")
    if not physical[slot] then
      physical[slot] = {}
      physicalOrder[#physicalOrder + 1] = slot
    end
    table.insert(physical[slot], { row = row, composite = composite,
      spelled = (spelled ~= "" and spelled .. "+" or "") .. tostring(row.key) })
  end
  for _, row in ipairs(rows) do
    if row.layer == GLOBAL then
      local base = row.leader and (compositeLeaders or {})[row.leader]
      if base then
        local held = {}
        for _, m in ipairs(base) do held[m] = true end
        local overlaps = false
        for _, m in ipairs(row.mods or {}) do
          if held[m] then overlaps = true end
        end
        if not overlaps then
          local union = {}
          for _, m in ipairs(base) do union[#union + 1] = m end
          for _, m in ipairs(row.mods or {}) do union[#union + 1] = m end
          claimPhysical(row, (obj.mods(union)), true)
        end
      elseif row.leader == nil or (modifierLeaders or {})[row.leader] then
        local mods = row.mods or {}
        if row.leader then
          local union = {}
          for _, m in ipairs(modifierLeaders[row.leader]) do union[#union + 1] = m end
          for _, m in ipairs(mods) do union[#union + 1] = m end
          mods = obj.mods(union)
        end
        claimPhysical(row, mods, false)
      end
    end
  end
  for _, slot in ipairs(physicalOrder) do
    local claims = physical[slot]
    for i = 1, #claims do
      for j = i + 1, #claims do
        local a, b = claims[i], claims[j]
        if (a.composite or b.composite) and a.row.leader ~= b.row.leader then
          local where = obj.chordText(b.row) .. " in " .. GLOBAL
          if b.row.entry then where = "config/keymap.lua keys " .. tostring(b.row.entry) end
          problems[#problems + 1] = {
            where = where,
            why = named(a.row) .. " on " .. obj.chordText(a.row) .. " and " .. named(b.row) .. " on "
              .. obj.chordText(b.row) .. " both claim " .. b.spelled .. " once a leader's modifiers are counted, so on a "
              .. "machine sending that leader as modifiers one of them can never be reached by it",
          }
        end
      end
    end
  end
  return problems
end

--- obj.fallbackLeaders(roles, listLeaders) -> sorted list of leader names
--- The leaders in use when the keymap failed to build and binds no global key. Every leader a role
--- names, lowercased the way a row spells it, and every leader a list key binds on, one name or a
--- list of them, which the contexts still bind on, so every list keeps its keys even where the
--- roles moved the app role off its leader.
function obj.fallbackLeaders(roles, listLeaders)
  local seen, out = {}, {}
  local function add(name)
    if name and not seen[name] then seen[name] = true out[#out + 1] = name end
  end
  for _, catalogName in pairs(roles or {}) do add(tostring(catalogName):lower()) end
  if type(listLeaders) == "table" then
    for _, name in ipairs(listLeaders) do add(name) end
  else
    add(listLeaders)
  end
  table.sort(out)
  return out
end

--- obj.leadersInUse(built) -> sorted list of leader names
--- Every leader some row of a built keymap binds on, the names a row spells, so a held leader is
--- remapped exactly while a chord uses it. A global row counts when the binder will bind it, a
--- function to run and neither refused nor quiet, and a list key counts always, since the contexts
--- bind it. A plain combo names no leader and is never in the answer.
function obj.leadersInUse(built)
  local seen, out = {}, {}
  for _, row in ipairs((built or {}).rows or {}) do
    local live = not row.field
    if row.layer == GLOBAL then
      live = type(row.run) == "function" and not row.refused and not row.quiet
    end
    if live and row.leader ~= nil and not seen[row.leader] then
      seen[row.leader] = true
      out[#out + 1] = row.leader
    end
  end
  table.sort(out)
  return out
end

return obj
