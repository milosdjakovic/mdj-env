-- The keymap, one read model of every chord Olm binds.
--
-- Every key Olm binds comes from one of four sources, a tool's or a host's open row, a plugin's
-- own bindings, a host's included, rows a plugin provides from its own data, and every list's
-- context bindings, and then the person's own keymap, config/keymap.lua, is laid over them. A
-- tool's open key is not a field of its own
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
-- plugin ever reads, into its four sections, and build lays the keys section over the defaults by
-- three rules. An action the person names takes exactly the chords listed for it and loses every
-- row it had. A row the person set wins a slot a default holds, and the default row on that slot
-- is dropped with one routine note naming it, never bound beside it. And false frees a chord,
-- dropping whatever default holds it with nothing bound there. The notes come back beside the
-- problems for the root to log.
--
-- The row.
--
--   layer       the word global for a key live whenever its leader is held, or always for a plain
--               combo, otherwise the name of the list the key is live in while that list is open.
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
--   action      what the chord does, open for a tool's or a host's open row, the app name for a
--               toggle, and the binding's own action name for everything else.
--   source      one word naming the path, tool, host, bindings, provided or context. A row the
--               person's keymap set keeps the source of the action it runs, so every reader
--               treats it as it treats that action's own default.
--   when        the predicate gating the chord, where there is one.
--   priority    the context priority, where there is one.
--   description the declared label, the binding's own, else the descriptor's, else for an open
--               row the plugin's own description.
--   group       the section a cheat sheet files the row under, the descriptor's own group, a word or a
--               function answering one, or nil for the sheet's default section.
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
--
-- The lines this module can name are problems. A problem is a table with where, the chord, and
-- why, one sentence, so the root can hand each straight to the wiring report.

local obj = {}

local GLOBAL = "global"

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

-- user when any of the named paths came from the person, otherwise default. A provenance
-- table is keyed by dotted path and a list is one entry, so bindings is a single path.
local function originOf(prov, ...)
  for i = 1, select("#", ...) do
    if (prov or {})[(select(i, ...))] == "user" then return "user" end
  end
  return "default"
end

--------------------------------------------------------------------------------
-- The person's keymap, config/keymap.lua, read into one shape
--------------------------------------------------------------------------------

-- The sections the file may hold. lists joins them in phase 7 of the keymap plan.
local SECTIONS = { "keys", "leaders", "roles", "aliases" }
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

--- obj.parseChord(text, leaders, keycodes) -> chord or nil, why
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
function obj.parseChord(text, leaders, keycodes)
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
  if not leader and #mods == 0 then
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

--- obj.readConfig(config, opts) -> { keys, leaders, roles, aliases, problems }
--- config/keymap.lua as one shape, every entry checked here so the rest of Olm reads clean data.
---   opts.catalog    the leader catalog, whose names lowercased are the built in held leaders.
---   opts.roleWords  the role words a default may name, app and window.
---   opts.keycodes   the keycode table a key is spelled with, or nil.
---
--- leaders is a list of { name, mods }, a name the person gave a set of real modifiers, sorted by
--- name. roles maps a role word to the catalog name of the held leader it moves to. aliases maps a
--- plugin or host identity to its words, the identity checked by the caller, which knows the
--- plugins. keys is a list, sorted by the chord as written, of { text, leader, mods, key, free,
--- owner, action }, free true for an entry answering false. Every entry that cannot be read is one
--- problem naming the entry and is left out, and every other entry is still read.
function obj.readConfig(config, opts)
  opts = opts or {}
  local out = { keys = {}, leaders = {}, roles = {}, aliases = {}, problems = {} }
  local function problem(where, why)
    out.problems[#out.problems + 1] = { where = "config/keymap.lua " .. where, why = why }
  end
  if config == nil then return out end
  if type(config) ~= "table" then
    problem("itself", "answers a " .. type(config) .. " rather than a table, so every key keeps its default")
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

  local held = {}
  for name in pairs(opts.catalog or {}) do held[tostring(name):lower()] = name end
  local roleWord = {}
  for _, word in ipairs(opts.roleWords or {}) do roleWord[word] = true end

  -- The leaders a chord may open with, the held ones and then every set the person named.
  local chordLeaders = {}
  for lower in pairs(held) do chordLeaders[lower] = true end
  local leaders = section("leaders")
  for _, name in ipairs(sortedKeys(leaders)) do
    local where = "leaders " .. tostring(name)
    local set = leaders[name]
    local lower = type(name) == "string" and name:lower() or nil
    if not lower or not lower:match("^%a%w*$") then
      problem(where, "is not a name, a leader is one word of letters and digits, so it is ignored")
    elseif held[lower] then
      problem(where, "is the name of the built in held leader " .. held[lower] .. ", so it is ignored")
    elseif CHORD_MODS[lower] then
      problem(where, "is a modifier word, so a chord could not tell the two apart, and it is ignored")
    elseif roleWord[lower] then
      problem(where, "is a role word a plugin's defaults name, so it is ignored")
    elseif chordLeaders[lower] ~= nil then
      problem(where, "names a leader already named in another case, so it is ignored")
    elseif type(set) ~= "table" or #set == 0 then
      problem(where, "is not a list of modifiers, or an empty one, so it is ignored")
    else
      local mods, bad = {}, nil
      for _, m in ipairs(set) do
        local word = tostring(m):lower()
        if not LEADER_MODS[word] then bad = tostring(m) break end
        mods[#mods + 1] = word
      end
      if bad then
        problem(where, "holds '" .. bad .. "', and a leader holds only shift, ctrl, alt and cmd, so it is ignored")
      else
        local list = obj.mods(mods)
        chordLeaders[lower] = list
        out.leaders[#out.leaders + 1] = { name = lower, mods = list }
      end
    end
  end

  local roles = section("roles")
  for _, role in ipairs(sortedKeys(roles)) do
    local where = "roles " .. tostring(role)
    local value = roles[role]
    if not roleWord[role] then
      problem(where, "is not a role a plugin's defaults name, which are "
        .. table.concat(opts.roleWords or {}, " and ") .. ", so it is ignored")
    elseif type(value) ~= "string" or not held[value:lower()] then
      problem(where, "names '" .. tostring(value) .. "', which is no held leader, so the role keeps its default")
    else
      out.roles[role] = held[value:lower()]
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
      local chord, why = obj.parseChord(text, chordLeaders, opts.keycodes)
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
  return out
end

--- obj.build(inputs) -> { rows = list, bound = list, problems = list, notes = list, roles = table }
--- rows is every row sorted by chord, the read model. bound is the global rows again in the
--- order the engines receive them, which is the order the paths bound in before the binder
--- existed, since two rows on one key are resolved by that order and only by that order.
--- notes are routine lines, a default a person's chord displaced or a chord false freed, which
--- the root logs and never reports as problems. roles is the roles table it was built with.
--- Reads declarations and nothing else.
---
---   plan        the root's plan, its effective, provenance, contexts, identity and order.
---   roles       the role word to leader catalog name table, app and window at least.
---   keycodes    Hammerspoon's keycode table, or nil, in which case a key is only lowercased.
---   shortcuts   what the registry holds as shortcuts, in registration order, entries with a
---               name, a kind and the fn the chord calls.
---   actions     the action descriptors each plugin answered, by directory, already validated.
---   refusedActions the action names each plugin declared and had refused, by directory, or
---               true for a plugin whose whole actions member failed.
---   provided    the rows a plugin answered through provides.bindings, by directory, each with
---               its own action, key, mods, leader role or none, description and fn.
---   hostRun     a function from a host's directory to the function its key calls, or nil.
---   personKeys  the keys section readConfig read from config/keymap.lua, or nil.
---   modifierLeaders the leaders the person named, name to its sorted set of modifiers, or nil.
---   listLeader  the leader every list key binds on, the one whose policy turns contexts on, or
---               nil for the app role's leader.
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
      origin = spec.origin or "default",
      repeats = spec.repeats,
      afterRelease = spec.afterRelease,
      run = spec.run,
      refused = spec.refused,
      quiet = spec.quiet,
      entry = spec.entry,
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
      if type(b.mods) ~= "table" or #b.mods == 0 then
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
  -- open of its own, in which case it is an ordinary binding running that descriptor.
  local function isOpenRow(directory, b)
    return b.action == "open" and not (actions[directory] or {}).open
  end

  source("open keys", function()
    for hostIndex, directory in ipairs(sortedKeys(plan.effective)) do
      local eff = plan.effective[directory]
      local owner = identityOf[directory] or directory
      local prov = (plan.provenance or {})[directory] or {}

      -- The open row of a tool, or of a host that is not a tool. A tool's key sits on whatever
      -- leader its row names, the window leader included, and a tool registered with a global
      -- shortcut is a plain combo. A host's key calls whatever the root answers for it. The
      -- person's key override arrives on this row too, see lib/defaults.lua, so its origin
      -- also reads the key and mods paths.
      for _, b in ipairs(eff.bindings or {}) do
        if isOpenRow(directory, b) then
          local place, why = placeOfRow(b, eff)
          local entry = shortcutOf[owner]
          local origin = originOf(prov, "bindings", "key", "mods", "leader")
          if not place then
            badRow(owner, b, why)
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
      local prov = (plan.provenance or {})[directory] or {}
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
              origin = originOf(prov, "bindings"),
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

  -- Every list's context bindings, live only while that list is open. They bind on the leader
  -- whose policy turns contexts on, the app role's leader unless the root says otherwise, under
  -- the context's own gate and priority. A binding that says chord is false is listed for
  -- reading and never bound as a key.
  source("list keys", function()
    for _, name in ipairs(sortedKeys(plan.contexts)) do
      local block = plan.contexts[name]
      for _, b in ipairs(block.bindings or {}) do
        if b.chord ~= false then
          add({
            layer = name, leader = listLeader, role = roleOfLeader(listLeader), key = b.key, mods = b.mods, owner = name,
            action = b.action, source = "context", when = block.when, priority = block.priority,
            description = b.description, origin = "default",
          })
        end
      end
    end
  end)

  -- The rows a plugin answered through provides.bindings, each complete with its own function.
  -- A row naming a leader role sits on that role's leader and one naming none is a plain combo.
  -- This is a bridge for a plugin whose keys are still built from the person's own data, so
  -- every row of it is the person's, which is how the collision check has always classed them.
  source("provided rows", function()
    for _, directory in ipairs(sortedKeys(inputs.provided)) do
      local owner = identityOf[directory] or directory
      for i, r in ipairs(inputs.provided[directory] or {}) do
        -- A key on a leader stating no modifiers is a catch all, as it is everywhere, while a plain
        -- combo always states its own.
        local mods = r.mods
        if not r.leader and mods == nil then mods = {} end
        add({
          leader = r.leader and leaderOf(r.leader) or nil,
          role = r.leader and (roles[r.leader] and r.leader or "app") or nil,
          key = r.key, mods = mods, owner = owner,
          action = r.action, source = "provided", when = r.when, description = r.description,
          origin = "user", repeats = r.repeats, run = r.fn,
          order = orderOf(1, position[directory], i),
        })
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
    local template, rowsOfId = {}, {}
    for _, row in ipairs(rows) do
      if row.layer == GLOBAL then
        local id = idOf(row)
        local held = template[id]
        if not held or placeOf[row].order < placeOf[held].order then template[id] = row end
        rowsOfId[id] = rowsOfId[id] or {}
        table.insert(rowsOfId[id], row)
      end
    end

    -- What one action id names, the row it had, else a descriptor, a refused descriptor, a
    -- tool's or a host's open, or a row the plugin provides, each with the place in binding order
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
      -- One id over several rows running different functions is two actions sharing a name, the
      -- app toggler's two toggles of one app until phase 6 gives a variant an id of its own. Moving
      -- one would move both and keep only the first's behaviour in silence, so the entry is refused
      -- and both rows stay bound where they are.
      local runsSeen, distinct, chords = {}, 0, {}
      for _, row in ipairs(rowsOfId[id] or {}) do
        if row.run ~= nil and not runsSeen[row.run] then
          runsSeen[row.run] = true
          distinct = distinct + 1
        end
        chords[#chords + 1] = obj.chordText(row)
      end
      if distinct > 1 then
        table.sort(chords)
        return nil, "names " .. id .. ", which answers " .. #chords .. " rows running different functions, "
          .. table.concat(chords, " and ") .. ", so both stay bound where they are"
      end
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
          description = descriptor.description, group = descriptor.group,
          repeats = descriptor.repeats, afterRelease = descriptor.afterRelease, order = tail }
      end
      if refusedHere == true or (type(refusedHere) == "table" and refusedHere[entry.action]) then
        return { source = "bindings", refused = true, order = tail }
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
      for i, r in ipairs((inputs.provided or {})[directory] or {}) do
        if r.action == entry.action then
          return { source = "provided", run = r.fn, when = r.when, description = r.description,
            repeats = r.repeats, order = orderOf(1, position[directory], i) }
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
        origin = "user", repeats = t.repeats, afterRelease = t.afterRelease, run = t.run,
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
  -- beside it, with one routine line naming what was displaced. The person's own rows are the
  -- keymap's entries and also the rows still built from the person's other files, a toggle or a
  -- binding written in config/plugins.lua, so one rule answers every one of them, and a default
  -- never meets a person's row in the collision check below. A keymap entry ranks above every
  -- other source of the person's, since it is the one file a person writes keys in, so it drops a
  -- toggle on its slot first, the same way and with the same line.
  local entrySlot = {}
  for _, row in ipairs(rows) do
    if row.layer == GLOBAL and row.entry then
      local slot = slotOf(row, modifierLeaders)
      entrySlot[slot] = entrySlot[slot] or row
    end
  end
  for _, row in ipairs(drop(function(row)
    return row.layer == GLOBAL and not row.entry and row.origin == "user"
      and entrySlot[slotOf(row, modifierLeaders)] ~= nil
  end)) do
    local winner = entrySlot[slotOf(row, modifierLeaders)]
    notes[#notes + 1] = "the keymap entry '" .. tostring(winner.entry) .. "' takes " .. obj.chordText(row)
      .. ", so the person's own " .. idOf(row) .. " is not bound there"
  end
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
    local by = winner.entry and ("the keymap entry '" .. tostring(winner.entry) .. "'")
      or ("the person's own " .. idOf(winner))
    notes[#notes + 1] = by .. " takes " .. obj.chordText(row) .. ", so the default "
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

  -- A registered tool with a leader shortcut and no open row has no key, which the person's own
  -- key NONE or false asks for and anything else, a bindings override that dropped the row or a
  -- manifest without one, does not. Said once per tool, and quiet where the person unbound it.
  local hasOpen = {}
  for _, row in ipairs(rows) do
    if row.source == "tool" then hasOpen[row.owner] = true end
  end
  local directoryOf = {}
  for directory in pairs(plan.effective or {}) do directoryOf[identityOf[directory] or directory] = directory end
  for _, entry in ipairs(inputs.shortcuts or {}) do
    if type(entry) == "table" and entry.kind == "leader" and not hasOpen[entry.name] and not touchedOpen[entry.name] then
      local directory = directoryOf[entry.name]
      local prov = directory and (plan.provenance or {})[directory] or {}
      if prov.key ~= "user" then
        rowProblems[#rowProblems + 1] = { where = tostring(entry.name) .. " open",
          why = "the registered tool has a leader shortcut and no bindings row whose action is open, so it has no key" }
      end
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

  local problems = obj.collisions(rows, modifierLeaders)
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
function obj.collisions(rows, modifierLeaders)
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
      if b.entry then where = "config/keymap.lua keys " .. tostring(b.entry) end
      problems[#problems + 1] = {
        where = where,
        why = named(a) .. " and " .. named(b) .. " both bind "
          .. obj.chordText(b) .. " in the " .. b.layer .. " layer, so one of them can never be reached by it",
      }
    end
  end
  return problems
end

--- obj.fallbackLeaders(roles, listLeader) -> sorted list of leader names
--- The leaders in use when the keymap failed to build and binds no global key. Every leader a role
--- names, lowercased the way a row spells it, and the leader hosting lists, which the contexts
--- still bind on, so every list keeps its keys even where the roles moved the app role off it.
function obj.fallbackLeaders(roles, listLeader)
  local seen, out = {}, {}
  local function add(name)
    if name and not seen[name] then seen[name] = true out[#out + 1] = name end
  end
  for _, catalogName in pairs(roles or {}) do add(tostring(catalogName):lower()) end
  add(listLeader)
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
    local live = true
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
