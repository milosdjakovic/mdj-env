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
---
--- LIST KEYS ARE A LAYER ON EVERY LEADER, since phase A of the list keys addendum to the keymap
--- plan. A binding stating when is a list binding on whichever leader it was bound on, live only
--- while its list's predicate holds. One rule covers every held leader over an open list. While
--- any Olm list is open the leader answers only its bindings for the open list and swallows every
--- other key, so no global key fires underneath a list and nothing leaks past one. That replaced
--- two policy fields, quietOverLists, which made META inert over a list, and sealedOverLists, which
--- swallowed whatever Hyper left unresolved there, and a leader binding no list key is inert over
--- a list exactly as META was. Outside lists a leader resolves its global bindings first, by its
--- own tier rule, and a key bound only in a list is swallowed as a key switched off for the moment.
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
--- binds every list key through its contexts onto the held leader its chord names.

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
--   drivenRepeat        a repeating binding repeats on the engine's own schedule and its run is
--                       handed how deep into the hold it is, rather than riding the OS autorepeat.
--   ranked              the global bindings on one key compete by priority, the best answering and
--                       one gated off falling out of its tier so the next can answer, rather than
--                       the first exact match answering and a gated one being swallowed there, and
--                       among catch alls the first bound answers rather than the last. List
--                       bindings are ranked on every leader whatever this says, see _resolve.
--   sheet               a hold reveals this leader's cheat sheet, drawn by the one sheet host. Absent
--                       means a hold reveals nothing. On a leader of modifiers the sheet is revealed
--                       once exactly that set has been held for the hold delay, see the modifier
--                       trigger.
--   sheetLayout         how that sheet is laid out, a table of the SHEET_FIELDS below. Absent means
--                       the defaults, and it means nothing on a leader with no sheet.
--   holdDelay           seconds a hold waits before it reveals, else the engine's own.
local FIELDS = {
  drivenRepeat = "boolean",
  ranked = "boolean",
  sheet = "boolean",
  sheetLayout = "table",
  holdDelay = "number",
}

-- Fields a policy once carried and no leader reads now, each with what replaced it, so a config
-- still setting one is told rather than having the value ignored in silence. All three went in
-- phase A of the list keys addendum to the keymap plan, when list keys left the one leader that
-- hosted them.
local RETIRED = {
  tapTogglesCapsLock = "a quick tap toggles Caps Lock when the leader's key is capsLock and does "
    .. "nothing for any other key, the held trigger decides it from the key",
  contexts = "list keys bind on the leader each chord names and the list role in the roles "
    .. "section of config/keymap.lua places the defaults, and the tier rule it also chose is ranked",
  quietOverLists = "every held leader over an open list answers only its bindings for that list "
    .. "and swallows every other key",
  sealedOverLists = "every held leader over an open list answers only its bindings for that list "
    .. "and swallows every other key",
}

-- What a sheet layout may carry, with the type each takes. Every field is absent unless stated,
-- and an absent size is the shared renderer's own.
--
--   title       the heading over rows that name no group. Absent, which is how every leader ships,
--               it follows the role the leader holds, see sheetHeading below, so a person states
--               one only to pin a heading on one leader whatever it holds.
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
    if RETIRED[field] then
      problems[#problems + 1] = { where = tostring(name), why = "the leader policy field '"
        .. field .. "' is retired, " .. RETIRED[field] .. ", so it is ignored" }
    elseif not want then
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

--- obj.sheetHeading(catalogName, roles, roleTitles) -> string
--- The heading over a leader's rows that name no group, which is what the leader does rather than
--- what it is called, since the leader's own name says nothing to somebody reading a list of
--- window actions. What a leader does is the role it holds, so the heading follows the role. roles
--- maps each role word to the catalog name holding it, the keymap's roles over the shipped ones,
--- and roleTitles maps a role word to its heading. A leader holding two roles takes the first in
--- name order that has a heading, and a leader holding none, which carries only chords a person
--- put on it by name, reads as its own name, since nothing else is true of every row on it.
function obj.sheetHeading(catalogName, roles, roleTitles)
  local held = {}
  for role, holder in pairs(roles or {}) do
    if holder == catalogName then held[#held + 1] = role end
  end
  table.sort(held)
  for _, role in ipairs(held) do
    local title = (roleTitles or {})[role]
    if type(title) == "string" and title ~= "" then return title end
  end
  return tostring(catalogName)
end

--- obj.roleTitles(shipped, person) -> titles, problems
--- The role titles the sheets read, the person's entries laid over the shipped ones by role. Merged
--- here by key rather than through lib/defaults.lua, whose merge reads an empty table as a list
--- that replaces, so roleTitles = {} would have left every sheet headed by its leader's name. A
--- person's value that is no table, or an entry that is no word, is a problem line and ignored.
function obj.roleTitles(shipped, person)
  local out, problems = {}, {}
  for role, title in pairs(shipped or {}) do out[role] = title end
  if person == nil then return out, problems end
  if type(person) ~= "table" then
    problems[1] = { where = "roleTitles", why = "is a " .. type(person) .. " rather than a table of role to title, so the shipped titles stand" }
    return out, problems
  end
  local roles = {}
  for role in pairs(person) do roles[#roles + 1] = role end
  table.sort(roles, function(a, b) return tostring(a) < tostring(b) end)
  for _, role in ipairs(roles) do
    local title = person[role]
    if type(role) ~= "string" or type(title) ~= "string" or title == "" then
      problems[#problems + 1] = { where = "roleTitles " .. tostring(role), why = "is not a role word with a title, so it is ignored" }
    else
      out[role] = title
    end
  end
  return out, problems
end

--- obj.sheetLayout(policy, renderer, heading) -> layout
--- The layout a leader's sheet is drawn with, the policy's own fields over the defaults. The
--- policy is one already through checkPolicy, so every field is the type it takes. renderer is the
--- shared renderer's own defaults table, the source of columns, colWidth and gap where the policy
--- states none. heading is the title where the policy states none, sheetHeading's answer as the
--- root passes it, and a sheet given neither is headed plainly.
function obj.sheetLayout(policy, renderer, heading)
  local out = { title = heading or SHEET_TITLE }
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
---   keyCode     the keycode the sheet is shown for, the held key's own, nil on a leader of modifiers
---               whose sheet is found by name
---   listOpen    function answering true while any Olm list is open. A hold never reveals over an
---               open list, on every leader, and while it answers true the leader answers only
---               its bindings for the open list and swallows every other key.
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
  -- keycode to the bindings on it, in the order they arrived, and every binding once more in that
  -- order, which a trigger that claims combos walks so it claims them in a fixed order.
  self._bindings = {}
  self._sequence = {}
  -- The predicate names list keys carry, which drive the modal rule, on every leader.
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
--- The policy this leader was built with.
function obj:policy()
  return self._policy
end

--- Leader:bind(key, fn, mods, opts)
--- Method
--- Register a handler for key under this leader. mods is an optional list of required modifier
--- names, omitted for a catch all that fires when no exact binding matches. opts carries
---   when          a list key's predicate, which makes the binding a list binding on any leader, so
---                 while the predicate holds the leader is modal.
---   gate          a global row's predicate, eligibility alone, never modal on any leader.
---   priority      higher wins between eligible bindings in one tier, among list bindings on every
---                 leader and among global bindings on a ranked one.
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
  if opts.when then
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
--- Whether any list binding's context on this leader is live right now. While one is, the leader
--- belongs to that context, so bindings with no when are dropped and only list bindings act. That
--- is what makes a context modal rather than an overlay, so while the clipboard is open Hyper and A
--- does nothing instead of toggling an app.
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

--- Leader:_resolve(list, flags, overList) -> handler, repeats
--- Method
--- Pick the handler for the modifiers held. An exact match on the real modifiers beats a catch
--- all, fn ignored. The chosen binding's repeats flag travels with it, the shape the shared
--- engine's onKey contract asks for.
---
--- The list bindings and the global bindings are two layers. While a list is open, overList, or a
--- list binding's context is live on this leader, only the list bindings are eligible, the modal
--- rule. Otherwise the global bindings answer first and a list binding only where no global one
--- does, which outside its list means a key bound only in a list is gated off and swallowed.
---
--- List bindings are ranked on every leader. Every eligible one competes and the best priority
--- wins, the first bound among equals, and one that is not eligible drops out of its tier, since
--- every list shares its move keys and a first match would let a closed list's gated binding
--- swallow the open list's. Global bindings follow the leader's own tier rule, the two the old
--- adapters kept. On a ranked leader they compete the same way, so a key on Shift and J gated off
--- leaves the plain J binding to answer. On any other leader the first matching exact binding
--- answers and a gated one is swallowed there rather than falling through, and among catch alls
--- the last one bound answers.
---
--- Either way, a key whose matching bindings are all gated off is swallowed as a no op rather than
--- left unbound. A binding dropped by the modal rule is not gated off, it is outranked, so a key
--- whose only binding is a global one resolves to nothing here while a list's context is live, and
--- _onKey decides what an open list does with that.
function obj:_resolve(list, flags, overList)
  if not list then return nil end
  local present = heldSet(flags or {})

  -- One ranked pass over the bindings accept lets through, answering the binding chosen and whether
  -- a matching one was gated off.
  local function rankedPass(accept)
    local gated = false
    local bestExact, bestExactP = nil, -math.huge
    local bestCatch, bestCatchP = nil, -math.huge
    for _, b in ipairs(list) do
      if accept(b) and (b.mods == nil or modsMatch(b, present)) then
        if not self:_passes(b) then
          gated = true
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
    return bestExact or bestCatch, gated
  end
  local function isList(b) return b.when ~= nil end
  local function isGlobal(b) return b.when == nil end

  local chosen, gatedOff
  if overList or self:_modal() then
    chosen, gatedOff = rankedPass(isList)
  else
    if self._policy.ranked then
      chosen, gatedOff = rankedPass(isGlobal)
    else
      local catch, catchGated = nil, false
      for _, b in ipairs(list) do
        if isGlobal(b) then
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
      end
      chosen, gatedOff = catch, catchGated
    end
    if not chosen then
      local listChosen, listGated = rankedPass(isList)
      chosen, gatedOff = listChosen, gatedOff or listGated
    end
  end

  if chosen then return self:_handlerOf(chosen), chosen.repeats end
  if gatedOff then return noop, false end
  return nil
end

-- What a trigger asks of a pressed key. While a list is open only the open list's bindings act and
-- anything they leave unresolved is the bound no op, so nothing fires underneath a list and nothing
-- leaks past it, on every leader.
--
-- The rule is for a leader whose trigger says it seals over lists. A held leader always does. A
-- leader on real modifiers does when it hosts a list key, which the root knows once the lists are
-- laid out and states to the trigger, so its other keys are the bound no op over a list. The plain
-- leader and a modifier leader hosting no list key never seal, so their combination fires over a
-- list exactly as it does anywhere else.
function obj:_onKey(code, flags)
  local seals = self._trigger ~= nil and self._trigger.sealsOverLists == true
  local over = (seals and self._listOpen and self._listOpen()) and true or false
  local handler, repeats = self:_resolve(self._bindings[code], flags, over)
  if handler == nil and over then return noop, false end
  return handler, repeats
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
  -- A held leader is shown by its keycode and a leader of modifiers, which has none, by its name.
  sheet:show(code or self._keyCode or self._name)
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
--- True while this leader is physically asserted, the key held or every base modifier held, read
--- from the live keyboard.
--- A synthetic keystroke waits on it, since the shared tap swallows every key while a held leader
--- is down.
function obj:isActive()
  return self._trigger ~= nil and self._trigger.isActive() == true
end

--- Leader:owns(ev) -> bool
--- Method
--- Whether a key down event belongs to this leader right now, so a consumer that claims every key
--- for itself, the default chooser's field among them, can let this one through to the dispatch
--- downstream of it. The consumer is handed a predicate over this and never names the leader. A
--- trigger on real modifiers reads the flags the event itself carries.
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
