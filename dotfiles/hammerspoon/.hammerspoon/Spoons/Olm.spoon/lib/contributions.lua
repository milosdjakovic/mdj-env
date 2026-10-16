--- === contributions ===
---
--- How what other plugins contribute reaches a host. Two hosts ask today, the launcher with two
--- questions and a leader's cheat sheet with one.
---
--- The launcher. A plugin declares provides.launcherRows, a member answering plain row
--- descriptors, and provides.launcherRun, a member handed a chosen row's item. The launcher
--- asks the set for both and names no plugin. This module turns the set answers into what the
--- launcher receives, one supplier per contributor and one runner per owner identity, and wraps
--- a query row source so the rows it computes carry their owner too.
---
--- A leader's cheat sheet. A plugin declares provides.cheatSheetSections, a member answering
--- the sections it adds to the sheet of the leader its defaults.leader names, asked on every
--- show so a section may read live state. The sheet asks the set and names no plugin, and this
--- module hands it one ordered list mixing those suppliers with the sheet's own sections, placed
--- by defaults.cheatSheetOrder the way launcher rows are placed by defaults.launcherOrder.
---
--- The launcher's app rows. A plugin declares provides.launcherAppDetails, a member answering
--- what the launcher's row for an installed app shows beyond the app itself, keyed by bundle id,
--- the chord that brings it forward and the url the row opens. The launcher asks the set and
--- names no plugin, and this module hands it one function merging every supplier's answer.
---
--- It lives here rather than inline in the composition root since phase three of the core
--- split, so the unit case can drive the very code the root runs instead of restating it.
--- Pure, no state and no hs, every collaborator handed in by the caller. The registrar is
--- the one dependency it does not take as data, and it is handed in rather than loaded, the
--- same door a scope's rows and run resolve through, so a plugin that assembles a member
--- inside its own configure is still found at call time.

local M = {}

--- contributions.ownRows(rows, owner) -> rows
--- Every row stamped with owner on its item, by a copy since the plugin may hold the row it
--- built. Always overwritten, never kept, so a plugin cannot name another plugin's identity on
--- a row and route a chosen row into that plugin's runner. The owner is a plain string, so the
--- row still survives hs.chooser.
function M.ownRows(rows, owner)
  local out = {}
  for i, row in ipairs(rows or {}) do
    if type(row) == "table" and type(row.item) == "table" then
      local copy, item = {}, {}
      for k, v in pairs(row) do copy[k] = v end
      for k, v in pairs(row.item) do item[k] = v end
      item.owner = owner
      copy.item = item
      out[i] = copy
    else
      out[i] = row
    end
  end
  return out
end

-- A row's place in the catalog, its own order when it carries one, otherwise the number its
-- plugin declares as defaults.launcherOrder, merged with the person's override like any
-- default. Absent on both means the row has no number and sorts after every numbered row.
local function stampOrder(rows, pluginOrder)
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.order == nil then row.order = pluginOrder end
  end
  return rows
end

--- contributions.queryProvider(provider, owner, stampIcons) -> source
--- A query row source wrapped so the rows it answers carry owner on every item and as the
--- owner of every icon key, which is what lets a computed row name an icon and never draw one,
--- and lets a source that declares launcherRun run its own rows. The launcher still sees only
--- a table answering rows(query).
function M.queryProvider(provider, owner, stampIcons)
  return {
    rows = function(_, query)
      local rows, exclusive = provider:rows(query)
      if stampIcons then rows = stampIcons(rows, owner) end
      return M.ownRows(rows, owner), exclusive
    end,
  }
end

-- The member a plugin declares under provides[field], resolved through the registrar's own
-- door, or nil after naming it once when it names nothing on the real module, since the host
-- would otherwise lose that plugin's contribution in silence. Shared by every host this module
-- serves, so a contribution point added later resolves its members the same way.
local function resolveMember(opts, identity, field, hostWords)
  local manifests, modules, registrar = opts.manifests or {}, opts.modules or {}, opts.registrar
  local say = opts.log or function() end
  local spec = ((manifests[identity] or {}).provides or {})[field]
  local member = registrar.memberSpec(spec)
  if member == nil or not registrar.memberResolves(modules[identity], member) then
    say("'" .. tostring(identity) .. "' provides " .. field
      .. " but it names no function on the module, so " .. hostWords .. " skips it")
    return nil
  end
  return registrar.action(modules, identity, identity, spec)
end

--- contributions.assemble(opts) -> rowSuppliers, runners
--- opts.host        the identity of the host whose set answers are read, the launcher
--- opts.plan        the load plan, its sets and its effective defaults
--- opts.manifests   every manifest by identity
--- opts.modules     every loaded module by identity
--- opts.registrar   lib/registrar.lua, for memberSpec, memberResolves and action
--- opts.stampIcons  optional, function(rows, owner) stamping iconOwner on rows naming an icon
--- opts.log         optional, function(message) for a member that resolves to nothing
---
--- One supplier per plugin answering the launcherRows set, in the set's own order, each a
--- function calling that plugin's declared member when the launcher builds its rows and
--- answering them owned, icon stamped and ordered. One runner per plugin answering the
--- launcherRun set, keyed by its identity. A member that resolves to nothing on the real module
--- is named once and skipped, since the launcher would otherwise lose that plugin's rows or
--- runs in silence.
function M.assemble(opts)
  local plan, modules = opts.plan or {}, opts.modules or {}
  local stampIcons = opts.stampIcons
  local sets = (plan.sets or {})[opts.host] or {}

  local function resolve(identity, field)
    return resolveMember(opts, identity, field, "the launcher")
  end

  local rowSuppliers, runners = {}, {}
  for _, identity in ipairs(sets.launcherRows or {}) do
    local call = modules[identity] and resolve(identity, "launcherRows")
    if call then
      local pluginOrder = ((plan.effective or {})[identity] or {}).launcherOrder
      rowSuppliers[#rowSuppliers + 1] = function()
        local rows = call() or {}
        if stampIcons then rows = stampIcons(rows, identity) end
        return stampOrder(M.ownRows(rows, identity), pluginOrder)
      end
    end
  end
  for _, identity in ipairs(sets.launcherRun or {}) do
    local call = modules[identity] and resolve(identity, "launcherRun")
    if call then runners[identity] = call end
  end
  return rowSuppliers, runners
end

--- contributions.appDetails(opts) -> function() -> { [bundleID] = details }
--- opts.host        the identity of the host whose set answer is read, the launcher
--- opts.plan        the load plan and its sets
--- opts.manifests   every manifest by identity
--- opts.modules     every loaded module by identity
--- opts.registrar   lib/registrar.lua, for memberSpec, memberResolves and action
--- opts.log         optional, function(message) for a member that resolves to nothing or raises
---
--- One function the launcher calls whenever it builds its app rows, answering every supplier of
--- the launcherAppDetails set merged into one table keyed by bundle id. Asked then rather than at
--- load, because a supplier knows what it bound only after its own wiring step has run. Where two
--- suppliers answer one bundle id the earlier in the set's order wins the whole entry, since a
--- chord taken from one and a url from another would describe a row neither of them built. Each
--- supplier is wrapped so one that raises or answers something other than a table costs its own
--- details and nothing else. With no supplier the function answers an empty table, which is an
--- app row carrying no chord.
function M.appDetails(opts)
  local plan, modules = opts.plan or {}, opts.modules or {}
  local say = opts.log or function() end
  local sets = (plan.sets or {})[opts.host] or {}
  local suppliers = {}
  for _, identity in ipairs(sets.launcherAppDetails or {}) do
    local call = modules[identity] and resolveMember(opts, identity, "launcherAppDetails", "the launcher")
    if call then suppliers[#suppliers + 1] = { identity = identity, call = call } end
  end
  return function()
    local out = {}
    for _, s in ipairs(suppliers) do
      local ok, details = pcall(s.call)
      if not ok then
        say("'" .. tostring(s.identity) .. "' failed answering its launcher app details, "
          .. tostring(details))
      elseif type(details) == "table" then
        for bundleID, entry in pairs(details) do
          if out[bundleID] == nil and type(entry) == "table" then out[bundleID] = entry end
        end
      end
    end
    return out
  end
end

--- contributions.sheetSections(opts) -> entries
--- opts.host        the identity of the cheat sheet host whose set answer is read
--- opts.role        the leader role word the sheet reveals, app or window
--- opts.plan        the load plan, its sets and its effective defaults
--- opts.manifests   every manifest by identity
--- opts.modules     every loaded module by identity
--- opts.registrar   lib/registrar.lua, for memberSpec, memberResolves and action
--- opts.own         optional, the sheet's own sections, a list, placed as one block
--- opts.ownOrder    optional, the number the sheet's own block sits at
--- opts.log         optional, function(message) for a member that resolves to nothing
---
--- One ordered list for the sheet, each entry either one of its own sections, a plain table,
--- or a supplier, a function answering a list of sections when the sheet is shown. A supplier
--- is one plugin answering the cheatSheetSections set whose effective leader is the role this
--- sheet reveals, so a plugin on another leader never reaches this sheet, and one stating no
--- leader is left out rather than guessed at. Placed by the plugin's effective
--- cheatSheetOrder, the sheet's own block by ownOrder. A tie keeps the set's order of
--- suppliers and puts the sheet's own block after them, and an entry with no number sorts after
--- every numbered one, the rules launcher rows already follow.
---
--- A supplier is wrapped so a member that raises or answers something other than a list costs
--- its own sections and nothing else. The sheet draws on a key hold, and one plugin's fault
--- must not leave the person holding a leader over an empty screen.
function M.sheetSections(opts)
  local plan = opts.plan or {}
  local say = opts.log or function() end
  local sets = (plan.sets or {})[opts.host] or {}
  local blocks = {}

  for position, identity in ipairs(sets.cheatSheetSections or {}) do
    local eff = (plan.effective or {})[identity] or {}
    if eff.leader ~= opts.role then
      -- Dropped on purpose, and said once, since a supplier whose sections reach no sheet is
      -- otherwise indistinguishable from one that has nothing to show. A leader whose sheet
      -- never asks this set, the window one today, lands here as well.
      say("'" .. tostring(identity) .. "' supplies cheat sheet sections but reached no sheet, "
        .. (eff.leader == nil and "it states no defaults.leader"
          or ("its leader is '" .. tostring(eff.leader) .. "' and the sheet asking reveals '"
            .. tostring(opts.role) .. "'")))
    else
      local call = (opts.modules or {})[identity]
        and resolveMember(opts, identity, "cheatSheetSections", "the cheat sheet")
      if call then
        blocks[#blocks + 1] = { order = eff.cheatSheetOrder, position = position,
          entries = { function()
            local ok, sections = pcall(call)
            if not ok then
              say("'" .. tostring(identity) .. "' failed answering its cheat sheet sections, "
                .. tostring(sections))
              return {}
            end
            return type(sections) == "table" and sections or {}
          end } }
      end
    end
  end
  if opts.own and #opts.own > 0 then
    blocks[#blocks + 1] = { order = opts.ownOrder, position = math.huge, entries = opts.own }
  end

  table.sort(blocks, function(a, b)
    if a.order ~= b.order then
      if a.order == nil then return false end
      if b.order == nil then return true end
      return a.order < b.order
    end
    return a.position < b.position
  end)

  local out = {}
  for _, block in ipairs(blocks) do
    for _, entry in ipairs(block.entries) do out[#out + 1] = entry end
  end
  return out
end

return M
