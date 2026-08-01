--- === BrowserTabs ===
---
--- Every open tab across every browser in one list, the ones you have opened through this tool
--- first, each row carrying its browser's icon. Choosing a tab selects it in its window and brings
--- that browser to the front. The last row opens settings, where each browser is switched on or
--- off and shows whether it is installed, open, and allowed to be scripted.
---
--- This file is the spoon composition root and the ordering policy, nothing else. It loads
--- the pieces, exposes the providers so the main root can name the concrete browsers, owns
--- which browsers are switched on, and assembles the one api the surface talks through.
--- `engine.lua` is the mechanism, `contract.lua` is the provider spec, `recency.lua` is the
--- remembered order, `permissions.lua` reads and asks for the Apple Events grant, `chooser.lua`
--- is the surface, and `providers/` holds one file per browser.
---
--- It names no browser itself. The main root picks which providers exist and which are on by
--- default, so adding a browser is a new file in providers plus one line there. The Chromium
--- provider is a factory rather than a module because Chrome, Brave, Edge, Vivaldi and Opera
--- share one dictionary, so which application is a parameter the root supplies.
---
--- Ordering lives here because it is policy, not mechanism. The engine merges and knows nothing
--- about order, and `recency.lua` knows only what this tool has opened. What is left is where
--- everything else rests and where the tab you are on belongs, both decided below. Not one term
--- of it reads the world, so the order is the same at any moment and changes only when you open
--- a tab through the tool. That is deliberate and the reasoning is in the CLAUDE.md beside this
--- file.

local obj = {}
obj.__index = obj
obj.name = "BrowserTabs"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("BrowserTabs", "info")

-- Load the siblings by absolute path off this file's own location, the loadfile pattern the
-- spoons use since a spoon directory is not on package.path.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("BrowserTabs: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local contract = load("contract.lua")
local jxa = load("jxa.lua")
local permissions = load("permissions.lua")

obj.engine = load("engine.lua")
obj.recency = load("recency.lua")
obj.chooser = load("chooser.lua")

--- BrowserTabs.providers - the backends, exposed by reference so the composition root names
--- the concrete browsers and their order, the same way the root names the Emoji backends.
--- chromium is a factory taking { name, bundleID }, since one dictionary serves several
--- applications; the others are modules that own their own bundle id.
obj.providers = {
  chromium = load("providers/chromium.lua"),
  safari = load("providers/safari.lua"),
  arc = load("providers/arc.lua"),
}

-- Injected via configure
obj._providers = nil       -- the validated, ordered provider list
obj._defaultEnabled = nil  -- bundle ids switched on before the user has chosen
obj._settingsKey = nil     -- where the on and off choices are kept

--------------------------------------------------------------------------------
-- Which browsers are switched on
--------------------------------------------------------------------------------

-- The choices are per machine preference, so they live in hs.settings rather than a git
-- tracked file, matching the overlay display policy and the VPN recency rather than the
-- DisplayProfiles store. A browser with no stored choice falls back to the root's default
-- set, so a browser added later starts off rather than silently switched on.
function obj:_enabledMap()
  return hs.settings.get(self._settingsKey) or {}
end

function obj:isEnabled(bundleID)
  local stored = self:_enabledMap()[bundleID]
  if stored ~= nil then return stored == true end
  for _, id in ipairs(self._defaultEnabled or {}) do
    if id == bundleID then return true end
  end
  return false
end

function obj:setEnabled(bundleID, on)
  local map = self:_enabledMap()
  map[bundleID] = on == true
  hs.settings.set(self._settingsKey, map)
  return self
end

--------------------------------------------------------------------------------
-- The order the tabs are shown in
--------------------------------------------------------------------------------

-- Where a tab rests when this tool has never opened it. Each browser in the order the main root
-- named them, then that browser's own windows and its own tabs within them, which is the order
-- you already see along your tab bar. It never moves on its own, and that is the whole point of
-- it.
--
-- It used to be depth on screen, the browser furthest forward first, its windows front to back,
-- and each window's showing tab lifted above the rest. That reads as sensible and behaves badly.
-- Every term in it is something the browser decides rather than something you asked this tool
-- for, so switching a tab or clicking a window rearranged the list, and the rearranging is what
-- made the tool feel unpredictable. It also cost a walk of every window on screen, measured
-- between 34 and 59 milliseconds, on the one path where the list is waiting to appear.
local function restingOrder(tabs, browserRank)
  local arrival = {}
  for i, t in ipairs(tabs) do arrival[t] = i end
  table.sort(tabs, function(a, b)
    -- A browser the root never named sorts after every one it did.
    local ra = browserRank[a.bundleID] or math.huge
    local rb = browserRank[b.bundleID] or math.huge
    if ra ~= rb then return ra < rb end
    if (a.windowIndex or 0) ~= (b.windowIndex or 0) then
      return (a.windowIndex or 0) < (b.windowIndex or 0)
    end
    if (a.tabIndex or 0) ~= (b.tabIndex or 0) then
      return (a.tabIndex or 0) < (b.tabIndex or 0)
    end
    -- table.sort is not stable, so arrival breaks every remaining tie.
    return arrival[a] < arrival[b]
  end)
  return tabs
end

-- The tab you are sitting on is the one row you will never choose, so it does not lead the list.
-- Ordinary alt tab behaviour, where the thing you came from leads and the thing you are on sits
-- directly beneath it, one keystroke away rather than banished to the end.
--
-- What decides which tab that is, is the remembered order and deliberately not the browser's own
-- report of which tab is showing, even though every listing carries that flag. The flag is only
-- learned when the browsers answer, so leaning on it would put the list straight back to
-- rearranging itself a third of a second after it opened, every time a tab had been switched by
-- hand, which is the fault this whole change exists to remove. The remembered order is known the
-- instant it is asked for and changes only when you act here, so this never moves.
--
-- Only when both leading tabs are ones this tool has opened. With fewer than that, the second row
-- is a tab with no recency at all and swapping would lead the list with something arbitrary, which
-- is worse than leading with where you already are.
local function currentBelowPrevious(tabs, isRemembered)
  if #tabs > 1 and isRemembered(tabs[1]) and isRemembered(tabs[2]) then
    tabs[1], tabs[2] = tabs[2], tabs[1]
  end
  return tabs
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- BrowserTabs:init()
--- Method
--- Nothing to build yet, every collaborator arrives through configure.
function obj:init()
  return self
end

--- BrowserTabs:configure(opts)
--- Method
--- Wire everything. opts.providers is the ordered provider list the main root assembled and is
--- required. opts.defaultEnabled is the list of bundle ids switched on before the user has
--- chosen anything. opts.settingsKey overrides where the on and off choices are stored, and
--- opts.recencyKey where the observed order is. Each provider is validated against the
--- contract and a bad one is dropped with a log rather than killing the whole tool, since one
--- broken backend should not cost the browsers that do work.
function obj:configure(opts)
  opts = opts or {}
  self._settingsKey = opts.settingsKey or "BrowserTabs.enabledBrowsers"
  self._defaultEnabled = opts.defaultEnabled or {}

  local ok = {}
  for _, p in ipairs(opts.providers or {}) do
    local valid, missing = contract.validate(p)
    if valid then
      ok[#ok + 1] = p
    else
      log.e("dropping a browser provider, it does not implement " .. tostring(missing))
    end
  end
  self._providers = ok
  if #ok == 0 then
    log.w("no usable browser providers, the tab list will be empty")
  end

  local this = self
  self.engine.configure({
    providers = ok,
    -- The enabled policy, injected so the engine never learns what switched on means or
    -- where that choice is kept.
    enabled = function(p) return this:isEnabled(p.bundleID) end,
  })
  self.recency.configure({ settingsKey = opts.recencyKey })

  -- Where each browser sits relative to the others, taken once from the order the main root named
  -- them in, since that is fixed for the life of the config and asking per listing would only be
  -- rebuilding the same table.
  local browserRank = {}
  for i, p in ipairs(ok) do browserRank[p.bundleID] = i end

  -- The whole ordering policy, in one place. Tabs this tool has opened lead in the order it opened
  -- them, everything else keeps its resting place, and the tab you are on steps below the one you
  -- came from. Nothing in it reads the world, so it gives the same answer at any moment and costs
  -- nothing to apply.
  local function ordered(list)
    local remembered = function(t) return this.recency.rankOf(t.bundleID, t.url) ~= nil end
    return currentBelowPrevious(
      this.recency.order(restingOrder(list or {}, browserRank)), remembered)
  end

  -- The one api the surface talks through, so the chooser reaches the engine, the recency
  -- memory and the permission probe while naming none of them. This is the seam that keeps
  -- the surface pure policy, the same shape DisplayProfiles builds for its chooser.
  self.chooser.configure({
    api = {
      status = function() return this.engine.status() end,
      isEnabled = function(bundleID) return this:isEnabled(bundleID) end,
      setEnabled = function(bundleID, on) this:setEnabled(bundleID, on) end,
      -- The full read, merged across the live browsers and put in order.
      listTabs = function(cb)
        this.engine.listTabs(function(tabs, errors) cb(ordered(tabs), errors) end)
      end,
      -- The same order applied again to a listing the surface is already holding, so it can paint
      -- the right list at once instead of painting a stale one and correcting it a third of a
      -- second later when the browsers answer. It is the same function the full read uses, which
      -- is what makes the early paint and the answer agree rather than merely resemble each other.
      --
      -- This is exact now, where it used to be an approximation. The order can only change when
      -- this tool opens a tab, and that is recorded before this is ever called, so there is nothing
      -- left for the read to correct except a tab genuinely opened or closed in the browser.
      order = ordered,
      -- Where a tab sits in the remembered order, or nil for one this tool has never opened. The
      -- untyped order above is only one of the two things that reads it, the second being a small
      -- reordering among tabs that matched a typed query alike, which the surface can only do a tab
      -- at a time. What it reads here is mostly the nil, since a tab this tool never opened must
      -- earn nothing, and it counts positions among the tabs it was given rather than trusting
      -- these numbers, which run over every address ever opened and not over what is still open.
      recencyRank = function(tab) return this.recency.rankOf(tab.bundleID, tab.url) end,
      -- Opening a tab is the only thing that writes the remembered order, so this is where it is
      -- written. Nothing watches the browsers any more, which is what makes the order predictable.
      activate = function(tab)
        this.recency.touch(tab.bundleID, tab.url)
        this.engine.activate(tab)
      end,
      permissionStatus = permissions.status,
      permissionRequest = permissions.request,
      openPermissionSettings = permissions.openSettings,
      notPermitted = jxa.notPermitted,
    },
  })
  return self
end

--- BrowserTabs:start()
--- Method
--- Warm the permission probe so the first settings open is instant. There is nothing else to
--- start, since the remembered order reads itself on first use and nothing watches the browsers.
--- The surface itself is built by the main root once it has injected the Chooser factory, the
--- theme, and the shortcut panel.
function obj:start()
  permissions.warm()

  -- The integration harness, loaded only while a suite is actually running. The runner writes
  -- the marker beside the harness before it starts and removes it afterwards, so a normal
  -- machine never carries any of this. The gate lives here rather than in the main root because
  -- the harness belongs to this spoon, and nothing else in the spoon knows it exists.
  if hs.fs.attributes(spoonPath .. "test/ENABLED") then
    local chunk = loadfile(spoonPath .. "test/agent.lua")
    if chunk then
      -- Kept on the spoon rather than dropped, because the harness now reads its command channel
      -- on a timer and a timer lives only as long as something refers to it. Discarding the module
      -- here collected that timer within seconds, so the agent went deaf with nothing logged and
      -- every command sat unread in the channel. That is the trap the module CLAUDE.md records,
      -- and it is no less silent for happening inside a test harness.
      self._testAgent = chunk().start()
    else
      log.w("the test marker is present but the harness would not load")
    end
  end

  return self
end

--- BrowserTabs:stop()
--- Method
--- Nothing runs in the background, so there is nothing to stop. Kept because a spoon that can be
--- started should answer to being stopped, and because the main root pairs the two.
function obj:stop()
  return self
end

--- BrowserTabs:show()
--- Method
--- Open the tab list.
function obj:show()
  self.chooser.show()
  return self
end

--- BrowserTabs:isShowing()
--- Method
--- Whether the list is open. Read by the browserTabsOpen predicate in the main root.
function obj:isShowing()
  return self.chooser.isShowing()
end

return obj
