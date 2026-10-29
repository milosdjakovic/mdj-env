--- === Stage ===
---
--- The one host owning the single live chooser instance every tool presents into. A
--- presentation is a plain table of policy, name, placeholder, rows, onSelect, and the rest
--- of the presentation contract, and this host is the engine that shows whichever one is
--- current. Two doors show one, present and push, docs/BRIEF-HANDOFF.md decision one.
--- present means a fresh stack, the shape a hotkey opening its own tool wants, replacing
--- whatever stack exists even while the window is already up. push means stack on top of
--- what is showing, the shape a launcher row choosing a presenting tool wants, so drilling
--- into VPN from the launcher is a swap rather than a close and a reopen. Backspace on an
--- empty field pops, hide clears. This is Strategy for the presentations over one engine,
--- wired at the composition root, which is the only place that ever hands this host a
--- concrete presentation.
---
--- Phase two built this host with the launcher as its only presentation, one door, present,
--- serving both the hotkey open and the reopen of what is already current, since with one
--- presentation the two questions never came apart. Phase three of the handoff brief adds
--- push, VPN as the first tool migrated onto it, and widens onClose so a discarded stack
--- tells every level rather than only the one on top, decision six. Every other consumer
--- still opens its own window, that is phase five, so this host's stack sits at depth two at
--- most today, launcher then VPN. See docs/BRIEF-STAGE.md and docs/BRIEF-HANDOFF.md for the
--- decisions this file follows, and their own evidence in docs/CONSUMER-MAP-2026-08-27.md
--- and docs/REVIEW-STAGE-PHASE2.md.
---
--- One instance, built once at configure, never rebuilt. Every consumer used to build its own
--- hs.chooser and tear it down with its window; this host builds one and keeps it for the
--- life of the config, so a handoff between presentations is a swap into a window already on
--- screen rather than a close and a reopen. The probe behind that decision is in
--- docs/PROBE-FINDINGS-2026-08-27.md.
---
--- What a presentation is not asked to carry. Screen policy, the matcher, the theme, the
--- action bar's collaborator, and the poll interval are all atom level policy this host owns for
--- the life of the one instance, never per presentation, the same list the stage design
--- brief's own decisions name. A presentation that wants any of those is asking the wrong
--- layer.
---
--- surfaceFor(name), added this phase, is the fix for a divergence phase two only warned
--- about. The one nav adapter every presenting plugin used to share answered isShowing for
--- the window, not for whichever presentation actually owned it, so once a second
--- presentation existed the earliest one in plan.order would have won every routed key
--- regardless of which was really on screen. Each presenting plugin now asks this host for
--- an adapter scoped to its own name instead, host/launcher/init.lua and VPN's own manifest
--- presentation block alike, closing review finding ten.
---
--- Live geometry, docs/BRIEF-GEOMETRY.md, phase four of the chooser stage track. A
--- presentation may declare paneWidth, the atom's own companionWidth semantics carried one
--- layer up. present, push, and pop alike write the current presentation's own value into
--- the shared instance's layout.companionWidth before touching the window, the one
--- lib/chooser reach this phase keeps beyond setRows, so a cold show computes the pair's
--- centering natively, through the atom's own _positionAndShow, rather than painting alone
--- and correcting itself a beat later. A swap or the resize path's own reshow touches no
--- frame the atom would reposition on its own, so those still move the live window by hand,
--- through the same window finding trick _settleFrames uses, gated on how long ago this
--- instance last showed rather than on what kind of call this one is, adversarial review
--- finding M1. onPositioned, refired through _positionPane on the manual path and through
--- the atom's own automatic firing on the native one, converge on one function, _onPositioned,
--- which once also re anchored the docked shortcut panel, finding M2, using paneAnchor,
--- the one true copy of the anchor arithmetic three plugins once carried their own copy of,
--- consumer map sections 7.3 and 9.11, built for phase five's migrations to call instead, and
--- the survey of 2026-09-11 found every one of those migrations already done. The
--- presentation a transition leaves behind is told its own
--- onPositioned with nil frames before the incoming one is given real ones, finding H2, on
--- every door, present, push, and pop, so a pane consumer never sits drawn beside a window
--- that already moved past it. pop now routes through the same _show every other door does,
--- finding H1, so a two row window from caffeinate cannot survive a Backspace back into a ten
--- row list, and its own docstring says so.
---
--- Contract v2, docs/BRIEF-CONTRACT-V2.md, forced open by the trickle migrations rather than
--- scheduled. Two gaps neither the design brief nor the geometry phase anticipated, both
--- surfaced by plugins that resisted version one honestly rather than being bent to fit it.
--- A presentation may now declare matcher, false or a strategy name from the same table
--- root/compose.lua already resolves this word against for every unmigrated consumer,
--- written onto the shared instance live before every show and swap through setMatcher and
--- _resolveMatcher, the identical discipline paneWidth already keeps for companionWidth. A
--- presentation may also declare enter, a member handed one function, proceed, instead of
--- showing immediately, for a tool whose own rows depend on gathering something first and
--- whose own author already rejected a show then correct flash. present and push both honour
--- it now, each deferring its own stack mutation and show into a closure proceed alone
--- triggers, guarded by _enterGen against a proceed that fires twice or fires after the
--- stage has since moved on, pop or hide or a newer present or push having run meanwhile.
---
--- Contract v3, docs/BRIEF-CONTRACT-V3.md, child presentations. A presentation's own onSelect
--- may answer a presentation table instead of nothing, and when it does the row it was asked
--- about was never a completion at all, it was a drill into a level of its own, so _intercept
--- pushes the answered table as a child of whoever asked and answers true, exactly the "this
--- list becomes another list" contract intercept already keeps for the plain mutation case
--- decision three still reserves for a row that acts on the list it is on and stands. Riding
--- the existing intercept chain is not a choice among several, it is the only place capable
--- of the promise decision one makes, that such a row swaps the list in place with no window
--- ever closing. onSelect fires before Return is ever let through to hs.chooser's own native
--- completion, legacy.lua's own key watcher asking intercept first on every path, Return,
--- insertSelected, and a click alike, so this is the one gate a decision here can still stop
--- a real close from happening at all. Backspace on an empty field needs nothing new,
--- Stage:pop already restores whatever sits below the top of the stack, which is the parent
--- the moment a child sits above it. A child answering nil, the ordinary case, still means
--- what a completion has always meant here, the whole stack tears down, since _onClose
--- already clears every level on any unintercepted close and this revision changes nothing
--- about that. _selectHandled is the seam that keeps onSelect from running twice over one
--- row, once inside _intercept to learn whether a child came back and once more where the
--- atom's own separate onSelect hook would otherwise run it again the moment intercept has
--- answered false and the row is let through for real.

--- Cycle, the second way a list is shown, beside present. cycle(p, { keyCode }) is what a tool's
--- cycle key calls, through the keymap, the way its open key calls present. The first press shows
--- p bare, the provider's list alone with no field and no action bar, with the highlight one row
--- down, since a list a person cycles is ordered by recent use and row one is where they already
--- are, the way Command and Tab lands on the app used before. Each further press of the same key
--- steps the highlight down one row, wrapping at the end. The list then completes by itself on
--- the highlighted row a moment after the last press, through the presentation's own onSelect,
--- the same completion Return gives. Moving the highlight by hand, an arrow or the pointer, stops
--- that, and the list waits for Return or Escape. Any other key completes the list on the
--- highlighted row and is typed again into the app underneath once the list is gone, since a bare
--- list has nothing to type into and the person was already typing. The same presentation shown
--- through present, from its open key, the launcher row or its alias, is the full list as before,
--- so a plugin declares one list and the door it came through decides how it is shown.
---
--- The highlight belongs to the person, and the stage moving it here is not a plugin moving it,
--- it is the person's own repeated key, the one exception the core makes and the only place.

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

-- What Chooser.new reads before any presentation exists to set its own. Never asked of the
-- root and never configurable, finding eleven of the phase two adversarial review, since
-- Stage:present sets a presentation's own placeholder before every show and present is the
-- only way this window ever opens, so this literal is never on screen for a single frame. A
-- shipped default here once leaked through the same ambient grant every surfaced plugin's own
-- placeholder falls back to and silently rewrote five other tools' fields, which is the
-- damage a value that can actually render would risk again.
local CONSTRUCTION_PLACEHOLDER = ""

-- How long a cycled list waits after the last press of its key before it completes by itself.
-- 0.8 seconds, settled by trying 1.2, 0.6, 0.35 and 0.5 on 2026-10-25, the shorter ones closing
-- before a second tap could land.
local CYCLE_IDLE = 0.8

-- How long after a cycled list closes on a typed key that key is typed again, so the app the list
-- covered has taken focus back by the time it arrives.
local RETYPE_DELAY = 0.05

-- Injected via configure
obj._chooser = nil          -- the Chooser factory (has .new), the one door this host builds through
obj._theme = nil
obj._footer = nil           -- the action bar's model for whatever is showing, fixed for the life of the instance

-- Owned state
obj._instance = nil         -- the one Chooser instance, built once and never rebuilt
obj.surface = nil           -- the one nav adapter, delegated to whichever presentation is current
obj._stack = nil            -- ordered presentations, the last entry is the one showing
obj._openId = nil           -- bumped on every fresh stack, see _bumpOpenId and world()
obj._coveredApp = nil       -- tied to the window's own appearance, see _captureCoveredApp
obj._rowCount = nil          -- the row count the window is currently built for, seeded at configure
obj._defaultRowCount = nil   -- the atom's own default, read once at configure, never mutated after
obj._defaultMatcher = nil    -- the root's own matcher, read once at configure the same way
                              -- _defaultRowCount is, what a presentation naming no matcher of its
                              -- own is asking to return to, contract v2 decision one
obj._defaultTitleLineBreak = nil -- the atom's own "truncateTail", read once at configure the
                              -- identical way, rework rider restoring filesearch's own field
obj._geometryTimer = nil     -- held so a pending pane settle cannot be collected before it fires, see _applyPaneGeometry
obj._suppressClose = false   -- true only while _applyRowCount's own internal hide is in flight, see _onClose
obj._lastShowAt = nil        -- hs.timer.secondsSinceEpoch() at the last real show(), see _applyPaneGeometry
obj._enterGen = 0            -- bumped by every present, push, hide, and pop, contract v2 decision
                              -- two, so a deferring presentation's own proceed can tell whether the
                              -- stage is still waiting on it or has since moved on, see _bumpEnterGen
obj._closedObservers = nil   -- functions told once each time the stage goes away, see onClosed
obj._highlighted = nil       -- the item last reported highlighted, what a level's labels are asked of
obj._cycle = nil             -- the cycle in progress, its presentation and the keycode of its key, see cycle
obj._cycleNext = nil         -- the cycle the present cycle is about to run, taken by _takeCycle
obj._cycleTimer = nil        -- held so the idle completion cannot be collected before it fires
obj._retypeTimer = nil       -- held the same way, the typed key's second arrival
obj._selectHandled = false   -- contract v3, set true the instant _intercept has already run the
                              -- current presentation's own onSelect and found no child, so the
                              -- atom's own separate call to config.onSelect a moment later, once
                              -- intercept has answered false and Return is let through for real,
                              -- does not run the same onSelect a second time over the same row

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
--- opts.stampIcons     function of a list of rows and the owning plugin's identity, answering
---                     the rows with iconOwner set on every row that names an icon,
---                     lib/icons/rows.lua. It draws nothing, the chooser turns icon and
---                     iconOwner into a picture when it paints. Without it a row that names an
---                     icon without an owner shows nothing.
--- opts.footer       a function of no arguments answering the action bar's model for whatever
---                     is showing, lib/hints.lua's footerModel, handed to the one instance as
---                     its footer collaborator. Fixed atom level policy rather than something a
---                     presentation carries, the way the docked shortcut panel triple it
---                     replaced was. The root builds it over current and labels below. Without
---                     it the instance draws no action bar.
function obj:configure(opts)
  -- Decision one of the stage design brief, the one instance this host ever builds is never
  -- rebuilt. A second call here would not merely waste a chooser, it would orphan the first
  -- one inside ActionPanel's own instance roster, which appends every instance decorate ever
  -- sees and never removes one, so an orphan would sit in that roster forever, finding six of
  -- the phase two adversarial review. Not reachable today, this host is configured exactly
  -- once in the ordinary wiring pass and never again, but the guard costs one comparison and
  -- follows the same idempotent shape Launcher:start already keeps for the identical reason.
  if self._instance then
    log.w("Stage configure ran a second time, ignoring it, the one instance this host builds is never rebuilt")
    return self
  end

  opts = opts or {}
  self._chooser = opts.chooser
  self._theme = opts.theme
  self._stampIcons = opts.stampIcons
  self._footer = opts.footer
  self._footerAction = opts.footerAction

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
  -- never named either before this host existed. Contract v2 decision one. This is only the
  -- SEED, the matcher a presentation naming none of its own returns to, captured below into
  -- _defaultMatcher the instant construction has resolved it, exactly the way _defaultRowCount
  -- is captured a few lines further down. From the first present onward, _show writes every
  -- presentation's own matcher onto the shared instance live, through setMatcher, before
  -- each show and swap, the identical discipline the pane width already follows.
  self._instance = self._chooser.new({
    theme = self._theme,
    placeholder = CONSTRUCTION_PLACEHOLDER,
    rows = function(query) return self:_rows(query) end,
    onSelect = function(item) self:_onSelect(item) end,
    -- Decision five of the stage design brief. This host's own intercept and back are what
    -- Chooser.new sees, so the ActionPanel decorator wraps these two exactly once, at this
    -- construction, and answers for the panel first at runtime, falling through to these
    -- otherwise. Under that, the current presentation's own intercept or back is asked
    -- first, and a back the presentation declines pops the stack instead.
    --
    -- Review findings H1 and H2, rework. enabled is legacy.lua's own second argument now,
    -- the row's own enabled state at the moment intercept was asked, forwarded straight
    -- through so _intercept's own disabled row guard, the very first thing it checks, has
    -- something to check.
    intercept = function(item, enabled) return self:_intercept(item, enabled) end,
    back = function() return self:_back() end,
    onHighlight = function(item) self:_onHighlight(item) end,
    -- Review findings N1 and N2, reverting the construction half of M5. onScroll and
    -- onRightClick are permanent closures again. lib/chooser/providers/legacy.lua installs
    -- rightClickCallback exactly once, at construction inside obj.new, never re-read
    -- afterward, so writing this field only on a later cold show, M5's own first attempt,
    -- meant the callback was never registered on the real hs.chooser at all and every right
    -- click delete went dead on every door. _startScrollWatcher IS re-read, but only from
    -- Chooser:show(), never from a swap, so the same write-on-cold-show-only left every
    -- presentation reached by push, which is the launcher door, with no watcher and a dead
    -- trackpad gesture, a door dependent bug M5's own promise made worse rather than better.
    -- These closures already route through _onScroll and _onRightClick below, which ask
    -- _current() fresh on every call and no-op when the current presentation declares
    -- neither, which is M5's own isolation goal reached at the routing layer, where it holds
    -- for every call regardless of which door showed the window, rather than at the
    -- installation layer, where the atom's own once-at-construction and only-on-a-real-show
    -- lifecycles defeated it.
    onScroll = function(points) self:_onScroll(points) end,
    onRightClick = function(item, row) self:_onRightClick(item, row) end,
    -- Adversarial review finding M2. Routed through this host's own _onPositioned, the
    -- identical function a manual placement uses on a swap, so the current presentation's own
    -- pane hook hears the same frames whichever of the two placed the window.
    onPositioned = function(chooserFrame, companionFrame) self:_onPositioned(chooserFrame, companionFrame) end,
    onClose = function() self:_onClose() end,
    -- A key typed over a list shown bare, which a cycle answers, see _onBareKey.
    onBareKey = function(ev) return self:_onBareKey(ev) end,
    -- The action bar's model, asked by the instance on its own schedule. A provider that draws
    -- no bar never asks.
    footer = self._footer,
    -- What a press on an entry of the bar runs, by its action name.
    footerAction = self._footerAction,
  })

  -- Decision two of the geometry brief. The row count the window is currently built for is
  -- read straight off the fresh instance's own rowCount() rather than assumed, so this can
  -- never drift from whatever lib/chooser/providers/legacy.lua actually ships as its own
  -- default, and _defaultRowCount is what a presentation naming no rowCount of its own is
  -- asking to return to. Read once, right here, before setRows is ever called on this
  -- instance, since that is the only moment rowCount() still answers the atom's own default
  -- rather than something this host already asked it to become. Read through the accessor
  -- rather than off layout directly since the contract freeze phase, docs/BRIEF-CONTRACT-
  -- FREEZE.md, closed every reach this host used to make into that table.
  self._rowCount = self._instance:rowCount()
  self._defaultRowCount = self._rowCount

  -- Contract v2 decision one. self._instance:matcher() already answers the resolved module
  -- wide default the instant construction above returns, legacy.lua's own `matcher = config.matcher`
  -- having already folded DEFAULT_MATCHER in for a config that named none, lib/chooser/init.lua:122.
  -- Read once, right here, before any presentation has ever written to it, the same moment
  -- _defaultRowCount is read for the identical reason, so a presentation naming no matcher of
  -- its own asks to return to exactly what this host would have shown before contract v2 ever
  -- started writing this field on every show.
  self._defaultMatcher = self._instance:matcher()

  -- Rework rider. self._instance:titleLineBreak() already answers the atom's own default,
  -- "truncateTail", DEFAULT_LAYOUT's own value folded in at construction the identical way
  -- rowCount() is. Read once, right here, for the identical reason _defaultRowCount and
  -- _defaultMatcher are, so a presentation naming no titleLineBreak of its own asks to return
  -- to exactly what this host would have shown before this field existed.
  self._defaultTitleLineBreak = self._instance:titleLineBreak()

  -- The one nav adapter, unscoped, answering isShowing for the shared window itself rather
  -- than for any one presentation. selectNext, selectPrev, insertSelected, and hide are safe
  -- to share exactly as written, since moving the highlight or hiding the window means the
  -- same thing regardless of which presentation asked, and so is peekPreview, which is
  -- already scoped by reading whatever _current answers rather than by anything the caller
  -- states. isShowing is the one member a presenting plugin must never point at directly, see
  -- surfaceFor below, which is why this table is kept for the members that are safe to share
  -- rather than handed out by name to every presenting plugin's own surface.member.
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

--- Stage:surfaceFor(name) -> table
--- Method
--- The nav adapter one presenting plugin's own context should point at, isShowing scoped to
--- whether THIS name is the one currently presented, the other four members reused exactly
--- as this.surface already answers them, since selectNext, selectPrev, insertSelected, and
--- hide are correct regardless of which presenting plugin's own adapter happened to be asked,
--- only isShowing decides who wins lib/nav.lua's own activeSurface race. This is the fix
--- review finding ten asked for, generalised so a second presenting plugin costs no new
--- routing logic anywhere, only a call to this method from wherever that plugin's own surface
--- is resolved.
function obj:surfaceFor(name)
  local shared = self.surface
  return {
    isShowing = function() return self:current() == name and self:isShowing() end,
    selectNext = shared.selectNext,
    selectPrev = shared.selectPrev,
    insertSelected = shared.insertSelected,
    hide = shared.hide,
    peekPreview = shared.peekPreview,
  }
end

-- The presentation currently on top of the stack, or nil when nothing is presented. Every
-- routing closure below asks this fresh on each call rather than caching it, since the stack
-- can change between two calls of the same closure.
function obj:_current()
  return self._stack[#self._stack]
end

-- Whether p is a well formed presentation, name, rows, and onSelect all required and
-- nothing else asked, the same three fields BRIEF-STAGE.md's own contract calls required.
-- Shared by present and push so the two doors refuse a malformed table identically, naming
-- what was missing, the same discipline lib/registry.lua's own register keeps for a
-- malformed descriptor.
local function isPresentation(p)
  return type(p) == "table" and type(p.name) == "string" and p.name ~= ""
    and type(p.rows) == "function" and type(p.onSelect) == "function"
end

-- Every presentation currently on the stack is told its own onClose, top down, without
-- touching the stack itself, the caller's job. Decision six of the handoff brief, closing
-- review finding twelve, a discarded level used to hear nothing at all. A presentation that
-- declares none is silently skipped, exactly as an ordinary missing field already is
-- everywhere else in this file.
local function closeStack(stack)
  for i = #stack, 1, -1 do
    local p = stack[i]
    if p.onClose then p.onClose() end
  end
end

-- The same walk, except keep is never told, wherever in the stack it sits. Phase three
-- review finding three. present's own dedup only recognised a reopen when the whole stack
-- was keep alone, so re presenting the surviving top of a deeper stack, VPN's own hotkey
-- pressed again while VPN is already what a push landed on, told VPN it had closed while it
-- is exactly what stays on screen. Identity decides who is told, not depth, so keep is
-- skipped wherever it sits and everything else still hears its own onClose top down.
local function closeStackExcept(stack, keep)
  for i = #stack, 1, -1 do
    local p = stack[i]
    if p ~= keep and p.onClose then p.onClose() end
  end
end

-- Advances the open id, once per fresh stack, regardless of whether the window was already
-- up. Split from covered app capture below, phase three review finding five, since decision
-- one makes a present over a visible window a normal and expected thing, and a consumer
-- keying a per open cache off this id, MenuSearch among them, has to see a new id every time
-- the stack genuinely starts over, a present replacing a live stack included, or it would
-- read an answer that belongs to whatever the stack held before the replacement.
function obj:_bumpOpenId()
  self._openId = (self._openId or 0) + 1
end

-- Contract v2 decision two. Advances once at the start of present, push, pop, and hide alike,
-- whether or not the call in front of it ends up deferring through enter, so a proceed closure
-- built from an earlier call can always tell whether it is still the request the stage is
-- waiting on. Answers the new value, which the caller keeps as its own myGen to compare
-- against later, since self._enterGen itself keeps moving and a proceed asked to fire after
-- something else already bumped it again must find itself stale rather than lucky.
function obj:_bumpEnterGen()
  self._enterGen = (self._enterGen or 0) + 1
  return self._enterGen
end

-- Records the app this stack covers, tied to the window's own appearance rather than to the
-- stack starting over, since a present that replaces a live stack still covers the same app
-- the window originally opened over, the window itself never having gone anywhere for focus
-- to have left. Guarded against recording Hammerspoon itself the way the launcher's own
-- capture already is, for the identical reason, two quick opens would otherwise hand a
-- presentation Hammerspoon's own frontmost state instead of whatever app was really covered.
function obj:_captureCoveredApp()
  local front = hs.application.frontmostApplication()
  if not (SELF_BUNDLE and front and front:bundleID() == SELF_BUNDLE) then
    self._coveredApp = front
  end
end

-- What both doors reach when the outcome is a fresh stack, present always and push only when
-- it finds nothing to stack on top of, phase three review finding eight, which closes the gap
-- where push discarded a stack in silence and present did not. Tells every discarded level
-- except p itself its own onClose, bumps the open id, and replaces the stack with p alone.
-- Does not touch the covered app, _show below does that, and only on the branch that finds
-- the window hidden, per finding five's own split.
function obj:_freshStack(p, old)
  closeStackExcept(old, p)
  self._stack = { p }
  self:_bumpOpenId()
end

-- What every door does once the stack itself has already been decided, placeholder first
-- since setting it cannot change visibility, then a swap into a window already up or a cold
-- show into a hidden one, the single question every caller of this asked before calling it.
-- outgoing is the presentation that was current a moment ago, nil at the first open of a
-- session, and it is told before the incoming side is given anything, adversarial review
-- finding H2. The covered app is captured here, and only here, because it is tied to the
-- window's own appearance, finding five, never to the stack, which _freshStack above already
-- handles on its own terms. pop now calls this too, finding H1, present and push already did.
function obj:_show(p, wasShowing, outgoing)
  -- Rider N2 of the geometry review, second pass. Cancelled unconditionally here, on every
  -- door, rather than only inside _applyPaneGeometry, which only the swap branch below ever
  -- reaches. A timer a cold show leaves armed from an earlier swap used to survive a cold
  -- show untouched, and a stale fire landing after this presentation had already changed
  -- again would place a window for a pane that is no longer current, the identity guard in
  -- _positionPane catching most of it but not the case where the same presentation is what
  -- reopens before the timer fires. Moved here so every call to _show starts from a clean
  -- slate, the reason the old unconditional cancel existed in the first place.
  if self._geometryTimer then
    self._geometryTimer:stop()
    self._geometryTimer = nil
  end
  self._instance:setPlaceholder(p.placeholder or "")
  -- Adversarial review finding M6. Written before every show, cold or swap alike, so a cold
  -- show's own _positionAndShow computes the pair's centering natively, through the atom's
  -- own arithmetic, rather than painting a lone chooser first and being shifted by hand a
  -- beat later. Just as important on the branch that does NOT show anything this call, since
  -- a settle timer left pending by an EARLIER cold show reads this live when it finally
  -- fires, docs/PROBE-FINDINGS-2026-08-27.md section C3, so writing it here keeps that timer
  -- honest too rather than only the show this call might itself trigger. A presentation
  -- naming no paneWidth writes nil, which the atom's own _resolveCompanionWidth already
  -- treats as no pane, so the window centres itself alone with nothing else asked. Written
  -- through setPaneWidth() rather than onto layout directly since the contract freeze phase
  -- closed that reach.
  self._instance:setPaneWidth(p.paneWidth)
  -- Contract v2 decision one. Written before every show, cold or swap alike, the identical
  -- placement and the identical reasoning the pane width just above already carries, since
  -- legacy.lua's own Chooser:_build reads its own matcher live on every keystroke rather than
  -- once at construction, lib/chooser/init.lua's own note on why that reference is safe to
  -- mutate after construction. A presentation naming no matcher of its own resolves back to
  -- _defaultMatcher, the module wide default this host itself inherited at configure, so a
  -- tool that never asks for anything unusual keeps behaving exactly as it did before this
  -- field existed. Written through setMatcher() now, the same accessor rename that also
  -- closed the equivalent reach for the pane width just above.
  -- searchText and rowLimit, phase three of docs/PLAN-UNIFIED-SEARCH.md, travel beside the
  -- matcher in the same write, so a presentation declaring neither clears what the one before
  -- it declared rather than inheriting it.
  self._instance:setMatcher(self:_resolveMatcher(p.matcher), self:_searchOf(p))
  -- Rework rider, filesearch's own titleLineBreak restored. Written before every show, cold
  -- or swap alike, the identical placement the matcher just above keeps, since a swap's own
  -- refresh(true) rebuilds every row's styling live off titleLineBreak exactly the way it
  -- rebuilds off the pane width. A presentation naming none of its own resolves to
  -- _defaultTitleLineBreak, the atom's own "truncateTail" this host inherited at configure.
  self._instance:setTitleLineBreak(p.titleLineBreak or self._defaultTitleLineBreak)
  -- Decision two of the geometry brief. A row count change takes the one resize path that
  -- exists, hide, rows(n), show, which the probe found applies on the next show of the same
  -- instance, docs/PROBE-FINDINGS-2026-08-27.md section C2. _applyRowCount below drives that
  -- cycle itself when it is needed and answers whether it did, since a window it already
  -- reshowed for a resize must not also run the ordinary swap or cold show path just below on
  -- top of that.
  local reshaped = self:_applyPosture(self._cycle and self._cycle.p == p and "bare" or "full")
  local resized = self:_applyRowCount(p) or reshaped
  local cold = resized or not wasShowing
  -- Adversarial review finding H2. present already tells a genuinely discarded outgoing
  -- level its own onClose through _freshStack, and this still runs for it too, since
  -- onPositioned is where a pane consumer actually knows to erase its own canvas, never
  -- onClose, and telling both is cheap and never wrong. push tells nobody's onClose, by
  -- design, decision six of the handoff brief, so without this the level it stacked under
  -- would sit drawn beside a window that already moved on. pop's own leaving already hears
  -- onClose, and is told this too for the identical reason present's survivor is. Skipped
  -- when there is no outgoing, or when the outgoing IS the incoming, a reopen that must not
  -- be told it lost anything it still has.
  if outgoing and outgoing ~= p and outgoing.onPositioned then
    outgoing.onPositioned(nil, nil)
  end
  if cold then
    -- The covered app is only ever worth capturing on a genuinely fresh appearance, never on
    -- the reshow a resize just drove, since nothing had anywhere else to send focus during a
    -- same tick hide and show, finding five of the phase three review keeping the identical
    -- split for the identical reason.
    if not resized then self:_captureCoveredApp() end
    self._instance:show()
    -- Rider N1 of the geometry review, second pass. Stamped after show() returns rather
    -- than before it is called, since the atom arms its own settle timer at the END of
    -- show, once the theme is applied, every row is rebuilt, and hs.chooser:show has
    -- actually run, docs/PROBE-FINDINGS-2026-08-27.md's own note that this is the
    -- dominant cost of a cold open. Stamping above the call understated the window by the
    -- full cost of show() itself, which is what made the age gate's own comment untrue,
    -- a swap landing in that undercounted gap would run its manual placement before the
    -- settle it claimed to have waited out. M6 already makes the eventual outcome correct
    -- either way, since the atom's own settle recomputes and overwrites, but this is what
    -- makes the comment describe what the code actually does.
    self._lastShowAt = hs.timer.secondsSinceEpoch()
    -- Nothing further to do here. layout.companionWidth already carries this presentation's
    -- own value, so _positionAndShow and _settleFrames both compute the pair natively and
    -- fire onPositioned, routed to this host's own _onPositioned below, on their own.
  else
    self._instance:setQuery("")
    self._instance:refresh(true)
    -- A swap touches no frame the atom itself would reposition, refresh only rebuilds rows,
    -- so the pair still has to be placed by hand, decision one of the geometry brief.
    self:_applyPaneGeometry(p, outgoing)
  end
end

-- Applies a presentation's own row count when it differs from what the window is currently
-- built for, decision two of the geometry brief, paid only on that difference, which today is
-- only caffeinate's two rows both ways, entering it and returning to the default the moment
-- anything else is shown next. A presentation naming no rowCount of its own wants the atom's
-- own default back, self._defaultRowCount, read once at configure.
--
-- A window not yet up has nowhere to hide from, so the new count takes effect for free on the
-- cold show _show is about to run anyway, and this only remembers it. A window already up is
-- genuinely hidden and reshown, the one resize path that exists, which the probe found applies
-- cleanly with no rebuilt instance, docs/PROBE-FINDINGS-2026-08-27.md section C2. That hide
-- runs through the atom's own teardown, which fires onClose, the same signal a genuine
-- dismissal fires, and this is not one, the presentation being resized is still current and
-- about to be reshown on the very next line inside _show, so _suppressClose holds the door
-- shut for exactly this one call rather than let onClose tell every presentation on the stack
-- it just closed. Answers true when it drove that hide itself, so _show above knows not to
-- also run its own swap or cold show path on top of this one.
--
-- Adversarial review finding M3. The hide is wrapped in pcall and the flag is cleared
-- unconditionally right after, since without that a raise anywhere inside the atom's own
-- teardown, or inside the ActionPanel decorator it calls through on the way, would leave
-- _suppressClose stuck true for the life of the config, silencing every future onClose,
-- launcher and every presentation alike, with nothing anywhere saying why. Nothing found in
-- that path is known to raise today, the cost of guarding it anyway is one pcall.
function obj:_applyRowCount(p)
  local desired = p.rowCount
  -- A presentation whose height follows its own list answers a function, asked here on every
  -- show and clamped to the default, which stays the ceiling. A bad answer or a raise falls
  -- back to the default rather than reaching the atom's arithmetic.
  if type(desired) == "function" then
    local ok, n = pcall(desired)
    if ok and type(n) == "number" and n >= 1 then
      desired = math.min(math.floor(n), self._defaultRowCount)
    else
      desired = nil
    end
  end
  desired = desired or self._defaultRowCount
  if desired == self._rowCount then return false end
  self._rowCount = desired
  if not self._instance:isShowing() then
    self._instance:setRows(desired)
    return false
  end
  self._suppressClose = true
  local ok, err = pcall(function() self._instance:hide() end)
  self._suppressClose = false
  if not ok then
    log.w(string.format("Stage's own resize hide raised, %s, continuing to setRows and show regardless", tostring(err)))
  end
  self._instance:setRows(desired)
  return true
end

-- Applies the posture a list is shown in, bare for a cycle and full for everything else, the
-- same way _applyRowCount applies a row count. A provider that knows no posture, the legacy one,
-- is left as it is. Over a window already up a change takes the same hide and reshow, held shut
-- by _suppressClose, and answers true so _show runs the cold show that follows it.
function obj:_applyPosture(word)
  local instance = self._instance
  if type(instance.setPosture) ~= "function" or instance:posture() == word then return false end
  if not instance:isShowing() then
    instance:setPosture(word)
    return false
  end
  self._suppressClose = true
  local ok, err = pcall(function() instance:hide() end)
  self._suppressClose = false
  if not ok then
    log.w(string.format("Stage's own posture hide raised, %s, continuing to show regardless", tostring(err)))
  end
  instance:setPosture(word)
  return true
end

-- Places a presentation's own pane on a swap, decision one of the geometry brief. A cold show
-- no longer reaches this at all, adversarial review finding M6, since layout.companionWidth
-- already carries this presentation's own value by the time show() runs and the atom computes
-- the pair natively. A swap touches no frame the atom would reposition on its own, so the
-- pair still has to be placed by hand here.
--
-- Skipped when neither this presentation nor the one it replaces wanted a pane, which is
-- every swap this phase actually exercises, launcher and VPN alike, so the unchanged
-- behaviour the brief's own acceptance asks for costs nothing beyond the comparison below.
--
-- Adversarial review finding M1. The deferral that used to gate on whether THIS call was a
-- cold show is replaced with a gate on the window's own age. A swap landing within the
-- provider's own settle delay of this instance's last show still races that show's own
-- pending settle timer, which reads layout.companionWidth live and, now that this host
-- writes it honestly, would confirm rather than corrupt the shift, but the window frame this
-- function reads before that timer fires may not have settled yet, docs/PROBE-FINDINGS-
-- 2026-08-27.md's own note that a first show renders taller than its steady state, so this
-- still waits out whatever remains of that window before reading the frame itself. A swap
-- landing later than that, the overwhelming ordinary case, races nothing and runs at once.
-- The delay itself is asked of the instance through settleDelay() rather than carried here
-- as a second copy, the contract freeze phase collapsing what used to be a duplicated
-- literal into the one legacy.lua already needs for its own _settleFrames.
function obj:_applyPaneGeometry(p, outgoing)
  -- The unconditional cancel that used to open this function now sits at the top of _show
  -- instead, rider N2 of the geometry review, so every door clears a pending timer before
  -- either the cold or the swap path runs, not only the swap path this function itself is
  -- reached from.
  local hadPane = outgoing and outgoing.paneWidth
  if not p.paneWidth and not hadPane then return end
  local settleDelay = self._instance:settleDelay()
  local age = hs.timer.secondsSinceEpoch() - (self._lastShowAt or 0)
  if age < settleDelay then
    self._geometryTimer = hs.timer.doAfter(settleDelay - age, function()
      self._geometryTimer = nil
      self:_positionPane(p)
    end)
  else
    self:_positionPane(p)
  end
end

-- Delegates the actual placement to the provider's own reposition, contract freeze phase,
-- docs/BRIEF-CONTRACT-FREEZE.md, which is the method that replaces this host reaching into
-- the running application, hunting a window by its own title, and moving it directly.
-- reposition answers the same two frames this used to compute by hand and stamps the
-- provider's own paneFrames itself now, the field the atom's own click watcher reads for
-- every hit test, so a click on the new companion keeps testing honestly. What stays here
-- is only what this host itself owns, the guard that the presentation asking is still
-- current, and the report of the two frames onward to _onPositioned, the one function that
-- also fires on the atom's own native path, so this presentation's own
-- onPositioned is told through the identical route regardless of which of the two placed
-- the window, adversarial review finding M2.
--
-- Guarded against a stale call landing after a newer presentation already took over, which
-- the settle wait above makes possible, a present, push, or pop racing ahead of the timer
-- before it ever fires. Also guarded, adversarial review finding L1, against reaching a
-- provider that no longer believes itself active, the identical isActive() question
-- _settleFrames itself asks before running its own search, so a stale timer finds nothing
-- to move rather than moving a window that has already torn down.
function obj:_positionPane(p)
  if self:_current() ~= p then return end
  if not (self._instance and self._instance:isActive()) then return end
  local chooserFrame, companionFrame = self._instance:reposition(p.paneWidth)
  if chooserFrame then
    self:_onPositioned(chooserFrame, companionFrame)
  end
end

-- Where every geometry pass that has real frames to report converges, the atom's own
-- automatic firing on a cold show, docs/BRIEF-GEOMETRY.md decision one wired through
-- configure above, and _positionPane's own manual one on a swap alike, adversarial review
-- finding M2. Tells the current presentation's own onPositioned the two frames, so a pane
-- consumer draws into the real rect or hides when this presentation declares none. A
-- presentation with no onPositioned of its own is silently skipped, exactly as an ordinary
-- missing field already is everywhere else in this file. It once re anchored the docked
-- shortcut panel first, which the action bar inside the chooser's own canvas replaced.
function obj:_onPositioned(chooserFrame, companionFrame)
  local p = self:_current()
  if p and p.onPositioned then p.onPositioned(chooserFrame, companionFrame) end
end

-- Told once a presentation has become current, through present or push alike, right after
-- the stack is decided and before the window itself is touched. Phase three review finding
-- two, the presentation contract's own onPresent, for a plugin whose rows depend on an async
-- fetch nothing else has necessarily warmed, VPN among them. Never told on pop, which
-- restores a presentation rather than making it current through either door, decision two's
-- own three doors, present, push, and the hotkey, pop not being one of them.
function obj:_announce(p)
  if p.onPresent then p.onPresent() end
end

--- Stage:present(p) -> bool
--- Method
--- The hotkey door, decision one of the handoff brief. Always a fresh stack, p and nothing
--- below it, replacing whatever stack exists even while the window is already up, which is
--- what closes review finding four, a tool opened by its own hotkey no longer becomes a
--- level of whatever happened to be showing. Resets the highlight to row one either way.
--- Answers false and refuses when p is not a presentation this host can show.
---
--- Every discarded level except p itself, wherever it sits in the old stack, is told its own
--- onClose top down before it is dropped, decision six, closing finding three, a reopen of
--- p from any depth is a reshow rather than a close and must never fire p's own onClose over
--- being asked to show itself again.
---
--- Contract v2 decision two. p.enter, when declared, is called with one function, proceed,
--- INSTEAD of the stack mutation and the show below running immediately, so a tool whose own
--- rows depend on gathering something first, Processes' own scan among them, keeps whatever is
--- currently up exactly as it is until proceed actually runs. p without an enter of its own
--- keeps today's synchronous behaviour untouched, finish() below running on the same call. The
--- generation bumped before either branch is what lets a proceed that fires late, after the
--- person escaped or opened something else meanwhile, recognise itself as stale and do nothing,
--- and the fired flag is what makes a second call to the same proceed a no op rather than a
--- second show. The stage asks p.enter to call proceed and nothing more, it never learns why a
--- tool deferred or what it was waiting for.
function obj:present(p)
  if not isPresentation(p) then
    log.w("Stage present was given something that is not a presentation, name, rows, and onSelect are all required, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage present for '%s' arrived with no instance built, refusing", p.name))
    return false
  end

  self:_takeCycle()
  local myGen = self:_bumpEnterGen()
  local function finish()
    local wasShowing = self._instance:isShowing()
    -- Captured before _freshStack mutates the stack, so _show can tell whatever was current a
    -- moment ago that it lost the pane, adversarial review finding H2, alongside whatever
    -- onClose it may separately hear as a discarded level. Read fresh here rather than at the
    -- top of present, since a deferring p may run this closure long after the call that built
    -- it, by which point what is actually showing is the only honest answer.
    local outgoing = self:_current()
    self:_freshStack(p, self._stack)
    self:_announce(p)
    self:_show(p, wasShowing, outgoing)
  end
  if p.enter then
    local fired = false
    -- Review finding H4. Answers whether this call actually made p current, true only on the
    -- one call that ran finish, false on a second call and on a call that finds itself stale,
    -- so a presentation whose own enter queues several proceeds behind one scan can tell which
    -- of them, if any, was honoured rather than assuming its own call succeeded just because it
    -- was allowed to run.
    local function proceed()
      if fired or self._enterGen ~= myGen then return false end
      fired = true
      finish()
      return true
    end
    p.enter(proceed)
  else
    finish()
  end
  return true
end

--- Stage:push(p) -> bool
--- Method
--- The row selection door, decision one and two of the handoff brief. Stacks p on top of
--- whatever is already showing, the shape a launcher row choosing a presenting tool wants,
--- so drilling into VPN from the launcher is a swap into a window already up rather than a
--- close and a reopen. Tells nobody's onClose when it stacks, decision six, since stacking
--- discards nothing, it only adds a level. Answers false and refuses when p is not a
--- presentation this host can show.
---
--- A push that finds the window hidden has nothing to stack on top of, so it degrades to
--- present's own fresh stack, findings three, five, and eight together, closing finding
--- eight's own gap where this branch used to discard a stack in silence while present told
--- it. Pushing the presentation already on top is a reopen, the identical dedup present's
--- own reopen case keeps, and neither pushes a duplicate level nor fires anyone's onClose.
---
--- Contract v2 decision two, the identical deferral present's own docstring describes, on the
--- door that matters most for it, since this is what a launcher row choosing Processes actually
--- calls, decision three, "the launcher remains up and responsive until proceed runs, so
--- choosing processes feels like the list swapping once the scan lands rather than a window
--- blinking empty." A p with no enter of its own keeps today's synchronous behaviour.
function obj:push(p)
  if not isPresentation(p) then
    log.w("Stage push was given something that is not a presentation, name, rows, and onSelect are all required, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage push for '%s' arrived with no instance built, refusing", p.name))
    return false
  end

  self:_takeCycle()
  local myGen = self:_bumpEnterGen()
  local function finish()
    local wasShowing = self._instance:isShowing()
    -- Captured before the stack mutation below, for the identical reason present captures it,
    -- adversarial review finding H2. This is the door where telling it matters most, since push
    -- deliberately fires nobody's onClose when it stacks, decision six of the handoff brief, so
    -- without this the level being stacked under would have no other way to learn its pane is
    -- gone. Read fresh inside finish for the identical reason present's own copy is, a deferring
    -- p may run this long after the call that built it.
    local outgoing = self:_current()
    if not wasShowing then
      self:_freshStack(p, self._stack)
    elseif self:_current() ~= p then
      self._stack[#self._stack + 1] = p
    end
    self:_announce(p)
    self:_show(p, wasShowing, outgoing)
  end
  if p.enter then
    local fired = false
    -- Review finding H4. Answers whether this call actually made p current, true only on the
    -- one call that ran finish, false on a second call and on a call that finds itself stale,
    -- so a presentation whose own enter queues several proceeds behind one scan can tell which
    -- of them, if any, was honoured rather than assuming its own call succeeded just because it
    -- was allowed to run.
    local function proceed()
      if fired or self._enterGen ~= myGen then return false end
      fired = true
      finish()
      return true
    end
    p.enter(proceed)
  else
    finish()
  end
  return true
end

--- Stage:cycle(p, opts) -> bool
--- Method
--- The cycle door, see the header. opts.keyCode is the code of the key that called it, so a press
--- of that key while the list is up steps rather than completing it. A first press shows p bare
--- as a fresh stack and steps once, a press while p is the cycle on screen steps again, and every
--- press arms the idle completion afresh. A presentation that defers through enter cannot be
--- stepped before it shows, so it is presented in full instead, as its open key would.
function obj:cycle(p, opts)
  if not isPresentation(p) then
    log.w("Stage cycle was given something that is not a presentation, name, rows, and onSelect are all required, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage cycle for '%s' arrived with no instance built, refusing", p.name))
    return false
  end
  local c = self._cycle
  if c and c.p == p and self:_current() == p and self._instance:isShowing() then
    self:_stepCycle()
    return true
  end
  if p.enter then return self:present(p) end
  self._cycleNext = { p = p, keyCode = (opts or {}).keyCode }
  self:present(p)
  self:_stepCycle()
  return true
end

-- Every door but cycle ends any cycle in progress, and cycle hands its own over through
-- _cycleNext, so the present it calls is the one door that starts one.
function obj:_takeCycle()
  local nextCycle = self._cycleNext
  self._cycleNext = nil
  self:_disarmCycle()
  self._cycle = nextCycle
end

function obj:_endCycle()
  self._cycleNext = nil
  self:_disarmCycle()
  self._cycle = nil
end

function obj:_disarmCycle()
  if self._cycleTimer then
    self._cycleTimer:stop()
    self._cycleTimer = nil
  end
end

-- One row down, wrapping, through the provider's own move, marked as the cycle's so _onHighlight
-- does not take it for the person's, then the idle completion armed afresh.
function obj:_stepCycle()
  local c = self._cycle
  if not c then return end
  c.stepping = true
  local ok, err = pcall(function() self._instance:selectNext() end)
  c.stepping = false
  if not ok then log.e("Stage cycle could not step, " .. tostring(err)) end
  self:_disarmCycle()
  self._cycleTimer = hs.timer.doAfter(CYCLE_IDLE, function()
    self._cycleTimer = nil
    if self._cycle == c and self:_current() == c.p and self._instance:isShowing() then
      self._instance:insertSelected()
    end
  end)
end

-- A key down over a list shown bare that the list itself does not read. The cycle's own key steps.
-- Any other key completes the list on the highlighted row and is posted again once the list is
-- gone, built afresh after the completion rather than let through, since the press already
-- carries the characters of whatever the completion may have changed, a keyboard layout among
-- them, and its own key up arrives as it would. Answers true, the key claimed, while a cycle runs.
function obj:_onBareKey(ev)
  local c = self._cycle
  if not c then return false end
  local code = ev:getKeyCode()
  if code == c.keyCode then
    self:_stepCycle()
    return true
  end
  local mods = {}
  for flag, on in pairs(ev:getFlags() or {}) do
    if on and flag ~= "fn" then mods[#mods + 1] = flag end
  end
  self:_disarmCycle()
  self._instance:insertSelected()
  if self._retypeTimer then self._retypeTimer:stop() end
  self._retypeTimer = hs.timer.doAfter(RETYPE_DELAY, function()
    self._retypeTimer = nil
    -- A completion that answered a child keeps the window up, and the key is not typed into it.
    if self:isShowing() then return end
    hs.eventtap.event.newKeyEvent(mods, code, true):post()
  end)
  return true
end

--- Stage:pop() -> bool
--- Method
--- Back one presentation, restoring the one below with an empty query and the highlight at
--- row one, answering false when the stack holds one or none, the case that leaves backspace
--- an ordinary press. Tells only the one leaving its own onClose, decision six, never the one
--- it lands back on, since that one is not hiding, it is what is left showing, and never
--- calls onPresent either, restoring is not becoming current through present or push.
---
--- Routed through the same _show every other door already uses, adversarial review finding
--- H1. Before this fix pop rebuilt the field and the rows by hand and stopped there, so a
--- presentation the stack is landing back on that differs in row count or in pane from the
--- one that just left kept whatever the departing level last left the window built for, a
--- caffeinate exit leaving a ten row list rendered into a two row window until some later
--- present or push happened to self correct it. leaving is handed to _show as the outgoing
--- presentation, finding H2, so a pane it drew is told to hide on the same path present and
--- push already use, and the one leaving still hears its own onClose first, exactly as
--- before, since that is a real dismissal for it and _show's own outgoing notice is not a
--- substitute for it, the two are told for different reasons and neither replaces the other.
---
--- Bumps the enter generation, contract v2 decision two, only once it is known there is
--- something real to pop, since answering false here means nothing about the stage actually
--- moved on. A proceed some earlier present or push is still waiting on reads this bump and
--- drops itself rather than showing a presentation Backspace has since stepped away from.
function obj:pop()
  if #self._stack <= 1 then return false end
  self:_takeCycle()
  self:_bumpEnterGen()
  local leaving = table.remove(self._stack)
  if leaving.onClose then leaving.onClose() end
  local below = self:_current()
  if self._instance then
    self:_show(below, self._instance:isShowing(), leaving)
  end
  return true
end

-- Where the first row whose item carries every field of match stands in the list as the
-- provider shows it now, or nil. Under a typed query the shown order is the ranked one, and
-- the stage finds it by running the current rows through the facade's own rank with the
-- instance's own matcher, the same module and the same three inputs the provider ranks with,
-- so the index is the one on screen without the provider having to hand its rows out. A
-- facade with no rank can only answer for an order it already knows, an empty field or a
-- level that stood the matcher down.
--
-- The rows and the ranking are a plugin's code and a matcher, called a second time here, so
-- both run under pcall the way the provider's own safeCall runs them. A raise is logged and
-- answers nil, which leaves the row number standing, rather than unwinding out of a refresh
-- into whatever background tick asked for the redraw and stopping it.
function obj:_shownIndexWhere(match)
  local p = self:_current()
  if not (p and self._instance and type(match) == "table" and next(match) ~= nil) then
    return nil
  end
  local query = self:query()
  local ok, rows = pcall(self._rows, self, query)
  if not ok then
    log.e("Stage could not rebuild the rows to hold the highlight, " .. tostring(rows))
    return nil
  end
  rows = rows or {}
  -- The search beside the matcher is read too, since a searchText decides what the rows are
  -- ranked by and a rowLimit which rows are shown at all, an empty field included, so a row
  -- past the limit is not on screen and must not be found here.
  local matcher, search = self._instance:matcher()
  local rank = self._chooser and self._chooser.rank
  if rank and rank.apply then
    local ranked
    ok, ranked = pcall(rank.apply, rows, query, matcher, search)
    if not ok then
      log.e("Stage could not rank the rows to hold the highlight, " .. tostring(ranked))
      return nil
    end
    rows = ranked
  elseif query ~= "" and type(matcher) == "function" then
    return nil
  end
  for index, row in ipairs(rows) do
    local item = type(row) == "table" and row.item or nil
    local all = type(item) == "table"
    if all then
      for k, v in pairs(match) do
        if item[k] ~= v then all = false break end
      end
    end
    if all then return index end
  end
  return nil
end

-- The one place the highlight is held on the same item across a repaint that keeps the person
-- on the same level, a stay, a refresh and an async redraw alike. The provider keeps the row
-- number on its own, which is the item the person chose only while nothing above it moved. A
-- permission line landing above, an Apply row appearing, or a typed query ranking the rebuilt
-- rows differently would each leave the highlight on a different item, and Enter would then act
-- on something the person never chose. So an item that states a key is found again by that key
-- after the rows are rebuilt. With no key, or a key that is gone, the row number stands, which
-- is exactly what every level without keys had before.
function obj:_repaintHolding(key)
  self._instance:refresh(false)
  if key == nil then return end
  local index = self:_shownIndexWhere({ key = key })
  if index and index ~= self._instance:selectedRow() then self._instance:selectRow(index) end
end

--- Stage:selectWhere(match) -> bool
--- Method
--- Moves the highlight to the first row whose item carries every field of match with an equal
--- value, answering whether one was found. The row is found in the list as currently filtered
--- and ranked, so it works under a typed query too. For the stage's own hold by key and for a
--- resumed highlight, never for a plugin, since the highlight belongs to the person.
function obj:selectWhere(match)
  local index = self:_shownIndexWhere(match)
  if not index then return false end
  self._instance:selectRow(index)
  return true
end

--- Stage:presentAt(p, path, highlight) -> bool
--- Method
--- Presents p as a fresh stack the way present does, then walks path inside it, each step an
--- item handed to the current level's own onSelect exactly as choosing a row would, stacking
--- every child that comes back, and shows only the deepest level reached, with the highlight on
--- the row matching highlight when there is one. The levels are real, so Back and Backspace
--- leave them as if the person had walked down by hand. A step whose onSelect answers no child
--- stops the walk where it is, so a stale path degrades to the deepest level still reachable.
--- For the composition root resuming a place after a reload, from a note the tool wrote about
--- itself, so a path is only ever made of steps that tool's own onSelect answers with a child
--- and never one that completes. A p that defers through enter is presented plainly and the
--- path is skipped, since the walk cannot wait on it.
function obj:presentAt(p, path, highlight)
  if p and p.enter then return self:present(p) end
  if not isPresentation(p) then
    log.w("Stage presentAt was given something that is not a presentation, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage presentAt for '%s' arrived with no instance built, refusing", p.name))
    return false
  end
  self:_takeCycle()
  self:_bumpEnterGen()
  local levels = { p }
  for _, step in ipairs(path or {}) do
    local top = levels[#levels]
    local ok, child = pcall(top.onSelect, step)
    if ok and type(child) == "table" and (child.name == nil or child.name == "") then
      child.name = top.name
    end
    if not (ok and isPresentation(child)) or child.enter then break end
    levels[#levels + 1] = child
  end
  local wasShowing = self._instance:isShowing()
  local outgoing = self:_current()
  self:_freshStack(p, self._stack)
  for i = 2, #levels do self._stack[i] = levels[i] end
  local top = levels[#levels]
  self:_announce(top)
  self:_show(top, wasShowing, outgoing)
  if highlight then self:selectWhere(highlight) end
  return true
end

--- Stage:hide()
--- Method
--- Hide the window and clear the stack, unconditionally, so a fresh present afterward always
--- starts a fresh stack whatever state the last one was left in. Tells every presentation
--- still on the stack its own onClose, top down, decision six, the same widened notice
--- _onClose gives the atom's own teardown. The two can run for the same hide, since
--- self._instance:hide() below fires the atom's own teardown synchronously when the window
--- was genuinely showing, which already empties the stack through _onClose before this
--- function's own closeStack call ever runs, leaving nothing left to walk and making the
--- second call harmless rather than a second notice, the identical reasoning phase two's own
--- version of this method already relied on for clearing the stack twice.
---
--- Bumps the enter generation unconditionally, contract v2 decision two, the same "the stage
--- moved on" signal pop gives, so a proceed still waiting on an earlier present or push finds
--- itself stale the moment a person escapes out from under it, rather than showing a
--- presentation over a window that was just asked to clear.
function obj:hide()
  self:_endCycle()
  self:_bumpEnterGen()
  if self._geometryTimer then
    self._geometryTimer:stop()
    self._geometryTimer = nil
  end
  if self._instance then self._instance:hide() end
  -- The atom's own teardown above has usually emptied the stack and told the observers already.
  -- A stack still standing here belonged to a window that was not up, so it is closed and the
  -- observers told now, and only once either way.
  if #self._stack > 0 then
    closeStack(self._stack)
    self._stack = {}
    self:_notifyClosed()
  end
end

--- Stage:refresh(resetRow, force)
--- Method
--- Re run the current presentation's rows, keeping the highlight by default. resetRow mirrors
--- the atom's own Chooser:refresh(resetRow), for a caller that swapped what the field means
--- and wants the highlight back at the top. A no op while nothing is showing, unless force is
--- true.
---
--- force exists for exactly one caller, Launcher:show's own seeded query rebuild, finding
--- three of the phase two adversarial review. The old code called instance:refresh(true)
--- straight, with no visibility guard at all, right after instance:show(), and
--- host/launcher/init.lua's own comment on that call site states why, hs.chooser:isVisible()
--- can still read false for a moment after show returns, so gating this call on isShowing
--- immediately after a show is a guard the old code never had and can silently drop the
--- rebuild that makes a seeded query mean anything. Every other caller wants the ordinary
--- guarded behaviour, a query source redrawing late through Launcher:refresh should still be a
--- no op while closed, so the guard stays the default and force is how one caller opts out of
--- it rather than the guard being removed for everybody.
---
--- Keeping the highlight means keeping it on the same item, not the same row number. An async
--- redraw lands while the person is looking at the list, so a row inserted above the one they
--- are on would otherwise slide the highlight onto a neighbour, and the item under it is read
--- before the rebuild and found again after through _repaintHolding, by its key when it states
--- one.
function obj:refresh(resetRow, force)
  if not (self._instance and (force or self._instance:isShowing())) then return end
  if resetRow then
    self._instance:refresh(resetRow)
    return
  end
  local held = self._instance:selectedItem()
  self:_repaintHolding(type(held) == "table" and held.key or nil)
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

--- Stage:labels() -> table or nil
--- Method
--- The words the level on screen gives its primary and its secondary for the highlighted row, a
--- table with primary and secondary strings, either one absent, or nil when nothing is showing,
--- the level declares no labels, or its labels raised or answered something else. A registered
--- presentation's labels is the member the registrar resolved, and a child presentation hands
--- its own function, so both are read the same way. Asked live, so the action bar can count
--- what is checked. A raise is logged and answers nil, so the bar falls back to the declared
--- descriptions rather than losing its words.
function obj:labels()
  local p = self:_current()
  if not p or type(p.labels) ~= "function" then return nil end
  local ok, answer = pcall(p.labels, self._highlighted)
  if not ok then
    log.w("Stage labels of '" .. tostring(p.name) .. "' raised, " .. tostring(answer))
    return nil
  end
  return type(answer) == "table" and answer or nil
end

--- Stage:toggleKeys()
--- Method
--- Opens or closes the key panel above the action bar of the one instance, what the shared
--- showKeys list verb runs. A provider that draws no action bar has no key panel and is not
--- asked, so this does nothing there.
function obj:toggleKeys()
  local instance = self._instance
  if instance and type(instance.toggleKeys) == "function" then instance:toggleKeys() end
end

--- Stage:closeKeys()
--- Method
--- Closes the key panel above the action bar of the one instance, which every list key that acts
--- does first. A provider with no key panel is not asked.
function obj:closeKeys()
  local instance = self._instance
  if instance and type(instance.closeKeys) == "function" then instance:closeKeys() end
end

--- Stage:depth() -> number
--- Method
--- How many levels are on the stack, zero when nothing is presented. A level above the first is
--- one Backspace on an empty field leaves, which is what the action bar's key panel asks.
function obj:depth()
  return #(self._stack or {})
end

--- Stage:isCurrent(token) -> bool
--- Method
--- Whether token, a presentation table, is the one currently on top of the stack, table
--- identity rather than name. Review finding M2, rework, docs/BRIEF-CONTRACT-V3.md. A
--- child's own name is deliberately its parent's, decision two, so two levels of the same
--- tool cannot be told apart by name, and an async answer that belongs to one specific level
--- needs a question sharper than "is this tool showing at any depth". The presentation table
--- itself, or whatever a plugin closed over while building one, is that sharper question,
--- since nothing else about a presentation is guaranteed unique. token nil always answers
--- false rather than matching an empty stack, which the bare == below would otherwise do
--- were _current() and token both nil at once.
function obj:isCurrent(token)
  return token ~= nil and self:_current() == token
end

--- Stage:world() -> the covered app, number
--- Method
--- The app this stack covers and the id of this open. The two halves are captured on
--- different terms, phase three review finding five, since decision one made a present over
--- a visible window a normal and expected thing and the old single invariant, one capture per
--- fresh stack, stopped holding for both halves at once. The covered app is tied to the
--- window's own appearance, _captureCoveredApp, since a stack replaced while the window stays
--- up still covers the same app that window originally opened over, focus never having had
--- anywhere to go. The open id is tied to the stack instead, _bumpOpenId, advancing on every
--- fresh stack regardless of visibility, so a consumer keying a cache off this id, the reason
--- BRIEF-STAGE.md decision seven wants it captured at all, never serves an answer that
--- belongs to whatever the stack held before a replacement. Nil before the first capture.
function obj:world()
  return self._coveredApp, self._openId
end

-- Contract v2 decision one. A presentation's own matcher field survives the registrar as a
-- plain value, false, a string, or nil, exactly what paneWidth and rowCount already are, the
-- registrar having already refused any string that does not name a strategy this host's own
-- Chooser factory exports, lib/registrar.lua's own check against deps.matchers. false is
-- honoured outright, the supplier owns filtering, the same meaning it already carries at
-- construction. A string is looked up against self._chooser.matchers, the identical table the
-- composition root already resolves this same word against for every unmigrated consumer,
-- root/compose.lua's own ambientServices.matcher. nil, and a string that somehow still failed
-- to resolve even though the registrar already checked it, both answer _defaultMatcher, the
-- module wide default this host itself inherited at configure, so a presentation naming
-- nothing unusual keeps this host behaving exactly as it always has.
function obj:_resolveMatcher(matcher)
  if matcher == false then return false end
  if type(matcher) == "string" then
    local fn = self._chooser.matchers and self._chooser.matchers[matcher]
    if fn then return fn end
  end
  return self._defaultMatcher
end

-- How a presentation asks its rows to be searched beside the matcher, its searchText and its
-- rowLimit, as the table lib/chooser/rank.lua's M.apply reads, or nil when it declares neither.
-- A registered presentation's searchText is already the function the registrar resolved, and
-- a child presentation hands its own function, so both are read the same way here. A value
-- of the wrong type is passed along as it is, since the engine reads it as absent.
function obj:_searchOf(p)
  if p.searchText == nil and p.rowLimit == nil then return nil end
  return { searchText = p.searchText, rowLimit = p.rowLimit }
end

--- Stage:paneAnchor(chooserFrame, companionFrame) -> table
--- Method
--- The one true copy of the anchor arithmetic three plugins carried a literal copy of before
--- this phase, decision three of the geometry brief, consumer map sections 7.3 and 9.11,
--- plugins/clipboard/manager/ui.lua:1180, plugins/filesearch/chooser.lua:454,
--- plugins/processes/chooser.lua:347. Spans the chooser and its companion so a panel docked
--- beneath sits full width under both rather than stopping short under the list alone.
--- Answers the plain chooser frame when there is no companion, exactly as the three copies
--- already do, so a plugin migrating onto this host in phase five drops its own copy in
--- favour of this one call with no change in what its own docked panel receives. Pure
--- arithmetic, kept a method only for the same reason every other member of this host's
--- public api is one, a plugin that already holds this host through its own needs.siblings
--- reaches it the same way it reaches present and push.
function obj:paneAnchor(chooserFrame, companionFrame)
  if not companionFrame then return chooserFrame end
  return {
    x = chooserFrame.x, y = chooserFrame.y, h = chooserFrame.h,
    w = (companionFrame.x + companionFrame.w) - chooserFrame.x,
  }
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
---
--- Review finding H6. Guarded on the stack being non empty rather than on isShowing, and the
--- two are not the same question here. legacy.lua's own show sequence fires config.onPositioned
--- BEFORE self.chooser:show(...) ever runs, so a presentation's own seed call, docking its pane
--- and asking for the row already on it, lands while isShowing() still answers false, and a
--- guard borrowed from selectedRow's own would have answered nil for the one call that most
--- needs the real row. The stack is populated by _freshStack before _show ever runs, so it is
--- already true by the time any presentation's own code could possibly ask, and it is false
--- exactly when hide has cleared it and nothing is current, which is the one case worth
--- refusing, the underlying Chooser:selectedItem() answering whatever was highlighted before a
--- hide the same way Chooser:selectedRow() does, hs.chooser restoring rather than forgetting a
--- selection across one. This is also what closes the cache every one of the three trickle
--- migrations built, host/compose.lua's own stageSelectedItem handing this out so a plugin
--- reads the widget live instead of a module local a poll interval behind it.
function obj:selectedItem()
  if #self._stack == 0 then return nil end
  return self._instance and self._instance:selectedItem() or nil
end

--- Stage:selectedRow() -> number or nil
--- Method
--- The highlighted row NUMBER on the live instance, or nil, the plain public counterpart
--- Chooser:selectedRow() already answers for ActionPanel. Added for the menu search cache,
--- docs/BRIEF-MENUSEARCH-CACHE.md, whose own background correction has to know whether a
--- person has moved off row one before it is safe to redraw without disturbing a considered
--- position, a row number being the whole question rather than the item sitting on it.
---
--- Guarded on isShowing rather than only on the instance existing, second review pass of the
--- cache build, finding N1. hs.chooser keeps its own selected row across a hide, restoring
--- it only on the next show, lib/chooser/providers/legacy.lua's own reason for resetting the
--- highlight there, so an unguarded read answers a row that belonged to whatever was on
--- screen before the window last closed rather than nothing. A consumer asking what the
--- highlight is doing while nothing is showing almost never means "what was it last", so nil
--- is the honest answer for every caller of this method at once rather than a fix each one
--- would otherwise have to invent for itself.
function obj:selectedRow()
  if not self:isShowing() then return nil end
  return self._instance:selectedRow()
end

--- Stage:query() -> string
--- Method
--- The current field text on the live instance, "" when there is none. The same addition as
--- setQuery and for the same reason, the launcher's own currentQuery reads what is actually
--- typed rather than only ever writing to it.
function obj:query()
  return self._instance and self._instance:query() or ""
end

--- Stage:textBudget() -> number
--- Method
--- The pixel room a row's text has, title and subtitle alike, on the live instance, 0 before
--- one exists. Found during the trickle migrations, FileSearch's own fitDir needing this and
--- Chooser:textWidth below to elide a long path against the room the row actually has, a
--- measurement it used to ask its own instance for directly and now has no instance left to
--- ask, the same addition as setQuery and for the same reason.
function obj:textBudget()
  return self._instance and self._instance:textBudget() or 0
end

--- Stage:textWidth(str, which) -> number
--- Method
--- How wide that string renders in a row, in pixels, on the live instance, 0 before one
--- exists. Found alongside textBudget above, for the identical caller.
function obj:textWidth(str, which)
  return self._instance and self._instance:textWidth(str, which) or 0
end

-- Everything below installs at Chooser.new's own config and reads only the stack above,
-- through _current, so every one of these behaves correctly however deep the stack is,
-- launcher to tool being depth two and a plugin's own child presentations, contract v3,
-- growing it further from there.

function obj:_rows(query)
  local p = self:_current()
  if not p or not p.rows then return {} end
  local rows = p.rows(query) or {}
  -- THE ONE PLACE a presentation's rows learn who owns their icon keys. p.name is the owning
  -- plugin, a child presentation taking its parent's name when it declares none, so a level a
  -- plugin pushes is read against that same plugin's manifest icons with nothing more to know.
  -- No picture is drawn here, the chooser draws it at paint so it follows the light and dark halves.
  if self._stampIcons then return self._stampIcons(rows, p.name) end
  return rows
end

-- Contract v3's own seam. A presentation whose onSelect already ran once inside _intercept
-- below, and did not result in a genuine push, leaves _selectHandled true for exactly the
-- one subsequent call this is, the atom's own real completion firing config.onSelect the
-- moment intercept has answered false and Return, insertSelected, or a click has been let
-- through for real. Consuming the flag here rather than checking it inside _intercept is
-- what keeps a STALE true from ever surviving into some later, unrelated row, since this is
-- the only place that clears it and it is asked on the very next call this host receives
-- after _intercept sets it. When a child was pushed instead, this function is never reached
-- at all for that keypress, legacy.lua's own key watcher swallowing Return outright once
-- intercept answers true, so the flag is never even written down that path and needs no
-- clearing here for it.
function obj:_onSelect(item)
  if self._selectHandled then
    self._selectHandled = false
    return
  end
  local p = self:_current()
  if p and p.onSelect then p.onSelect(item) end
end

-- Asked before a row is allowed to complete. Review findings H1 and H2, rework. A disabled
-- row answers true and does absolutely nothing, before anything else in this chain, no
-- presentation intercept, no onSelect probe, no flag, no push, matching the guard
-- legacy.lua's own click path already kept at its own call site. This has to live here
-- rather than at each of legacy.lua's three callers, since it is the stage's own contract v3
-- addition, the onSelect probe just below, that turned a merely unused disabled selection
-- into one that runs a plugin's own onSelect and can drill, and disabled rows becoming this
-- host's own business is what keeps that fix in one place rather than three. enabled arrives
-- as legacy.lua's own second argument to config.intercept now, nil for a caller that never
-- learned a row's state, which this treats the same as true, so an unmigrated caller loses
-- nothing.
--
-- Failing that, the current presentation's own intercept answers next, the plain mutation
-- case contract v3 decision three still reserves for it, a row that acts on the list it is
-- on and stands. Its answer, true or the string "stay", is returned exactly as given rather
-- than normalized to plain true, since legacy.lua's own Chooser:_intercept is the one place
-- that actually decides whether to reset the highlight or hold it, and can only tell the two
-- cases apart if the string survives the trip through here unchanged. true means the row
-- swapped to a different list and the highlight resets to the top, "stay" means the row
-- mutated the same list it already stood on and the highlight holds on the row just chosen.
--
-- Contract v3, docs/BRIEF-CONTRACT-V3.md. Failing both, the current presentation's own
-- onSelect is asked here, before Return is ever let through, so this is the one place able
-- to answer the promise decision one makes, that a row drilling into a level of its own
-- swaps the list in place with no window ever closing. A presentation table answered back
-- is a child, not a completion, so it is pushed onto the stack the identical way
-- root/compose.lua's own rowIntercept already pushes a tool chosen from a launcher row, name
-- filled in from the parent's own when the child names none itself, decision two, and this
-- answers true, the atom then rebuilding the shared window from the top exactly as its own
-- contract for intercept already promises.
--
-- Review finding M1, rework. _selectHandled is now set on every path through this branch
-- that does NOT end in a genuine push, a nil answer or a child push's own refusal alike,
-- rather than only the nil case, since both left onSelect already run once and both are
-- about to see it let through to a real completion that would otherwise run it a second
-- time. Only the true push, which answers true here and swallows the row for good, skips
-- setting it.
function obj:_intercept(item, enabled)
  if enabled == false then return true end
  local p = self:_current()
  if p and p.intercept then
    local answer = p.intercept(item)
    -- "stay" alone holds the highlight by row number, which is the row the person chose only
    -- while the rows above it stay put. A choice that adds or removes a row above, a pending
    -- line appearing at the top of a page, would leave the highlight one row off. An item that
    -- states its own key is held by that key instead through _repaintHolding, the same hold a
    -- refresh and an async redraw get, and the atom's own rebuild after this keeps that row.
    if answer == "stay" and type(item) == "table" and item.key ~= nil and self._instance then
      self:_repaintHolding(item.key)
    end
    if answer then return answer end
  end
  if p and p.onSelect then
    local child = p.onSelect(item)
    if type(child) == "table" and (child.name == nil or child.name == "") then
      child.name = p.name
    end
    if child ~= nil and self:push(child) then return true end
    self._selectHandled = true
  end
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
  -- A highlight the cycle did not move was moved by the person, an arrow or the pointer, so the
  -- list stops completing by itself and waits for them.
  if self._cycle and not self._cycle.stepping then self:_disarmCycle() end
  -- Remembered for labels below. The action panel answers the instance's highlight for itself
  -- while it is open and never reaches here, so this stays the row the panel was opened over.
  self._highlighted = item
  local p = self:_current()
  if p and p.onHighlight then p.onHighlight(item) end
end

-- A trackpad or a wheel scrolled over the companion rect, which a canvas cannot report for
-- itself, lib/chooser/providers/legacy.lua's own reason this exists at all. Found during the
-- trickle migrations, filesearch and the clipboard both already wiring one directly into
-- their own retired Chooser.new calls. Routed the identical way _onHighlight is, the current
-- presentation's own onScroll answering first and a presentation with none simply never
-- asked, since scrolling a pane that is not currently drawn would move nothing anyway.
function obj:_onScroll(points)
  local p = self:_current()
  if p and p.onScroll then p.onScroll(points) end
end

-- A canvas row right clicked, which a native chooser row cannot answer for itself, the reason
-- this exists at all. Routed the identical way _onScroll is, clipboard's own presentation
-- being the only consumer today.
function obj:_onRightClick(item, row)
  local p = self:_current()
  if p and p.onRightClick then p.onRightClick(item, row) end
end

-- Fired for any teardown, a completed selection, escape, a click away, or a programmatic
-- hide, never for a swap or a push between presentations while the window stays open, since
-- neither ever tears the atom down at all. Forgets the remembered highlight first, since that
-- belongs to this host regardless of what was showing, then tells every
-- presentation still on the stack its own onClose, top down, decision six of the handoff
-- brief, closing review finding twelve, which used to tell only the one on top and leave
-- every level below it silently discarded. Then clears the whole stack, so the next present
-- or push anywhere starts fresh.
function obj:_onClose()
  -- Held shut for the one call that is not a real dismissal, _applyRowCount's own internal
  -- hide, which resizes the same presentation that is still current and about to be reshown
  -- on the very next line, never a level actually leaving the stack.
  if self._suppressClose then return end
  -- Review finding H3. The atom's own teardown is the one path a person actually takes,
  -- escape, a completed selection, or a click away, and until this fix it was the one door
  -- that did not bump the generation, so a proceed a deferring presentation is still waiting
  -- on when any of those happens found the stage's own book still open and showed itself
  -- over whatever the person went back to, seconds after they dismissed it. Placed after the
  -- suppress guard on purpose, since _applyRowCount's own internal hide is the one call that
  -- must not count as the stage moving on, the presentation it resizes being the one about to
  -- be reshown on the very next line rather than one actually leaving.
  self:_bumpEnterGen()
  self:_endCycle()
  self._highlighted = nil
  local had = #self._stack > 0
  closeStack(self._stack)
  self._stack = {}
  if had then self:_notifyClosed() end
end

--- Stage:onClosed(fn)
--- Method
--- Adds fn to the functions told, with no arguments, each time the stage goes away, escape, a
--- click away, a completed selection or a hide, once per close and after every presentation on
--- the stack has heard its own onClose. A pop, a push and a present over a window already up are
--- not a close, since the stage is still there. For the composition root, which wants to act
--- once a person is done with the stage whatever was showing, without any presentation having
--- to know it. A presentation still uses its own onClose. An observer that raises is logged and
--- the rest are still told.
function obj:onClosed(fn)
  if type(fn) ~= "function" then return end
  self._closedObservers = self._closedObservers or {}
  self._closedObservers[#self._closedObservers + 1] = fn
end

function obj:_notifyClosed()
  for _, fn in ipairs(self._closedObservers or {}) do
    local ok, err = pcall(fn)
    if not ok then log.e("Stage close observer failed, " .. tostring(err)) end
  end
end

return obj
