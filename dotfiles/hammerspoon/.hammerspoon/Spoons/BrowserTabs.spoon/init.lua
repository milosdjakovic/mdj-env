--- === BrowserTabs ===
---
--- Every open tab across every browser in one list, most recently looked at first, each row
--- carrying its browser's icon. Choosing a tab selects it in its window and brings that
--- browser to the front. The last row opens settings, where each browser is switched on or
--- off and shows whether it is installed, open, and allowed to be scripted.
---
--- This file is the spoon composition root and the ordering policy, nothing else. It loads
--- the pieces, exposes the providers so the main root can name the concrete browsers, owns
--- which browsers are switched on, and assembles the one api the surface talks through.
--- `engine.lua` is the mechanism, `contract.lua` is the provider spec, `recency.lua` is the
--- observed order, `permissions.lua` reads and asks for the Apple Events grant, `chooser.lua`
--- is the surface, and `providers/` holds one file per browser.
---
--- It names no browser itself. The main root picks which providers exist and which are on by
--- default, so adding a browser is a new file in providers plus one line there. The Chromium
--- provider is a factory rather than a module because Chrome, Brave, Edge, Vivaldi and Opera
--- share one dictionary, so which application is a parameter the root supplies.
---
--- Ordering lives here because it is policy, not mechanism. The engine merges and knows
--- nothing about order, and `recency.lua` knows only what was looked at. What is left is the
--- resting order of tabs never seen, decided below.

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
-- Resting order for tabs never seen
--------------------------------------------------------------------------------

-- A tab nobody has looked at since Hammerspoon started has no recorded recency, so it needs
-- a sensible resting place. The closest honest proxy is depth on screen: the browser whose
-- window is furthest forward first, then that browser's windows front to back, then the
-- selected tab of each window ahead of the rest, then left to right. It is front to back
-- order and not recency, which is why it only ever decides the tail of the list, below
-- everything actually observed.
local function frontToBackRank()
  local rank, next_ = {}, 1
  for _, win in ipairs(hs.window.orderedWindows()) do
    local app = win:application()
    local id = app and app:bundleID()
    if id and rank[id] == nil then
      rank[id] = next_
      next_ = next_ + 1
    end
  end
  return rank
end

local function byDepth(tabs)
  local rank = frontToBackRank()
  local arrival = {}
  for i, t in ipairs(tabs) do arrival[t] = i end
  local function key(t)
    -- A browser with no window on screen sorts after every browser that has one.
    return rank[t.bundleID] or math.huge
  end
  table.sort(tabs, function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then return ka < kb end
    if (a.windowIndex or 0) ~= (b.windowIndex or 0) then
      return (a.windowIndex or 0) < (b.windowIndex or 0)
    end
    if (a.active == true) ~= (b.active == true) then return a.active == true end
    if (a.tabIndex or 0) ~= (b.tabIndex or 0) then
      return (a.tabIndex or 0) < (b.tabIndex or 0)
    end
    -- table.sort is not stable, so arrival breaks every remaining tie.
    return arrival[a] < arrival[b]
  end)
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
  self.recency.configure({ engine = self.engine, settingsKey = opts.recencyKey })

  -- The one api the surface talks through, so the chooser reaches the engine, the recency
  -- memory and the permission probe while naming none of them. This is the seam that keeps
  -- the surface pure policy, the same shape DisplayProfiles builds for its chooser.
  self.chooser.configure({
    api = {
      status = function() return this.engine.status() end,
      isEnabled = function(bundleID) return this:isEnabled(bundleID) end,
      setEnabled = function(bundleID, on) this:setEnabled(bundleID, on) end,
      -- The full read: merge across the live browsers, settle the tabs nobody has looked at
      -- into front to back order, then lift everything observed above them in recency order.
      listTabs = function(cb)
        this.engine.listTabs(function(tabs, errors)
          cb(this.recency.order(byDepth(tabs or {})), errors)
        end)
      end,
      -- Opening a tab is also the strongest signal that it is now the current one, so it is
      -- recorded here rather than waiting for the observer to notice the focus change.
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
--- Begin observing which tab is current and warm the permission probe so the first settings
--- open is instant. The surface itself is built by the main root once it has injected the
--- Chooser factory, the theme, and the shortcut panel.
function obj:start()
  self.recency.start()
  permissions.warm()

  -- The integration harness, loaded only while a suite is actually running. The runner writes
  -- the marker beside the harness before it starts and removes it afterwards, so a normal
  -- machine never carries any of this. The gate lives here rather than in the main root because
  -- the harness belongs to this spoon, and nothing else in the spoon knows it exists.
  if hs.fs.attributes(spoonPath .. "test/ENABLED") then
    local chunk = loadfile(spoonPath .. "test/agent.lua")
    if chunk then
      chunk().start()
    else
      log.w("the test marker is present but the harness would not load")
    end
  end

  return self
end

--- BrowserTabs:stop()
--- Method
--- Stop observing. The chooser keeps working, it just stops learning.
function obj:stop()
  self.recency.stop()
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
