-- Turning declarations into a wiring plan, and nothing else.
--
-- This is the integration point of the manifest layer. It reads what every plugin declared,
-- merges the user's own configuration over the defaults each one proposed, answers the
-- questions hosts asked about the set, builds each surface, and returns a PLAN.
--
-- The split between planning and applying is the whole design of this file. `plan` is pure.
-- It calls no configure, starts no watcher, and binds no key, so it can be run and printed
-- without changing anything. That is what makes an inspect command possible, and an inspect
-- command is the thing that keeps a defaults system honest. Once a binding is not written in
-- the user's own file, the question of what a key does has no answer anywhere unless
-- something can be asked, and a plan nobody can read is how a config becomes simple to start
-- and impossible to understand.
--
-- It is also what makes this testable at all. A plan is a table, so every decision in it can
-- be asserted against without a live Hammerspoon, real plugins, or any order of operations.
--
-- Purity survives capability checking, which needs real modules, because the modules are
-- passed IN rather than loaded here. Loading is the caller's business. This file still
-- requires nothing and touches nothing.

local obj = {}

-- The three collaborators, injected rather than required, so this file names no concrete
-- module and can be tested with stand ins for all three. They are separate arguments rather
-- than one table because each answers a genuinely different question and folding them
-- together would hide which one a failure came from.
--
--   plugins, the manifest reader, answering about the set
--   defaults, the merge, answering what a value ends up as and where it came from
--   surface, the context builder, answering what a list's bindings are
function obj.new(deps)
  deps = deps or {}
  local P, D, S = deps.plugins, deps.defaults, deps.surface
  assert(P and D and S, "resolve needs plugins, defaults, and surface injected")

  local self = {}

  -- One pass over the declarations, producing everything a composition root needs to wire
  -- the set, plus everything a person needs to understand what it decided.
  --
  -- Order matters inside here and it is not arbitrary. Tools are probed first, because a
  -- missing required tool removes a plugin and every later answer has to already know that.
  -- The block then cascades along the sibling graph, since a plugin whose dependency is gone
  -- is gone too. Only then is anything merged, ordered, or built, so nothing is ever computed
  -- for a plugin that will not exist.
  --
  -- `input` carries the whole question rather than a fixed argument list, because the list
  -- grew twice and a positional call is where a new argument gets silently dropped.
  --   manifests, what every plugin declared
  --   user,      the person's own configuration
  --   present,   a predicate answering whether a tool is on this machine
  --   libNames,  the set of real lib module names
  --   modules,   the real loaded modules by identity, OPTIONAL
  --   data,      the data values the root and the user can actually supply, OPTIONAL
  --   available, the wiring time choices a binding may name through `needs`, OPTIONAL
  function self.plan(input)
    input = input or {}
    local manifests = input.manifests or {}
    local userConfig = input.user or {}
    local present = input.present or function() return true end
    local libNames = input.libNames or {}
    local modules = input.modules
    local supplied = input.data or {}
    -- Which wiring time choices were actually made, so a binding that named one through `needs`
    -- is dropped here rather than being bound to nothing. This is answered ONCE, unlike `when`,
    -- which is a live predicate asked on every press, and the difference matters because a
    -- `needs` gate must remove the binding from the key wiring and from the hint panel together.
    -- A binding present in one and absent from the other is the exact disagreement the two
    -- discoverability rules exist to prevent.
    --
    -- Left as nil rather than defaulted to an empty table, and the difference is not cosmetic.
    -- An absent table means filter nothing, an EMPTY one means nothing is available and every
    -- gated binding is dropped. Defaulting it would silently delete bindings from any caller
    -- that had no opinion, which is the failure this whole layer exists to make loud.
    local available = input.available

    local out = {
      order = {},
      blocked = {},
      degraded = {},
      effective = {},
      provenance = {},
      contexts = {},
      predicates = {},
      identity = {},
      wiring = {},
      sets = {},
      disabled = {},
      problems = {},
      unchecked = {},
      obligations = {},
    }

    local function problem(kind, where, why)
      out.problems[#out.problems + 1] = { kind = kind, where = where, why = why }
    end

    -- A plugin the user switched off entirely. Taken out before anything else looks at it,
    -- since a disabled plugin must not appear in a host's set, must not claim a default key,
    -- and must not be reported as blocked, which would read as a failure rather than a choice.
    local live = {}
    for name, m in pairs(manifests) do
      if userConfig[name] == false then
        out.disabled[name] = true
      else
        live[name] = m
      end
    end

    -- Identity. The directory a plugin was found in is NOT its name outside that directory.
    -- Seven of the twelve real tools spell their identity differently from their folder, and
    -- one of them, colorPicker, lives in a folder called eyedropper. Everything downstream
    -- that has to match a name against the rest of the config, a registry roster or a key
    -- catalog, must read this rather than the directory, which is the mistake that made the
    -- first apply register every plugin under a name nothing else in the config used.
    for name, m in pairs(live) do
      out.identity[name] = m.name or name
    end

    -- 1. Tools. A required tool missing takes its plugin down, an optional one costs it a part.
    local blocked, degraded = P.tools(live, present)
    out.degraded = degraded

    -- 2. Cascade along siblings and lib, so a name that cannot resolve is either a block or a
    -- reported defect, never a silent absence.
    local unresolved
    blocked, unresolved = P.cascade(live, blocked, libNames)
    for where, why in pairs(unresolved or {}) do
      problem("unresolved", where, why)
    end

    -- 3. Capability existence, which is a different question from plugin existence and the one
    -- the first version never asked. A sibling need naming a plugin that IS present but a
    -- member that is not gets past the cascade untouched, which is how three manifests went on
    -- declaring four capabilities that had been deleted from the clipboard module, resolving
    -- every one of them to nil with nothing anywhere reporting it.
    --
    -- Skipped, and recorded as skipped, when no modules are supplied. An inspect run has no
    -- reason to load every plugin, but it must not then claim the capabilities were verified.
    if modules or input.libs then
      local capBlocked, capProblems = P.capabilities(live, modules, input.libs)
      for name, why in pairs(capBlocked or {}) do
        blocked[name] = blocked[name] or why
      end
      for where, why in pairs(capProblems or {}) do
        problem("capability", where, why)
      end
    end
    -- Reported per namespace, since supplying one and not the other verifies half the
    -- declarations and must not read as having verified all of them.
    if not modules then
      out.unchecked[#out.unchecked + 1] = "sibling capabilities, no plugin modules were supplied"
    end
    if not input.libs then
      out.unchecked[#out.unchecked + 1] = "lib capabilities, no lib modules were supplied"
    end

    -- 4. Data. A parameter a plugin cannot derive and cannot work without, which is neither a
    -- tool nor a capability and had no category at all in the first schema. DisplayMemory
    -- declared an empty table while a bundle id was a hard requirement whose absence made its
    -- start a silent no operation, and that silence is what this exists to end.
    -- The answer arrives already sorted into a required bucket and an optional one, each field
    -- mapped to its `breaks` sentence. Reading it as one flat field keyed table was the first
    -- version and it failed in the worst possible direction. Every field name came back as the
    -- literal string required or optional, so no policy ever matched, nothing ever blocked, and
    -- a required parameter nothing supplied wired the plugin anyway. A bug in this layer that
    -- makes the layer permissive is far worse than one that makes it noisy, so the two buckets
    -- are read separately and by name.
    local needData, dataDefects = {}, {}
    if P.data then needData, dataDefects = P.data(live) end
    for where, why in pairs(dataDefects or {}) do
      problem("data", where, why)
    end

    local function absent(name, field)
      return not (supplied[name] and supplied[name][field] ~= nil)
    end

    -- Whether a required need BLOCKS depends on who was supposed to supply it, and conflating
    -- the two sources was a real defect. A need sourced from the user is a statement that this
    -- plugin cannot ship working, so a plan with nothing configured must show it blocked, since
    -- that is the honest answer for a fresh install. A need sourced from the root is Olm's own
    -- obligation to itself, and the root always meets it, so blocking on it in a plan that has
    -- no root attached yet would report six plugins broken on a machine where nothing is wrong.
    -- An inspect run is the main caller with no root, and it must not lie about a fresh install
    -- in either direction.
    --
    -- So a root sourced need that nothing supplied is recorded as an obligation rather than a
    -- block, ALWAYS, whether or not any data came in with this call.
    --
    -- That last part is the correction, and getting it wrong cost the whole of window
    -- management. The test used to be whether any data table arrived at all, and a composition
    -- root plans TWICE, the first time to work out the values it can only compute once it knows
    -- what the plan says. That first pass carries the person's own data, so the test read true,
    -- so every root sourced need looked unmet by a root that was present, so windowmanager was
    -- blocked on the very pass whose purpose was to produce the mapping it was blocked for
    -- wanting. It never reached the second pass, its sixteen bindings were stamped off an empty
    -- list, and holding the window leader did nothing while the report said no problems, since
    -- a blocked plugin is a planning outcome rather than a wiring failure. A source of root
    -- means Olm owes itself, and a debt Olm owes itself is never grounds for refusing to plan.
    --
    -- What keeps that honest is that the obligation is still recorded either way, so a root
    -- that genuinely fails to discharge one leaves a line a person can read rather than silence.
    for name, buckets in pairs(needData) do
      if not blocked[name] then
        for field, breaks in pairs(buckets.required or {}) do
          if absent(name, field) then
            local source = ((live[name].needs or {}).data or {})[field]
            source = source and source.source
            if source == "root" then
              out.obligations[#out.obligations + 1] = name .. "." .. field
            else
              blocked[name] = breaks or ("it needs " .. field .. ", which nothing supplied")
            end
          end
        end
        -- The same exemption the required branch above makes, and for the same reason. A field
        -- Olm owes itself is not absent, it is not due yet, because the root discharges these at
        -- wiring time and the plan is drawn up before that. Without this the optional branch
        -- called six root sourced needs losses on a completely healthy config, four of them the
        -- launcher's, one of which announced that choosing almost any row does nothing at all
        -- while the launcher was demonstrably opening and dispatching. A report that cries wolf
        -- on every load is worse than no report, since the next real loss scrolls past with it.
        --
        -- Recorded as an obligation rather than dropped, so a root that genuinely never hands one
        -- over still leaves a line a person can read, which is the same bargain the required
        -- branch already strikes.
        for field, breaks in pairs(buckets.optional or {}) do
          if absent(name, field) then
            local source = ((live[name].needs or {}).data or {})[field]
            source = source and source.source
            if source == "root" then
              out.obligations[#out.obligations + 1] = name .. "." .. field
            else
              out.degraded[name] = out.degraded[name] or {}
              table.insert(out.degraded[name], breaks or (field .. " was not supplied"))
            end
          end
        end
      end
    end

    out.blocked = blocked

    -- 5. Order. A cycle is fatal for the whole plan rather than for one plugin, because there
    -- is no correct subset to wire and picking one would be inventing an answer.
    local order, cycle = P.order(live, blocked)
    if not order then
      problem("cycle", "sibling graph", cycle)
      return out
    end
    out.order = order

    -- 6. Merge each plugin's proposed defaults under the user's own configuration, keeping the
    -- provenance so every effective value can say where it came from.
    for _, name in ipairs(order) do
      local proposed = (live[name].defaults) or {}
      local mine = userConfig[name]
      out.effective[name] = D.merge(proposed, mine)
      out.provenance[name] = D.provenance(proposed, mine)
    end

    -- 7. Collisions between what two plugins proposed. Reported, never resolved. Two defaults
    -- wanting one key is a defect identical on every machine, and picking a winner by load
    -- order would make it a different defect on every reload instead.
    for _, hit in ipairs(D.collisions(out.effective, out.provenance) or {}) do
      problem("collision", "defaults", type(hit) == "string" and hit or (hit.why or "two declarations claim one slot"))
    end

    -- 8. The questions hosts asked about the set, answered from what the plugins declared, so
    -- no host holds a roster and adding a tool joins every list for free.
    local sets, empty = P.sets(live, blocked)
    out.sets = sets
    for where, why in pairs(empty or {}) do
      problem("emptySet", where, why)
    end

    -- 9. Surfaces.
    --
    -- A surface declaration is NOT one of the proposed defaults and must not be merged as if
    -- it were. It sits at manifest.surface, so there is nothing under manifest.defaults for a
    -- user fragment to land on, and merging the two axes together meant a user who changed one
    -- key handed the builder a table holding only that key. The context name, the extra
    -- bindings and the navigation flag all vanished with it, and the plugin lost its whole
    -- block. The earlier version of this comment claimed the opposite of what the code did,
    -- which is worse than no comment, and the test that passed only ever checked that the
    -- changed key had changed.
    --
    -- So the user's surface fragment merges over the DECLARED surface, on its own axis.
    for _, name in ipairs(order) do
      local decl = live[name].surface
      if decl then
        local mine = userConfig[name]
        local fragment = type(mine) == "table" and mine.surface or nil
        local effectiveDecl = fragment and D.merge(decl, fragment) or decl

        local ok, err = S.validate(name, effectiveDecl)
        if ok then
          -- Keyed on the declared context name rather than the directory name, since
          -- several plugins spell their context in camel case, browserTabs for one, and
          -- surface.lua derives the predicate name from whatever key it is handed. Passing
          -- the directory name here would key the block browsertabs and its predicate
          -- browsertabsOpen, silently different from the browserTabs and browserTabsOpen
          -- everything else in this config still expects, with no error anywhere, since an
          -- unresolvable when is treated as always active by design.
          local contextName = effectiveDecl.context or out.identity[name] or name
          local block = S.context(contextName, effectiveDecl, available)
          out.contexts[contextName] = block

          -- Every predicate name the built contexts depend on, collected in one place the
          -- caller cannot forget to read. The first apply computed a table like this and
          -- installed it nowhere while binding the keys that needed it in the same run, and
          -- because an unknown name is treated as ALWAYS ACTIVE, the result would have been
          -- every list's navigation keys live at all times and the base layer never
          -- suppressed. Returning the names is what lets a caller be checked against them.
          local when = block.when or (contextName .. "Open")
          out.predicates[when] = contextName
        else
          problem("surface", name, err)
        end
      end
    end

    -- 10. Wiring steps beyond configure. Recorded per plugin in declared order, because five
    -- plugins keep their picker on a submodule and several need a call that is not configure
    -- at all. Without this, WindowManager wired up completely dead, since bindToLeader never
    -- ran and nothing anywhere said that it should.
    for _, name in ipairs(order) do
      local steps = live[name].wiring
      if steps and #steps > 0 then
        out.wiring[name] = steps
      end
    end

    return out
  end

  -- What the plan decided, as lines a person can read. This is the inspect command's whole
  -- output, and it deliberately reports the boring cases too, since a plugin loading normally
  -- with all its defaults is exactly what someone is checking when they ask.
  function self.explain(plan)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add(#plan.order .. " plugin(s) would be wired")
    for _, name in ipairs(plan.order) do
      local marks = {}
      local id = plan.identity[name]
      if id and id ~= name then marks[#marks + 1] = "known as " .. id end
      if plan.wiring[name] then marks[#marks + 1] = #plan.wiring[name] .. " extra step(s)" end
      if plan.degraded[name] then marks[#marks + 1] = "degraded" end
      local prov = plan.provenance[name] or {}
      local userSet = 0
      for _, source in pairs(prov) do
        if source == "user" then userSet = userSet + 1 end
      end
      marks[#marks + 1] = userSet .. " value(s) from you"
      add("  " .. name .. ", " .. table.concat(marks, ", "))
    end

    local surfaced = 0
    for _ in pairs(plan.contexts) do surfaced = surfaced + 1 end
    add(surfaced .. " surface(s) built, needing " .. (function()
      local n = 0
      for _ in pairs(plan.predicates) do n = n + 1 end
      return n
    end)() .. " predicate(s)")

    for name in pairs(plan.disabled) do
      add("  " .. name .. ", switched off in your configuration")
    end
    for name, why in pairs(plan.blocked) do
      add("  " .. name .. ", NOT wired, " .. why)
    end
    for host, fields in pairs(plan.sets) do
      for field, list in pairs(fields) do
        add("  " .. host .. " asked the set for " .. field .. ", got " .. #list)
      end
    end
    if #plan.obligations > 0 then
      add("  " .. #plan.obligations .. " value(s) Olm owes itself at wiring time, "
        .. table.concat(plan.obligations, ", "))
    end
    for _, note in ipairs(plan.unchecked) do
      add("  NOT VERIFIED " .. note)
    end
    for _, p in ipairs(plan.problems) do
      add("  PROBLEM " .. p.kind .. " at " .. p.where .. ", " .. tostring(p.why))
    end
    return table.concat(lines, "\n")
  end

  return self
end

return obj
