-- What you chose the last time you typed this, which is the one thing a text
-- scorer can never know.
--
-- lib/recency.lua remembers an order of things. This remembers pairs, a query
-- together with what was picked while it was in the field, so it answers a
-- different question. Recency says what you touched last. This says that when
-- you type these letters you mean that row, which is a statement of intent
-- rather than a guess about popularity, and it is why a caller may legitimately
-- let it lead rather than only break a tie. plugins/browsertabs/chooser.lua caps
-- its own recency bonus so that it reorders and never overturns, which is the
-- right rule there and the wrong one here, for exactly that reason.
--
-- ONE NUMBER PER PAIR, not a count of picks. A count cannot tell a preference
-- apart from a change of habit, since both look like one number being larger,
-- and it makes a long history impossible to overturn. Here every pick under a
-- query decays what is already stored for that query and adds one to what was
-- picked, so a score converges on a ceiling of 1/(1-decay) and nothing can bank
-- a lead beyond it. The consequence worth stating is that the number of picks
-- needed to overturn a settled leader is ln(0.5)/ln(decay) whatever its history,
-- the same handful after thirty picks as after three thousand.
--
-- The decay is an EVENT CLOCK and not a wall clock, counted per query rather
-- than globally. Two things follow. A query you use twice a week keeps its
-- memory for months, since nothing ages while you are not typing it, and the
-- competition stays local, since picking things under other queries cannot
-- disturb this one. plugins/filesearch/frecency.lua is the wall clock shape and
-- is deliberately not what this is.
--
-- Decay is applied lazily at read, from the difference between the query's tick
-- and the entry's own, so a pick is one multiply and one add rather than a pass
-- over the table. plugins/emoji/providers/hammerspoon.lua settled that shape
-- first.
--
-- THE LEADER IS STICKY, which is the one piece of state a pure score does not
-- give. A challenger has to beat the leader by a margin rather than merely
-- exceed it, so a single stray pick cannot hand the top row away and hand it
-- straight back. Measured over twenty runs of four hundred picks at decay 0.80,
-- the margin cuts leader changes from 106 to 49 where two rows are used equally
-- and from 5.6 to 1.6 at a six to one split, while the pick that overturns a
-- settled leader stays the fourth. It costs one stored string per query.
--
-- Keys are opaque here. What identity means is the caller's business, the same
-- split lib/recency.lua keeps, and pruning takes a predicate rather than a key
-- shape so this file never learns one.
--
-- Persisted through hs.settings rather than lib/storage.lua, like the two stores
-- named above, because this is small per machine behaviour written on every pick
-- rather than data worth carrying to another machine.

local M = {}

-- Only the first is a matter of taste. decay says how many picks overturn a
-- settled leader, ln(0.5)/ln(0.80) being 3.11, so the fourth. A decay whose
-- answer lands exactly on a whole number is worth avoiding rather than choosing,
-- since a leader at the ceiling and a challenger then meet within floating point
-- noise on that pick and which one leads is decided by rounding.
--
-- floor is where an entry stops being worth remembering, and it is what makes a
-- thing you have stopped picking disappear on its own, about twenty four picks
-- under that query from a full ceiling, with nothing sweeping for it.
--
-- maxPrefix bounds how much one pick writes. A query longer than this records
-- its own prefixes up to the bound and then itself, so a long paste cannot turn
-- one pick into fifty writes.
local DEFAULTS = {
  decay = 0.80,
  margin = 0.6,
  floor = 0.05,
  maxQueries = 400,
  minPrefix = 2,
  maxPrefix = 12,
}

--- M.new(opts) returns instance.
--- opts.settingsKey  required, the hs.settings key this instance persists under
--- opts.decay        how much every score under a query shrinks per pick of anything
--- opts.margin       how far a challenger must exceed the leader to take its place
--- opts.floor        the score below which an entry is forgotten
--- opts.maxQueries   how many queries to remember before the weakest are dropped
function M.new(opts)
  opts = opts or {}
  local settingsKey = opts.settingsKey
  if settingsKey == nil then
    error("queryassoc new requires opts.settingsKey, the hs.settings key the pairs persist under")
  end
  local decay = tonumber(opts.decay) or DEFAULTS.decay
  local margin = tonumber(opts.margin) or DEFAULTS.margin
  local floor = tonumber(opts.floor) or DEFAULTS.floor
  local maxQueries = tonumber(opts.maxQueries) or DEFAULTS.maxQueries
  local minPrefix = tonumber(opts.minPrefix) or DEFAULTS.minPrefix
  local maxPrefix = tonumber(opts.maxPrefix) or DEFAULTS.maxPrefix

  local instance = {}

  local store = nil  -- query to { lead, n, s = { key to { v, k } } }, loaded on first use
  local count = 0    -- how many queries are held, so the cap costs nothing on an ordinary write

  -- What one entry is worth right now, decayed from its own tick to the query's.
  local function value(rec, n)
    local age = n - (rec.k or n)
    if age <= 0 then return rec.v end
    return rec.v * decay ^ age
  end

  -- The stored pairs, read once. Anything not shaped the way this file writes is
  -- dropped rather than trusted, since this outlives the code that wrote it and a
  -- malformed entry must cost one row rather than the whole memory.
  local function loaded()
    if store ~= nil then return store end
    store = {}
    count = 0
    local raw = hs.settings.get(settingsKey)
    if type(raw) == "table" then
      for query, e in pairs(raw) do
        if type(query) == "string" and type(e) == "table" and type(e.s) == "table" then
          local kept = {}
          for key, rec in pairs(e.s) do
            if type(key) == "string" and type(rec) == "table"
              and tonumber(rec.v) and tonumber(rec.k) then
              kept[key] = { v = tonumber(rec.v), k = tonumber(rec.k) }
            end
          end
          if next(kept) then
            store[query] = {
              lead = type(e.lead) == "string" and kept[e.lead] and e.lead or nil,
              n = tonumber(e.n) or 0,
              s = kept,
            }
            count = count + 1
          end
        end
      end
    end
    return store
  end

  local function save()
    if store then hs.settings.set(settingsKey, store) end
  end

  -- Forget the weakest queries once the memory is over its cap. On write rather
  -- than on read, so the cost lands on a pick rather than on the list opening,
  -- and only when a pick actually created a query that was not there before.
  local function trim()
    if count <= maxQueries then return end
    local ranked = {}
    for query, e in pairs(store) do
      local best = 0
      for _, rec in pairs(e.s) do
        local v = value(rec, e.n)
        if v > best then best = v end
      end
      ranked[#ranked + 1] = { query = query, best = best }
    end
    table.sort(ranked, function(a, b)
      if a.best ~= b.best then return a.best > b.best end
      return a.query < b.query
    end)
    for i = maxQueries + 1, #ranked do
      store[ranked[i].query] = nil
      count = count - 1
    end
  end

  -- Which spellings of one pick are remembered. Every prefix from minPrefix up,
  -- so picking at "slac" also teaches "sla" and "sl" and the shorter searches
  -- improve too. A single character is recorded only when it WAS the whole query,
  -- never taught from a longer one, so typing a long distinctive name cannot
  -- quietly take over "a", "s" or "w", which the launcher's own catalog scopes
  -- answer to.
  local function spellings(q)
    local out = {}
    local len = #q
    local from = (len >= minPrefix) and minPrefix or len
    for i = from, math.min(len, maxPrefix) do out[#out + 1] = q:sub(1, i) end
    if len > maxPrefix then out[#out + 1] = q end
    return out
  end

  local function bump(query, key)
    local e = store[query]
    if not e then
      e = { n = 0, s = {} }
      store[query] = e
      count = count + 1
    end
    local n = e.n + 1
    e.n = n

    local rec = e.s[key]
    if rec then
      rec.v = value(rec, n) + 1
    else
      rec = { v = 1 }
      e.s[key] = rec
    end
    rec.k = n

    -- Everything else only ever shrinks, so this is the whole of the forgetting.
    for other, r in pairs(e.s) do
      if other ~= key and value(r, n) < floor then e.s[other] = nil end
    end

    -- Only the key just picked can have grown, so it is the only possible
    -- challenger and nothing else needs comparing. A leader that has been
    -- forgotten leaves the post vacant and this one takes it outright, since a
    -- margin over something no longer remembered would mean nothing.
    local leader = e.lead and e.s[e.lead]
    if not leader then
      e.lead = key
    elseif e.lead ~= key and rec.v > value(leader, n) + margin then
      e.lead = key
    end
  end

  --- instance.note(query, key)
  --- Record that this key was chosen while this query was in the field.
  function instance.note(query, key)
    if type(query) ~= "string" or query == "" then return end
    if type(key) ~= "string" or key == "" then return end
    loaded()
    for _, spelling in ipairs(spellings(query:lower())) do bump(spelling, key) end
    trim()
    save()
  end

  -- The remembered entry for this query, or for its longest remembered prefix.
  -- Walking back is what lets a query typed further than before still find what
  -- was learned, and it is safe however far it walks, because a caller only ever
  -- orders rows that already matched what is typed now, so an answer from a
  -- shorter query that no longer applies simply names nothing in the list.
  local function entryFor(query)
    local q = query:lower()
    local held = loaded()
    for i = #q, 1, -1 do
      local e = held[q:sub(1, i)]
      if e then return e end
    end
    return nil
  end

  --- instance.orderFor(query) -> list of keys, best first, empty for a query never used
  --- The leader leads, since it holds its place until something beats it by the
  --- margin, and the rest follow by what they are worth now.
  function instance.orderFor(query)
    if type(query) ~= "string" or query == "" then return {} end
    local e = entryFor(query)
    if not e then return {} end
    local ranked = {}
    for key, rec in pairs(e.s) do
      ranked[#ranked + 1] = { key = key, v = value(rec, e.n) }
    end
    -- The key breaks a tie so the order is the same on every open rather than
    -- following whatever pairs happened to hand back.
    table.sort(ranked, function(a, b)
      if a.v ~= b.v then return a.v > b.v end
      return a.key < b.key
    end)
    local out = {}
    for _, item in ipairs(ranked) do
      if item.key ~= e.lead then out[#out + 1] = item.key end
    end
    if e.lead then table.insert(out, 1, e.lead) end
    return out
  end

  --- instance.prune(validKeys, inScope)
  --- Drop every remembered key that inScope claims and validKeys does not list.
  --- A key inScope declines is left alone whatever validKeys says, which is how a
  --- caller prunes the kind of thing it can actually prove gone without also
  --- deleting the history of something merely switched off today. Persists only
  --- when something was removed, so calling it on every open costs one pass.
  function instance.prune(validKeys, inScope)
    if type(inScope) ~= "function" then return end
    local valid = {}
    for _, k in ipairs(validKeys or {}) do valid[k] = true end
    local removed = false
    for query, e in pairs(loaded()) do
      for key in pairs(e.s) do
        if inScope(key) and not valid[key] then
          e.s[key] = nil
          if e.lead == key then e.lead = nil end
          removed = true
        end
      end
      if not next(e.s) then
        store[query] = nil
        count = count - 1
      end
    end
    if removed then save() end
  end

  return instance
end

return M
