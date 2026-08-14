-- What a plugin proposes for itself, reconciled against what a person actually configured.
--
-- Olm ships a working default per plugin so a fresh macOS install needs no configuration at
-- all. A person's own file is read afterwards, and this module is the seam where the two
-- meet. It answers three questions. What does the effective config look like once both are
-- combined, where did each effective value come from, and do two plugins' own proposals
-- reach for the same physical key or the same typed word. Everything here is pure data in
-- and data out, no hs.* call at all, so the merge rules can be tested without Hammerspoon
-- running.

local obj = {}

-- The removal sentinel. A key set to exactly this table, compared by identity and nothing
-- else, is how a person declines one default. Identity rather than a magic string such as
-- "__remove__", because a magic string can collide with a genuine value a default or a
-- person's own file might actually want to hold, and this cannot, there is only one table
-- that is this table. It exists because the boolean `false` does not have room to mean two
-- things at once. browsertabs declares `surface.matcher = false` to opt itself out of the
-- shared matcher entirely, where absent means the opposite, use it, so a person who wants to
-- set that same key to the ordinary value false has to be able to do so and have it stick,
-- rather than have it read as "decline this back to absent" and land on the meaning they
-- were trying to get away from.
obj.NONE = {}
local NONE = obj.NONE

-- A table with no keys, or with only 1, 2, 3, ... n and nothing past n, is a list rather
-- than a settings map. The distinction decides the merge rule entirely, replace the whole
-- thing versus merge per key, so it has to be read from shape rather than from convention,
-- since nothing marks a table as one or the other on its own.
local function isList(value)
  local n = 0
  for k in pairs(value) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do
    if value[i] == nil then return false end
  end
  return true
end

-- A deep copy, so a table handed back from a merge belongs to whoever asked for it. A
-- manifest is loaded fresh every time it is read, but a merge result can still be inspected
-- and then merged again elsewhere, and handing back a table that aliases the plugin's own
-- default would let an edit made against one caller's copy bleed into another's.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- Reconcile one plugin's defaults against one person's override for it.
--
-- `nil` means the person has no opinion here and the default stands exactly as shipped.
-- `false` at this top level means the whole plugin is switched off, and that has to come
-- back out as the boolean `false` rather than as an empty table, since an empty table still
-- looks, to anything that keys into it, like a plugin with every default intact. Only the
-- boolean lets a caller tell "off" apart from "unopinionated". This is the one place `false`
-- keeps a special meaning, because a whole plugin has no ordinary value that false could
-- otherwise mean, and nothing below overloads it again.
--
-- A list shaped override replaces the default list wholesale rather than merging into it.
-- A person's app list, or their enabled browser list, is a complete statement of what they
-- want, and a default entry they never typed and cannot see sitting in their own file would
-- be unremovable except by finding it in this code instead of theirs.
--
-- A map shaped override merges key by key, recursively, so setting one nested value, one
-- theme colour for instance, leaves every sibling value exactly as shipped instead of
-- wiping the whole nested table down to only the key that was touched.
--
-- Inside a map, an ordinary value, including the boolean `false`, replaces the default at
-- that one key exactly as written, the same as any other setting. Declining a default
-- entirely, so the key reads as absent rather than as any particular value, needs `obj.NONE`
-- instead, since a default can carry a real false, browsertabs opting itself out of the
-- shared matcher for instance, and false can no longer double as both that value and the
-- instruction to remove it.
function obj.merge(defaults, user)
  defaults = defaults or {}

  if user == nil then return copy(defaults) end
  if user == false then return false end

  if isList(user) then return copy(user) end

  local out = copy(defaults)
  for k, v in pairs(user) do
    if v == NONE then
      out[k] = nil
    elseif type(v) == "table" and type(defaults[k]) == "table" then
      out[k] = obj.merge(defaults[k], v)
    else
      out[k] = copy(v)
    end
  end
  return out
end

-- Every leaf still standing under `value` once there is no override left to consider,
-- recorded as "default". Walked separately from the merge above because provenance has to
-- visit a key the person never mentioned at all, which the merge loop, driven by
-- `pairs(user)`, never does on its own.
local function recordDefaults(value, prefix, out)
  if type(value) ~= "table" or isList(value) then
    if prefix ~= "" then out[prefix] = "default" end
    return
  end
  for k, v in pairs(value) do
    local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
    recordDefaults(v, path, out)
  end
end

-- Mirrors `merge` structurally, the same list rule and the same recursive map rule, but
-- records where the value at each path came from instead of the value itself. The two have
-- to agree on shape, or an inspect command could report "user" for a path the merge actually
-- resolved from a default, and that gap would only ever surface as someone debugging a
-- config that looks fine and is lying about where a setting came from.
local function walk(defaults, user, prefix, out)
  if user == nil then
    recordDefaults(defaults, prefix, out)
    return
  end
  if user == NONE then
    -- Declined at this path, so nothing under it is effective, and the merge result has no
    -- key here at all. It is still recorded, as "user", because declining a default is a
    -- choice a person made, not silence, and an inspect command has to be able to show that
    -- choice rather than have the key simply vanish with no trace of why.
    if prefix ~= "" then out[prefix] = "user" end
    return
  end
  if type(user) == "table" and isList(user) then
    if prefix ~= "" then out[prefix] = "user" end
    return
  end
  if type(user) == "table" then
    local base = (type(defaults) == "table" and not isList(defaults)) and defaults or {}
    local keys = {}
    for k in pairs(base) do keys[k] = true end
    for k in pairs(user) do keys[k] = true end
    for k in pairs(keys) do
      local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
      walk(base[k], user[k], path, out)
    end
    return
  end
  -- A plain value overriding a plain value, the simplest leaf there is, false included, now
  -- that false carries no removal meaning below the top level.
  if prefix ~= "" then out[prefix] = "user" end
end

-- Where every effective value came from, keyed by its dotted path, "surface.primary.action"
-- for a nested one. This is what makes an inspect command possible at all, letting someone
-- see whether a setting is what shipped or what they chose, since the merged table itself
-- looks identical either way once the merge is done and the provenance is the only place
-- that distinction still exists.
--
-- `false` at the top level is handled here rather than inside `walk`, because it means the
-- whole plugin was declined, the same special case `merge` carries at this one level, and
-- nothing is effective under a plugin that was never wired, so there is nothing to report.
function obj.provenance(defaults, user)
  if user == false then return {} end
  local out = {}
  walk(defaults, user, "", out)
  return out
end

-- Two different plugins reaching for the same leader and key, or for the same alias word.
--
-- `byPlugin` is `{ [pluginName] = effectiveDefaults }`. Called with only that argument, every
-- entry is read as a plugin's own shipped proposal, and any two different plugins landing on
-- the same slot is reported, since two defaults colliding is a fact about the repository
-- itself, identical on every machine it runs on, and exactly why it must be reported rather
-- than silently decided one way. This never picks a winner. Whichever plugin's directory
-- happens to sort first is not a resolution, it is a coin flip wearing an ordering, so the
-- pair is named and the fix is left to a person.
--
-- The optional second argument is `{ [pluginName] = provenanceTable }`, the output of
-- `obj.provenance` per plugin, and it is what lets a live, already merged config be checked
-- without wrongly flagging the one case that is not a defect. A person's own override
-- landing on ground a default still holds is that person's call, not a repository defect,
-- so it is excluded, and it is excluded only there. Two untouched defaults colliding is
-- still reported, and two of the person's own choices colliding with each other is still
-- reported too, since neither of those is the one named exception, only a default meeting a
-- user override is. Bucketing each slot and each alias by this class, rather than checking
-- one exemption rule against a single earliest claimant, is what keeps a third late arrival
-- comparing against the right kind of claim instead of whichever name happened to be seen
-- first.
function obj.collisions(byPlugin, provenanceByPlugin)
  provenanceByPlugin = provenanceByPlugin or {}

  local function sourceOf(name, path)
    local prov = provenanceByPlugin[name]
    return (prov and prov[path]) or "default"
  end

  -- A slot is the person's own doing the moment either half of it is, since touching just
  -- the key and leaving the leader untouched is still a deliberate claim on the pair.
  local function slotClass(name)
    if sourceOf(name, "leader") == "user" or sourceOf(name, "key") == "user" then
      return "user"
    end
    return "default"
  end

  local names = {}
  for name in pairs(byPlugin) do names[#names + 1] = name end
  table.sort(names)

  local out = {}
  local slotOwners, aliasOwners = {}, {}

  for _, name in ipairs(names) do
    local proposal = byPlugin[name]
    if proposal and proposal ~= false then
      if proposal.leader and proposal.key then
        local slot = tostring(proposal.leader) .. "+" .. tostring(proposal.key)
        local class = slotClass(name)
        slotOwners[slot] = slotOwners[slot] or {}
        local owner = slotOwners[slot][class]
        if not owner then
          slotOwners[slot][class] = name
        else
          table.insert(out, "'" .. owner .. "' and '" .. name .. "' both propose leader '" ..
            tostring(proposal.leader) .. "' with key '" .. tostring(proposal.key) .. "'")
        end
      end
      for _, alias in ipairs(proposal.aliases or {}) do
        local class = sourceOf(name, "aliases")
        aliasOwners[alias] = aliasOwners[alias] or {}
        local owner = aliasOwners[alias][class]
        if not owner then
          aliasOwners[alias][class] = name
        else
          table.insert(out, "'" .. owner .. "' and '" .. name .. "' both propose the alias '" .. alias .. "'")
        end
      end
    end
  end
  return out
end

return obj
