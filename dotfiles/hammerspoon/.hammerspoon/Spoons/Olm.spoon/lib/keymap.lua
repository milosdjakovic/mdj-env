-- The keymap, one read model of every chord Olm binds.
--
-- Every key Olm binds comes from one of five sources, a tool's or a host's open row, a plugin's
-- own bindings, rows a plugin provides from its own data, and the keys Olm owns itself, the lock
-- and sleep rows and every list's context bindings. A tool's open key is not a field of its own
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
-- to, and a plugin is whatever the plan's identity table calls its directory.
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
--               toggle, the row name for a special row, and the binding's own action name for
--               everything else.
--   source      one word naming the path, tool, host, bindings, provided, special or context.
--   when        the predicate gating the chord, where there is one.
--   priority    the context priority, where there is one.
--   description the declared label, the binding's own, else the descriptor's, else for an open
--               row the plugin's own description.
--   origin      default when the plugin shipped the chord and user when the person set it.
--   repeats     whether the action keeps firing while its key is held, where the source says.
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

--- obj.build(inputs) -> { rows = list, bound = list, problems = list }
--- rows is every row sorted by chord, the read model. bound is the global rows again in the
--- order the engines receive them, which is the order the paths bound in before the binder
--- existed, since two rows on one key are resolved by that order and only by that order.
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
---   specialRun  a function from a host's identity and a special row's name to its function.
---
function obj.build(inputs)
  local plan = assert(inputs and inputs.plan, "keymap needs a plan")
  local roles = assert(inputs.roles, "keymap needs the roles")
  assert(roles.app, "keymap needs the app role")
  local keycodes = inputs.keycodes
  local identityOf = plan.identity or {}
  local rows = {}

  -- The order the engines receive the global rows in, one number per row. The paths this list
  -- replaced bound in four passes, every plugin's own bindings in plan order, then every
  -- registered shortcut in registration order, then the hosts' keys, then the special rows, and
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
      origin = spec.origin or "default",
      repeats = spec.repeats,
      run = spec.run,
      refused = spec.refused,
      quiet = spec.quiet,
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
              origin = originOf(prov, "bindings"),
              repeats = repeats, run = descriptor and descriptor.run or nil,
              refused = refusedHere == true
                or (type(refusedHere) == "table" and refusedHere[b.action] == true),
              order = orderOf(1, position[directory], i),
            })
          end
        end
      end
    end
  end)

  source("special rows", function()
    for _, directory in ipairs(sortedKeys(plan.effective)) do
      local eff = plan.effective[directory]
      local owner = identityOf[directory] or directory
      local prov = (plan.provenance or {})[directory] or {}
      -- The special rows of a host that carry a key, which bind on the app leader.
      for i, row in ipairs(eff.specialRows or {}) do
        if row.key then
          add({
            leader = leaderOf("app"), role = "app", key = row.key, owner = owner, action = row.name,
            source = "special", description = row.description,
            origin = originOf(prov, "specialRows"),
            run = inputs.specialRun and inputs.specialRun(owner, row.name) or nil,
            order = orderOf(4, i),
          })
        end
      end
    end
  end)

  -- Every list's context bindings, live only while that list is open. They bind on the app
  -- leader under the context's own gate and priority. A binding that says chord is false is
  -- listed for reading and never bound as a key.
  source("list keys", function()
    for _, name in ipairs(sortedKeys(plan.contexts)) do
      local block = plan.contexts[name]
      for _, b in ipairs(block.bindings or {}) do
        if b.chord ~= false then
          add({
            layer = name, leader = leaderOf("app"), role = "app", key = b.key, mods = b.mods, owner = name,
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
    if type(entry) == "table" and entry.kind == "leader" and not hasOpen[entry.name] then
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

  local problems = obj.collisions(rows)
  for _, problem in ipairs(rowProblems) do problems[#problems + 1] = problem end
  for _, problem in ipairs(sourceProblems) do problems[#problems + 1] = problem end
  return { rows = rows, bound = bound, problems = problems }
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

--- obj.collisions(rows) -> list of problems
--- Two rows collide when they share layer, leader, key and modifiers. A catch all and an exact
--- modifier row on one key are different slots, since both resolvers prefer the exact one, and
--- rows in different layers never meet, which is how a global key and a list key share a chord
--- on purpose.
---
--- A row the person set is a different class from a shipped default. A default meeting a
--- person's override is that person's call and is not reported, the one exemption the old slot
--- check made. Two defaults are reported, since that is a fact about the repository and the same
--- on every machine, and two of the person's own are reported too. Rows are bucketed by class
--- within a slot, so a third arrival is compared against the right kind of claim. Nothing here
--- picks a winner, the pair is named and the fix is left to a person.
function obj.collisions(rows)
  local slots, order = {}, {}
  for _, row in ipairs(rows) do
    local id = table.concat({ row.layer, row.leader or "", row.key, rowModsText(row) }, "\0")
    if not slots[id] then
      slots[id] = { user = nil, default = nil }
      order[#order + 1] = id
    end
    local class = row.origin == "user" and "user" or "default"
    local first = slots[id][class]
    if not first then
      slots[id][class] = row
    else
      slots[id][class .. "Extra"] = slots[id][class .. "Extra"] or {}
      table.insert(slots[id][class .. "Extra"], { first = first, row = row })
    end
  end

  local problems = {}
  for _, id in ipairs(order) do
    for _, class in ipairs({ "default", "user" }) do
      for _, pair in ipairs(slots[id][class .. "Extra"] or {}) do
        local a, b = pair.first, pair.row
        problems[#problems + 1] = {
          where = obj.chordText(b) .. " in " .. b.layer,
          why = "'" .. tostring(a.owner) .. "' action '" .. tostring(a.action) .. "' and '"
            .. tostring(b.owner) .. "' action '" .. tostring(b.action) .. "' both bind "
            .. obj.chordText(b) .. " in the " .. b.layer .. " layer, so one of them can never be reached by it",
        }
      end
    end
  end
  return problems
end

return obj
