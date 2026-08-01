--- === BrowserTabs.recency ===
---
--- Which tabs you have opened through this tool, most recent first, remembered across restarts.
---
--- It used to watch the browsers instead, because no browser exposes a per tab last access time
--- and the obvious reading of recency is whatever you last looked at. That was given up, and the
--- argument is in the spoon's CLAUDE.md under the section on why the order is no longer observed.
--- The short of it is that watching cost an application watcher, a window filter over every
--- browser window and an Apple Event for each switch, arrived eight tenths of a second late at
--- best, could not see Arc at all, and moved the list for things you did in the browser rather
--- than in the tool. What this tool opens is exact, free, and known the instant it happens.
---
--- So this is a plain remembered order with one writer, the activation the surface performs. It
--- is the same shape FileSearch's frecency takes, a record of what you chose through the tool
--- rather than a claim about the world. Nothing here watches anything, and there is no lifecycle
--- to start or stop.
---
--- Identity is the bundle id plus the URL. It cannot be a browser tab id, because Safari has none
--- and the ids Chrome and Arc do give are not stable across a restart, so a remembered order keyed
--- on them would be worthless after a reboot. The cost of a URL key is that two tabs on the same
--- page in the same browser share one slot, and a set of fresh blank tabs collapse together. That
--- trade is recorded in the spoon's CLAUDE.md.

local M = {}

local cfg = {}    -- injected: settingsKey, limit
local order = nil -- list of keys, newest first, loaded on first use
local ranks = nil -- key to position in order, built on demand, dropped when order changes

local DEFAULTS = {
  settingsKey = "BrowserTabs.recentTabs",
  -- Enough to cover any plausible open tab count several times over, so a tab you opened long ago
  -- still leads the list, while the stored table stays small. An entry whose URL is no longer open
  -- simply never matches, so a stale key is inert rather than an error.
  limit = 2000,
}

local function opt(name)
  local v = cfg[name]
  if v == nil then return DEFAULTS[name] end
  return v
end

-- The stored order, read once. There is no start to call because there is nothing to start, so
-- the first read is what loads it. Everything below goes through here rather than touching the
-- local, which is what makes that true.
local function loaded()
  if order == nil then order = hs.settings.get(opt("settingsKey")) or {} end
  return order
end

--- M.keyFor(bundleID, url) - the identity a remembered tab is stored under. The one place that
--- decision lives, so the writer and the ordering can never disagree about it.
function M.keyFor(bundleID, url)
  return (bundleID or "") .. "\0" .. (url or "")
end

--- M.touch(bundleID, url) - lift a tab to the front of the remembered order and persist. Any
--- earlier entry for the same tab is dropped first, so a key appears once and its newest use
--- wins. The list is capped, oldest falling off the end.
---
--- This is the only writer. It is called when the tool opens a tab and at no other time, which is
--- what makes the order predictable, since it can only change through something you did here.
function M.touch(bundleID, url)
  if not url or url == "" then return end
  local key = M.keyFor(bundleID, url)
  local limit = opt("limit")
  local out = { key }
  for _, prev in ipairs(loaded()) do
    if prev ~= key and #out < limit then out[#out + 1] = prev end
  end
  order = out
  ranks = nil
  hs.settings.set(opt("settingsKey"), order)
end

--- M.rankOf(bundleID, url) - where this tab sits in the remembered order, one being the most
--- recently opened, or nil for a tab this tool has never opened. Nil is the honest answer rather
--- than a large number, because such a tab has no recency at all and a caller must be able to tell
--- that apart from one opened long ago.
---
--- The position map is built once and dropped whenever the order changes, since this is asked for
--- every tab on every keystroke while the stored order runs to a couple of thousand keys, and
--- walking that list per tab per keystroke would be the only expensive thing in the search.
function M.rankOf(bundleID, url)
  if ranks == nil then
    ranks = {}
    for i, key in ipairs(loaded()) do
      if ranks[key] == nil then ranks[key] = i end
    end
  end
  return ranks[M.keyFor(bundleID, url)]
end

--- M.order(tabs) - the given tabs, most recently opened first. Remembered tabs lead in remembered
--- order, then everything else follows in the order it arrived, so the caller decides what the
--- resting order of the rest is and this file only knows what it was told. Two tabs sharing a key
--- both sort to that key's place, keeping their relative order.
function M.order(tabs)
  local seen, rest = {}, {}
  for _, t in ipairs(tabs or {}) do
    if M.rankOf(t.bundleID, t.url) then
      seen[#seen + 1] = t
    else
      rest[#rest + 1] = t
    end
  end
  -- A stable sort is needed so tabs sharing a key keep their arrival order. table.sort is not
  -- stable, so the arrival index is folded into the comparison as the tie breaker.
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

--- M.configure(opts) - optional overrides for where the order is kept and how long it may grow.
--- Anything already read is dropped, so a changed key takes effect rather than being masked by
--- what the previous one loaded.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  order = nil
  ranks = nil
  return M
end

return M
