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
--
-- deps.onAction, optional, a function of the action name, is told before every handler in the
-- table runs, routed and exception alike, so a caller can do one thing for every list key that
-- acts without each surface or exception remembering to. The root closes the action bar's key
-- panel there. It is folded in after the exceptions, so no handler escapes it.
function obj.actions(plan, deps)
  deps = deps or {}
  local methodFor = deps.methodFor or {}
  local exceptions = deps.exceptions or {}
  local surfaces = deps.surfaces
  local hideShortcuts = deps.hideShortcuts
  local onAction = deps.onAction

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

  if type(onAction) == "function" then
    for name, fn in pairs(built) do
      built[name] = function(...)
        onAction(name)
        return fn(...)
      end
    end
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

-- The four modifiers a field key compares, the same four every leader compares.
local FIELD_MODS = { "shift", "ctrl", "alt", "cmd" }

--- obj.fieldKeys(contexts, deps) -> watch, keys
--- The list keys the open list's own field answers, phase B of the list keys addendum to the keymap
--- plan, every binding of every context that opens with no held leader, leader false for modifiers
--- alone or a leader the person named from modifiers. None is bound on a leader or as a hotkey.
--- The default chooser's field asks watch(event) for each key down while it is up, and watch runs
--- the binding whose chord matches exactly, whose context's predicate holds, the best priority
--- first, and answers true, or answers false so the field goes on with the key itself.
---   deps.keycodes         the keycode table, a key name to its code.
---   deps.modifierLeaders  a leader the person named to its set of modifiers.
---   deps.predicates       a predicate name to a function, asked at the press. An unknown or
---                         missing name is not live, since a field key that acts in every list is
---                         worse than one that acts in none, and it is warned about once, the way
---                         the leaders warn about an unknown predicate.
---   deps.repeats          an action name to true for an action worth repeating while held, the
---                         table the leaders read.
---   deps.isRepeat         a function from the event to whether it is the keyboard's autorepeat.
---                         A repeat of a binding whose action does not repeat is swallowed, so a
---                         held delete deletes once and a held close leaks nothing to the app
---                         beneath.
--- Once a binding matched, the key is the field's whatever the binding does, so one that raises is
--- reported and the key is still claimed rather than typed.
--- keys is the same set as plain records, context, key, mods, when and priority, for anything that
--- lists what the field answers. binding.fn is read at the press, so this may be built before the
--- dispatch table stamps it.
function obj.fieldKeys(contexts, deps)
  deps = deps or {}
  local keycodes = deps.keycodes or {}
  local named = deps.modifierLeaders or {}
  local byCode, keys = {}, {}
  local names = {}
  for name in pairs(contexts or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local block = contexts[name]
    for _, b in ipairs(block.bindings or {}) do
      local field = b.chord ~= false and (b.leader == false or (type(b.leader) == "string" and named[b.leader] ~= nil))
      local code = field and keycodes[b.key] or nil
      if field and type(code) == "number" then
        local need = {}
        for _, m in ipairs(b.leader and named[b.leader] or {}) do need[m] = true end
        for _, m in ipairs(b.mods or {}) do need[m] = true end
        byCode[code] = byCode[code] or {}
        table.insert(byCode[code], { binding = b, block = block, need = need, context = name })
        local list = {}
        for _, m in ipairs(FIELD_MODS) do if need[m] then list[#list + 1] = m end end
        table.sort(list)
        keys[#keys + 1] = { context = name, key = b.key, mods = list, when = block.when, priority = block.priority }
      elseif field then
        log.w("context '" .. tostring(name) .. "' lists '" .. tostring(b.key) .. "' for its field, which the keyboard has no code for")
      end
    end
  end

  local warned = {}
  local function live(name, context)
    local pred = name and (deps.predicates or {})[name]
    if type(pred) ~= "function" then
      local what = tostring(name or "no predicate")
      if not warned[what] then
        warned[what] = true
        log.w("the list " .. tostring(context) .. " names " .. what .. " for its field keys, which no predicate answers, so they never act")
      end
      return false
    end
    return pred() == true
  end
  local repeats = deps.repeats or {}

  local function watch(ev)
    local candidates = byCode[ev:getKeyCode()]
    if not candidates then return false end
    local flags = ev:getFlags() or {}
    local best, bestP = nil, -math.huge
    for _, c in ipairs(candidates) do
      local exact = true
      for _, m in ipairs(FIELD_MODS) do
        if (flags[m] and true or false) ~= (c.need[m] or false) then exact = false break end
      end
      local p = c.block.priority or 0
      if exact and p > bestP and type(c.binding.fn) == "function" and live(c.block.when, c.context) then
        best, bestP = c, p
      end
    end
    if not best then return false end
    if deps.isRepeat and not repeats[best.binding.action] then
      local ok, isRepeat = pcall(deps.isRepeat, ev)
      if ok and isRepeat then return true end
    end
    local ok, err = pcall(best.binding.fn)
    if not ok then
      log.e("the field key " .. tostring(best.binding.key) .. " of the list " .. tostring(best.context)
        .. " raised, so the key is claimed and did nothing, " .. tostring(err))
    end
    return true
  end

  return watch, keys
end

return obj
