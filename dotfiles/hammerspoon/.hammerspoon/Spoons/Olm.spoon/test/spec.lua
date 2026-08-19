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
      --
      -- Written as steps rather than as an open followed by a look, and that is the whole
      -- reason three tools reported here as broken while they open perfectly by hand. Menu
      -- search walks the accessibility tree, processes shells out, and text case reads the
      -- selection through the pasteboard, so all three ask for their data first and show
      -- only once the answer lands. Every one of those answers is delivered on the MAIN
      -- THREAD, so anything that blocks that thread while waiting is guaranteeing the show
      -- it is waiting for can never happen. Only the runner may wait, between steps, where
      -- a real timer lets the run loop turn.
      --
      -- The tools that passed this check before passed by accident. A plain chooser sets its
      -- own showing flag inside show(), so a blocking wait could not stop it, and the three
      -- that gather first were the only ones the defect was ever visible through.
      if manifest.registry.surface then
        -- One look, remembered once it is a yes, so a tool that appears on the second look
        -- is not scored on the fifth. Written once here and used by every polling step below
        -- rather than repeated, since the steps differ only in when they happen.
        local function look(w)
          if not w._surfaceOpened then w._surfaceOpened = w.showing(identity) end
        end
        add({
          tier = "surface",
          scenario = ("%s opens and closes"):format(identity),
          -- Looked at repeatedly rather than once, because how long a tool takes to appear is
          -- its own business and one number cannot be right for all of them. A plain chooser
          -- is up in the same breath as the call, while text case posts a Cmd+C and waits out
          -- a timeout before it knows whether anything was selected, half a second later on a
          -- machine with nothing selected at all. A single wait long enough for the slowest
          -- would be paid by every other tool on every run, and one short enough to stay quick
          -- reports the slow ones as broken, which is what it did.
          --
          -- So it polls rather than looking a fixed number of times, and the runner's polling
          -- step moves on the instant it sees the list. Quick tools now cost one look instead of
          -- five, and a slow one may take up to five seconds without anybody paying for that
          -- unless it needs it. The budget is a whole second per look longer than the old row
          -- was in total, which is what a first build after a relaunch turned out to want.
          steps = {
            { fn = function(w) w._surfaceOpened = nil w.open(identity) end, wait = 0.25 },
            { poll = function(w) look(w) return w._surfaceOpened end, every = 0.25, upTo = 5 },
            { fn = function(w) w.close(identity) end, wait = 0.4 },
          },
          expect = function(w)
            if not w._surfaceOpened then
              return false, "it was asked to open and never showed"
            end
            if w.showing(identity) then
              return false, "it opened but would not close again"
            end
            return true
          end,
        })

        -- Whether the config KNOWS it is open, which is a different question from whether it
        -- is, and the one every chord inside a picker hangs off. Each context binding is gated
        -- on a predicate named for the context, so a predicate that answers false while the
        -- list is up leaves j, k and every other in list key bound and dead, and the plain
        -- chord on the same key fires instead. In the clipboard that meant pressing j to move
        -- down opened the emoji picker.
        --
        -- Five of the twelve pickers answered false forever, because the answer was read off
        -- the plugin root and those five keep their picker on a submodule. Nothing raised, and
        -- the check that only asked whether the picker appeared passed on every one of them,
        -- which is why this is a separate scenario rather than another line in that one.
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

    -- Whether the config KNOWS a list is open, which is a different question from whether it
    -- is, and the one every chord inside a list hangs off. Each context binding is gated on a
    -- predicate named for the context, so a predicate answering false while the list is up
    -- leaves j, k and every other in list key bound and dead, and the plain chord on the same
    -- key fires instead. In the clipboard that meant pressing j to move down opened the emoji
    -- picker.
    --
    -- Five of the twelve answered false forever, because the answer was read off the plugin
    -- root and those five keep their picker on a submodule. Nothing raised, and the check that
    -- only asked whether the picker appeared passed on every one of them, which is exactly why
    -- this is its own scenario rather than another line inside that one.
    --
    -- Guarded on the surface context ALONE, deliberately outside the registry block above. The
    -- launcher declares a context and no registry entry at all, being a host rather than a
    -- registered tool, so a check nested in there skipped the one list with more in list keys
    -- than any other.
    local context = ((manifest or {}).surface or {}).context
    if context then
      local predicate = context .. "Open"
      local function look(w)
        if not w._contextSeen then w._contextSeen = w.hasContext(predicate) end
      end
      add({
        tier = "surface",
        scenario = ("%s is known to be open while it is open"):format(identity),
        steps = {
          { fn = function(w) w._contextSeen = nil w.open(identity) end, wait = 0.25 },
          -- Stops on a yes only. A predicate answering false may still turn true once the list
          -- is really up, and one answering nil has no predicate at all, which polling cannot
          -- mend, so both simply run the budget out and let expect tell the two apart.
          { poll = function(w) look(w) return w._contextSeen == true end, every = 0.25, upTo = 5 },
          { fn = function(w) w.close(identity) end, wait = 0.4 },
        },
        expect = function(w)
          if w._contextSeen == nil then
            return false, "this config has no " .. predicate .. " predicate at all, so every "
              .. "chord inside this list is gated on a question nobody answers"
          end
          if w._contextSeen ~= true then
            return false, "its list was open and " .. predicate .. " still said no, so every "
              .. "chord inside it is dead and the plain chord on the same key fires instead"
          end
          if w.hasContext(predicate) == true then
            return false, "its list was closed and " .. predicate .. " still says yes, so its "
              .. "keys stay captured after it goes away"
          end
          return true
        end,
      })

      -- And whether the surface that IS open answers the verbs its own keys are bound to,
      -- which is the last link in the chain and the one nothing checked.
      --
      -- Knowing a list is open only gets a key as far as being eligible. Routing then picks
      -- whichever surface says it is showing and calls the action on it, and a surface that
      -- does not answer that name is left alone in silence. So j was bound, eligible, routed,
      -- and then dropped, in the clipboard, emoji, menu search and the launcher, while working
      -- perfectly in the VPN list, whose methods happen to sit where the root was looking. A
      -- person cannot debug that from the outside and no check could see it either.
      --
      -- The verb list comes off the plan rather than being written here, so a context that
      -- gains a key is checked for that key with nobody having to remember.
      add({
        tier = "surface",
        scenario = ("%s answers every key it binds"):format(identity),
        steps = {
          { fn = function(w)
              w._unanswered = nil
              w._asked = false
              w.open(identity)
            end, wait = 0.25 },
          { poll = function(w)
              if not w._asked then
                local missing = w.unanswered(w.boundActions(context))
                if missing then w._asked = true w._unanswered = missing end
              end
              return w._asked
            end, every = 0.25, upTo = 5 },
          { fn = function(w) w.close(identity) end, wait = 0.4 },
        },
        expect = function(w)
          if not w._asked then
            return false, "its list never reported itself open, so no surface could be found "
              .. "to ask, and every key bound inside it routes to nothing"
          end
          if #w._unanswered > 0 then
            return false, "its live surface answers nothing for " ..
              table.concat(w._unanswered, ", ") .. ", so those keys are bound and do nothing"
          end
          return true
        end,
      })
    end

    -- A required tool that is missing is why a plugin is not here, so it is worth stating
    -- plainly rather than leaving somebody to work out why a picker never opens.
    for _, tool in ipairs(((manifest or {}).needs or {}).tools or {}) do
      if tool.policy == "required" then
        add({
          tier = "structure",
          scenario = ("%s has %s, which it cannot work without"):format(identity, tool.name),
          expect = function()
            local answer = world.present(tool)
            -- nil rather than false means nothing could answer, since this config recorded no
            -- dependency door, so there is no result to report either way.
            if answer == nil then
              return nil, "this root records no dependency door, so nothing can say whether "
                .. tool.name .. " is here"
            end
            if answer then return true end
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

  -- EVERY root sourced declaration, delivered or not, whatever its policy said.
  --
  -- This is the check whose absence let a whole afternoon of breakage pass as a clean run, and
  -- the reason it was absent is worth stating exactly. plan.obligations, which the check above
  -- reads, records only the REQUIRED root sourced needs. Every one of the values that actually
  -- went missing was declared optional, correctly, because each tool really does still open and
  -- still run without it. So all of them landed in plan.degraded, a list nothing asserts on, and
  -- the suite reported no problems on a config where the tab list could hold no tabs, file
  -- search had no vocabulary, the colour sampler could not build, and this machine's display
  -- arrangements had never arrived.
  --
  -- The word optional describes what breaks for the PERSON. It says nothing about whether the
  -- root owes the value, and a promise made inside this repository is either kept or it is a
  -- defect, identical on every machine. So policy is deliberately not consulted here.
  for name, manifest in pairs(world.manifests or {}) do
    for field, decl in pairs(((manifest or {}).needs or {}).data or {}) do
      if type(decl) == "table" and decl.source == "root" then
        local identity = (plan.identity or {})[name] or name
        add({
          tier = "structure",
          scenario = ("%s was given the root value %s"):format(identity, field),
          expect = function()
            if world.suppliedData(name, field) ~= nil then return true end
            return false, "nothing supplied it, so "
              .. (decl.breaks or "whatever this value is for does not happen")
          end,
        })
      end
    end
  end

  -- Every plugin something was configured FOR is a plugin that exists.
  --
  -- A value handed to a name no plugin answers to is merged, carried the whole way through, and
  -- given to nobody, and nothing about that looks wrong from the inside. It happened because a
  -- manifest is keyed by the name a plugin declares for itself while eight of them sit in a
  -- directory spelled differently, so browsertabs and browserTabs were two different plugins as
  -- far as delivery was concerned and only one of them was real. Three configured values went
  -- that way at once and every check in this suite still passed.
  for name in pairs(world.suppliedFor and world.suppliedFor() or {}) do
    add({
      tier = "structure",
      scenario = ("%s, which something was configured for, is a real plugin"):format(name),
      expect = function()
        if (world.manifests or {})[name] ~= nil then return true end
        return false, "no plugin answers to that name, so everything supplied under it was "
          .. "handed to nobody. Check it against the name the plugin declares for itself, "
          .. "which is not always its directory."
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
