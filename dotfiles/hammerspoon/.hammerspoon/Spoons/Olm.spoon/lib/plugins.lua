-- The plugin set, read as data before any of it runs.
--
-- Every plugin directory holding a manifest.lua is a plugin, so adding one is a new
-- directory and no edit here or anywhere else. This module answers six questions about
-- the set it finds. What each plugin declared, which ones a missing tool takes down,
-- which ones a missing capability takes down once the real modules are loaded, which
-- ones are missing plain data they cannot derive for themselves, what order they can be
-- wired in, and the deduped list of tools a person needs to install.
--
-- A manifest is PURE DATA and is loaded without loading its plugin. That is the property
-- everything else rests on. It lets the wiring order be computed before anything
-- initializes, it lets the install list be produced with no plugin code executed at all,
-- and it means a plugin whose own code is broken still reports what it wanted.

local obj = {}

local log = hs.logger.new("Plugins", "info")

-- A manifest field may be absent, and absent is a complete answer rather than a missing
-- one. What is checked is only that a field present has the right shape, since a string
-- where a table belongs fails far from the typo otherwise.
local SHAPE = {
  needs = "table",
  provides = "table",
  defaults = "table",
  surface = "table",
}

-- A dotted name splits into a plugin or lib module and, when there is a second part, the
-- member wanted from it. No second part means the module itself was named, which used to
-- be inexpressible and is exactly what WindowManager needs from WindowLeader.
local function splitDotted(value)
  if not value then return nil, nil end
  local first, rest = value:match("^([^.]+)%.(.+)$")
  if first then return first, rest end
  return value, nil
end

-- A sibling need, normalized to one shape whichever way it was written. Manifests are
-- being migrated toward the table form with `plugin`, `member`, and `call` while this
-- module is being rebuilt, so both the new shape and the old dotted one have to resolve
-- to the same answer or every manifest not yet touched breaks the moment this loads.
--
-- `call` only exists on the sibling form, never the lib form, because a sibling member is
-- something Olm calls on the consumer's behalf and has to know the convention for, while
-- a lib member is read off a table with no self to bind.
--
-- `ordering` defaults to true and is the one field existence checking never looks at,
-- because needing a capability and needing it to have run already are not the same claim.
-- MenuSearch is the real case. The live root hands it coveredApp and refreshLauncher as
-- CLOSURES that reach into the Launcher host only at call time, so the launcher does not
-- have to be configured first, and the live sequence configures MenuSearch before the
-- launcher and lets the launcher's own registry block read what MenuSearch left behind
-- afterward. A need declared the ordinary way would have forced an edge the live wiring
-- never needed, inverted that sequence, and in some pairings turned into a cycle that
-- fails the whole plan for a dependency nothing was actually waiting on. `ordering = false`
-- says the capability still has to exist and is still checked exactly as any other need,
-- it only carries no weight when `order` is deciding what must run before what.
local function normalizeSibling(value)
  if type(value) == "string" then
    local plugin, member = splitDotted(value)
    return { plugin = plugin, member = member, call = "method", policy = "required", ordering = true }
  end
  if value.plugin then
    return {
      plugin = value.plugin,
      member = value.member,
      call = value.call or "method",
      policy = value.policy or "required",
      ordering = (value.ordering ~= false),
    }
  end
  -- The old shape names both halves in one dotted string under `from`, since that is
  -- what every manifest in the tree still writes today.
  local plugin, member = splitDotted(value.from)
  return {
    plugin = plugin,
    member = member,
    call = "method",
    policy = value.policy or "required",
    ordering = (value.ordering ~= false),
  }
end

local function normalizeLib(value)
  if type(value) == "string" then
    local mod, member = splitDotted(value)
    return { module = mod, member = member, policy = "required" }
  end
  local mod, member = splitDotted(value.from)
  return { module = mod, member = member, policy = value.policy or "required" }
end

-- Read one manifest. Loaded with loadfile rather than require, since a plugin directory
-- is not on package.path, and called in a protected call so a syntax error names the
-- plugin instead of taking the whole config down with it.
local function readOne(dir, name)
  local path = dir .. "/" .. name .. "/manifest.lua"
  local chunk, err = loadfile(path)
  if not chunk then return nil, "unreadable, " .. tostring(err) end
  local ok, value = pcall(chunk)
  if not ok then return nil, "errored while loading, " .. tostring(value) end
  if type(value) ~= "table" then return nil, "returned " .. type(value) .. " rather than a table" end
  if value.name ~= nil and type(value.name) ~= "string" then
    return nil, "name is a " .. type(value.name) .. " rather than a string"
  end
  for field, want in pairs(SHAPE) do
    local got = value[field]
    if got ~= nil and type(got) ~= want then
      return nil, field .. " is a " .. type(got) .. " rather than a " .. want
    end
  end
  return value
end

-- Every plugin under one directory, keyed by its identity, `name` when the manifest
-- carries one and the directory otherwise. The directory and the identity are not the
-- same thing. Seven of the twelve surfaced tools differ by case, and one, colorPicker,
-- lives in a directory named eyedropper, so the directory is recorded separately for
-- whoever needs to go find the file rather than treated as the name itself.
--
-- A plugin whose manifest will not load is named in the console and left out, so one bad
-- plugin costs itself and nothing else.
function obj.read(dir)
  local found, skipped, directories = {}, {}, {}
  -- hs.fs.dir hands back an iterator AND the directory object it walks, and the second one
  -- must be carried into the loop. Keeping only the first leaves the iterator with no state
  -- and it fails on the first step, which is how this was written the first time.
  local iter, dirObj = hs.fs.dir(dir)
  if not iter then
    log.e("could not read the plugins directory at " .. tostring(dir))
    return found, skipped, directories
  end
  for entry in iter, dirObj do
    if entry ~= "." and entry ~= ".." then
      local attrs = hs.fs.attributes(dir .. "/" .. entry)
      if attrs and attrs.mode == "directory" then
        local manifest, err = readOne(dir, entry)
        if manifest then
          local identity = manifest.name or entry
          if found[identity] then
            -- Two directories naming themselves the same identity is a defect rather
            -- than something to resolve, since which one wins would then depend on the
            -- order the filesystem happened to hand them back.
            skipped[identity] = "identity is declared by more than one directory here, both ignored"
            log.e("plugin identity '" .. identity .. "' is declared by more than one directory, both ignored")
            found[identity] = nil
            directories[identity] = nil
          else
            found[identity] = manifest
            directories[identity] = dir .. "/" .. entry
          end
        elseif hs.fs.attributes(dir .. "/" .. entry .. "/manifest.lua") then
          -- Only complain when a manifest is actually there and unusable. A directory
          -- without one is simply not a plugin, which is how a helper directory sits
          -- beside the real ones without being mistaken for one.
          skipped[entry] = err
          log.e("plugin '" .. entry .. "' skipped, its manifest " .. err)
        end
      end
    end
  end
  return found, skipped, directories
end

-- Every plugin across several directories, so `plugins` and `host` are read as one set.
--
-- They are one set on purpose. A host is not a different kind of thing to load, it differs
-- only in knowing that a set exists, and keeping two registries would mean every question
-- below being asked twice and answered slightly differently the first time one was missed.
function obj.readAll(dirs)
  local found, skipped, directories = {}, {}, {}
  for _, dir in ipairs(dirs) do
    local f, s, d = obj.read(dir)
    for identity, m in pairs(f) do
      if found[identity] then
        skipped[identity] = "is declared in more than one directory, so the identity is ambiguous"
        log.e("plugin identity '" .. identity .. "' appears in more than one directory, both ignored")
        found[identity] = nil
        directories[identity] = nil
      else
        found[identity] = m
        directories[identity] = d[identity]
      end
    end
    for name, err in pairs(s) do skipped[name] = err end
  end
  return found, skipped, directories
end

-- Answer one question about the whole set, which is what a host needs instead of a name.
--
-- This is the seam that keeps a host ignorant of its members. A host says it wants every
-- plugin offering some capability, and the answer is computed from what those plugins
-- declared about themselves, so adding a scopable tool puts it in every host's list with no
-- edit anywhere. The alternative is what the composition root does today, a hand written
-- roster of ten names beside another of twelve, each one plugin behind from the day somebody
-- forgets, which is the exact drift a generated manifest was already introduced to stop.
--
-- Two forms, deliberately only two. `has` names a manifest field that must be present, and
-- `provides` names capabilities that must ALL be provided. Anything cleverer would be a query
-- language nobody asked for, and the moment a host needs one specific plugin it should name
-- it as a sibling instead and be honest about the coupling.
function obj.set(manifests, query, blocked)
  blocked = blocked or {}
  local names = {}
  for name, m in pairs(manifests) do
    if not blocked[name] then
      local keep = true
      if query.has and m[query.has] == nil then keep = false end
      for _, capability in ipairs(query.provides or {}) do
        if (m.provides or {})[capability] == nil then keep = false end
      end
      if keep then names[#names + 1] = name end
    end
  end
  -- Sorted so the answer is stable across reloads. Two reloads producing two orders would
  -- mean a latent ordering bug showing up on one run in ten.
  table.sort(names)
  return names
end

-- Resolve every `needs.set` question a host asked, and report one that answers nothing.
--
-- An empty answer is reported rather than passed along quietly, because the overwhelmingly
-- likely cause is a misspelled capability name, and a host silently receiving an empty list
-- looks exactly like a host whose tools are all switched off.
function obj.sets(manifests, blocked)
  local answers, empty = {}, {}
  for name, m in pairs(manifests) do
    if not blocked[name] then
      for field, query in pairs((m.needs or {}).set or {}) do
        answers[name] = answers[name] or {}
        local got = obj.set(manifests, query, blocked)
        answers[name][field] = got
        if #got == 0 then
          empty[name .. "." .. field] = "asks the set for something nothing provides"
        end
      end
    end
  end
  return answers, empty
end

-- Every tool the whole set declares, once each, in a stable order, as the flat list the
-- runtime resolver wants rather than the per plugin shape the manifests are written in.
--
-- This is the aggregator the split needs. A plugin declares a tool beside itself and knows
-- nothing about who else wants it, while the resolver probes once for the whole machine and
-- must not ask twice for the same thing. Without this the two halves cannot meet, and they
-- did not, the resolver went on reading the separate declaration files the manifests
-- replaced, so every tool a manifest had taken over was reported as undeclared the moment a
-- plugin asked for it, nine such lines on a clean run.
--
-- Deduplication is by name and locator together rather than by name alone, since the same
-- command reached through two different absolute paths is two different questions. Where two
-- plugins declare the same tool their reasons are joined, because the resolver's own warning
-- names what an absent tool costs and losing all but one plugin's answer would understate it.
-- A REQUIRED declaration wins over an OPTIONAL one for the same tool, since a tool one plugin
-- merely prefers and another cannot live without is, for the machine, not optional.
--
-- consumer is passed in rather than decided here, because who a resolved tool is scoped to is
-- the composition root's arrangement and no business of the manifest layer.
function obj.declarations(manifests, consumer)
  local seen, out = {}, {}
  local names = {}
  for name in pairs(manifests) do names[#names + 1] = name end
  table.sort(names)

  for _, name in ipairs(names) do
    for _, tool in ipairs((manifests[name].needs or {}).tools or {}) do
      local locator = tool.locator or tool.name
      local key = tool.name .. "\0" .. locator
      local already = seen[key]
      if already then
        if tool.reason and not already.reason:find(tool.reason, 1, true) then
          already.reason = already.reason .. ", and " .. tool.reason
        end
        if tool.policy == "required" then already.policy = "required" end
        already.owner = already.owner .. ", " .. name
      else
        local entry = {
          name = tool.name,
          kind = tool.kind,
          locator = locator,
          policy = tool.policy,
          reason = tool.reason or "no stated reason",
          consumer = consumer,
          owner = name,
        }
        seen[key] = entry
        out[#out + 1] = entry
      end
    end
  end
  return out
end

-- Which plugins a missing tool takes down, and what each absent tool costs.
--
-- `present` answers whether one tool name resolved, and is injected rather than probed
-- here, so this module never learns what a tool is or how presence is proven. A REQUIRED
-- tool missing means the plugin is not wired at all, since a dead surface is worse than
-- no surface. An OPTIONAL one missing means the plugin still loads and states what it
-- lost, which is the whole difference between the two policies.
function obj.tools(manifests, present)
  local blocked, degraded = {}, {}
  for name, m in pairs(manifests) do
    for _, tool in ipairs((m.needs or {}).tools or {}) do
      if not present(tool) then
        if tool.policy == "required" then
          blocked[name] = "needs " .. tool.name .. ", which is for " .. (tool.reason or "no stated reason")
        else
          degraded[name] = degraded[name] or {}
          table.insert(degraded[name], tool.name .. " is absent, so it loses " .. (tool.reason or "part of itself"))
        end
      end
    end
  end
  return blocked, degraded
end

-- Whether one member is there to be had, given the module it should live on. A nil module
-- means the identity never resolved to anything real, and a present module missing the
-- named member means the capability itself is gone, which are different sentences even
-- though both end with nothing to call.
local function missingMember(mod, member)
  if mod == nil then return "which does not resolve to a loaded module" end
  if member == nil then return nil end
  if mod[member] == nil then return "which has no '" .. member .. "'" end
  return nil
end

-- Prove that every sibling and every lib need names something that actually exists on the
-- real, loaded module, not merely something that exists in the manifest set.
--
-- This is the check the first attempt never made. It proved a plugin's NAME resolved and
-- stopped there, so three manifests going on declaring clipboard.pasteText, clipboard's
-- own copySelection, and clipboard.setContents kept reading as fine right up to the moment
-- the emoji picker inserted nothing, because all three capabilities had already been
-- deleted from the clipboard module and nothing anywhere compared the name against the
-- module's real shape. A required need that cannot be proven blocks the plugin, since a
-- surface that is present and broken is worse than one that never opened. An optional one
-- is reported and the plugin still loads, degraded, the same shape `tools` already uses.
--
-- `modules` is the live wiring, an identity to module mapping or a function that returns
-- one given an identity, deliberately not the manifest set, since the manifest set is
-- exactly what the first attempt mistook for proof.
--
-- `libs` is a SECOND mapping, for Olm's own lib modules, and it is separate from `modules`
-- rather than folded into it. Plugin identities and lib names are two namespaces, so one
-- shared table would let a plugin called paste and the lib called paste answer for each
-- other. The first version did share one, and the ambiguity was not theoretical, a caller
-- supplying plugins but no libs got six plugins reported as blocked when nothing was wrong
-- with any of them. A check whose failure mode is a false alarm gets ignored just as fast
-- as one that misses a real fault.
--
-- Either mapping may be absent, and absent means NOT CHECKED rather than nothing found, so
-- no need is reported against a namespace the caller never supplied.
function obj.capabilities(manifests, modules, libs)
  local blocked, unresolved = {}, {}
  local function lookup(bag, key)
    if type(bag) == "function" then return bag(key) end
    return (bag or {})[key]
  end
  for name, m in pairs(manifests) do
    local needs = m.needs or {}
    for field, value in pairs(needs.siblings or {}) do
      local sib = normalizeSibling(value)
      local problem = modules and sib.plugin and missingMember(lookup(modules, sib.plugin), sib.member)
      if problem then
        local label = "sibling '" .. sib.plugin .. (sib.member and ("." .. sib.member) or "") .. "'"
        if sib.policy == "required" then
          blocked[name] = "needs " .. label .. ", " .. problem
        else
          unresolved[name .. "." .. field] = "needs " .. label .. ", " .. problem
        end
      end
    end
    for field, value in pairs(needs.lib or {}) do
      local lib = normalizeLib(value)
      local problem = libs and lib.module and missingMember(lookup(libs, lib.module), lib.member)
      if problem then
        local label = "lib '" .. lib.module .. (lib.member and ("." .. lib.member) or "") .. "'"
        if lib.policy == "required" then
          blocked[name] = "needs " .. label .. ", " .. problem
        else
          unresolved[name .. "." .. field] = "needs " .. label .. ", " .. problem
        end
      end
    end
  end
  return blocked, unresolved
end

-- Plain data a plugin cannot derive for itself, the required names and the optional ones,
-- each carrying the sentence to print when the value never arrives.
--
-- The category exists because a required parameter with no name behind it used to be
-- invisible to this whole layer. DisplayMemory's manifest could answer `return {}` while
-- its bundleID was a hard requirement, and nothing here would have said a word while
-- start() quietly did nothing. `breaks` is what turns a missing value into a sentence a
-- person can act on rather than only a fact that something, somewhere, is off.
--
-- Validation lives here rather than at read time, since it is a question about the
-- declaration's own honesty rather than its shape. `source` must say where the value comes
-- from, the person's own knowledge or something this root computes, and a REQUIRED entry
-- with no `breaks` is treated as a defect of the same kind, a declaration that cannot keep
-- the promise the category exists to make.
function obj.data(manifests)
  local answers, defects = {}, {}
  for name, m in pairs(manifests) do
    for field, value in pairs((m.needs or {}).data or {}) do
      local policy = value.policy or "required"
      if value.source ~= "user" and value.source ~= "root" then
        defects[name .. "." .. field] = "declares data with source '" .. tostring(value.source)
          .. "', neither 'user' nor 'root'"
      end
      if policy == "required" and not value.breaks then
        defects[name .. "." .. field] = "is required and carries no breaks sentence, "
          .. "so nothing can say what stopped working once it is absent"
      end
      answers[name] = answers[name] or { required = {}, optional = {} }
      local bucket = (policy == "optional") and answers[name].optional or answers[name].required
      bucket[field] = value.breaks
    end
  end
  return answers, defects
end

-- Cascade a block along the sibling graph, and catch a name that resolves to nothing.
--
-- Two different failures meet here and they deserve different words. A sibling that EXISTS
-- but is not being wired is a machine condition, some tool it wanted is absent. A sibling
-- that is not a plugin at all is a typo, identical on every machine, and the whole point of
-- declaring needs is lost if a misspelled one silently means no injection. That was the gap
-- the first version of this had, and it is the exact class of silent failure this layer is
-- meant to remove, so an unresolvable name is always reported however it is policed.
--
-- A required need that will not arrive blocks the plugin either way, since the alternative
-- is a surface that is present and broken. An optional one that cannot resolve loads
-- anyway, degraded, and is still named, because an optional capability that can never
-- arrive is a defect rather than a choice.
--
-- Runs to a fixed point, since a chain of three is possible and blocking the first has to
-- reach the third. This still answers only whether the PLUGIN a sibling names exists and
-- is up. Whether the specific member it wants exists on the real module is a later
-- question, `capabilities` answers it, since a manifest has to load with nothing else
-- running and cannot be asked to prove anything about a module it never touches.
function obj.cascade(manifests, blocked, libNames)
  libNames = libNames or {}
  local unresolved = {}
  local changed = true
  while changed do
    changed = false
    for name, m in pairs(manifests) do
      if not blocked[name] then
        local needs = m.needs or {}
        for field, value in pairs(needs.siblings or {}) do
          local sib = normalizeSibling(value)
          local dep = sib.plugin
          if dep then
            local absent = (manifests[dep] == nil)
            local down = (blocked[dep] ~= nil)
            if absent then
              unresolved[name .. "." .. field] = "names '" .. dep .. "', which is not a plugin here"
            end
            if sib.policy == "required" and (absent or down) then
              blocked[name] = absent
                and ("needs sibling '" .. dep .. "', which does not exist")
                or ("needs sibling '" .. dep .. "', which is itself not loaded")
              changed = true
              break
            end
          end
        end
        -- The same check for a lib capability, since a misspelled one fails identically and
        -- silently. The available set is injected, so this module never learns what lib holds.
        for field, value in pairs(needs.lib or {}) do
          local lib = normalizeLib(value)
          if lib.module and not libNames[lib.module] then
            unresolved[name .. "." .. field] = "names lib '" .. lib.module .. "', which does not exist"
            if lib.policy == "required" and not blocked[name] then
              blocked[name] = "needs lib '" .. lib.module .. "', which does not exist"
              changed = true
            end
          end
        end
      end
    end
  end
  return blocked, unresolved
end

-- The order plugins can be wired in, so a plugin is always configured after whatever it
-- needs from a sibling or from a satisfied set query. This is what replaces an order
-- maintained by hand, where nothing states the constraint and a rearrangement breaks
-- something far away.
--
-- A set query is an edge too, to every member the query resolves to, not only to a plugin
-- named directly. Leaving this out is how the launcher once got wired before
-- SystemSettings, since nothing in the launcher's own manifest names SystemSettings by
-- name, it only asks the set for every scope, and SystemSettings answers that question only
-- after its own configure has run. Missing the edge silently emptied every settings pane
-- row the launcher would otherwise have listed.
--
-- Depth first with a visiting mark, so a cycle is caught and named rather than looping.
-- A cycle is a defect in the declarations and identical on every machine, so it is an
-- error for the whole plan rather than something resolved by dropping one side of it.
function obj.order(manifests, blocked)
  blocked = blocked or {}
  local out, state = {}, {}
  local cycle = nil

  -- A plugin that also happens to satisfy its own set query is not a dependency of
  -- itself. The launcher's own manifest is the real case, it asks the set for every
  -- plugin declaring a surface and it declares one too, so it is a member of its own
  -- answer. Keeping that edge would report a cycle for a plugin that never actually
  -- waits on anything, and a cycle here is fatal for the whole plan, so a plugin's own
  -- name is dropped from what its own queries return before it ever becomes an edge.
  local function dependenciesOf(name, m)
    local deps = {}
    for _, value in pairs((m.needs or {}).siblings or {}) do
      local sib = normalizeSibling(value)
      -- A lazy need, ordering false, still has to exist and is still checked by
      -- capabilities and cascade exactly like any other need. It contributes no edge
      -- here, and only here, since wanting a capability and wanting it configured first
      -- are different claims and MenuSearch's closures over the launcher only need
      -- the first one.
      if sib.plugin and sib.plugin ~= name and sib.ordering then deps[#deps + 1] = sib.plugin end
    end
    for _, query in pairs((m.needs or {}).set or {}) do
      for _, member in ipairs(obj.set(manifests, query, blocked)) do
        if member ~= name then deps[#deps + 1] = member end
      end
    end
    return deps
  end

  local function visit(name, trail)
    if state[name] == "done" then return end
    if state[name] == "visiting" then
      cycle = table.concat(trail, " needs ") .. " needs " .. name
      return
    end
    state[name] = "visiting"
    local m = manifests[name]
    for _, dep in ipairs(dependenciesOf(name, m)) do
      -- An unknown or blocked dependency is not fatal here. It is either already
      -- explained by cascade, or misspelled, which resolution reports against the live
      -- set, so ordering itself only ever walks edges it can actually stand on.
      if manifests[dep] and not blocked[dep] then
        trail[#trail + 1] = name
        visit(dep, trail)
        trail[#trail] = nil
        if cycle then return end
      end
    end
    state[name] = "done"
    out[#out + 1] = name
  end

  -- Sorted entry order so the result is stable across reloads. Without this the order
  -- rides on pairs, which varies per run, and two reloads could wire the same set two
  -- ways and only one of them would show a latent bug.
  local names = {}
  for name in pairs(manifests) do
    if not blocked[name] then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    visit(name, {})
    if cycle then return nil, cycle end
  end
  return out
end

-- Every external tool the set wants, each named once however many plugins want it, with
-- who wants it and where it comes from. This is the install list, and it is deliberately
-- a different view of the same declarations rather than a second copy of them. The
-- manifest repeats a tool per consumer because that answers what breaks without it. This
-- answers what to install, which is a different question and needs the dedupe.
--
-- `stage` separates a tool needed to RUN a plugin from one needed only to regenerate a
-- dataset or run a test suite. Without it an install list tells someone to fetch a
-- dataset builder to use the emoji picker, which is false and makes the whole thing look
-- heavier than it is.
function obj.installList(manifests, stage)
  stage = stage or "runtime"
  local byName = {}
  for _, name in ipairs((function()
    local n = {}
    for k in pairs(manifests) do n[#n + 1] = k end
    table.sort(n)
    return n
  end)()) do
    local m = manifests[name]
    for _, tool in ipairs((m.needs or {}).tools or {}) do
      if (tool.stage or "runtime") == stage then
        local row = byName[tool.name]
        if not row then
          row = { name = tool.name, kind = tool.kind, origin = tool.origin, policy = tool.policy, wanted = {} }
          byName[tool.name] = row
        end
        -- Required anywhere makes the tool required overall, since one plugin refusing
        -- to load is the strongest claim on it.
        if tool.policy == "required" then row.policy = "required" end
        table.insert(row.wanted, name)
      end
    end
  end
  local out = {}
  for _, row in pairs(byName) do out[#out + 1] = row end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- One summary a person can read after a reload, which is the gate this whole layer is
-- judged by. It names what loaded, what did not and why, and what each degraded plugin
-- gave up. Silence is not an acceptable answer to a plugin having quietly vanished.
function obj.report(order, blocked, degraded, skipped, unresolved)
  log.i(#order .. " plugin(s) wired")
  for name, err in pairs(skipped or {}) do
    log.e("plugin '" .. name .. "' has an unusable manifest, " .. err)
  end
  -- An error rather than a warning. A name that resolves to nothing is a repository defect,
  -- the same on every machine, unlike a tool that merely is not installed here.
  for where, why in pairs(unresolved or {}) do
    log.e("declaration '" .. where .. "' " .. why)
  end
  for name, why in pairs(blocked or {}) do
    log.w("plugin '" .. name .. "' NOT loaded, it " .. why)
  end
  for name, losses in pairs(degraded or {}) do
    for _, loss in ipairs(losses) do
      log.w("plugin '" .. name .. "' loaded degraded, " .. loss)
    end
  end
end

return obj
