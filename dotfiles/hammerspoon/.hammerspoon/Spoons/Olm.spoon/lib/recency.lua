-- The lift to front ordering service, the generic half of
-- BrowserTabs.spoon/recency.lua pulled out so a plugin with a remembered
-- order asks this for an instance rather than hand rolling the same handful
-- of functions again. Key building stays with each caller, since a key is
-- what a caller means by identity, the same way storage takes a finished
-- name rather than building one. See the design's recency section for the
-- split this follows and why Emoji and FileSearch, which keep a decayed
-- score rather than a plain order, stay out of it.
--
-- M.new(opts) returns an independent instance, since Vpn, Launcher, and
-- BrowserTabs each keep their own remembered list under their own settings
-- key. opts.settingsKey names where the order persists through hs.settings.
-- opts.limit is an optional cap on how many keys the order remembers, oldest
-- falling off first when it is given, and no cap at all when it is left out,
-- since a hand rolled block with no cap of its own converts to an instance
-- that behaves the same way.
--
-- Every instance exposes four functions, touch, rankOf, order, and prune, carrying the
-- donor's own semantics for the first three. touch(key) lifts a key to the front, dropping
-- any earlier entry for the same key and anything past the cap, then persists. rankOf(key)
-- answers the position, one being most recent, or nil for a key never touched, built
-- through a memo that is dropped whenever the order changes, the donor's own performance
-- reasoning, since this is asked for on every item on every keystroke. order(items, keyOf)
-- returns the items with remembered ones leading in remembered order and the rest
-- following in arrival order, stable for items sharing a key, with keyOf the
-- caller's function from an item to its key.
--
-- prune(validKeys) is the one function neither donor needed, added for TmuxSessions,
-- whose remembered keys name a session or a window that a person can simply kill, unlike
-- an app's bundle id or a VPN city, which stay valid as long as the tool itself runs. It
-- drops every remembered key not present in validKeys (an array, checked as a set built
-- once per call) and persists only when something actually changed, so a caller free to
-- call it on every open pays nothing on the ordinary reload where nothing went away.
--
-- The stored order loads lazily on first use, and there is no start or stop,
-- the same reasoning the donor records, since there is nothing to start.

local M = {}

--- M.new(opts) returns instance.
--- Returns a fresh instance holding its own remembered order and its own
--- rank memo, independent of any other instance even one built against the
--- same settings key, so two callers of new never see each other's state
--- and only the persisted order under hs.settings ties them together.
function M.new(opts)
  opts = opts or {}
  local settingsKey = opts.settingsKey
  if settingsKey == nil then
    error("recency new requires opts.settingsKey, the hs.settings key the order persists under")
  end
  local limit = opts.limit

  local instance = {}

  local order = nil -- list of keys, newest first, loaded on first use
  local ranks = nil -- key to position in order, built on demand, dropped when order changes

  -- The stored order, read once. There is no start to call because there is
  -- nothing to start, so the first read is what loads it. Everything below
  -- goes through here rather than touching the local, which is what makes
  -- that true.
  local function loaded()
    if order == nil then order = hs.settings.get(settingsKey) or {} end
    return order
  end

  --- instance.touch(key)
  --- Lift a key to the front of the remembered order and persist. Any
  --- earlier entry for the same key is dropped first, so a key appears once
  --- and its newest use wins. The list is capped when a limit was given,
  --- oldest falling off the end, and left to grow when no limit was given,
  --- matching a caller whose original block never capped its own list
  --- either.
  function instance.touch(key)
    if key == nil then return end
    local out = { key }
    for _, prev in ipairs(loaded()) do
      if prev ~= key and (not limit or #out < limit) then out[#out + 1] = prev end
    end
    order = out
    ranks = nil
    hs.settings.set(settingsKey, order)
  end

  --- instance.rankOf(key)
  --- Where this key sits in the remembered order, one being the most
  --- recently touched, or nil for a key never touched. Nil is the honest
  --- answer rather than a large number, since such a key has no recency at
  --- all and a caller must be able to tell that apart from one touched long
  --- ago.
  function instance.rankOf(key)
    if ranks == nil then
      ranks = {}
      for i, k in ipairs(loaded()) do
        if ranks[k] == nil then ranks[k] = i end
      end
    end
    return ranks[key]
  end

  --- instance.order(items, keyOf)
  --- The given items, remembered ones leading in remembered order and the
  --- rest following in arrival order, so the caller decides what the
  --- resting order of the rest is and this only knows what it was told.
  --- keyOf is the caller's function from an item to its key, since key
  --- building is caller policy. Two items sharing a key both sort to that
  --- key's place, keeping their relative order.
  function instance.order(items, keyOf)
    local seen, rest = {}, {}
    for _, item in ipairs(items or {}) do
      if instance.rankOf(keyOf(item)) then
        seen[#seen + 1] = item
      else
        rest[#rest + 1] = item
      end
    end
    -- A stable sort is needed so items sharing a key keep their arrival
    -- order. table.sort is not stable, so the arrival index is folded into
    -- the comparison as the tie breaker, the same trick the donor uses.
    local arrival = {}
    for i, item in ipairs(seen) do arrival[item] = i end
    table.sort(seen, function(a, b)
      local ra, rb = instance.rankOf(keyOf(a)), instance.rankOf(keyOf(b))
      if ra ~= rb then return ra < rb end
      return arrival[a] < arrival[b]
    end)
    for _, item in ipairs(rest) do seen[#seen + 1] = item end
    return seen
  end

  --- instance.prune(validKeys)
  --- Drop every remembered key that is not in validKeys, an array of the keys that still
  --- exist right now. Persists and drops the rank memo only when a key was actually
  --- removed, so calling this on every open of a list that has not changed costs one pass
  --- over a short array and nothing else.
  function instance.prune(validKeys)
    local valid = {}
    for _, k in ipairs(validKeys or {}) do valid[k] = true end
    local out, removed = {}, false
    for _, k in ipairs(loaded()) do
      if valid[k] then
        out[#out + 1] = k
      else
        removed = true
      end
    end
    if not removed then return end
    order = out
    ranks = nil
    hs.settings.set(settingsKey, order)
  end

  return instance
end

return M
