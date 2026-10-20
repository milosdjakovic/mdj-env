--- === Leader ===
---
--- The one leader adapter. A leader is a binding table, one resolver that picks a handler for
--- the modifiers held, a policy saying how this leader behaves, and a trigger saying what
--- physically means this leader. The composition root builds one instance per leader in use,
--- each with its trigger and its policy, and loops over them naming none.
---
--- It replaced lib/hyperkey.lua and lib/windowleader.lua in phase 3 of the keymap plan. The two
--- were near copies that differed in policy, and every difference is now a field of the policy
--- below rather than a second file. Exactly two behaviours changed in the merge, both agreed in
--- decisions/olm-keymap.md. A key whose only matching bindings are all gated off is swallowed as
--- a bound no op on every leader, where Hyper used to skip it and with passthrough on leaked it to
--- the app in front, and an unknown predicate name warns once on every leader, where Hyper passed
--- it in silence. A key with no binding at all still passes through as it always did. Outside a
--- list that swallows only a key every binding of which is a list key, Hyper and H, Q and Y here.
--- Inside an open list it reaches further. The modal rule drops every base binding, and a key whose
--- base binding is dropped that way is still swallowed when some other list binds it, since that
--- list's binding matches and is gated off, so with the launcher open Hyper and A, D, F, L, M, R,
--- S, X, H, Q and Y are swallowed while B, C and E, which no other list binds, pass through.
---
--- THE TRIGGER IS A STRATEGY, and the seam is the four functions a trigger answers, start, bound,
--- isActive and owns. This file never names a concrete trigger. lib/leader/triggers/held.lua is
--- one physical key held through the shared ChordKey engine, and lib/leader/triggers/modifier.lua
--- is a set of real modifiers claimed through hs.hotkey. The root names which one each leader
--- gets, so a third kind is a file there plus a line in the root.
---
--- THE POLICY is data, shipped by the root per catalog name beside its leader catalog and
--- overridable through cfg.policy the same way. Every choice with two answers is a boolean, so
--- there is no closed set of words to spell. Whether a hold reveals a sheet is a boolean and how
--- that sheet is laid out is a table beside it, so a new leader gets a sheet by policy alone. See
--- FIELDS and SHEET_FIELDS below.
---
--- Only the core calls bind. lib/binder.lua binds every global row of the keymap, and the root
--- binds every list key through its contexts onto the one leader whose policy turns contexts on.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Leader"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Leader", "info")

-- The only sub modifiers a binding may require. fn is deliberately excluded, since macOS stamps
-- fn onto arrow and navigation keys, so a raw exact check would never match a Shift and arrow
-- binding. Every comparison below reads these four only.
local REAL_MODS = { "shift", "ctrl", "alt", "cmd" }

-- What a key that is bound but gated off, or a leader gone quiet, resolves to. A bound handler
-- that does nothing rather than nil, because the shared engine treats an unresolved key as unbound,
-- and with passthrough on it would synthesize the pressed key downstream. Bound and inert is the
-- only answer that both runs nothing and swallows.
local function noop() end
obj.noop = noop

--------------------------------------------------------------------------------
-- The policy
--------------------------------------------------------------------------------

-- Every field a leader's policy may carry, with the type it takes. Absent is false or nothing.
--
--   tapTogglesCapsLock  a quick tap of the leader alone toggles real Caps Lock, which is what Caps
--                       Lock remapped to HYPER loses otherwise.
--   drivenRepeat        a repeating binding repeats on the engine's own schedule and its run is
--                       handed how deep into the hold it is, rather than riding the OS autorepeat.
--   contexts            list keys bind here, with priority between them and the modal rule, so
--                       while a list's context is live every base binding is dropped and the list
--                       owns the leader. Exactly one leader in use turns it on.
--   quietOverLists      while any Olm list is open every bound key is inert though still
--                       swallowed, since a window action fired over a list moves whatever sits
--                       underneath it.
--   sheet               a hold reveals this leader's cheat sheet, drawn by the one sheet host. Absent
--                       means a hold reveals nothing.
--   sheetLayout         how that sheet is laid out, a table of the SHEET_FIELDS below. Absent means
--                       the defaults, and it means nothing on a leader with no sheet.
--   holdDelay           seconds a hold waits before it reveals, else the engine's own.
local FIELDS = {
  tapTogglesCapsLock = "boolean",
  drivenRepeat = "boolean",
  contexts = "boolean",
  quietOverLists = "boolean",
  sheet = "boolean",
  sheetLayout = "table",
  holdDelay = "number",
}

-- What a sheet layout may carry, with the type each takes. Every field is absent unless stated,
-- and an absent size is the shared renderer's own.
--
--   title       the heading over rows that name no group, what the leader does rather than what it
--               is called, since the leader's own name says nothing to somebody reading a list.
--   columns     how many columns the rows fill, row major, a whole number of one or more.
--   colWidth    the width of one column.
--   iconSize    the side of an application icon, the icon grid of a section that asks for icons.
--   gap         the space around a badge or an icon.
--   groupGap    the vertical space between sections.
--   badgeWidth  a fixed badge width, for a leader whose chords carry modifiers, else the badge is
--               square.
local SHEET_FIELDS = {
  title = "string",
  columns = "number",
  colWidth = "number",
  iconSize = "number",
  gap = "number",
  groupGap = "number",
  badgeWidth = "number",
}

-- The heading of a leader's sheet when its layout states none. The sizes come from the renderer,
-- handed to sheetLayout, so they cannot drift from it.
local SHEET_TITLE = "SHORTCUTS"

local function isCount(v)
  return type(v) == "number" and v == v and v >= 0 and v ~= math.huge
end

--- obj.checkPolicy(name, policy) -> policy, problems
--- A policy as a leader reads it, every field of the wrong type or not a field at all named in
--- one problem line and left out, so a typo is said once at load rather than read as absent.
--- A problem is a table with where and why, the shape the wiring report takes.
function obj.checkPolicy(name, policy)
  local clean, problems = {}, {}
  if policy ~= nil and type(policy) ~= "table" then
    problems[1] = { where = tostring(name), why = "the leader policy is a " .. type(policy)
      .. " rather than a table, so the leader keeps every default" }
    return clean, problems
  end
  local fields = {}
  for field in pairs(policy or {}) do fields[#fields + 1] = field end
  table.sort(fields, function(a, b) return tostring(a) < tostring(b) end)
  for _, field in ipairs(fields) do
    local value, want = policy[field], FIELDS[field]
    if not want then
      problems[#problems + 1] = { where = tostring(name), why = "the leader policy field '"
        .. tostring(field) .. "' is not one a leader reads, so it is ignored" }
    elseif value ~= false and type(value) ~= want then
      problems[#problems + 1] = { where = tostring(name), why = "the leader policy field '"
        .. field .. "' is a " .. type(value) .. " where a leader takes a " .. want
        .. ", so it is left at its default" }
    elseif field == "sheetLayout" and value ~= false then
      local layout, layoutProblems = obj._checkSheetLayout(name, value)
      for _, problem in ipairs(layoutProblems) do problems[#problems + 1] = problem end
      clean.sheetLayout = layout
    elseif value ~= false then
      clean[field] = value
    end
  end
  -- A person turning a sheet off with sheet = false leaves the shipped layout merged beside it,
  -- which is a legitimate config and drops the layout in silence. Only a layout stated with no
  -- sheet stated at all is a problem.
  if clean.sheetLayout and policy and policy.sheet == false then
    clean.sheetLayout = nil
  elseif clean.sheetLayout and not clean.sheet then
    problems[#problems + 1] = { where = tostring(name), why = "the leader policy states a sheet layout and no sheet, so "
      .. "the layout is ignored and a hold reveals nothing" }
    clean.sheetLayout = nil
  end
  return clean, problems
end

-- A sheet layout as the sheet reads it, every field of the wrong type, out of range or not a
-- field at all named in one problem line and left out.
function obj._checkSheetLayout(name, layout)
  local clean, problems = {}, {}
  local fields = {}
  for field in pairs(layout) do fields[#fields + 1] = field end
  table.sort(fields, function(a, b) return tostring(a) < tostring(b) end)
  for _, field in ipairs(fields) do
    local value, want = layout[field], SHEET_FIELDS[field]
    if not want then
      problems[#problems + 1] = { where = tostring(name), why = "the sheet layout field '" .. tostring(field)
        .. "' is not one a sheet reads, so it is ignored" }
    elseif type(value) ~= want then
      problems[#problems + 1] = { where = tostring(name), why = "the sheet layout field '" .. field .. "' is a "
        .. type(value) .. " where a sheet takes a " .. want .. ", so it is left at its default" }
    elseif want == "number" and not isCount(value) then
      problems[#problems + 1] = { where = tostring(name), why = "the sheet layout field '" .. field
        .. "' is not a size of zero or more, so it is left at its default" }
    elseif field == "columns" and (value < 1 or value ~= math.floor(value)) then
      problems[#problems + 1] = { where = tostring(name), why = "the sheet layout field 'columns' is not a whole "
        .. "number of one or more, so it is left at its default" }
    else
      clean[field] = value
    end
  end
  return clean, problems
end

--- obj.sheetLayout(policy, renderer) -> layout
--- The layout a leader's sheet is drawn with, the policy's own fields over the defaults. The
--- policy is one already through checkPolicy, so every field is the type it takes. renderer is the
--- shared renderer's own defaults table, the source of columns, colWidth and gap where the policy
--- states none, and a sheet's heading defaults to a plain one.
function obj.sheetLayout(policy, renderer)
  local out = { title = SHEET_TITLE }
  for _, field in ipairs({ "columns", "colWidth", "gap" }) do
    out[field] = (renderer or {})[field]
  end
  for field, value in pairs((policy or {}).sheetLayout or {}) do out[field] = value end
  return out
end

--------------------------------------------------------------------------------
-- An instance
--------------------------------------------------------------------------------

--- obj.new(opts) -> leader
---   name        the leader's name as a keymap row spells it, hyper or meta, nil for the unnamed
---               plain combo leader
---   trigger     the trigger strategy, required
---   policy      the leader's policy, already through checkPolicy
---   sheet       the module a hold reveals, show(keyCode) and hide(), nil for none. The root hands the
---               one sheet host to every leader whose policy states a sheet.
---   keyCode     the keycode the sheet is shown for, the held key's own
---   listOpen    function answering true while any Olm list is open. A hold never reveals over an
---               open list, on every leader, and a leader whose policy goes quiet over lists is
---               inert while it answers true.
---   predicates  name to function answering a bool, what a binding's gate is resolved against
---   holdDelay, tapThreshold  the engine's timing, a policy holdDelay winning over the first
function obj.new(opts)
  opts = opts or {}
  local self = setmetatable({}, obj)
  -- Kept off the field name, since the module's own metadata is read through the metatable and a
  -- plain leader with no name would otherwise answer the module's.
  self._name = opts.name
  self._trigger = opts.trigger
  self._policy = opts.policy or {}
  self._sheet = opts.sheet
  self._keyCode = opts.keyCode
  self._listOpen = opts.listOpen
  self._predicates = opts.predicates
  self._holdDelay = self._policy.holdDelay or opts.holdDelay
  self._tapThreshold = opts.tapThreshold
  self._tap = self._policy.tapTogglesCapsLock and function() hs.hid.capslock.toggle() end or nil
  -- keycode to the bindings on it, in the order they arrived, and every binding once more in that
  -- order, which a trigger that claims combos walks so it claims them in a fixed order.
  self._bindings = {}
  self._sequence = {}
  -- The predicate names list keys carry, which drive the modal rule. Only filled on a leader whose
  -- policy turns contexts on.
  self._contextWhens = {}
  -- Unknown predicate names already warned about, per leader, so each is said once per leader.
  self._unknownSeen = {}
  self._revealed = false
  return self
end

--- Leader:configure(opts)
--- Method
--- What arrives after the leader is built, today only the predicate table the wiring's stage four
--- installs into every leader.
function obj:configure(opts)
  opts = opts or {}
  if opts.predicates ~= nil then self._predicates = opts.predicates end
  return self
end

--- Leader:leaderName() -> string or nil
--- Method
--- The name a keymap row spells this leader with, nil for the unnamed plain combo leader.
function obj:leaderName()
  return self._name
end

--- Leader:policy() -> table
--- Method
--- The policy this leader was built with. The root asks which leader turns contexts on.
function obj:policy()
  return self._policy
end

--- Leader:bind(key, fn, mods, opts)
--- Method
--- Register a handler for key under this leader. mods is an optional list of required modifier
--- names, omitted for a catch all that fires when no exact binding matches. opts carries
---   when          a list key's predicate. On a leader with contexts it makes the binding a
---                 context binding, so while the predicate holds the leader is modal. On any other
---                 leader it gates the binding like a gate.
---   gate          a global row's predicate, eligibility alone, never modal on any leader.
---   priority      higher wins between eligible bindings in one tier, on a leader with contexts.
---   repeats       the handler keeps firing while its key stays held.
---   afterRelease  the handler waits until this leader is released before it runs, for an action
---                 that posts a keystroke the held leader would otherwise stand in front of.
function obj:bind(key, fn, mods, opts)
  opts = opts or {}
  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if not code then
    log.w("unknown key '" .. tostring(key) .. "'")
    return self
  end
  local binding = {
    key = key, code = code, mods = mods, fn = fn,
    when = opts.when, gate = opts.gate, priority = opts.priority,
    repeats = opts.repeats, afterRelease = opts.afterRelease,
  }
  self._bindings[code] = self._bindings[code] or {}
  table.insert(self._bindings[code], binding)
  self._sequence[#self._sequence + 1] = binding
  if opts.when and self._policy.contexts then
    self._contextWhens[opts.when] = true
  end
  if self._trigger then self._trigger.bound(self, binding) end
  return self
end

-- Whether one predicate name allows a binding right now, asked live at each press. No name always
-- passes. An unknown name is treated as active and warned about once per leader, so a typo fails
-- visibly, the key stays live, rather than a binding silently dying.
local function predicatePasses(self, name)
  if not name then return true end
  local pred = self._predicates and self._predicates[name]
  if pred == nil then
    if not self._unknownSeen[name] then
      self._unknownSeen[name] = true
      log.w("unknown predicate '" .. tostring(name) .. "' on the " .. tostring(self._name or "plain") .. " leader")
    end
    return true
  end
  return pred() and true or false
end

function obj:_passes(binding)
  return predicatePasses(self, binding.when) and predicatePasses(self, binding.gate)
end

--- Leader:_modal() -> bool
--- Method
--- Whether any context is live right now, which only a leader with contexts asks. While one is,
--- the leader belongs to that context, so bindings with no when are dropped and only context
--- bindings act. That is what makes a context modal rather than an overlay, so while the clipboard
--- is open Hyper and A does nothing instead of toggling an app.
function obj:_modal()
  for name in pairs(self._contextWhens) do
    local pred = self._predicates and self._predicates[name]
    if pred and pred() then return true end
  end
  return false
end

local function heldSet(flags)
  local present = {}
  for _, m in ipairs(REAL_MODS) do
    if flags[m] then present[m] = true end
  end
  return present
end

local function modsMatch(binding, present)
  local need = {}
  for _, m in ipairs(binding.mods) do need[m] = true end
  for _, m in ipairs(REAL_MODS) do
    if (present[m] or false) ~= (need[m] or false) then return false end
  end
  return true
end

-- The handler a chosen binding answers, wrapped when the binding waits for this leader's release.
function obj:_handlerOf(binding)
  if not binding.afterRelease then return binding.fn end
  local fn = binding.fn
  return function(...)
    local args = table.pack(...)
    self:afterRelease(function() fn(table.unpack(args, 1, args.n)) end)
  end
end

--- Leader:afterRelease(fn)
--- Method
--- Runs fn now, or once this leader is released when it is held right now. The waiter is held in
--- a field, since a Hammerspoon timer is userdata whose finalizer stops it, and one nothing refers
--- to can be collected before it fires, which would lose the action with nothing said. A second
--- wait while the leader is still down replaces the first, since two of the same action arriving
--- together on release is not a usable outcome. This was capture's own wait on Hyper until phase 3.
function obj:afterRelease(fn)
  if not self:isActive() then return fn() end
  if self._releaseWait then self._releaseWait:stop() end
  self._releaseWait = hs.timer.waitUntil(function() return not self:isActive() end, fn, 0.02)
end

--- obj.afterAllReleased(leaders, fn)
--- Runs fn now when no leader in the list is held, or once every one of them is released, for a
--- launcher row whose action waits for release, since nothing says which leader the person is
--- holding. One waiter, held on the module for the same reason as afterRelease, and a second wait
--- replaces the first.
function obj.afterAllReleased(leaders, fn)
  local function anyHeld()
    for _, leader in ipairs(leaders or {}) do
      if leader:isActive() then return true end
    end
    return false
  end
  if not anyHeld() then return fn() end
  if obj._allReleaseWait then obj._allReleaseWait:stop() end
  obj._allReleaseWait = hs.timer.waitUntil(function() return not anyHeld() end, fn, 0.02)
end

--- Leader:_resolve(list, flags) -> handler, repeats
--- Method
--- Pick the handler for the modifiers held. An exact match on the real modifiers beats a catch
--- all, fn ignored. The chosen binding's repeats flag travels with it, the shape the shared
--- engine's onKey contract asks for.
---
--- Within a tier the two policies differ, and each keeps exactly what its old adapter did. On a
--- leader with contexts every eligible binding competes and the best priority wins, the first
--- bound among equals, and a binding that is not eligible drops out of its tier, so a list key on
--- Shift and J gated off leaves the plain J binding to answer. While a context is live a binding
--- with no when is not eligible at all. On any other leader the first matching exact binding
--- answers and a gated one is swallowed there rather than falling through, and among catch alls
--- the last one bound answers.
---
--- Either way, a key whose matching bindings are all gated off is swallowed as a no op rather than
--- left unbound. A binding dropped by the modal rule is not gated off, it is outranked, so a key
--- whose only binding is a base one still passes through while a list is open, as before, but a key
--- that also carries another list's binding, gated off while that list is closed, is swallowed.
function obj:_resolve(list, flags)
  if not list then return nil end
  local present = heldSet(flags or {})
  local gatedOff = false

  if self._policy.contexts then
    local modal = self:_modal()
    local bestExact, bestExactP = nil, -math.huge
    local bestCatch, bestCatchP = nil, -math.huge
    for _, b in ipairs(list) do
      if not (modal and not b.when) then
        local matches = b.mods == nil or modsMatch(b, present)
        if matches then
          if not self:_passes(b) then
            gatedOff = true
          else
            local p = b.priority or 0
            if b.mods then
              if p > bestExactP then bestExact, bestExactP = b, p end
            elseif p > bestCatchP then
              bestCatch, bestCatchP = b, p
            end
          end
        end
      end
    end
    local chosen = bestExact or bestCatch
    if chosen then return self:_handlerOf(chosen), chosen.repeats end
  else
    local catch, catchGated = nil, false
    for _, b in ipairs(list) do
      if b.mods then
        if modsMatch(b, present) then
          if not self:_passes(b) then return noop, false end
          return self:_handlerOf(b), b.repeats
        end
      elseif self:_passes(b) then
        catch, catchGated = b, false
      else
        catch, catchGated = nil, true
      end
    end
    if catch then return self:_handlerOf(catch), catch.repeats end
    gatedOff = catchGated
  end

  if gatedOff then return noop, false end
  return nil
end

-- What a trigger asks of a pressed key, the quiet rule first and then the resolver.
function obj:_onKey(code, flags)
  if self._policy.quietOverLists and self._listOpen and self._listOpen() then return noop end
  return self:_resolve(self._bindings[code], flags)
end

-- The engine's word for the repeat mode, nil leaving the engine's own default.
function obj:_repeatMode()
  if self._policy.drivenRepeat then return "driven" end
  return nil
end

--------------------------------------------------------------------------------
-- The hold reveal
--------------------------------------------------------------------------------

function obj:_reveals()
  return self._sheet ~= nil
end

-- Shows this leader's sheet once a hold passes the delay, never over an open list on any leader,
-- since a sheet drawn over a list covers what a person is reading and no list key fires from it.
-- Both old adapters already held back there, Hyper in the root's own reveal and the window leader
-- through its quiet gate.
function obj:_reveal(code)
  if self._listOpen and self._listOpen() then return end
  local sheet = self._sheet
  if not sheet then return end
  sheet:show(code or self._keyCode)
  self._revealed = true
end

--- Leader:conceal()
--- Method
--- Takes this leader's sheet down if this leader put it up, the release of a hold, a key pressed
--- under it, or an action that hides whatever overlay is showing.
function obj:conceal()
  if not self._revealed then return self end
  self._revealed = false
  if self._sheet then self._sheet:hide() end
  return self
end

--------------------------------------------------------------------------------
-- The trigger's contract, delegated
--------------------------------------------------------------------------------

--- Leader:isActive() -> bool
--- Method
--- True while this leader is physically asserted, the key held or every base modifier held.
--- A synthetic keystroke waits on it, since the shared tap swallows every key while a held leader
--- is down.
function obj:isActive()
  return self._trigger ~= nil and self._trigger.isActive() == true
end

--- Leader:owns(ev) -> bool
--- Method
--- Whether a key down event belongs to this leader right now, so a consumer that claims every key
--- for itself, the default chooser's field among them, can let this one through to the dispatch
--- downstream of it. The consumer is handed a predicate over this and never names the leader.
function obj:owns(ev)
  return self._trigger ~= nil and self._trigger.owns(ev) and true or false
end

--- Leader:start()
--- Method
--- Begins the trigger, registering the key into the shared engine or claiming every combo. A
--- binding added after this still works.
function obj:start()
  if not self._trigger then
    log.w("the " .. tostring(self._name or "plain") .. " leader has no trigger, so none of its keys is live")
    return self
  end
  local ok, why = self._trigger.start(self)
  if ok == false then
    log.w("the " .. tostring(self._name or "plain") .. " leader did not start, " .. tostring(why))
  end
  return self
end

return obj
