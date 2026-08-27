--- === Stage ===
---
--- The one host owning the single live chooser instance every tool presents into. A
--- presentation is a plain table of policy, name, placeholder, rows, onSelect, and the rest
--- of the presentation contract, and this host is the engine that shows whichever one is
--- current. Presentations stack, present pushes, backspace on an empty field pops, hide
--- clears. This is Strategy for the presentations over one engine, wired at the composition
--- root, which is the only place that ever hands this host a concrete presentation.
---
--- Phase two of the stage design build plan, host/stage owning the one Chooser.new and the
--- launcher migrated onto it as the first presentation. Nine tools still open their own
--- window, that is later phases, so this host's stack sits at depth one everywhere today,
--- which is correct and expected here. See docs/BRIEF-STAGE.md for the decisions this file
--- follows, and its own evidence in docs/CONSUMER-MAP-2026-08-27.md.
---
--- One instance, built once at configure, never rebuilt. Every consumer used to build its own
--- hs.chooser and tear it down with its window; this host builds one and keeps it for the
--- life of the config, so a handoff between presentations is a swap into a window already on
--- screen rather than a close and a reopen. The probe behind that decision is in
--- docs/PROBE-FINDINGS-2026-08-27.md.
---
--- What a presentation is not asked to carry. Screen policy, the matcher, the theme, the
--- docked shortcut panel, and the poll interval are all atom level policy this host owns for
--- the life of the one instance, never per presentation, the same list the stage design
--- brief's own decisions name. A presentation that wants any of those is asking the wrong
--- layer.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Stage"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Stage", "info")

-- The bundle id of this very process, so a world capture never records Hammerspoon itself as
-- the app a presentation covers. The same guard the launcher's own capture already keeps at
-- host/launcher/init.lua, carried here too since decision seven of the stage design brief asks
-- this host to capture its own world from day one, kept beside the launcher's rather than
-- replacing it, so a later phase deletes the launcher's copy rather than inventing this one.
local SELF_BUNDLE = hs.processInfo and hs.processInfo.bundleID

-- Injected via configure
obj._chooser = nil          -- the Chooser factory (has .new), the one door this host builds through
obj._theme = nil
obj._placeholder = nil
obj._panelOnPositioned = nil -- the docked shortcut panel triple, fixed for the life of the instance
obj._panelOnActivity = nil
obj._panelOnClose = nil

-- Owned state
obj._instance = nil         -- the one Chooser instance, built once and never rebuilt
obj.surface = nil           -- the one nav adapter, delegated to whichever presentation is current
obj._stack = nil            -- ordered presentations, the last entry is the one showing
obj._openId = nil           -- world capture, see _captureWorld and world()
obj._coveredApp = nil

--- Stage:init()
--- Method
--- Initialize the spoon. Nothing is built until configure runs, since the instance needs the
--- injected Chooser factory before it can exist at all.
function obj:init()
  return self
end

--- Stage:configure(opts)
--- Method
--- opts.chooser       the Chooser factory this host builds its one instance through. Without
---                     it nothing can ever be presented, see the manifest's own breaks
---                     sentence.
--- opts.theme          the shared palette, forwarded once at construction.
--- opts.placeholder    what the field reads before any presentation is current.
--- opts.onPositioned, opts.onActivity, opts.onClose
---                     the docked shortcut panel triple, fixed atom level policy rather than
---                     something a presentation carries. Phase two hands this the launcher's
---                     own panel, the only one that exists yet.
function obj:configure(opts)
  opts = opts or {}
  self._chooser = opts.chooser
  self._theme = opts.theme
  self._placeholder = opts.placeholder or ""
  self._panelOnPositioned = opts.onPositioned
  self._panelOnActivity = opts.onActivity
  self._panelOnClose = opts.onClose

  self._stack = {}
  self._openId = nil
  self._coveredApp = nil

  if not self._chooser then
    log.w("Stage configure ran with no chooser factory, so no instance was built and nothing can ever be presented")
    return self
  end

  -- The one Chooser.new call this configuration ever makes from this host. Every function
  -- below is a closure that asks the current presentation, live, on each call, exactly the
  -- same live read every other consumer of this atom already relies on for its own rows,
  -- intercept, back, onSelect, onHighlight, and onClose, see lib/chooser/init.lua's own note
  -- on why that reference is safe to mutate after construction. Screen and matcher are left
  -- unset here on purpose, so this instance inherits the module wide defaults the composition
  -- root already installed on the Chooser facade, the same way the launcher's own config
  -- never named either before this host existed.
  self._instance = self._chooser.new({
    theme = self._theme,
    placeholder = self._placeholder,
    rows = function(query) return self:_rows(query) end,
    onSelect = function(item) self:_onSelect(item) end,
    -- Decision five of the stage design brief. This host's own intercept and back are what
    -- Chooser.new sees, so the ActionPanel decorator wraps these two exactly once, at this
    -- construction, and answers for the panel first at runtime, falling through to these
    -- otherwise. Under that, the current presentation's own intercept or back is asked
    -- first, and a back the presentation declines pops the stack instead.
    intercept = function(item) return self:_intercept(item) end,
    back = function() return self:_back() end,
    onHighlight = function(item) self:_onHighlight(item) end,
    onPositioned = self._panelOnPositioned,
    onActivity = self._panelOnActivity,
    onClose = function() self:_onClose() end,
  })

  -- The one nav adapter every presenting plugin's own surface delegates to, phase two's
  -- launcher included. isShowing, selectNext, selectPrev, insertSelected, and hide answer
  -- against this host's own instance regardless of which presentation is current, since
  -- moving the highlight means the same thing whatever is on screen. peekPreview is the
  -- exception, the sixth function consumer map section 2.2 already found on the launcher's
  -- own surface, so it is asked of the current presentation and answered only when that
  -- presentation carries one.
  self.surface = {
    isShowing = function() return self:isShowing() end,
    selectNext = function() if self._instance then self._instance:selectNext() end end,
    selectPrev = function() if self._instance then self._instance:selectPrev() end end,
    insertSelected = function() if self._instance then self._instance:insertSelected() end end,
    hide = function() self:hide() end,
    peekPreview = function()
      local p = self:_current()
      if p and p.peekPreview then p.peekPreview() end
    end,
  }

  return self
end

-- The presentation currently on top of the stack, or nil when nothing is presented. Every
-- routing closure below asks this fresh on each call rather than caching it, since the stack
-- can change between two calls of the same closure.
function obj:_current()
  return self._stack[#self._stack]
end

-- Records the app this stack covers and an id for this open, once per stack, at the first
-- present that finds the window hidden. Decision seven of the stage design brief. Guarded
-- against recording Hammerspoon itself the way the launcher's own capture already is, for the
-- identical reason, two quick opens would otherwise hand a presentation Hammerspoon's own
-- frontmost state instead of whatever app was really covered.
function obj:_captureWorld()
  self._openId = (self._openId or 0) + 1
  local front = hs.application.frontmostApplication()
  if not (SELF_BUNDLE and front and front:bundleID() == SELF_BUNDLE) then
    self._coveredApp = front
  end
end

--- Stage:present(p) -> bool
--- Method
--- Show p, pushing it on the stack unless p is already the presentation on top, in which case
--- this is a reopen of what is already current rather than a second level of it, the shape a
--- tool's own hotkey opening its own already-open list needs. Swaps live when the instance is
--- already showing, resets the highlight to row one either way, per decision two of the stage
--- design brief. Answers false and refuses when p is not a presentation this host can show,
--- naming what was missing, the same discipline lib/registry.lua's own register keeps for a
--- malformed descriptor.
function obj:present(p)
  if type(p) ~= "table" or type(p.name) ~= "string" or p.name == ""
    or type(p.rows) ~= "function" or type(p.onSelect) ~= "function" then
    log.w("Stage present was given something that is not a presentation, name, rows, and onSelect are all required, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage present for '%s' arrived with no instance built, refusing", p.name))
    return false
  end
  if self:_current() ~= p then
    self._stack[#self._stack + 1] = p
  end
  self._instance:setPlaceholder(p.placeholder or "")
  if self._instance:isShowing() then
    self._instance:setQuery("")
    self._instance:refresh(true)
  else
    self:_captureWorld()
    self._instance:show()
  end
  return true
end

--- Stage:pop() -> bool
--- Method
--- Back one presentation, restoring the one below with an empty query and the highlight at
--- row one, answering false when the stack holds one or none, the case that leaves backspace
--- an ordinary press. Self sufficient, rebuilding the rows and the highlight itself rather
--- than relying on being called only from the atom's own back path, so a caller reaching this
--- directly gets the same result Backspace does.
function obj:pop()
  if #self._stack <= 1 then return false end
  table.remove(self._stack)
  local below = self:_current()
  if self._instance then
    self._instance:setPlaceholder(below and below.placeholder or "")
    self._instance:setQuery("")
    self._instance:refresh(true)
  end
  return true
end

--- Stage:hide()
--- Method
--- Hide the window and clear the stack, unconditionally, so a fresh present afterward always
--- starts a fresh stack whatever state the last one was left in.
function obj:hide()
  if self._instance then self._instance:hide() end
  self._stack = {}
end

--- Stage:refresh(resetRow)
--- Method
--- Re run the current presentation's rows, keeping the highlight by default. resetRow mirrors
--- the atom's own Chooser:refresh(resetRow), for a caller that swapped what the field means
--- and wants the highlight back at the top, the shape Launcher:show's own seeded query needs.
--- A no op while nothing is showing.
function obj:refresh(resetRow)
  if self._instance and self._instance:isShowing() then
    self._instance:refresh(resetRow)
  end
end

--- Stage:isShowing() -> bool
--- Method
--- Whether the one instance is currently visible. Safe before configure.
function obj:isShowing()
  return self._instance ~= nil and self._instance:isShowing()
end

--- Stage:current() -> string or nil
--- Method
--- The current presentation's own name, for a predicate or a hint to ask what is showing
--- without reaching for the presentation table itself.
function obj:current()
  local p = self:_current()
  return p and p.name or nil
end

--- Stage:world() -> hs.application, number
--- Method
--- The app this stack covers and the id of this open, captured once per stack at the first
--- present over a hidden window. Nil before the first capture.
function obj:world()
  return self._coveredApp, self._openId
end

--- Stage:setQuery(text)
--- Method
--- Set the field text on the live instance. Not part of the eight-member stage api the design
--- brief names, added because the launcher's own paging and seeding, decision six's "the _page
--- mechanism is internal launcher state" and the alias directory's seedQuery, need direct
--- field control no combination of present, pop, and refresh provides, the same setQuery the
--- launcher used to call straight on its own instance. Scoped to whichever presentation is
--- current in practice, since only the presentation currently being shown has any reason to
--- call it, but not enforced here, the same trust every other routing closure in this file
--- already extends to the presentation asking.
function obj:setQuery(text)
  if self._instance then self._instance:setQuery(text) end
end

--- Stage:setPlaceholder(text)
--- Method
--- Set the field placeholder on the live instance. The same addition as setQuery and for the
--- same reason, paging changes what the empty field says without changing which presentation
--- is current.
function obj:setPlaceholder(text)
  if self._instance then self._instance:setPlaceholder(text) end
end

--- Stage:selectedItem() -> item or nil
--- Method
--- The opaque item under the highlight on the live instance, or nil. The same addition as
--- setQuery and for the same reason, the launcher's own peekSelected, canPeekSelected, and
--- selectedKind all read the highlighted row and had nowhere else to reach it from once they
--- stopped holding the instance themselves.
function obj:selectedItem()
  return self._instance and self._instance:selectedItem() or nil
end

--- Stage:query() -> string
--- Method
--- The current field text on the live instance, "" when there is none. The same addition as
--- setQuery and for the same reason, the launcher's own currentQuery reads what is actually
--- typed rather than only ever writing to it.
function obj:query()
  return self._instance and self._instance:query() or ""
end

-- Everything below installs at Chooser.new's own config and reads only the stack above,
-- through _current, so every one of these behaves correctly however deep the stack is even
-- though it never exceeds one today.

function obj:_rows(query)
  local p = self:_current()
  if not p or not p.rows then return {} end
  return p.rows(query) or {}
end

function obj:_onSelect(item)
  local p = self:_current()
  if p and p.onSelect then p.onSelect(item) end
end

-- Asked before a row is allowed to complete. The current presentation's own intercept
-- answers first, and a presentation with none, or one that declines, leaves this false, the
-- row completing exactly as an ordinary selection.
function obj:_intercept(item)
  local p = self:_current()
  if p and p.intercept and p.intercept(item) then return true end
  return false
end

-- Asked on Backspace while the field is empty. The current presentation's own back answers
-- first, decision five of the stage design brief, and only once it declines does this pop the
-- stack itself, which answers false at the bottom exactly as an ordinary press.
function obj:_back()
  local p = self:_current()
  if p and p.back and p.back() then return true end
  return self:pop()
end

function obj:_onHighlight(item)
  local p = self:_current()
  if p and p.onHighlight then p.onHighlight(item) end
end

-- Fired for any teardown, a completed selection, escape, a click away, or a programmatic
-- hide, never for a swap between presentations while the window stays open, since a swap
-- never tears the atom down at all. Tells the fixed docked panel first, since that is atom
-- level infrastructure this host owns regardless of what was showing, then the current
-- presentation's own onClose when it declares one, then clears the whole stack, so the next
-- present anywhere starts fresh.
function obj:_onClose()
  local p = self:_current()
  if self._panelOnClose then self._panelOnClose() end
  if p and p.onClose then p.onClose() end
  self._stack = {}
end

return obj
