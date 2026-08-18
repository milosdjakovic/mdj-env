-- Dispatch. Deciding which surface is showing right now and routing one navigation key or
-- one verb to it, generically, for every action the plan's contexts declare.
--
-- This file replaces the twenty six entry contextActions table the live root hand wrote, plus
-- activeChooser and routeNav beside it. The live table named every plugin's own surface by
-- hand, which is exactly the roster this whole design exists to stop hand keeping. A generic
-- version has to answer the same three questions the hand written one answered without ever
-- naming who it is answering them for.
--
-- Which surface is live right now. A total order over every surface that can possibly be
-- open, so if two ever answered showing at once the order is what decides which one wins, and
-- nothing anywhere in this tree proves that can never happen. The order is not this module's
-- business, so it always arrives as a parameter and is never sorted or rebuilt here.
--
-- What one key or one verb does on whichever surface is live. Almost every action is the same
-- named method called on whatever answered active, so an action no surface answers becomes a
-- no op everywhere rather than an error anywhere, which is what lets one action name serve
-- twelve different lists with nothing here ever asking which one it is.
--
-- What lib wire.lua's stage seven actually binds a key to. That stage owns the fixed order,
-- the chord equals false listing rule, and the needs gate already applied at plan time, so
-- this module's own binder only ever does the one thing that is genuinely its business, taking
-- the resolved handler for a binding's action and giving it to the chord engine along with the
-- when and the priority its own context already carries.
--
-- obj.actions and obj.bindOne share one fact that is worth stating once rather than twice.
-- obj.actions is the only place in this module that ever asks what an action name means, and
-- it answers that question exactly once per name while it builds the dispatch table, then
-- stamps the answer straight onto every binding that names it, as binding.fn. obj.bindOne
-- never asks the question again. It reads binding.fn, so a second consumer of the same plan
-- can never see a different answer than the first one got, and this module never has to keep
-- a table of action names anywhere beyond the one pass that builds it.

local obj = {}

-- hs.logger is the one hs call this module makes, and only to name a plan that asks for
-- something a binding needs but that no surface, no method map and no exception was ever
-- built for, so a plain Lua load with no Hammerspoon running still works for a unit test. A
-- silent stub in that case keeps the module loadable rather than failing on the first line.
local log
if hs and hs.logger then
  log = hs.logger.new("Nav", "info")
else
  log = { e = function() end, w = function() end, i = function() end }
end

-- The first surface in the given order that answers showing right now, or none at all when
-- nothing is open. The order is a parameter rather than a computed thing because deciding who
-- comes first when two lists are somehow both open is a policy question this module has no
-- way to answer honestly, so it is asked of whoever built the list instead.
function obj.activeSurface(surfaces)
  for _, surface in ipairs(surfaces or {}) do
    if type(surface.isShowing) == "function" and surface.isShowing() then
      return surface
    end
  end
  return nil
end

-- A zero argument closure that hides the shared shortcut panel, finds whichever surface from
-- the given order is showing right now, and calls the named method on it if that surface
-- happens to answer it. A surface that does not answer the method is left alone rather than
-- erroring, which is what makes one routed action safe to bind in every context regardless of
-- whether the surface currently active happens to be the one the key was meant for.
function obj.routeNav(method, surfaces, hideShortcuts)
  return function()
    if hideShortcuts then hideShortcuts() end
    local surface = obj.activeSurface(surfaces)
    if surface and type(surface[method]) == "function" then
      surface[method]()
    end
  end
end

-- The generic replacement for the whole hand written dispatch table. Walks every binding of
-- every context the plan built, once per distinct action name, and for each one builds a
-- routed handler using deps.methodFor's own name for it when one is given and the action name
-- itself otherwise. deps.exceptions then overrides any of those by name with a closure the
-- caller already built, which is how the one action that genuinely cannot be expressed as a
-- routed method, opening the action panel, joins the same table without this module ever
-- learning what the action panel is.
--
-- Once every name has an answer, this walks the same bindings a second time and stamps that
-- answer onto binding.fn, so obj.bindOne, and anything else handed the same plan afterward,
-- reads the resolved handler straight off the binding rather than asking this table again by
-- name. The second pass runs after the exceptions are folded in on purpose, so a binding whose
-- action is an exception ends up carrying the exception's own closure rather than the
-- placeholder this module would otherwise have built for it first.
function obj.actions(plan, deps)
  deps = deps or {}
  local methodFor = deps.methodFor or {}
  local exceptions = deps.exceptions or {}
  local surfaces = deps.surfaces
  local hideShortcuts = deps.hideShortcuts

  local built = {}
  for _, block in pairs(plan.contexts or {}) do
    for _, binding in ipairs(block.bindings or {}) do
      local name = binding.action
      if name and built[name] == nil then
        local method = methodFor[name] or name
        built[name] = obj.routeNav(method, surfaces, hideShortcuts)
      end
    end
  end

  for name, fn in pairs(exceptions) do
    built[name] = fn
  end

  for _, block in pairs(plan.contexts or {}) do
    for _, binding in ipairs(block.bindings or {}) do
      binding.fn = built[binding.action]
    end
  end

  return built
end

-- Returns the function lib wire.lua's stage seven calls once per bound binding, taking the
-- chord engine, the context name, the context's own block and the binding itself. The needs
-- gate and the chord equals false listing rule are both already settled before this ever runs,
-- one at plan time by dropping the binding outright and one by that stage itself skipping the
-- call entirely, so repeating either check here would only give the same rule a second place
-- to drift out of step with the first. The one thing this closure owns is turning a binding
-- already carrying its resolved handler into a real bind call, reading the repeat flag by
-- action name from the table the caller injected, and reading when and priority off the
-- context's own block rather than the binding, since those two describe the whole context and
-- not any one key in it.
function obj.bindOne(repeats)
  repeats = repeats or {}
  return function(engine, contextName, block, binding)
    local fn = binding.fn
    if type(fn) ~= "function" then
      log.w("context '" .. tostring(contextName) .. "' binds '" .. tostring(binding.key)
        .. "' to action '" .. tostring(binding.action)
        .. "', which no method map and no exception ever answered")
      return
    end
    engine:bind(binding.key, fn, binding.mods, {
      when = block.when,
      priority = block.priority,
      repeats = repeats[binding.action],
    })
  end
end

return obj
