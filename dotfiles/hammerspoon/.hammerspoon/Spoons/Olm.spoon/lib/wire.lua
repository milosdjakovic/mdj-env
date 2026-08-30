-- The stage pipeline. Everything a plan describes, actually done, in the one order that works.
--
-- This is the half of the design that the first attempt got wrong, and it got it wrong by
-- being a generic loop. It walked the plan plugin by plugin and configured each one, which
-- reads as the obvious shape and cannot work, because the constraints that decide the order
-- are not properties of any plugin. They are properties of the leader engines and the
-- registry. A leader keycode must be registered before the engine starts or the key is
-- silently never wired. The predicate table must be installed before the bind loop or every
-- navigation key is live at all times. Every tool must be registered before activation, and
-- activated before anything reads the shortcut list. None of that is derivable from a
-- manifest, so none of it is computed here. It is written down once, in order, below.
--
-- So the shape is a fixed skeleton with injected participation. The stages and their sequence
-- belong to this file and never change per plugin. What each plugin does inside a stage comes
-- from the plan. A plugin does not choose its stage and cannot reorder anything, which is what
-- makes adding one safe.
--
-- This file names no plugin and no tool. Every collaborator arrives through `services` from
-- the composition root, which is the only place that knows a concrete name.

local obj = {}

-- Which ambient services a plugin is entitled to, derived from what it already declared.
--
-- This table is the reason the manifests are short, and it is worth being clear about why it
-- is not a shortcut. Fifteen plugins need the shared chooser factory and the shared theme.
-- None of them declares either, because all fifteen declare a surface, and declaring a
-- surface IS the statement that this plugin opens a list. Writing chooser and theme into
-- fifteen manifests would retype global policy fifteen times and give it fifteen places to
-- drift, which is the defect this whole design exists to remove.
--
-- The rule generalises. If the root can derive a need from something already declared, the
-- plugin must not declare it again.
local ENTITLEMENTS = {
  -- earned by declaring a surface, since a surface means this plugin opens a list
  surface = { "chooser", "theme", "placeholder" },
  -- earned by declaring any external tool, since a tool name has to become a real path
  tools = { "deps" },
}

-- The docked hint panel arrives as three callbacks, and plugins disagree about the SHAPE they
-- want them in. Some read three flat fields, some read one nested table called shortcutPanel,
-- and one reads the same table called panel. That disagreement is real, it is in the plugins'
-- own configure contracts, so it has to be declared rather than assumed. Assuming one shape is
-- what silently removed the panel from four tools while handing each of them three fields none
-- of them read.
--
-- This field is the honest way to live with the disagreement, not an endorsement of it.
-- Normalising the four plugins onto one shape would delete it, and that is worth doing once
-- the wiring is proved, since the field only exists to describe an inconsistency.
local PANEL_CALLBACKS = { "onPositioned", "onActivity", "onClose" }

-- Services every plugin may have whether it declared anything or not. Kept deliberately tiny.
-- A service in here is one that cannot sensibly be refused, not merely one that is convenient.
local UNIVERSAL = { "after", "log" }

function obj.new(deps)
  deps = deps or {}
  local services = deps.services or {}
  local log = deps.log or function() end
  assert(deps.plan, "wire needs a plan")

  local self = {}
  local plan = deps.plan

  -- What this run actually did, so a failure has an account of itself rather than a console
  -- line saying something went wrong somewhere. Every stage appends, nothing is silent.
  self.record = { stages = {}, problems = {}, skipped = {} }

  local function note(stage, line)
    local s = self.record.stages[stage] or {}
    s[#s + 1] = line
    self.record.stages[stage] = s
  end

  local function fail(stage, where, why)
    self.record.problems[#self.record.problems + 1] = { stage = stage, where = where, why = why }
    log("e", "wire, " .. stage .. ", " .. where .. ", " .. why)
  end

  -- The options table a plugin receives. Its own effective declarations, plus exactly the
  -- ambient services its declarations earned, plus the data the root and the user supplied.
  --
  -- A plugin cannot tell an ambient value from a declared one and must not try. That is the
  -- point. It asks for what it needs by declaring a role, and the role is honoured here.
  local function optionsFor(name, manifest)
    local opts = {}
    for k, v in pairs(plan.effective[name] or {}) do opts[k] = v end

    local function grant(list)
      for _, key in ipairs(list) do
        if services[key] ~= nil then opts[key] = services[key] end
      end
    end

    grant(UNIVERSAL)
    if manifest.surface then grant(ENTITLEMENTS.surface) end
    if manifest.needs and manifest.needs.tools then grant(ENTITLEMENTS.tools) end

    -- Every lib capability the plugin declared, actually handed over under the field name it
    -- asked for. This was missing and its absence is the same defect as the one that started
    -- all of this. A declaration was validated at load, so it read as wired, and then nothing
    -- ever delivered the value, so the plugin got nil at the moment it mattered. Validating a
    -- need without satisfying it is worse than not declaring it, because the check reports
    -- success.
    local libs = deps.libs or {}
    for field, decl in pairs((manifest.needs or {}).lib or {}) do
      local moduleName, member
      if type(decl) == "table" then
        moduleName, member = decl.from or decl.module, decl.member
        -- The older form packs both into one dotted string, and it is still in use.
        if moduleName and not member then
          local a, b = tostring(moduleName):match("^([^.]+)%.(.+)$")
          if a then moduleName, member = a, b end
        end
      elseif type(decl) == "string" then
        moduleName, member = decl:match("^([^.]+)%.(.+)$")
        moduleName = moduleName or decl
      end

      local mod = moduleName and libs[moduleName]
      if mod then
        if member then
          local fn = mod[member]
          -- Bound to its own module when it is a method, so the plugin receives something it
          -- can call plainly. A bare method handed over unbound resolves and then fails on
          -- arity, which is the failure mode that is harder to find than a clean nil.
          if type(fn) == "function" and decl.call ~= "dot" then
            opts[field] = function(...) return fn(mod, ...) end
          else
            opts[field] = fn
          end
        else
          opts[field] = mod
        end
      end
    end

    -- Every sibling capability the plugin declared, handed over under the field name it asked
    -- for, exactly as the lib block above does. This was missing for the identical reason and
    -- with the identical result. resolve checks a sibling need names a real member on a real
    -- module and uses it to decide wiring order, both of which read as the need being handled,
    -- and then nothing delivered the value, so the launcher declared it wanted the window
    -- manager's action map and received nil. A need that is validated and never satisfied is
    -- worse than one never declared, because the check reports success.
    --
    -- ordering = false changes nothing here on purpose. That flag only says no edge is needed
    -- because the capability is called later rather than at wiring time, and a capability
    -- arriving late still has to arrive.
    local siblingModules = deps.modules or {}
    for field, decl in pairs((manifest.needs or {}).siblings or {}) do
      if type(decl) == "table" and decl.plugin then
        local identity = (plan.identity or {})[decl.plugin] or decl.plugin
        local mod = siblingModules[identity] or siblingModules[decl.plugin]
        if mod then
          if decl.member then
            local fn = mod[decl.member]
            -- Bound to its own module when the declaration says method, so what the plugin
            -- receives is callable on its own, the same discipline the lib block follows.
            if type(fn) == "function" and decl.call ~= "dot" then
              opts[field] = function(...) return fn(mod, ...) end
            else
              opts[field] = fn
            end
          else
            opts[field] = mod
          end
        end
      end
    end

    -- Per plugin presentation lives on the surface declaration rather than being ambient,
    -- because these two are genuinely a plugin's own choice. Three plugins want the words
    -- matcher rather than the shared fuzzy one, and three want the docked preview pane. The
    -- first attempt defaulted every plugin to fuzzy and declared the pane nowhere, so all
    -- three lost the matcher they were built around and all three came back with no pane.
    local decl = manifest.surface
    if decl then
      -- The panel's three callbacks, in whichever shape this plugin's own configure reads.
      -- `panelAs` names a field to nest them under, and its absence means the flat form.
      local panel = {}
      local anyPanel = false
      for _, key in ipairs(PANEL_CALLBACKS) do
        if services[key] ~= nil then
          panel[key] = services[key]
          anyPanel = true
        end
      end
      if anyPanel then
        if decl.panelAs then
          opts[decl.panelAs] = panel
        else
          for key, fn in pairs(panel) do opts[key] = fn end
        end
      end
    end
    if decl then
      if decl.matcher ~= nil then
        opts.matcher = decl.matcher ~= false and (services.matchers or {})[decl.matcher] or false
      else
        opts.matcher = services.matcher
      end
      -- A pane declaring plugin earns the empty state alongside the surface itself, the
      -- same one routine every docked pane paints when its highlight has nothing to
      -- describe, so the two never arrive one without the other.
      if decl.pane then
        opts.surface = services.paneElements
        opts.emptyState = services.emptyStateElements
      end
    end

    -- Data the plugin declared it cannot derive. Absent required values already blocked it
    -- during planning, so anything missing here is optional by construction.
    local supplied = (deps.data or {})[name]
    for field, value in pairs(supplied or {}) do opts[field] = value end

    return opts
  end

  -- Resolve one wiring target. Absent means the plugin root, a string names a submodule, which
  -- is where five plugins keep their picker and where the live root sends the chooser facing
  -- options. The first attempt sent everything to the parent for all five, so all five got
  -- global policy in a place that reads none of it and nothing where it reads all of it.
  local function targetOf(module, target)
    if not target then return module end
    local sub = module[target]
    if type(sub) ~= "table" then return nil, "has no submodule called " .. target end
    return sub
  end

  local function call(stage, name, module, step, opts)
    local recv, err = targetOf(module, step.target)
    if not recv then
      fail(stage, name, err)
      return
    end
    local fn = recv[step.method]
    if type(fn) ~= "function" then
      fail(stage, name, "has no " .. step.method .. " to call" .. (step.target and (" on " .. step.target) or ""))
      return
    end

    -- Arguments. Most steps take the options table, so that is the default. A step that
    -- declares `args` names what it wants instead, which is what lets a plugin whose contract
    -- is not configure(opts) join the pipeline rather than needing an exception written for it.
    --
    -- Each entry is a dotted string naming WHERE the value comes from, because the two sources
    -- are genuinely different and a bare name cannot say which. `self.` reads the plugin's own
    -- effective declarations, already merged with whatever the user overrode, which is what a
    -- binding list wants. `root.` reads a value the composition root supplies, which is what a
    -- catalog assembled from several plugins wants. Leaving the namespace implicit was the first
    -- version and two readers took it two different ways, so it is spelled out.
    local args = { opts }
    if step.args then
      args = {}
      for i, spec in ipairs(step.args) do
        local scope, path = tostring(spec):match("^(%a+)%.(.+)$")
        if scope == "self" then
          args[i] = opts[path]
        elseif scope == "root" then
          args[i] = (deps.args or {})[path]
        else
          fail(stage, name, "step " .. step.method .. " asks for " .. tostring(spec)
            .. ", which names no source, so prefix it with self or root")
          return
        end
      end
    end

    -- A step declares its own calling convention, defaulting to a method, because the receiver
    -- must be passed for a colon definition and must NOT be for a plain function. Getting this
    -- wrong does not fail cleanly, it shifts every argument by one, which is the same class of
    -- defect as a sibling capability resolving to a bare method the caller then invokes with a
    -- colon. At least one plugin's contract is a plain function rather than a method.
    local ok, e
    if step.call == "dot" then
      ok, e = pcall(fn, table.unpack(args))
    else
      ok, e = pcall(fn, recv, table.unpack(args))
    end
    if not ok then
      fail(stage, name, step.method .. " raised, " .. tostring(e))
    else
      note(stage, name .. " " .. (step.target and (step.target .. ".") or "") .. step.method)
    end
  end

  -- STAGE 1. Leaders.
  --
  -- Every chord engine receives its leader keycodes before anything is configured or started.
  -- This is first because it cannot be anywhere else. The engines only register keycodes that
  -- are already present when start runs, so a leader added later is silently never wired no
  -- matter what its configure call received afterwards.
  function self.leaders(engines, codes)
    for _, engine in ipairs(engines or {}) do
      for _, code in ipairs(codes or {}) do
        local ok, e = pcall(engine.addLeader, engine, code)
        if not ok then fail("leaders", tostring(code), tostring(e)) else note("leaders", tostring(code)) end
      end
    end
    return self
  end

  -- Whether a plugin's own declared wiring earns it a missing configure, rather than a
  -- plugin simply having forgotten one. KeyRemap's whole lifecycle is apply(catalog,
  -- activeNames), a call that is not configure(opts) and is declared as a step for exactly
  -- that reason, so KeyRemap has nothing for this stage to call and that is the correct
  -- shape rather than a hole in it. A plugin with no configure and no declared step either
  -- is a different thing entirely, one that does nothing at all no matter what runs, which
  -- is a real defect and must be reported as one rather than folded into the same silence.
  local function hasWiringSteps(name)
    local steps = plan.wiring[name]
    return steps ~= nil and #steps > 0
  end

  -- STAGE 2. Configure, in the order the plan computed.
  --
  -- The order comes from the graph, where a sibling need is an edge and a satisfied set query
  -- is also an edge to every member of that set. That second half was missing at first, and
  -- missing it wired the launcher before the plugin whose rows it displays, so every one of
  -- those rows silently vanished.
  function self.configure(modules, manifests)
    for _, name in ipairs(plan.order) do
      local module = modules[plan.identity[name]] or modules[name]
      if not module then
        fail("configure", name, "the plan wired it but no module was supplied")
      elseif type(module.configure) == "function" then
        local opts = optionsFor(name, manifests[name] or {})
        call("configure", name, module, { method = "configure" }, opts)
      elseif hasWiringSteps(name) then
        -- Nothing to call here, and that absence is the plugin's own declared shape rather
        -- than an omission. Its lifecycle runs entirely through stage 3 just below, so this
        -- is worth a line in the record and not a problem in it.
        note("configure", name .. " has no configure, its declared wiring steps are its whole lifecycle")
      else
        fail("configure", name, "has no configure and declares no wiring steps, so it does nothing at all")
      end
    end
    return self
  end

  -- STAGE 3. The declared steps beyond configure.
  --
  -- Without this stage window management wired up completely dead. Its binding call is not
  -- configure, nothing ran it, and nothing anywhere said that anything should.
  function self.steps(modules, manifests)
    for _, name in ipairs(plan.order) do
      local steps = plan.wiring[name]
      if steps then
        local module = modules[plan.identity[name]] or modules[name]
        local opts = module and optionsFor(name, manifests[name] or {})
        for _, step in ipairs(steps) do
          if module then call("steps", name, module, step, opts) end
        end
      end
    end
    return self
  end

  -- STAGE 4. Predicates, installed before any key that depends on one is bound.
  --
  -- The ordering here is the whole reason this is a named stage. An unknown predicate name is
  -- treated as ALWAYS ACTIVE, so a table installed late, or not at all, does not fail. It
  -- leaves every list's navigation keys live at all times and never suppresses the base layer,
  -- which is a silent wrong rather than a visible one. The first attempt computed this table
  -- and installed it nowhere while binding those keys in the same run.
  --
  -- `own` is the root's own predicates, which exist because a few gates are not any plugin's
  -- business. They merge with the generated ones rather than replacing them, and a name
  -- claimed twice is reported instead of one quietly winning.
  function self.predicates(engine, own)
    local table_ = {}
    for name, contextName in pairs(plan.predicates) do
      table_[name] = function() return self.isShowing(contextName) end
    end
    for name, fn in pairs(own or {}) do
      if table_[name] then
        fail("predicates", name, "is claimed by both a surface and the root")
      end
      table_[name] = fn
    end
    local ok, e = pcall(engine.configure, engine, { predicates = table_ })
    if not ok then fail("predicates", "engine", tostring(e)) end
    local n = 0
    for _ in pairs(table_) do n = n + 1 end
    note("predicates", n .. " installed")
    self._predicates = table_
    return self
  end

  -- Whether a named context's list is currently open. Injected rather than computed, because
  -- the answer lives on the plugin and the calling convention is not uniform. Several plugins
  -- define this as a colon method while the first attempt called every one of them with a dot,
  -- which is the resolves and then fails case rather than a clean absence.
  function self.isShowing(contextName)
    local ask = deps.isShowing
    if not ask then return false end
    local ok, answer = pcall(ask, contextName)
    return ok and answer or false
  end

  -- STAGE 5 and 6. Register every tool, then activate, then bind the open keys.
  --
  -- These three are one stage because their order is not negotiable and splitting them invites
  -- a caller to interleave something. The shortcut list only yields entries for tools both
  -- registered and active, so a tool registered after that list was read silently never gets
  -- its key. The descriptor must be complete on the way in, since the registry refuses an
  -- incomplete one outright and the first attempt built every descriptor without the version
  -- field, so every single registration was refused and nothing got a row, a scope or a key.
  function self.register(registry, describe, bind)
    for _, name in ipairs(plan.order) do
      local descriptor = describe(name, plan)
      if descriptor then
        -- registry.register's whole contract is to refuse rather than raise, an incomplete
        -- descriptor, a mismatched apiVersion, a surface handed in already built, every one
        -- of those comes back as a logged warning and a plain `return false`, never an
        -- error. pcall alone cannot see any of that, since nothing raised, so `ok` is true
        -- on a refusal exactly as it is on a real registration and reading only `ok` is the
        -- same blindness the first attempt shipped, where the entire launcher lost every
        -- one of twenty seven rows and nothing anywhere read the false that came back. What
        -- pcall hands back as its second value here is register's own true or false, and
        -- only when `ok` is true, so it has to be read on its own rather than folded into
        -- the raised case, and it is the only thing standing between a refusal and silence.
        local ok, registered = pcall(registry.register, descriptor)
        if not ok then
          fail("register", name, "register raised, " .. tostring(registered))
        elseif not registered then
          fail("register", name, "was refused by the registry, see its own warning line for why")
        else
          note("register", plan.identity[name] or name)
        end
      end
    end

    local ok, e = pcall(registry.activate)
    if not ok then fail("register", "activate", tostring(e)) end

    for _, entry in ipairs(registry.shortcuts() or {}) do
      local bound, be = pcall(bind, entry)
      if not bound then
        fail("register", tostring(entry.name or "a shortcut"), tostring(be))
      else
        note("register", "bound the open key for " .. tostring(entry.name))
      end
    end
    return self
  end

  -- STAGE 7. The in list navigation keys, for every surface the plan built.
  --
  -- Separate from the open keys above and must stay separate. One binds the key that OPENS a
  -- tool, the other binds the keys that are live while it is open. Conflating them loses the
  -- distinction that a few tools still bind their own open key directly.
  function self.contexts(engine, bindOne)
    for contextName, block in pairs(plan.contexts) do
      for _, binding in ipairs(block.bindings or {}) do
        -- chord equals false means listed in the hint panel but deliberately not bound. The
        -- first attempt dropped this rule along with the per binding needs gate and the repeat
        -- flag, which is three behaviours lost in one loop.
        if binding.chord == false then
          note("contexts", contextName .. " lists " .. tostring(binding.key) .. " without binding it")
        else
          local ok, e = pcall(bindOne, engine, contextName, block, binding)
          if not ok then fail("contexts", contextName .. " " .. tostring(binding.key), tostring(e)) end
        end
      end
      note("contexts", contextName .. ", " .. #(block.bindings or {}) .. " binding(s)")
    end
    return self
  end

  -- STAGE 8. Start, engines last, and the shared event tap last of all, because it must see a
  -- complete key set. Starting it earlier means it runs against whatever had registered so far.
  function self.start(engines, sharedTap)
    for _, engine in ipairs(engines or {}) do
      local ok, e = pcall(engine.start, engine)
      if not ok then fail("start", "an engine", tostring(e)) else note("start", "an engine") end
    end
    if sharedTap then
      local ok, e = pcall(sharedTap.start, sharedTap)
      if not ok then fail("start", "the shared tap", tostring(e)) else note("start", "the shared tap") end
    end
    return self
  end

  -- What happened, for the console. Read after every load, because a config that died before
  -- this printed is the only way to tell a broken load from a quiet one.
  function self.report()
    local lines = {}
    local order = { "leaders", "configure", "steps", "predicates", "register", "contexts", "start" }
    for _, stage in ipairs(order) do
      local entries = self.record.stages[stage]
      if entries then lines[#lines + 1] = stage .. ", " .. #entries .. " done" end
    end
    for _, p in ipairs(self.record.problems) do
      lines[#lines + 1] = "PROBLEM in " .. p.stage .. " at " .. p.where .. ", " .. p.why
    end
    if #self.record.problems == 0 then lines[#lines + 1] = "no problems" end
    return table.concat(lines, "\n")
  end

  return self
end

return obj
