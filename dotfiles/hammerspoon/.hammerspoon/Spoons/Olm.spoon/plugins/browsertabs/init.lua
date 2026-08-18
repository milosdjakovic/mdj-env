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
--- `engine.lua` is the mechanism, `contract.lua` is the provider spec, the remembered order
--- now comes from the shared recency service injected through configure, `permissions.lua`
--- reads and asks for the Apple Events grant, `chooser.lua` is the surface, and `providers/`
--- holds one file per browser.
---
--- It names no browser itself. The main root picks which providers exist and which are on by
--- default, so adding a browser is a new file in providers plus one line there. The Chromium
--- provider is a factory rather than a module because Chrome, Brave, Edge, Vivaldi and Opera
--- share one dictionary, so which application is a parameter the root supplies.
---
--- Ordering lives here because it is policy, not mechanism. The engine merges and knows nothing
--- about order, and the injected recency service knows only what this tool has opened. What is
--- left is where everything else rests and where the tab you are on belongs, both decided below.
--- Not one term of it reads the world, so the order is the same at any moment and changes only
--- when you open a tab through the tool. That is deliberate and the reasoning is in the
--- CLAUDE.md beside this file.
---
--- This is the olm side copy of BrowserTabs, made in the bundling pass, converted to use the
--- shared recency service at Olm.spoon/lib/recency.lua instead of the hand rolled recency.lua
--- module the original carries, and the original this was copied from lived at
--- Spoons/BrowserTabs.spoon. Unlike the vpn copy this conversion took, a missing recency here
--- is an optional degradation rather than a required guard, since the resting order alone is
--- still a working list, only ever less than it could be.

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
obj._recency = nil         -- optional, an instance of the shared lift to front ordering service

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
-- named them, then that browser's windows oldest first, then each window's own tabs, which is the
-- order you already see along its tab bar. Every term in it is fixed until a window or a tab is
-- opened, closed or dragged, so it never moves on its own, and that is the whole point of it.
--
-- It used to be depth on screen, the browser furthest forward first, its windows front to back,
-- and each window's showing tab lifted above the rest. That reads as sensible and behaves badly.
-- Every term in it is something the browser decides rather than something you asked this tool
-- for, so switching a tab or clicking a window rearranged the list, and the rearranging is what
-- made the tool feel unpredictable. It also cost a walk of every window on screen, measured
-- between 34 and 59 milliseconds, on the one path where the list is waiting to appear.
--
-- A window is placed by its id and never by its position in the listing. `windowIndex` reads like
-- an identity and is not one, it is the window's place in the browser's own window list, which
-- both Safari and Chromium keep in front to back order. Raising one Safari window was measured
-- changing the index of all three, with nothing opened and nothing closed, so ordering on it was
-- depth wearing another name and moved the list for the same reason the old order did. The id is
-- fixed for the life of a window, which is already why activation addresses windows by it, so
-- ordering on it gives each browser's windows a place that only a window opening or closing can
-- change. Which window then leads is its creation order, since both browsers hand out ascending
-- ids, and that is as good a resting place as any given no browser offers a window order of its
-- own that a person would recognise.
local function windowBefore(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return na < nb end
  return a < b
end

local function restingOrder(tabs, browserRank)
  local arrival = {}
  for i, t in ipairs(tabs) do arrival[t] = i end
  table.sort(tabs, function(a, b)
    -- A browser the root never named sorts after every one it did.
    local ra = browserRank[a.bundleID] or math.huge
    local rb = browserRank[b.bundleID] or math.huge
    if ra ~= rb then return ra < rb end
    local wa, wb = a.windowID or "", b.windowID or ""
    if wa ~= wb then return windowBefore(wa, wb) end
    if (a.tabIndex or 0) ~= (b.tabIndex or 0) then
      return (a.tabIndex or 0) < (b.tabIndex or 0)
    end
    -- table.sort is not stable, so arrival breaks every remaining tie.
    return arrival[a] < arrival[b]
  end)
  return tabs
end

--------------------------------------------------------------------------------
-- Tab recency (command policy, ordering lifted from the shared service)
--------------------------------------------------------------------------------

-- The tab this tool opened last leads the resting order above and pushes the rest down, the
-- ones opened before it following in the order they were opened. Ordering itself now comes
-- from an instance of the shared lift to front service, handed in through configure as
-- opts.recency, rather than the hand rolled recency.lua module the original spoon carries.
-- The settings key that instance persists under is built by the main root to match the one
-- recency.lua used, so the remembered order a person already has carries across a flip
-- between the two copies.
--
-- Identity here is the bundle id plus the URL, the same pairing recency.lua's own keyFor
-- built, and building that key from a tab stays this file's own policy, the service only
-- ever sees the finished key. It cannot be a browser tab id, since Safari has none and the
-- ids Chrome and Arc give are not stable across a restart, and the full reasoning is in the
-- CLAUDE.md beside this file, in the section on why identity is the bundle id plus the URL.
local function keyFor(bundleID, url)
  return (bundleID or "") .. "\0" .. (url or "")
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
--- chosen anything. opts.settingsKey overrides where the on and off choices are stored. Each
--- provider is validated against the contract and a bad one is dropped with a log rather than
--- killing the whole tool, since one broken backend should not cost the browsers that do work.
---
--- opts.recency is an instance of the shared lift to front ordering service from Olm.spoon,
--- already built against this tool's own settings key. It is optional. Unlike the vpn copy,
--- a missing one is not rejected, since the tab list is still a working surface on its resting
--- order alone, only ever less than it could be, and the plan for this conversion records that
--- as the right degradation here rather than a required guard.
-- One browser name, turned into the finished provider it names.
--
-- This is the composition root FOR THIS PLUGIN'S OWN BACKENDS, and having one is what makes a
-- name list a workable contract. Olm's own root must never name a browser, so somebody still has
-- to know that "chrome" means the shared Chromium dictionary pointed at one particular
-- application, and the only honest place for that is here, beside the directory those files live
-- in. Adding a browser is a new file in providers plus one line in this function.
--
-- Chromium is the one entry taking an argument, since Chrome, Brave, Edge, Vivaldi and Opera all
-- answer to one dictionary, so which application is a parameter rather than a fact any of them
-- carries. Its bundle id is the single value this plugin cannot know, which is exactly why the
-- manifest declares that and nothing else.
local function providerNamed(name, chromeBundleID)
  if name == "safari" then return obj.providers.safari end
  if name == "arc" then return obj.providers.arc end
  if name == "chrome" then
    if not chromeBundleID then return nil, "no Chrome bundle id was supplied" end
    return obj.providers.chromium({ name = "Chrome", bundleID = chromeBundleID })
  end
  return nil, "no provider answers to that name"
end

function obj:configure(opts)
  opts = opts or {}
  self._settingsKey = opts.settingsKey or "BrowserTabs.enabledBrowsers"
  self._recency = opts.recency

  -- The ordered list is BUILT HERE from names, rather than arriving already built.
  --
  -- It used to arrive built, from the retired root, which was the one place naming all three
  -- browsers. Nothing replaced that when the root became portable, so opts.providers was nil on
  -- every run, the list stayed empty, and this tool logged that the tab list would be empty and
  -- then was. A shipped order in the manifest plus this function is what makes it work on a
  -- machine with no configuration at all, which is the whole point of the port.
  local built, bundleOf = {}, {}
  for _, entry in ipairs(opts.providers or {}) do
    -- A finished provider table is still accepted, since a name is the ordinary case and an
    -- object is what somebody wiring an unusual browser by hand would reach for.
    if type(entry) == "table" then
      built[#built + 1] = entry
      if entry.name then bundleOf[tostring(entry.name):lower()] = entry.bundleID end
    else
      local provider, why = providerNamed(entry, opts.chromeBundleID)
      if provider then
        built[#built + 1] = provider
        bundleOf[tostring(entry):lower()] = provider.bundleID
      else
        log.w("skipping the browser '" .. tostring(entry) .. "', " .. tostring(why))
      end
    end
  end

  -- Which browsers are on before anybody has chosen, named the same way the list above names
  -- them and translated to bundle ids here, since that is what the stored choices are keyed by.
  --
  -- Two separate faults met in this one line. The field arrived as `enabled`, the name the
  -- manifest ships it under, and was read as `defaultEnabled`, the name the retired root used, so
  -- it was nil on every run. And the manifest names a browser, `safari`, where the comparison
  -- underneath wants `com.apple.Safari`, so even once the name was right the value could not have
  -- matched. Translating here is what lets the manifest keep saying safari, which is the only
  -- spelling a person reading it would think to write, without a bundle id constant being
  -- duplicated out of the provider file that already owns it.
  local defaultEnabled = {}
  for _, wanted in ipairs(opts.enabled or opts.defaultEnabled or {}) do
    local id = bundleOf[tostring(wanted):lower()] or wanted
    defaultEnabled[#defaultEnabled + 1] = id
  end
  self._defaultEnabled = defaultEnabled

  local ok = {}
  for _, p in ipairs(built) do
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
  -- Where each browser sits relative to the others, taken once from the order the main root named
  -- them in, since that is fixed for the life of the config and asking per listing would only be
  -- rebuilding the same table.
  local browserRank = {}
  for i, p in ipairs(ok) do browserRank[p.bundleID] = i end

  -- The whole ordering policy, in one place. The tab this tool opened last leads and pushes the
  -- rest down, then the ones before it in the order it opened them, then everything else in its
  -- resting place. Nothing in it reads the world, so it gives the same answer at any moment and
  -- costs nothing to apply. Without a recency instance the resting order stands untouched, which
  -- is the one place this copy's optional degradation shows.
  local function ordered(list)
    local resting = restingOrder(list or {}, browserRank)
    if not this._recency then return resting end
    return this._recency.order(resting, function(t) return keyFor(t.bundleID, t.url) end)
  end

  -- The one api the surface talks through, so the chooser reaches the engine, the recency
  -- memory and the permission probe while naming none of them. This is the seam that keeps
  -- the surface pure policy, the same shape DisplayProfiles builds for its chooser.
  self.chooser:configure({
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
      recencyRank = function(tab)
        if not this._recency then return nil end
        return this._recency.rankOf(keyFor(tab.bundleID, tab.url))
      end,
      -- Opening a tab is the only thing that writes the remembered order, so this is where it is
      -- written. Nothing watches the browsers any more, which is what makes the order predictable.
      -- A missing recency instance leaves the write a no op, the same degradation the read above
      -- takes.
      --
      -- This mirrors the guard the original recency.lua kept at its own touch, if not url or url
      -- equals empty string then return, and it must sit here before the key is built rather than
      -- inside the shared service, since the service only ever sees a finished key and keyFor
      -- turns a nil url into an empty string rather than a nil key, so a blank tab would otherwise
      -- persist under its bundle id alone and lead the picker forever.
      activate = function(tab)
        if this._recency and tab.url and tab.url ~= "" then
          this._recency.touch(keyFor(tab.bundleID, tab.url))
        end
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

--- BrowserTabs:explainOrder(n, cb)
--- Method
--- The top n rows exactly as the list would show them, each with the rank the memory gave it and
--- the window and position it came from, handed to cb as one block of text. Reads the browsers, so
--- it answers asynchronously like everything else here.
---
--- This exists because the ordering has twice been argued about from the code rather than from the
--- machine, and both times the code read correctly and the machine disagreed. A rank of nil means
--- this tool has never opened that tab, so it is sitting in its resting place, and a row that is
--- not in ascending rank order is the ordering being overridden by something.
---
---   hs -c 'spoon.BrowserTabs:explainOrder(10, function(s) print(s) end)'
function obj:explainOrder(n, cb)
  local this = self
  self.chooser.prepare(function()
    local lines = {}
    local rows = this.chooser.tabRows("")
    for i = 1, math.min(n or 10, #rows) do
      local t = rows[i].item and rows[i].item.tab
      if t then
        local rank = this._recency and this._recency.rankOf(keyFor(t.bundleID, t.url))
        lines[#lines + 1] = string.format("%3d  rank %-6s  %-18s win %-12s tab %-4s %s",
          i, tostring(rank), tostring(t.browser),
          tostring(t.windowID), tostring(t.tabIndex), tostring(t.title))
      end
    end
    lines[#lines + 1] = #rows .. " rows in all"
    cb(table.concat(lines, "\n"))
  end)
  return self
end

return obj
