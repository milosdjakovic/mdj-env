-- Which plugins are switched off, and the one switch that changes it.
--
-- There is one switch. A person writes false for a plugin in config/plugins.lua, or a settings
-- page saves the identity into a list in hs.settings, and the union of the two is the disabled
-- set the composition root hands to the loader and to the resolver before anything loads. A
-- disabled plugin's code never runs, and whether it runs is decided once per load, so changing
-- the set costs one reload. Toggling live was rejected, see decisions/olm-core-split.md.
--
-- Only a plugin found under plugins/ may be switched off. A host is core, and core is what
-- plugins consume, so letting a person switch it off would let one choice take down every
-- plugin standing on it. An identity that is not switchable is refused and named, never
-- honoured, wherever the switch came from.
--
-- Pure. Every hs call arrives as an injected function from the composition root, so the unit
-- case drives exactly this code and nothing here touches the running config.

local M = {}

-- Namespaced under Olm, since a bare key would collide with anything else on the machine that
-- calls hs.settings with the same short word.
M.SETTINGS_KEY = "Olm.disabledPlugins"

local function sortedKeys(set)
  local out = {}
  for key in pairs(set or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

--- M.merge(opts) -> disabled, lockedBy, refused
--- opts.entries is the person's config/plugins.lua table, opts.saved the list read from the
--- saved setting, opts.switchable(identity) whether a plugin under plugins/ answers to it and
--- opts.known(identity) whether anything does. disabled is a set of identities, lockedBy maps an
--- identity switched off in config to "config", and refused lists one { identity, source, why }
--- per switch that was not honoured. A switch in config wins the lock even when the same
--- identity is also saved, since a page cannot undo a line in a file the person wrote.
function M.merge(opts)
  opts = opts or {}
  local switchable = opts.switchable or function() return false end
  local known = opts.known or switchable
  local disabled, lockedBy, refused = {}, {}, {}

  local function consider(identity, source)
    if type(identity) ~= "string" then
      refused[#refused + 1] = { identity = tostring(identity), source = source,
        why = "is not a plugin identity" }
    elseif not known(identity) then
      refused[#refused + 1] = { identity = identity, source = source,
        why = "names no plugin here" }
    elseif not switchable(identity) then
      refused[#refused + 1] = { identity = identity, source = source,
        why = "is part of Olm's core rather than a plugin under plugins, so it cannot be switched off" }
    else
      disabled[identity] = true
      if source == "config" then lockedBy[identity] = "config" end
    end
  end

  -- Sorted so the refusals are logged in the same order on every load.
  local configOff = {}
  for identity, entry in pairs(opts.entries or {}) do
    if entry == false then configOff[identity] = true end
  end
  for _, identity in ipairs(sortedKeys(configOff)) do consider(identity, "config") end

  local saved = type(opts.saved) == "table" and opts.saved or {}
  for _, identity in ipairs(saved) do
    if not lockedBy[identity] then consider(identity, "saved") end
  end

  return disabled, lockedBy, refused
end

--- M.overrides(entries) -> entries without a false one
--- The person's entries as the resolver merges them. A false entry is handed over in the
--- disabled set instead, and leaving it here would let a refused one, a host written false,
--- switch that host off inside the resolver after this module refused it.
function M.overrides(entries)
  local out = {}
  for identity, entry in pairs(entries or {}) do
    if entry ~= false then out[identity] = entry end
  end
  return out
end

--- M.loadList(directories, spoonDir, off) -> rawNames, baseFor, identityOfRaw
--- What lib/loader.lua is handed, every plugin directory except those switched off or off
--- because of one, so their code is never run. directories maps identity to the absolute path a
--- manifest was found at, and baseFor is the part between spoonDir and the plugin root, since
--- the loader joins its configdir straight onto it. Sorted so the load order is stable.
function M.loadList(directories, spoonDir, off)
  off = off or {}
  local rawNames, baseFor, identityOfRaw = {}, {}, {}
  for _, identity in ipairs(sortedKeys(directories)) do
    if not off[identity] then
      local base, rawName = directories[identity]:match("^(.*/)([^/]+)$")
      if base and rawName then
        rawNames[#rawNames + 1] = rawName
        baseFor[rawName] = base:sub(#spoonDir + 1)
        identityOfRaw[rawName] = identity
      end
    end
  end
  return rawNames, baseFor, identityOfRaw
end

--- M.needsSummary(manifest) -> { tools, libs, siblings, data }
--- What a plugin needs, as sorted lists of names fit for a page to print. Policies and reasons
--- stay in the manifest, since a list a person scans wants names.
function M.needsSummary(manifest)
  local needs = (manifest or {}).needs or {}
  local tools, libs, siblings, data = {}, {}, {}, {}
  local seen = {}
  for _, tool in ipairs(needs.tools or {}) do
    if tool.name and not seen[tool.name] then
      seen[tool.name] = true
      tools[#tools + 1] = tool.name
    end
  end
  for _, decl in pairs(needs.lib or {}) do
    local name = type(decl) == "table" and (decl.from or decl.module) or decl
    name = type(name) == "string" and name:match("^([^.]+)") or nil
    if name and not seen["lib " .. name] then
      seen["lib " .. name] = true
      libs[#libs + 1] = name
    end
  end
  for _, decl in pairs(needs.siblings or {}) do
    local name = type(decl) == "table" and (decl.plugin or decl.from) or decl
    name = type(name) == "string" and name:match("^([^.]+)") or nil
    if name and not seen["sibling " .. name] then
      seen["sibling " .. name] = true
      siblings[#siblings + 1] = name
    end
  end
  for field in pairs(needs.data or {}) do data[#data + 1] = field end
  table.sort(tools)
  table.sort(libs)
  table.sort(siblings)
  table.sort(data)
  return { tools = tools, libs = libs, siblings = siblings, data = data }
end

--- M.catalog(opts) -> list
--- One row per switchable plugin, sorted by its about title, { identity, directory, about,
--- needs, disabled, lockedBy, offBecause }. opts carries manifests, directories,
--- switchable(identity), disabled, lockedBy and offBecause. A host never appears, since it is
--- not something a person can switch.
function M.catalog(opts)
  opts = opts or {}
  local out = {}
  for identity, manifest in pairs(opts.manifests or {}) do
    if opts.switchable and opts.switchable(identity) then
      local path = (opts.directories or {})[identity] or ""
      out[#out + 1] = {
        identity = identity,
        directory = path:match("([^/]+)$") or identity,
        about = manifest.about or {},
        needs = M.needsSummary(manifest),
        disabled = (opts.disabled or {})[identity] == true,
        lockedBy = (opts.lockedBy or {})[identity],
        offBecause = (opts.offBecause or {})[identity],
      }
    end
  end
  local function title(row) return tostring(row.about.title or row.identity):lower() end
  table.sort(out, function(a, b)
    if title(a) == title(b) then return a.identity < b.identity end
    return title(a) < title(b)
  end)
  return out
end

--- M.cascade(opts) -> list
--- Which identities would go off in addition if opts.identity were switched off, or, when
--- opts.off is false, which would come back with it. A dry run of the resolver's own plan over
--- the manifests, twice, once with the current set and once with the change, so the answer is
--- the plan's rather than a second reading of the sibling graph. opts.plan is the resolver's
--- plan function, and it is handed no modules and a present answering yes to every tool, so
--- nothing loads and nothing is probed. The identity itself is never in the answer.
function M.cascade(opts)
  opts = opts or {}
  local identity = opts.identity
  local current = {}
  for name in pairs(opts.disabled or {}) do current[name] = true end
  local proposed = {}
  for name in pairs(current) do proposed[name] = true end
  if opts.off == false then proposed[identity] = nil else proposed[identity] = true end

  local function offSet(disabled)
    local plan = opts.plan({
      manifests = opts.manifests,
      user = opts.user,
      disabled = disabled,
      present = function() return true end,
      libNames = opts.libNames,
    })
    local off = {}
    for name in pairs(plan.disabled or {}) do off[name] = true end
    for name in pairs(plan.offBecause or {}) do off[name] = true end
    return off
  end

  local before, after = offSet(current), offSet(proposed)
  local changed = {}
  for name in pairs(after) do
    if not before[name] and name ~= identity then changed[name] = true end
  end
  for name in pairs(before) do
    if not after[name] and name ~= identity then changed[name] = true end
  end
  return sortedKeys(changed)
end

--- M.set(identity, off, opts) -> ok, why
--- Switches one plugin off or back on in the saved set and asks for the reload that applies it.
--- opts carries switchable(identity), lockedBy, read() answering the saved list, write(list)
--- and reload(). A plugin switched off in config is locked, since the page cannot change a file
--- the person wrote, and saying no is better than saving a choice that changes nothing.
function M.set(identity, off, opts)
  opts = opts or {}
  if type(identity) ~= "string" or not (opts.switchable and opts.switchable(identity)) then
    return false, tostring(identity) .. " is not a plugin that can be switched off"
  end
  if (opts.lockedBy or {})[identity] then
    return false, identity .. " is switched off in config/plugins.lua, which only that file can change"
  end
  local set = {}
  for _, name in ipairs(opts.read and opts.read() or {}) do
    if type(name) == "string" then set[name] = true end
  end
  if off then set[identity] = true else set[identity] = nil end
  opts.write(sortedKeys(set))
  if opts.reload then opts.reload() end
  return true
end

--- M.reportLines(disabled, offBecause) -> list of strings
--- The one or two lines a report carries about switches. Nothing when nothing is off, since a
--- line saying so on every clean load is noise. These are choices rather than problems, so
--- they never stand in the way of a report saying no problems.
function M.reportLines(disabled, offBecause)
  local lines = {}
  local names = sortedKeys(disabled)
  if #names > 0 then
    lines[#lines + 1] = "switched off, " .. table.concat(names, ", ")
  end
  local byCause = {}
  for name, cause in pairs(offBecause or {}) do
    byCause[cause] = byCause[cause] or {}
    table.insert(byCause[cause], name)
  end
  for _, cause in ipairs(sortedKeys(byCause)) do
    table.sort(byCause[cause])
    lines[#lines + 1] = "off because " .. cause .. " is switched off, "
      .. table.concat(byCause[cause], ", ")
  end
  return lines
end

return M
