--- === contributions ===
---
--- How rows other plugins contribute reach the launcher, and how a chosen one finds its way
--- back. A plugin declares provides.launcherRows, a member answering plain row descriptors,
--- and provides.launcherRun, a member handed a chosen row's item. The launcher asks the set
--- for both and names no plugin. This module turns the set answers into what the launcher
--- receives, one supplier per contributor and one runner per owner identity, and wraps a
--- query row source so the rows it computes carry their owner too.
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
  local plan, manifests, modules = opts.plan or {}, opts.manifests or {}, opts.modules or {}
  local registrar, stampIcons = opts.registrar, opts.stampIcons
  local say = opts.log or function() end
  local sets = (plan.sets or {})[opts.host] or {}

  local function resolve(identity, field)
    local spec = ((manifests[identity] or {}).provides or {})[field]
    local member = registrar.memberSpec(spec)
    if member == nil or not registrar.memberResolves(modules[identity], member) then
      say("'" .. tostring(identity) .. "' provides " .. field
        .. " but it names no function on the module, so the launcher skips it")
      return nil
    end
    return registrar.action(modules, identity, identity, spec)
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

return M
