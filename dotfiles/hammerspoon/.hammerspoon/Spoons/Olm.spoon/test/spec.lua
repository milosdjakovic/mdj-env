--- === Olm test spec ===
---
--- The vocabulary a scenario is written in, and the machinery that DERIVES most of them so
--- almost nothing has to be written by hand.
---
--- The rule this file exists to enforce is the same one the config itself answers to. If the
--- suite can work out a check from what a plugin already declared, the plugin must not restate
--- it as a test. A plugin that declares a registry block is checked for being registered, for
--- being active, for having a key, and for its picker actually opening and closing, and it
--- earns all four by declaring, not by anybody writing them down. So adding a plugin adds its
--- own coverage, and a suite that had to be edited for each new plugin would rot exactly the
--- way the launcher's hand kept row list did.
---
--- What stays hand written is behaviour no declaration implies. That a copied string reaches
--- the top of the clipboard, that a typed sum computes, that recasing replaces a selection.
--- Those live in a test.lua beside the plugin they are about, in the same Given When Then
--- shape, and the runner finds them by scanning rather than by a roster.
---
--- Three verdicts, not two. pass and fail mean what they always mean. manual means this can
--- only be judged by a person looking at the screen, an OCR read or a colour sample or which
--- monitor an overlay landed on, and the runner collects those into a checklist rather than
--- guessing. A suite that quietly scores an unjudgeable thing as passing is worse than one
--- that admits the gap.

local obj = {}

--------------------------------------------------------------------------------
-- The vocabulary
--------------------------------------------------------------------------------

--- A scenario is a plain table. Three of its fields are the Given When Then, and each is
--- optional, because plenty of real checks are only a Then over the state a load left behind.
---
---   scenario  what is being claimed, in one sentence, read aloud in the report
---   given     set the world up, no assertion
---   when      do the thing
---   expect    answer true, or false and a sentence saying what was seen instead
---   manual    true when only a person can judge it, and then expect is never called
---   tier      structure, surface, behaviour, or input, deciding when it runs
---
--- `expect` answers a second value on failure ON PURPOSE. A bare false tells a reader that
--- something did not hold without telling them what did, which is the difference between a
--- report that leads somewhere and one that only says look again.
function obj.scenario(t)
  assert(type(t.scenario) == "string", "a scenario needs a sentence saying what it claims")
  t.tier = t.tier or "behaviour"
  return t
end

--------------------------------------------------------------------------------
-- Derived scenarios, the part nobody writes
--------------------------------------------------------------------------------

-- Everything a manifest already says, turned into checks. This is where the suite's real
-- coverage comes from, and every plugin gets it for nothing.
--
-- The list is deliberately built from the PLAN and the LIVE REGISTRY rather than from the
-- manifests alone, because a manifest is a claim and the plan and the registry are what
-- actually happened. A suite that read only manifests would agree with itself, which is the
-- exact failure that let a manifest naming a deleted capability pass for weeks.
function obj.derive(world)
  local out = {}
  local plan = world.plan
  local registry = world.registry

  local function add(t) out[#out + 1] = obj.scenario(t) end

  -- Every plugin the plan wired. A blocked one is not a failure by itself, since a plugin
  -- blocked for want of a tool this machine does not have is correct behaviour, but it is
  -- reported so the reason is visible rather than inferred from an absence.
  for _, name in ipairs(plan.order or {}) do
    local manifest = world.manifests[name]
    local identity = (plan.identity or {})[name] or name

    add({
      tier = "structure",
      scenario = ("the %s plugin is wired"):format(identity),
      expect = function()
        local module = world.module(identity)
        if not module then return false, "nothing loaded under that identity" end
        return true
      end,
    })

    -- A registry block is a claim that this tool is reachable, so all of it is checked.
    if manifest and manifest.registry then
      add({
        tier = "structure",
        scenario = ("%s is registered and active"):format(identity),
        expect = function()
          local entry = registry.get(identity)
          if not entry then return false, "the registry has no entry under that name" end
          local live = false
          for _, e in ipairs(registry.all()) do
            if e.name == identity then live = e.active end
          end
          if not live then return false, "it registered but is not in the active set" end
          return true
        end,
      })

      if manifest.registry.row and manifest.registry.row.category then
        add({
          tier = "structure",
          scenario = ("%s has a row a person can find in the launcher"):format(identity),
          expect = function()
            local row = registry.rowFor(identity)
            if not row then return false, "the registry built no row for it" end
            if not row.description then return false, "its row carries no description to show" end
            return true
          end,
        })
      end

      if manifest.registry.shortcut then
        add({
          tier = "structure",
          scenario = ("%s owns a key"):format(identity),
          expect = function()
            for _, entry in ipairs(registry.shortcuts() or {}) do
              if entry.name == identity then return true end
            end
            return false, "no shortcut entry, so nothing bound its open key"
          end,
        })
      end

      -- The one that actually proves something works. Open it the way the registry opens it,
      -- see it, close it the way every surface closes. Derived for every tool at once.
      if manifest.registry.surface then
        add({
          tier = "surface",
          scenario = ("%s opens and closes"):format(identity),
          when = function(w) return w.open(identity) end,
          expect = function(w)
            if not w.showing(identity) then
              return false, "it was asked to open and never showed"
            end
            w.close(identity)
            w.settle()
            if w.showing(identity) then
              return false, "it opened but would not close again"
            end
            return true
          end,
        })
      end

      -- A scope is the promise that typing a word reaches this tool, so the promise is kept.
      if manifest.registry.scope then
        add({
          tier = "structure",
          scenario = ("%s answers rows when its word is typed"):format(identity),
          expect = function()
            local scope = registry.scopeFor(identity)
            if not scope then return false, "the registry holds no scope for it" end
            if type(scope.rows) ~= "function" then return false, "its scope has no rows function" end
            local ok, rows = pcall(scope.rows, "")
            if not ok then return false, "asking it for rows raised, " .. tostring(rows) end
            if type(rows) ~= "table" then
              return false, "it answered a " .. type(rows) .. " rather than a list of rows"
            end
            return true
          end,
        })
      end
    end

    -- A required tool that is missing is why a plugin is not here, so it is worth stating
    -- plainly rather than leaving somebody to work out why a picker never opens.
    for _, tool in ipairs(((manifest or {}).needs or {}).tools or {}) do
      if tool.policy == "required" then
        add({
          tier = "structure",
          scenario = ("%s has %s, which it cannot work without"):format(identity, tool.name),
          expect = function()
            if world.present(tool) then return true end
            return false, tool.name .. " is not on this machine, so " .. tool.reason
          end,
        })
      end
    end
  end

  -- Plugins the plan refused, each with the sentence its own manifest wrote for this moment.
  for name, why in pairs(plan.blocked or {}) do
    add({
      tier = "structure",
      scenario = ("%s is blocked, and the reason is a real one"):format(name),
      expect = function()
        return false, tostring(why)
      end,
    })
  end

  -- Obligations Olm owes itself. An undischarged one is a root defect rather than a plugin's.
  for _, owed in ipairs(plan.obligations or {}) do
    local plugin, field = tostring(owed):match("^(.-)%.(.+)$")
    add({
      tier = "structure",
      scenario = ("the root supplied %s to %s"):format(field or owed, plugin or "a plugin"),
      expect = function()
        local supplied = plugin and world.suppliedData(plugin, field)
        if supplied == nil then
          return false, "the root declared it owed this and then did not hand it over"
        end
        return true
      end,
    })
  end

  -- Every context binding names an action something can actually answer. An unknown one is
  -- not an error anywhere at runtime, the key simply does nothing, which is the quietest
  -- possible failure and the reason this is checked rather than trusted.
  for contextName, block in pairs(plan.contexts or {}) do
    add({
      tier = "structure",
      scenario = ("every key in the %s overlay does something"):format(contextName),
      expect = function()
        local dead = {}
        for _, binding in ipairs((block or {}).bindings or {}) do
          if binding.action and not world.canDispatch(binding.action) then
            dead[#dead + 1] = binding.key .. " (" .. binding.action .. ")"
          end
        end
        if #dead > 0 then
          return false, "these keys are bound to nothing, " .. table.concat(dead, ", ")
        end
        return true
      end,
    })
  end

  -- Predicates a binding gates on but nothing defines. Treated as always true at runtime, so
  -- the key is live when it should be hidden, which reads as a bug in the tool rather than here.
  add({
    tier = "structure",
    scenario = "every gated key names a predicate that exists",
    expect = function()
      local missing = {}
      for contextName, block in pairs(plan.contexts or {}) do
        for _, binding in ipairs((block or {}).bindings or {}) do
          if binding.when and not world.hasPredicate(binding.when) then
            missing[#missing + 1] = contextName .. "." .. tostring(binding.key)
              .. " wants '" .. binding.when .. "'"
          end
        end
      end
      if #missing > 0 then
        return false, table.concat(missing, ", ")
      end
      return true
    end,
  })

  return out
end

--------------------------------------------------------------------------------
-- Hand written specs, found rather than listed
--------------------------------------------------------------------------------

--- Every test.lua beside a plugin, loaded. A file that fails to load is reported as one
--- failing scenario rather than taking the run down, since a broken test is a smaller problem
--- than no run at all and hiding it would be worse than either.
function obj.discover(roots)
  local features = {}
  for _, root in ipairs(roots) do
    local iter, dirObj = hs.fs.dir(root)
    if iter then
      local names = {}
      for entry in iter, dirObj do
        if entry ~= "." and entry ~= ".." then names[#names + 1] = entry end
      end
      -- Sorted, so a run reads the same on every machine rather than in whatever order the
      -- filesystem answered, which is the same reason the manifest reader sorts.
      table.sort(names)
      for _, entry in ipairs(names) do
        local path = root .. "/" .. entry .. "/test.lua"
        if hs.fs.attributes(path) then
          local chunk, err = loadfile(path)
          if not chunk then
            features[#features + 1] = {
              feature = entry,
              broken = "its test.lua does not load, " .. tostring(err),
              scenarios = {},
            }
          else
            local ok, answer = pcall(chunk)
            if ok and type(answer) == "table" then
              answer.feature = answer.feature or entry
              answer.scenarios = answer.scenarios or {}
              features[#features + 1] = answer
            else
              features[#features + 1] = {
                feature = entry,
                broken = "its test.lua raised, " .. tostring(answer),
                scenarios = {},
              }
            end
          end
        end
      end
    end
  end
  return features
end

return obj
