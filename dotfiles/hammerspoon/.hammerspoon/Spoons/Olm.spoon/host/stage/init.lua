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
--- docked shortcut panel, and the poll interval are all atom level policy this host owns for
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
--- which is also what re anchors the docked shortcut panel now, finding M2, using paneAnchor,
--- the one true copy of the anchor arithmetic three plugins still carry their own copy of,
--- consumer map sections 7.3 and 9.11, built for phase five's migrations to call rather than
--- inherit a fourth copy. The presentation a transition leaves behind is told its own
--- onPositioned with nil frames before the incoming one is given real ones, finding H2, on
--- every door, present, push, and pop, so a pane consumer never sits drawn beside a window
--- that already moved past it. pop now routes through the same _show every other door does,
--- finding H1, so a two row window from caffeinate cannot survive a Backspace back into a ten
--- row list, and its own docstring says so.

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

-- Mirrors lib/chooser/providers/native.lua's own hardcoded settle delay, the 0.03 seconds
-- _settleFrames waits after Chooser:show returns before it corrects the window's real
-- position. No accessor exposes that number, so this is the one duplicated constant the
-- geometry rework accepts, the alternative being to reach into the atom's own private
-- settleTimer field to ask it directly, which would trade one small duplication for a worse
-- one. Used by _applyPaneGeometry to gate a manual pane placement on the window's own age
-- rather than on the shape of the call that triggered it, adversarial review finding M1, a
-- swap landing inside this window of a recent cold show still races that show's own pending
-- settle correction, which reads layout.companionWidth live and would otherwise place the
-- window against a frame that has not settled yet.
local ATOM_SETTLE_DELAY = 0.03

-- Injected via configure
obj._chooser = nil          -- the Chooser factory (has .new), the one door this host builds through
obj._theme = nil
obj._panelOnPositioned = nil -- the docked shortcut panel triple, fixed for the life of the instance
obj._panelOnActivity = nil
obj._panelOnClose = nil

-- Owned state
obj._instance = nil         -- the one Chooser instance, built once and never rebuilt
obj.surface = nil           -- the one nav adapter, delegated to whichever presentation is current
obj._stack = nil            -- ordered presentations, the last entry is the one showing
obj._openId = nil           -- bumped on every fresh stack, see _bumpOpenId and world()
obj._coveredApp = nil       -- tied to the window's own appearance, see _captureCoveredApp
obj._rowCount = nil          -- the row count the window is currently built for, seeded at configure
obj._defaultRowCount = nil   -- the atom's own default, read once at configure, never mutated after
obj._geometryTimer = nil     -- held so a pending pane settle cannot be collected before it fires, see _applyPaneGeometry
obj._suppressClose = false   -- true only while _applyRowCount's own internal hide is in flight, see _onClose
obj._lastShowAt = nil        -- hs.timer.secondsSinceEpoch() at the last real show(), see _applyPaneGeometry

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
--- opts.onPositioned, opts.onActivity, opts.onClose
---                     the docked shortcut panel triple, fixed atom level policy rather than
---                     something a presentation carries. Phase two hands this the launcher's
---                     own panel, the only one that exists yet.
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
    placeholder = CONSTRUCTION_PLACEHOLDER,
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
    -- Adversarial review finding M2. Routed through this host's own _onPositioned rather
    -- than handed self._panelOnPositioned directly, so the docked panel is re anchored
    -- through the identical function a manual placement uses on a swap, _onPositioned
    -- being the one place that knows to span the pair through paneAnchor rather than
    -- anchor to the list alone. A presentation with no pane still reaches the panel
    -- exactly as before, paneAnchor answers the bare chooser frame back unchanged when
    -- there is no companion to span.
    onPositioned = function(chooserFrame, companionFrame) self:_onPositioned(chooserFrame, companionFrame) end,
    onActivity = self._panelOnActivity,
    onClose = function() self:_onClose() end,
  })

  -- Decision two of the geometry brief. The row count the window is currently built for is
  -- read straight off the fresh instance's own layout rather than assumed, so this can never
  -- drift from whatever lib/chooser/providers/native.lua actually ships as its own default,
  -- and _defaultRowCount is what a presentation naming no rowCount of its own is asking to
  -- return to. Read once, right here, before setRows is ever called on this instance, since
  -- that is the only moment layout.rowCount still holds the atom's own answer rather than
  -- something this host already asked it to become.
  self._rowCount = self._instance.layout.rowCount
  self._defaultRowCount = self._rowCount

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
  -- a settle timer left pending by an EARLIER cold show reads this field live when it finally
  -- fires, docs/PROBE-FINDINGS-2026-08-27.md section C3, so writing it here keeps that timer
  -- honest too rather than only the show this call might itself trigger. A presentation
  -- naming no paneWidth writes nil, which the atom's own _resolveCompanionWidth already
  -- treats as no pane, so the window centres itself alone with nothing else asked.
  self._instance.layout.companionWidth = p.paneWidth
  -- Decision two of the geometry brief. A row count change takes the one resize path that
  -- exists, hide, rows(n), show, which the probe found applies on the next show of the same
  -- instance, docs/PROBE-FINDINGS-2026-08-27.md section C2. _applyRowCount below drives that
  -- cycle itself when it is needed and answers whether it did, since a window it already
  -- reshowed for a resize must not also run the ordinary swap or cold show path just below on
  -- top of that.
  local resized = self:_applyRowCount(p)
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
  local desired = p.rowCount or self._defaultRowCount
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
-- cold show is replaced with a gate on the window's own age. A swap landing within
-- ATOM_SETTLE_DELAY of this instance's last show still races that show's own pending settle
-- timer, which reads layout.companionWidth live and, now that this host writes it honestly,
-- would confirm rather than corrupt the shift, but the window frame this function reads
-- before that timer fires may not have settled yet, docs/PROBE-FINDINGS-2026-08-27.md's own
-- note that a first show renders taller than its steady state, so this still waits out
-- whatever remains of that window before reading the frame itself. A swap landing later than
-- that, the overwhelming ordinary case, races nothing and runs at once.
function obj:_applyPaneGeometry(p, outgoing)
  -- The unconditional cancel that used to open this function now sits at the top of _show
  -- instead, rider N2 of the geometry review, so every door clears a pending timer before
  -- either the cold or the swap path runs, not only the swap path this function itself is
  -- reached from.
  local hadPane = outgoing and outgoing.paneWidth
  if not p.paneWidth and not hadPane then return end
  local age = hs.timer.secondsSinceEpoch() - (self._lastShowAt or 0)
  if age < ATOM_SETTLE_DELAY then
    self._geometryTimer = hs.timer.doAfter(ATOM_SETTLE_DELAY - age, function()
      self._geometryTimer = nil
      self:_positionPane(p)
    end)
  else
    self:_positionPane(p)
  end
end

-- Finds the live window through the same trick lib/chooser/providers/native.lua's own
-- _settleFrames uses, since hs.chooser hands out no window handle of its own, only a title an
-- hs.application can be asked for. Recomputes the pair the way _positionAndShow already
-- centers a chooser and its companion, moves the live window with setTopLeft rather than
-- reopening it, docs/PROBE-FINDINGS-2026-08-27.md section C3 having found that move exact and
-- the widget staying live through it. Stamps self._instance.paneFrames with the result, the
-- field the atom's own click watcher already reads for every hit test, so a click on the new
-- companion keeps testing honestly, and hands the two frames to _onPositioned, the one
-- function that also fires on the atom's own native path, so the panel and this
-- presentation's own onPositioned are told through the identical route regardless of which
-- of the two placed the window, adversarial review finding M2.
--
-- Guarded against a stale call landing after a newer presentation already took over, which
-- the settle wait above makes possible, a present, push, or pop racing ahead of the timer
-- before it ever fires. Also guarded, adversarial review finding L1, against a foreign
-- window also titled "Chooser", the overlay display picker or any of the twelve still
-- unmigrated consumers among them, being the one the loop above happens to find while this
-- instance's own window is not actually up, the same self.active guard _settleFrames itself
-- opens with before running the identical search.
function obj:_positionPane(p)
  if self:_current() ~= p then return end
  if not (self._instance and self._instance.active) then return end
  local app = hs.application.get("Hammerspoon")
  if not app then return end
  local w = nil
  for _, cand in ipairs(app:allWindows()) do
    if (cand:title() or "") == "Chooser" and cand:isVisible() then
      w = cand
      break
    end
  end
  if not w then return end

  local L = self._instance.layout
  local cf = w:frame()
  local paneW = self:_resolvePaneWidth(p.paneWidth, cf.w, L.paneMaxW)

  local sf = (w:screen() or hs.screen.mainScreen()):frame()
  local total = cf.w + (paneW > 0 and (L.gap + paneW) or 0)
  local x = sf.x + math.floor((sf.w - total) / 2)
  w:setTopLeft({ x = x, y = cf.y })

  local chooserFrame = { x = x, y = cf.y, w = cf.w, h = cf.h }
  local companionFrame = nil
  if paneW > 0 then
    companionFrame = { x = x + cf.w + L.gap, y = cf.y, w = paneW, h = cf.h }
  end
  self._instance.paneFrames = { chooser = chooserFrame, companion = companionFrame }
  self:_onPositioned(chooserFrame, companionFrame)
end

-- The atom's own companionWidth semantics, decision one of the geometry brief, reproduced
-- here rather than reached for on the instance, since the shared instance's own
-- _resolveCompanionWidth answers for layout.companionWidth, which by the time this runs
-- already carries this same presentation's own paneWidth, adversarial review finding M6, but
-- _positionPane needs the resolved PIXEL width for its own arithmetic, not the raw value, true
-- or a number or absent, the atom's own field stores. true inherits the chooser's own
-- width for this show, a number is the independent value, and both are capped at paneMaxW
-- exactly as the atom caps its own. Anything else, absent, false, or a non positive number,
-- means no pane.
function obj:_resolvePaneWidth(paneWidth, chooserW, paneMaxW)
  local w = paneWidth
  if w == true then w = chooserW end
  if type(w) ~= "number" or w <= 0 then return 0 end
  return math.min(w, paneMaxW)
end

-- Where every geometry pass that has real frames to report converges, the atom's own
-- automatic firing on a cold show, docs/BRIEF-GEOMETRY.md decision one wired through
-- configure above, and _positionPane's own manual one on a swap alike, adversarial review
-- finding M2. Re anchors the docked shortcut panel through paneAnchor, spanning the pair
-- rather than the list alone, so the host that claims to own that panel is the one that
-- actually moves it, and tells the current presentation's own onPositioned the same two
-- frames, so a pane consumer draws into the real rect or clears when this presentation
-- declares none. A presentation with no onPositioned of its own is silently skipped, exactly
-- as an ordinary missing field already is everywhere else in this file.
function obj:_onPositioned(chooserFrame, companionFrame)
  if self._panelOnPositioned then
    self._panelOnPositioned(self:paneAnchor(chooserFrame, companionFrame))
  end
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
function obj:present(p)
  if not isPresentation(p) then
    log.w("Stage present was given something that is not a presentation, name, rows, and onSelect are all required, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage present for '%s' arrived with no instance built, refusing", p.name))
    return false
  end

  local wasShowing = self._instance:isShowing()
  -- Captured before _freshStack mutates the stack, so _show can tell whatever was current a
  -- moment ago that it lost the pane, adversarial review finding H2, alongside whatever
  -- onClose it may separately hear as a discarded level.
  local outgoing = self:_current()
  self:_freshStack(p, self._stack)
  self:_announce(p)
  self:_show(p, wasShowing, outgoing)
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
function obj:push(p)
  if not isPresentation(p) then
    log.w("Stage push was given something that is not a presentation, name, rows, and onSelect are all required, refusing")
    return false
  end
  if not self._instance then
    log.w(string.format("Stage push for '%s' arrived with no instance built, refusing", p.name))
    return false
  end

  local wasShowing = self._instance:isShowing()
  -- Captured before the stack mutation below, for the identical reason present captures it,
  -- adversarial review finding H2. This is the door where telling it matters most, since push
  -- deliberately fires nobody's onClose when it stacks, decision six of the handoff brief, so
  -- without this the level being stacked under would have no other way to learn its pane is
  -- gone.
  local outgoing = self:_current()
  if not wasShowing then
    self:_freshStack(p, self._stack)
  elseif self:_current() ~= p then
    self._stack[#self._stack + 1] = p
  end
  self:_announce(p)
  self:_show(p, wasShowing, outgoing)
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
--- presentation, finding H2, so a pane it drew is told to clear on the same path present and
--- push already use, and the one leaving still hears its own onClose first, exactly as
--- before, since that is a real dismissal for it and _show's own outgoing notice is not a
--- substitute for it, the two are told for different reasons and neither replaces the other.
function obj:pop()
  if #self._stack <= 1 then return false end
  local leaving = table.remove(self._stack)
  if leaving.onClose then leaving.onClose() end
  local below = self:_current()
  if self._instance then
    self:_show(below, self._instance:isShowing(), leaving)
  end
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
function obj:hide()
  if self._geometryTimer then
    self._geometryTimer:stop()
    self._geometryTimer = nil
  end
  if self._instance then self._instance:hide() end
  closeStack(self._stack)
  self._stack = {}
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
function obj:refresh(resetRow, force)
  if self._instance and (force or self._instance:isShowing()) then
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

--- Stage:paneAnchor(chooserFrame, companionFrame) -> table
--- Method
--- The one true copy of the anchor arithmetic three plugins carried a literal copy of before
--- this phase, decision three of the geometry brief, consumer map sections 7.3 and 9.11,
--- plugins/clipboard/manager/ui.lua:1180, plugins/filesearch/chooser.lua:454,
--- plugins/processes/chooser.lua:347. Spans the chooser and its companion so a docked hint
--- panel sits full width beneath both rather than stopping short under the list alone.
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
function obj:selectedItem()
  return self._instance and self._instance:selectedItem() or nil
end

--- Stage:selectedRow() -> number or nil
--- Method
--- The highlighted row NUMBER on the live instance, or nil, the plain public counterpart
--- Chooser:selectedRow() already answers for ActionPanel. Added for the menu search cache,
--- docs/BRIEF-MENUSEARCH-CACHE.md, whose own background correction has to know whether a
--- person has moved off row one before it is safe to redraw without disturbing a considered
--- position, a row number being the whole question rather than the item sitting on it.
function obj:selectedRow()
  return self._instance and self._instance:selectedRow() or nil
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
-- hide, never for a swap or a push between presentations while the window stays open, since
-- neither ever tears the atom down at all. Tells the fixed docked panel first, since that is
-- atom level infrastructure this host owns regardless of what was showing, then every
-- presentation still on the stack its own onClose, top down, decision six of the handoff
-- brief, closing review finding twelve, which used to tell only the one on top and leave
-- every level below it silently discarded. Then clears the whole stack, so the next present
-- or push anywhere starts fresh.
function obj:_onClose()
  -- Held shut for the one call that is not a real dismissal, _applyRowCount's own internal
  -- hide, which resizes the same presentation that is still current and about to be reshown
  -- on the very next line, never a level actually leaving the stack.
  if self._suppressClose then return end
  if self._panelOnClose then self._panelOnClose() end
  closeStack(self._stack)
  self._stack = {}
end

return obj
