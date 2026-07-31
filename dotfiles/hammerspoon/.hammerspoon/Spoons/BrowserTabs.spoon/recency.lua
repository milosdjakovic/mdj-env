--- === BrowserTabs.recency ===
---
--- Which tab you looked at last, remembered because no browser will tell us.
---
--- Not one of the three browsers exposes a per tab last access time. Chrome and Arc give a
--- tab an id, a title, a URL and a loading flag, Safari gives it not even an id, and none of
--- them carries a timestamp. So ordering tabs by recency cannot be read, it has to be
--- observed, which is what this file does. It is the Observer half of the same pair
--- DisplayMemory forms with TerminalHandler, an watcher that records what it sees and a
--- persisted order a consumer reads back.
---
--- Identity is the bundle id plus the URL. It cannot be a browser tab id, because Safari
--- has none and the ids Chrome and Arc do give are not stable across a restart, so a
--- remembered order keyed on them would be worthless after a reboot. The cost of a URL key
--- is that two tabs on the same page in the same browser share one slot, and a set of fresh
--- blank tabs collapse together. That trade is recorded in the spoon's CLAUDE.md.
---
--- Two events say a tab became current. A browser coming to the front, seen through an
--- application watcher. And a tab switch inside a browser already frontmost, which has no
--- event of its own but does change the window title, so a window filter watching titles
--- catches it. Both are coalesced, because a page load fires title changes repeatedly and
--- each sample costs an Apple Event.
---
--- It never scripts a browser policy has switched off, the same rule the engine follows, so
--- turning a browser off silences the observer for it too.

local M = {}

local cfg = {}          -- injected: engine, settingsKey, limit, settleDelay
local order = nil       -- list of keys, newest first, loaded on start
local ranks = nil       -- key to position in order, built on demand, dropped when order changes
local appWatcher = nil
local titleFilter = nil
local settleTimers = {} -- one coalescing timer per bundle id

local DEFAULTS = {
  settingsKey = "BrowserTabs.recentTabs",
  -- Enough to cover any plausible open tab count several times over, so a tab you visited
  -- long ago still leads the list, while the stored table stays small. An entry whose URL is
  -- no longer open simply never matches, so a stale key is inert rather than an error.
  limit = 2000,
  -- How long to wait after the last focus or title event before sampling. A page load fires
  -- title changes in a burst, and sampling each one would spend an Apple Event per redraw.
  settleDelay = 0.45,
}

--- M.keyFor(bundleID, url) - the identity a remembered tab is stored under. The one place
--- that decision lives, so the observer and the ordering can never disagree about it.
function M.keyFor(bundleID, url)
  return (bundleID or "") .. "\0" .. (url or "")
end

local function opt(name)
  local v = cfg[name]
  if v == nil then return DEFAULTS[name] end
  return v
end

--- M.touch(bundleID, url) - lift a tab to the front of the remembered order and persist. Any
--- earlier entry for the same tab is dropped first, so a key appears once and its newest use
--- wins. The list is capped, oldest falling off the end.
function M.touch(bundleID, url)
  if not url or url == "" then return end
  local key = M.keyFor(bundleID, url)
  local limit = opt("limit")
  local out = { key }
  for _, prev in ipairs(order or {}) do
    if prev ~= key and #out < limit then out[#out + 1] = prev end
  end
  order = out
  ranks = nil
  hs.settings.set(opt("settingsKey"), order)
end

--- M.rankOf(bundleID, url) - where this tab sits in the remembered order, one being the most
--- recently looked at, or nil for a tab never observed. Nil is the honest answer rather than a
--- large number, because a tab nobody has looked at has no recency at all and a caller must be
--- able to tell that apart from a tab looked at long ago.
---
--- The position map is built once and dropped whenever the order changes, since this is asked
--- for every tab on every keystroke while the stored order runs to a couple of thousand keys,
--- and walking that list per tab per keystroke would be the only expensive thing in the search.
function M.rankOf(bundleID, url)
  if ranks == nil then
    ranks = {}
    for i, key in ipairs(order or {}) do
      if ranks[key] == nil then ranks[key] = i end
    end
  end
  return ranks[M.keyFor(bundleID, url)]
end

--- M.order(tabs) - the given tabs, most recently looked at first. Remembered tabs lead in
--- remembered order, then everything never seen follows in the order it arrived, so the
--- caller decides what the resting order of unseen tabs is and this file only knows recency.
--- Two tabs sharing a key both sort to that key's place, keeping their relative order.
function M.order(tabs)
  local seen, rest = {}, {}
  for _, t in ipairs(tabs or {}) do
    if M.rankOf(t.bundleID, t.url) then
      seen[#seen + 1] = t
    else
      rest[#rest + 1] = t
    end
  end
  -- A stable sort is needed so tabs sharing a key keep their arrival order. table.sort is
  -- not stable, so the arrival index is folded into the comparison as the tie breaker.
  local arrival = {}
  for i, t in ipairs(seen) do arrival[t] = i end
  table.sort(seen, function(a, b)
    local ra, rb = M.rankOf(a.bundleID, a.url), M.rankOf(b.bundleID, b.url)
    if ra ~= rb then return ra < rb end
    return arrival[a] < arrival[b]
  end)
  for _, t in ipairs(rest) do seen[#seen + 1] = t end
  return seen
end

--------------------------------------------------------------------------------
-- The observer
--------------------------------------------------------------------------------

-- Ask one browser what its current tab is and remember it. Routed through the engine's
-- enabled test so a browser switched off is never scripted, and skipped when it is not
-- running. A provider that cannot report an active tab, which Arc cannot, simply yields
-- nothing and costs no more than the call.
local function sample(bundleID)
  local engine = cfg.engine
  if not engine then return end
  local p = engine.provider(bundleID)
  if not p or not engine.enabled(p) or not p.running() then return end
  p.activeTab(function(tab)
    if tab and tab.url then M.touch(bundleID, tab.url) end
  end)
end

-- Coalesce a burst of events for one browser into a single sample, so a page load firing
-- title changes repeatedly costs one Apple Event rather than one per redraw.
local function scheduleSample(bundleID)
  if not bundleID then return end
  local t = settleTimers[bundleID]
  if t then t:stop() end
  settleTimers[bundleID] = hs.timer.doAfter(opt("settleDelay"), function()
    settleTimers[bundleID] = nil
    sample(bundleID)
  end)
end

-- Whether this bundle id is one of the browsers we know about at all. Cheap enough to run
-- per window event, since it is a walk over a handful of providers.
local function isWatched(bundleID)
  local engine = cfg.engine
  return engine ~= nil and bundleID ~= nil and engine.provider(bundleID) ~= nil
end

--- M.configure(opts) - inject the engine, which is how this file reaches the providers and
--- the enabled policy without naming either, plus optional overrides for the settings key,
--- the cap, and the coalescing delay.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- M.start() - load the remembered order and begin watching. Idempotent.
function M.start()
  order = hs.settings.get(opt("settingsKey")) or {}
  ranks = nil
  if appWatcher then return M end

  -- A browser came to the front, so whatever tab it is showing is now the current one.
  appWatcher = hs.application.watcher.new(function(_, event, app)
    if event ~= hs.application.watcher.activated then return end
    local bundleID = app and app:bundleID()
    if isWatched(bundleID) then scheduleSample(bundleID) end
  end)
  appWatcher:start()

  -- A tab switch inside an already frontmost browser fires no event of its own, but it does
  -- change the window title, since every one of these browsers titles its window after the
  -- active tab. So a title change is the only signal that a tab switch happened, and it is
  -- also why the sample reads the browser rather than trusting the title, which is a page
  -- name and not a URL.
  titleFilter = hs.window.filter.new(function(win)
    local app = win and win:application()
    return app ~= nil and isWatched(app:bundleID())
  end)
  titleFilter:subscribe(hs.window.filter.windowTitleChanged, function(win)
    local app = win and win:application()
    if app then scheduleSample(app:bundleID()) end
  end)

  return M
end

--- M.stop() - tear the watchers down and drop any pending sample.
function M.stop()
  if appWatcher then
    appWatcher:stop()
    appWatcher = nil
  end
  if titleFilter then
    titleFilter:unsubscribeAll()
    titleFilter = nil
  end
  for id, t in pairs(settleTimers) do
    t:stop()
    settleTimers[id] = nil
  end
  return M
end

return M
