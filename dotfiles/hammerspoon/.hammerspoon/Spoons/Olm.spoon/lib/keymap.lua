-- The keymap, one read model of every chord Olm binds.
--
-- Five paths bind a key today, a tool's open key, a registered command, a plugin's own
-- bindings, the person's toggles, and the keys Olm owns itself, the host key, the lock and
-- sleep rows and every list's context bindings. This module reads the declarations behind all
-- five and writes them down as one list of rows in one spelling, then checks that list for two
-- rows on the same chord. It binds nothing and changes nothing, who binds each key is still the
-- root's business. A later phase makes the binder walk this list, so the row shape is the part
-- worth getting right now.
--
-- It is pure Lua. It touches no hs global, and the keycode table it spells keys with arrives
-- through its inputs, so a plain test can drive it with a small fake. It names no plugin and no
-- leader. A leader is whatever word the roles table maps a role to, a plugin is whatever the
-- plan's identity table calls its directory, and a toggle is found by the shape of the data a
-- plugin was handed rather than by who the plugin is.
--
-- The row.
--
--   layer       the word global for a key live whenever its leader is held, or always for a plain
--               combo, otherwise the name of the list the key is live in while that list is open.
--   leader      the catalog name lowercased, or nil for a plain combo with no leader at all.
--   key         one spelling, the name the keycode table gives the key, lowercase.
--   mods        the required modifiers, sorted, spelled cmd, ctrl, alt and shift.
--   anyMods     true when the binding states no modifiers at all and fires whatever extra
--               modifiers are held. That is a different binding from one that states an empty
--               list, which demands no modifier, and the two never collide with each other.
--   owner       the identity of the plugin or host that declared the chord. For a list's own
--               keys it is the list's name.
--   action      what the chord does, open for a tool's open key, the command name for a
--               registered command, the app name for a toggle, the row name for a special row,
--               and the binding's own action name for everything else.
--   source      one word naming the path, tool, host, command, bindings, toggles, special or
--               context.
--   when        the predicate gating the chord, where there is one.
--   priority    the context priority, where there is one.
--   description the declared label, where there is one.
--   origin      default when the plugin shipped the chord and user when the person set it.
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

--- obj.build(inputs) -> { rows = list, problems = list }
--- Reads declarations and nothing else.
---
---   plan        the root's plan, its effective, provenance, contexts and identity tables.
---   roles       the role word to leader catalog name table, app and window at least.
---   keycodes    Hammerspoon's keycode table, or nil, in which case a key is only lowercased.
---   shortcuts   what the registry holds as shortcuts, entries with a name and a kind.
---   manifests   every live manifest by directory, read for the commands they declare.
---   commandKey  a function from a command name to its key, mods and origin, or nil, in which
---               case the key the declaring manifest ships is read and the origin is default.
---   data        the data each plugin was handed, by directory.
function obj.build(inputs)
  local plan = assert(inputs and inputs.plan, "keymap needs a plan")
  local roles = assert(inputs.roles, "keymap needs the roles")
  assert(roles.app, "keymap needs the app role")
  local keycodes = inputs.keycodes
  local identityOf = plan.identity or {}
  local rows = {}

  -- Any role word the roles table does not know falls back to the app leader, since that is
  -- where the root binds a key that names no other.
  local function leaderOf(role)
    local name = roles[role or "app"] or roles.app
    return tostring(name):lower()
  end

  local function add(spec)
    local mods, anyMods = obj.mods(spec.mods)
    rows[#rows + 1] = {
      layer = spec.layer or GLOBAL,
      leader = spec.leader,
      key = obj.keyName(spec.key, keycodes),
      mods = mods,
      anyMods = anyMods,
      owner = spec.owner,
      action = spec.action,
      source = spec.source,
      when = spec.when,
      priority = spec.priority,
      description = spec.description,
      origin = spec.origin or "default",
    }
  end

  -- The registered tools, by identity, so a chord of a tool is told from a chord of a host.
  local registered, kindOf = {}, {}
  for _, entry in pairs(inputs.shortcuts or {}) do
    if type(entry) == "table" and entry.name then
      registered[entry.name] = true
      kindOf[entry.name] = entry.kind
    end
  end

  for _, directory in ipairs(sortedKeys(plan.effective)) do
    local eff = plan.effective[directory]
    local owner = identityOf[directory] or directory
    local prov = (plan.provenance or {})[directory] or {}

    -- The open key of a tool, or of a host that is not a tool.
    if eff.key then
      add({
        leader = leaderOf(eff.leader), key = eff.key, mods = eff.mods, owner = owner,
        action = "open", source = registered[owner] and "tool" or "host",
        description = eff.description, origin = originOf(prov, "key", "mods", "leader"),
      })
    end

    -- A plugin's own bindings, each with its own key, modifiers and gate.
    for _, b in ipairs(eff.bindings or {}) do
      add({
        leader = leaderOf(eff.leader), key = b.key, mods = b.mods, owner = owner,
        action = b.action, source = "bindings", when = b.when, priority = b.priority,
        description = b.description, origin = originOf(prov, "bindings"),
      })
    end

    -- The special rows of a host that carry a key, which the root binds on the app leader.
    for _, row in ipairs(eff.specialRows or {}) do
      if row.key then
        add({
          leader = leaderOf("app"), key = row.key, owner = owner, action = row.name,
          source = "special", description = row.description,
          origin = originOf(prov, "specialRows"),
        })
      end
    end
  end

  -- Every list's context bindings, live only while that list is open. They bind on the app
  -- leader under the context's own gate and priority. A binding that says chord is false is
  -- listed for reading and never bound as a key.
  for _, name in ipairs(sortedKeys(plan.contexts)) do
    local block = plan.contexts[name]
    for _, b in ipairs(block.bindings or {}) do
      if b.chord ~= false then
        add({
          layer = name, leader = leaderOf("app"), key = b.key, mods = b.mods, owner = name,
          action = b.action, source = "context", when = block.when, priority = block.priority,
          description = b.description, origin = "default",
        })
      end
    end
  end

  -- The person's toggles, found by the shape of the data a plugin was handed, a list under the
  -- name toggles. An entry that states its own modifiers is a plain combo, any other is a key
  -- on the app leader. The list is the person's own, so every row of it is theirs.
  for _, directory in ipairs(sortedKeys(inputs.data)) do
    local data = inputs.data[directory]
    if type(data) == "table" and type(data.toggles) == "table" then
      local owner = identityOf[directory] or directory
      for _, t in ipairs(data.toggles) do
        if t.modifiers then
          add({
            key = t.key, mods = t.modifiers, owner = owner, action = t.app, source = "toggles",
            description = t.description, origin = "user",
          })
        else
          add({
            leader = leaderOf("app"), key = t.key, owner = owner, action = t.app,
            source = "toggles", description = t.description, origin = "user",
          })
        end
      end
    end
  end

  -- A registered command's own key. The command belongs to the manifest declaring it. A
  -- global one is a plain combo and a leader one a key on the app leader. The person's
  -- override of the key is applied by the lookup, which says so in its origin.
  for _, directory in ipairs(sortedKeys(inputs.manifests)) do
    local commands = ((inputs.manifests[directory] or {}).registry or {}).commands or {}
    for _, name in ipairs(sortedKeys(commands)) do
      local info = kindOf[name] and (inputs.commandKey and inputs.commandKey(name) or commands[name])
      if info and info.key then
        local description = info.description
        if description == nil and type(info.row) == "table" then description = info.row.description end
        add({
          leader = kindOf[name] ~= "global" and leaderOf("app") or nil,
          key = info.key, mods = info.mods, owner = identityOf[directory] or directory,
          action = name, source = "command", description = description,
          origin = info.origin,
        })
      end
    end
  end

  table.sort(rows, function(a, b)
    local ka = table.concat({ a.layer, a.leader or "", a.key, rowModsText(a), a.action or "", a.owner or "" }, "\0")
    local kb = table.concat({ b.layer, b.leader or "", b.key, rowModsText(b), b.action or "", b.owner or "" }, "\0")
    return ka < kb
  end)

  return { rows = rows, problems = obj.collisions(rows) }
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
