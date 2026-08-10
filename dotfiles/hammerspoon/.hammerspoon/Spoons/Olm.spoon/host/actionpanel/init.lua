--- === ActionPanel ===
---
--- The measurement phase eight's action panel is built on, and the panel itself, packet two of
--- the phase. It answers one question, given a context's bindings, which of them are verbs, the
--- things a person forgets the chord for, rather than navigation, every binding the panel does
--- not list, the shared moving up and down, inserting, closing, and scrolling the preview every
--- context already carries, and the panel's own chord besides, since a panel that listed its
--- own way in among the verbs it offers would break the one promise it makes.
---
--- This is a configured singleton, colon called, in the shape host/launcher and
--- host/queryscope already use, never a dot called factory like lib/registry.lua, since there
--- is exactly one classification policy and one panel for this whole configuration rather than
--- one per caller. verbsIn and kindOf know nothing about a chooser, about needs, about when, or
--- about whether anything is open, those are the root's own filters, already named
--- bindingApplies and bindingActive, and rowsFor, injected from the root, is what composes
--- bindingApplies with verbsIn on the root's own behalf. Keeping needs and when out of verbsIn
--- itself is what makes it a statement about the declarations themselves rather than about a
--- moment, which is what lets the measurement in test/inventory.lua stay true between one run
--- and the next.
---
--- decorate, toggle, and isOpen are the panel proper, the decorator that swaps a chooser's own
--- rows for the panel's whenever it is open on that instance, installed once at
--- Chooser.configure's decorate seam rather than at any of the twelve call sites to
--- Chooser.new, so no consumer is edited and no consumer learns this exists. decoratedCount is
--- a fourth, small door onto how many instances decorate has actually wrapped, answering a
--- question about construction rather than about presentation, which is why it asks nothing of
--- configure.
---
--- It names no action and no context. The composition root owns the map from an action name to
--- a kind, since config/keys.lua already knows what every action name means, and injects that
--- map through configure as deps.kindOf, and it owns the panel's own presentation and the
--- running of a chosen verb, injected as deps.rowsFor and deps.run. This module only asks
--- questions of what it is handed and never names a chooser, an action, or a context itself.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ActionPanel"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("ActionPanel", "info")

-- The named set of kinds a binding's action may classify as. Two members, closed, named here
-- so the composition root and this module both write spoon.ActionPanel.kinds.verb or
-- spoon.ActionPanel.kinds.navigation rather than a bare string either side could misspell with
-- nothing to catch it. verbsIn below checks a kind against these two members directly rather
-- than against a bare string, and that is as far as this table reaches. verbsIn has a branch
-- for verb and a branch for navigation and nothing else, so a third member added only here
-- would not be handled for free, it would fall into the same else branch an unclassified
-- action already falls into, dropped and reported as a defect. Growing this set to three
-- members is a new member here and a new branch in verbsIn together, not one without the other.
--
-- Navigation, since the panel exists, means every binding the panel does not list, not only the
-- eight shared moving, inserting, closing, and scrolling actions packet one named. The panel's
-- own chord, the way in, joins that same kind rather than earning a third member, since the
-- panel must never list its own way in among the verbs it offers and one binding does not earn
-- verbsIn a new branch. A kind is still closed at two, verb or navigation, and everything that
-- is not a verb, including a binding nobody had written yet when this module was, is navigation.
obj.kinds = {
  navigation = "navigation",
  verb = "verb",
}

-- Injected via configure
obj._kindOf = nil -- function(action) -> a member of obj.kinds or nil, required
obj._rowsFor = nil -- function(contextName) -> ordered rows { action, title, chord }, required
obj._run = nil -- function(action), runs a named action, required
obj._log = nil -- w(message), defaults to this module's own hs.logger instance

-- The panel's own runtime state, set only by decorate, toggle, and the private helpers below,
-- and read by nothing outside this file. _instances is every raw Chooser instance decorate has
-- ever been called with, in the order it was called, the same unproven assumption the root's
-- own activeChooser runs on standing in for a name here too, that at most one is ever showing
-- at once. _openInstance is the one the panel is currently open on, or nil, which doubles as
-- isOpen's whole answer. _panelRows is the row list currently being shown, valid only while
-- _openInstance is set. _capturedRow is the highlight and _capturedQuery is the field text to
-- restore on every way out, both captured once, the moment the panel opens, since the field is
-- as much a part of what the panel swaps as the rows are, an open panel answering nothing
-- because whatever was typed for the tool's own list matches no panel title being the failure
-- this exists to prevent.
obj._instances = nil
obj._openInstance = nil
obj._panelRows = nil
obj._capturedItem = nil
obj._capturedRow = nil
obj._capturedQuery = nil
-- The scheduler _choose below defers a verb's own restore and run through, defaulting to
-- hs.timer.doAfter and settable directly on an instance, bypassing configure exactly the way
-- a unit case sets _log directly, so a case can hand in a synchronous stand in, delay and fn
-- in, fn called at once, and read the continuation's own effect back without a real wait. The
-- composition root never sets this.
obj._defer = nil

--- ActionPanel:init()
--- Method
--- Initialize the spoon. Nothing is built until configure runs, since the whole of this
--- module's behaviour comes from the one function configure injects.
function obj:init()
  return self
end

--- ActionPanel:configure(deps)
--- Method
--- deps.kindOf   required, a function taking an action name and answering a member of
---               obj.kinds or nil. A missing or non function value raises, since that is a
---               caller misusing this module rather than a tool's own data, the same line
---               lib/registry.lua draws between the two for its own required opts.apiVersion.
--- deps.rowsFor  required, a function taking a context name and answering the ordered rows
---               the panel should show for it, each a table carrying action, title, and
---               chord. Presentation, so the root owns it, the same line drawn for kindOf.
--- deps.run      required, a function taking an action name and running it. The root owns
---               that too, since it already keeps the one map from an action name to what it
---               does, contextActions.
--- deps.log      optional, the logger every warning below is written through, defaulting to
---               this module's own hs.logger instance. It exists only so a unit case can hand
---               in a small table answering w(message) and read a warning back directly,
---               without going through hs.logger's own global, shared, process wide history
---               buffer, the same reason and the same wording lib/registry.lua gives for its
---               own opts.log. The composition root never passes it.
function obj:configure(deps)
  deps = deps or {}
  if type(deps.kindOf) ~= "function" then
    error("ActionPanel configure requires deps.kindOf, a function from an action name to a member of obj.kinds")
  end
  if type(deps.rowsFor) ~= "function" then
    error("ActionPanel configure requires deps.rowsFor, a function from a context name to its panel rows")
  end
  if type(deps.run) ~= "function" then
    error("ActionPanel configure requires deps.run, a function running a named action")
  end
  self._kindOf = deps.kindOf
  self._rowsFor = deps.rowsFor
  self._run = deps.run
  self._log = deps.log or log
  return self
end

-- Whether this instance has been configured, warning once naming the caller when it has not,
-- kept in the one place kindOf and verbsIn below both call rather than each carrying its own
-- copy of the same check. Answering a question before configure ran is a legitimate case
-- rather than a caller's own mistake, unlike a missing deps.kindOf on configure itself, so this
-- warns and lets the caller answer nil or an empty list rather than raising out of a key
-- handler or an inventory run. self._log falls back to this module's own logger, since
-- configure is exactly the thing that has not happened yet.
local function ensureConfigured(self, caller)
  if self._kindOf then return true end
  (self._log or log).w(string.format(
    "ActionPanel %s was asked before configure ran, answering as though nothing is classified", caller))
  return false
end

--- ActionPanel:kindOf(action) -> a member of obj.kinds or nil
--- Method
--- The injected classifier's own answer for one action name, or nil when this instance has
--- not been configured yet. Exposed as a public method rather than left on a private field so
--- anyone asking what an action classifies as, test/inventory.lua's own live read among them,
--- goes through the one door that carries the unconfigured guard rather than reaching past it.
function obj:kindOf(action)
  if not ensureConfigured(self, "kindOf") then return nil end
  return self._kindOf(action)
end

--- ActionPanel:rowsFor(contextName) -> list
--- Method
--- The injected rowsFor's own answer for one context name, or an empty list when this
--- instance has not been configured yet. Exposed as a public method for the same reason
--- kindOf is, so anyone asking what the panel would show for a context, test/inventory.lua's
--- own live read among them, goes through the one door that carries the unconfigured guard,
--- and so toggle below and that measurement both reach the composition root's presentation
--- through the exact same call rather than two copies of it agreeing by hand.
function obj:rowsFor(contextName)
  if not ensureConfigured(self, "rowsFor") then return {} end
  return self._rowsFor(contextName)
end

--- ActionPanel:verbsIn(bindings) -> list
--- Method
--- A context's binding list in, a new ordered list holding only the bindings whose action
--- classifies as a verb, in declaration order, out. The list handed in is never mutated,
--- since the caller may be holding the very table config/keys.lua built. Answers an empty
--- list, with the one warning ensureConfigured already logs, when this instance has not been
--- configured yet.
---
--- A binding whose action classifies as navigation is dropped in silence, which is the entire
--- point of this function, a panel that lists it would break the one promise it makes. A
--- binding whose action classifies as neither, because deps.kindOf answered nil or answered
--- something that is not a member of obj.kinds, is dropped as well, and costs one warning
--- naming the action, since an unclassified action is a defect rather than a legitimate
--- absence. Dropping rather than keeping either way is the safer of the two answers open to an
--- unclassified action, since keeping one that turns out to be navigation would break the
--- panel's whole promise where dropping one that turns out to be a verb only goes missing
--- loudly, and loudly is recoverable.
function obj:verbsIn(bindings)
  if not ensureConfigured(self, "verbsIn") then return {} end
  local out = {}
  for _, b in ipairs(bindings or {}) do
    local kind = self._kindOf(b.action)
    if kind == obj.kinds.verb then
      out[#out + 1] = b
    elseif kind == obj.kinds.navigation then
      -- Dropped in silence, on purpose, see the note above.
    else
      self._log.w(string.format(
        "ActionPanel dropped '%s', it classifies as neither a verb nor navigation", tostring(b.action)))
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- The panel proper. Everything below installs at Chooser.configure's decorate seam and
-- reads and writes only obj._instances, obj._openInstance, obj._panelRows,
-- obj._capturedItem, obj._capturedRow, and obj._capturedQuery, declared with the rest of
-- this instance's fields above.
--------------------------------------------------------------------------------

-- The panel's own rows, as decorate's wrapped rows function answers them while the panel is
-- open, filtered by a plain case insensitive substring against the title when the instance's
-- own supplier owns filtering (config.matcher was false at decoration time, filtersItself
-- below), or answered whole so the instance's own matcher ranks them, exactly the choice the
-- atom already gives every consumer over its ordinary rows. Every panel row's title already
-- doubles as its filterText, set where rows below builds them, so there is nothing separate to
-- read here.
local function filterOwnRows(rows, query, filtersItself)
  if not filtersItself or not query or query == "" then return rows end
  local q = query:lower()
  local out = {}
  for _, r in ipairs(rows) do
    if (r.title or ""):lower():find(q, 1, true) then out[#out + 1] = r end
  end
  return out
end

-- Chooser row shaped entries { title, subTitle, item, filterText } built from deps.rowsFor's
-- plain { action, title, chord } rows, one call away from both toggle below and
-- test/inventory.lua's own live read through the public rowsFor above, so a title or a chord
-- the panel shows is never a second opinion on what deps.rowsFor answered. The chord rides as
-- the row's subTitle, since a person opening the panel to look up a verb's chord is exactly
-- this feature's own reason to exist. item carries the plain row itself back whole, so
-- _choose below can read its action directly off whatever the atom hands back as the chosen
-- item, and the Back row, carrying no action since no context declares one, is what marks it
-- Back rather than a verb there.
function obj:_buildRows(contextName)
  local rows = {}
  for _, r in ipairs(self:rowsFor(contextName)) do
    rows[#rows + 1] = { title = r.title, subTitle = r.chord, item = r, filterText = r.title }
  end
  return rows
end

-- The first recorded instance answering isShowing, or nil when none does. The same rule and
-- the same unproven assumption the root's own activeChooser already runs on, that at most one
-- chooser is ever showing at once, so first found is first, and safely, the only one there is.
function obj:_findShowing()
  for _, instance in ipairs(self._instances or {}) do
    if instance:isShowing() then return instance end
  end
  return nil
end

-- Clears every piece of the panel's open state together, the one place that does, so onClose
-- below and _leave further down both reach the exact same idle state rather than two copies of
-- it agreeing by hand. Once this runs, every wrapped config function decorate installed falls
-- straight through to its original again, on every instance, since each checks
-- self._openInstance against its own instance and this clears it to nil. Callers that still
-- need the captured row or query read them before calling this, since it clears those too.
function obj:_close()
  self._openInstance = nil
  self._panelRows = nil
  self._capturedItem = nil
  self._capturedRow = nil
  self._capturedQuery = nil
end

-- The one place every way out of the panel ends, whichever of the four it is, choosing Back
-- through intercept, Backspace through back, choosing a verb through intercept, or the chord
-- toggling the panel closed again. All four owe the chooser the exact same thing back, the
-- field holding what it held when the panel opened and the highlight back on the row the panel
-- was opened over, and putting that in one place rather than four is what keeps them from
-- drifting the way three of them already had, restoring it for the verb path alone.
--
-- The query is restored SYNCHRONOUSLY, before this returns, since setQuery on the atom only
-- sets the field and asks nothing to rebuild on its own, so whichever rebuild runs next,
-- whether the atom's own refresh(true) right after intercept or back answers true, or the
-- explicit one toggle below runs itself on the chord path, reads this field rather than
-- whatever the panel's own query was left on.
--
-- The row is restored on a continuation deferred past that rebuild, for the same reason
-- action, when there is one, has to be too. Both intercept and back in providers/native.lua
-- call refresh(true) on instance the moment their own handler answers true, and they do that
-- AFTER the handler has already returned, which is exactly what every caller of this function
-- is. So anything this function did to the highlight synchronously would be undone a moment
-- later by that very rebuild, since refresh(true) resets the highlighted row to the first one.
-- The chord path gets no such rebuild for free and has to run its own, see toggle below, but
-- the restore still defers here so every path shares this one function rather than three
-- sharing it and a fourth carrying its own copy.
--
-- action is nil for Back, Backspace, and the chord closing the panel, and an action name for a
-- chosen verb, run only once the row is back where it was, through deps.run, exactly the same
-- contextActions entry the chord itself runs, against exactly the row the chord would have
-- acted on, so the panel and the chord cannot disagree about what a verb does.
function obj:_leave(instance, action)
  local capturedRow = self._capturedRow
  local capturedQuery = self._capturedQuery
  self:_close()
  instance:setQuery(capturedQuery)
  local defer = self._defer or hs.timer.doAfter
  defer(0, function()
    if not instance:isShowing() then
      if action then
        self._log.w(string.format(
          "ActionPanel action '%s' found its chooser gone by the time it ran, running nothing",
          tostring(action)))
      end
      return
    end
    instance:selectRow(capturedRow)
    if action then self._run(action) end
  end)
end

-- What decorate's wrapped intercept calls while the panel is open on instance, answering
-- exactly what _intercept in providers/native.lua asks of any consumer, true to keep the
-- chooser open, and it is always true here, since neither closing the panel nor running a
-- verb is a reason to let the row complete as an ordinary selection.
--
-- item is whatever decorate's wrapped rows function put in the row's own item field, above,
-- so it is either a plain { action, title, chord } verb row or the Back row, which carries no
-- action since no context declares one. That absence is what marks it Back here, not a
-- separate flag, since the panel is the only thing that ever builds this row and the only
-- thing that ever reads it back, and it is also what tells _leave whether there is an action
-- to run once the row is back where it was.
function obj:_choose(instance, item)
  self:_leave(instance, item and item.action or nil)
  return true
end

--- ActionPanel:decorate(instance, config)
--- Method
--- The function the root hands to Chooser.configure as opts.decorate, called once for every
--- instance Chooser.new builds, right after native.new returns and before new hands the
--- instance back. Records instance and wraps six of config's own functions, rows, intercept,
--- back, onSelect, onHighlight, and onClose, so that while the panel is open on THIS instance
--- each behaves the way the panel needs and otherwise falls straight through to whatever the
--- consumer supplied, unchanged. Every wrapped function below checks self._openInstance
--- against instance rather than a bare self._openInstance truthy test, since eleven of the
--- twelve decorated instances are not the open one at any given moment and must behave exactly
--- as they always did.
---
--- The atom that calls this learns nothing about what it does. This module, in turn, learns
--- nothing about which of the twelve consumers instance belongs to, only that it is one of
--- them, which is why toggle below has to be told a context's name rather than working it out
--- from instance itself.
function obj:decorate(instance, config)
  self._instances = self._instances or {}
  self._instances[#self._instances + 1] = instance

  local originalRows = config.rows
  local originalIntercept = config.intercept
  local originalBack = config.back
  local originalOnSelect = config.onSelect
  local originalOnHighlight = config.onHighlight
  local originalOnClose = config.onClose
  -- Read once, at decoration time, per the atom's own contract: config.matcher false means
  -- the supplier owns filtering and anything else means the atom's own matcher ranks whatever
  -- the supplier answers in full. Chooser.new above has already resolved config.matcher from
  -- nil to the module default by the time decorate ever sees it, so this is never itself nil.
  local filtersItself = config.matcher == false

  -- The swap, and there is no other. While the panel is open on this instance the supplier
  -- answers the panel's rows instead of the tool's; otherwise the tool's own supplier, exactly
  -- as before this module existed.
  config.rows = function(query)
    if self._openInstance == instance then
      return filterOwnRows(self._panelRows or {}, query, filtersItself)
    end
    return originalRows and originalRows(query) or {}
  end

  -- Choosing a panel row is answered here rather than completing as a row of the underlying
  -- list. Absent on ten of the twelve consumers, so this supplies one where there was none and
  -- falls through to the original where there was.
  config.intercept = function(item)
    if self._openInstance == instance then
      return self:_choose(instance, item)
    end
    if originalIntercept then return originalIntercept(item) end
    return false
  end

  -- Backspace on an empty field, one of the two ways out of the panel, the other being
  -- choosing its own Back row through intercept above. Absent on eleven of the twelve
  -- consumers, same treatment. Routed through _leave with no action, the same door Back and a
  -- chosen verb both use, so the field and the highlight come back the same way on every path.
  config.back = function()
    if self._openInstance == instance then
      self:_leave(instance, nil)
      return true
    end
    if originalBack then return originalBack() end
    return false
  end

  -- Every chooser here is in filter mode, so a panel row should never reach onSelect at all,
  -- since intercept above answers first and keeps the row from completing. Reaching here with
  -- the panel open is a defect, a panel row about to be treated as one of the tool's own
  -- items, so this warns naming it rather than calling the original in silence, and does not
  -- call the original at all, since the tool never asked to see a panel row.
  config.onSelect = function(item)
    if self._openInstance == instance then
      self._log.w(string.format(
        "ActionPanel row '%s' reached onSelect, a panel row should complete through intercept and never here",
        tostring(item and item.action or item)))
      return
    end
    if originalOnSelect then originalOnSelect(item) end
  end

  -- Deliberately not called at all while the panel is open on this instance, rather than an
  -- omission. A companion pane keeps showing the item the panel was opened over, which is
  -- exactly what a chosen verb acts on, and leaving the preview on it is more honest than
  -- blanking it or describing a menu row as though it were the thing being previewed.
  config.onHighlight = function(item)
    if self._openInstance == instance then return end
    if originalOnHighlight then originalOnHighlight(item) end
  end

  -- Escaping, clicking away, or the tool closing itself all tear the chooser down through
  -- this, so this is where the panel's own state clears too. Without it, an escape out of an
  -- open panel would leave the state set, and the next chooser opened anywhere would come up
  -- showing stale panel rows, the worst failure available here.
  config.onClose = function()
    if self._openInstance == instance then
      self:_close()
    end
    if originalOnClose then originalOnClose() end
  end

  return instance
end

--- ActionPanel:toggle(contextName)
--- Method
--- What the panel's chord runs. Closes the panel when it is already open, through _leave with
--- no action, the same door every other way out uses, and then runs its own refresh(true),
--- since this is the one way out that answers no to intercept and to back and so earns none of
--- their own automatic rebuild, unlike Back, Backspace, and a chosen verb, which all get one
--- for free the moment their own handler answers true. Otherwise finds the first recorded
--- instance answering isShowing (see _findShowing above) and does nothing at all when none
--- does, since the chord being pressed with nothing open is ordinary rather than a mistake.
---
--- contextName names the context whose rows to show. It has to be told rather than worked out
--- from the found instance, since decorate above learns nothing about which of the twelve
--- consumers an instance belongs to, and the root already has to resolve which context matched
--- before it can call this at all, the same resolution its own activeContext already runs, so
--- it is asked once there rather than taught to this module a second way.
---
--- Captures the highlighted item, row, and query, so a verb, once chosen, can act on the row
--- the panel was opened over and the field can be handed back exactly as it was found (see
--- _leave above), asks rowsFor for the named context's rows, sets the panel's state, clears the
--- field so the panel opens on its own full list rather than filtered by whatever the tool's
--- own query happened to be, and calls refresh(true) on the instance so decorate's wrapped rows
--- function is asked for the panel's rows right away.
function obj:toggle(contextName)
  if self._openInstance then
    local instance = self._openInstance
    self:_leave(instance, nil)
    instance:refresh(true)
    return
  end
  if not ensureConfigured(self, "toggle") then return end
  local instance = self:_findShowing()
  if not instance then return end
  self._capturedItem = instance:selectedItem()
  self._capturedRow = instance:selectedRow()
  self._capturedQuery = instance:query()
  self._panelRows = self:_buildRows(contextName)
  self._openInstance = instance
  instance:setQuery("")
  instance:refresh(true)
end

--- ActionPanel:isOpen() -> boolean
--- Method
--- Whether the panel is currently showing, on any instance.
function obj:isOpen()
  return self._openInstance ~= nil
end

--- ActionPanel:decoratedCount() -> integer
--- Method
--- How many instances decorate has ever wrapped. Public so test/inventory.lua can prove the
--- panel is actually installed on every chooser rather than trusting that Chooser.configure's
--- decorate seam ran before all twelve were built, since a chooser built before that call, or
--- one that stopped going through the Chooser facade at all, would leave the panel silently
--- dead on it with every other gate here still green. It reads twelve today and would read
--- eleven the moment that stopped being true, which is the whole point of measuring it rather
--- than assuming it. Needs no configure, the same reason decorate itself does not, since
--- recording an instance is a fact about construction rather than about the classification
--- policy configure injects.
function obj:decoratedCount()
  return #(self._instances or {})
end

return obj
