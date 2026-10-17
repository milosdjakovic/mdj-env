--- === Emoji.hammerspoon backend ===
---
--- The emoji picker's own data and dispatch, one of the backends the Emoji facade can
--- select. It owns the vendored emoji dataset loaded when this backend is configured, plus
--- a small persisted pick memory that floats your most used glyphs to the top of the empty
--- browse view. It owns no timer, watcher or eventtap, and the pick memory lives in
--- hs.settings, so nothing needs an explicit start or stop, matching the lifecycle contract.
---
--- Migrated onto host/stage, the trickle migration. This backend owns no Chooser instance
--- and builds no window any more, having never been the layer that showed one. The facade
--- is what declares a presentation now, plugins/emoji/manifest.lua, and its own rows and
--- insert forward straight through to this backend's identically named members, the same
--- forwarding the facade always did for a scope's own rows and run. This file keeps the
--- dataset, the matching, the icon cache, and the pick memory, none of which is presentation
--- wiring, and loses only the Chooser.new call and the navigation adapter that gave it
--- something to answer for.
---
--- The match belongs to the shared search since phase three of docs/PLAN-UNIFIED-SEARCH.md.
--- Each row declares its name as the title, its shortcodes as the subtitle, and the words the
--- generator folded in after the name, aliases, tags and category, as keywords, so a word like
--- happy or money or a group word like food or animal still finds the right glyphs without the
--- precise Unicode name. An emoji is tier zero and a symbol tier one. The decision trail, the
--- data source, and the tradeoffs live in AGENTS.md beside this file.
---
--- Rows are data, never functions. Each row carries only the glyph string as its item,
--- which the Chooser serialises and hands back to onSelect, and the injected onInsert
--- decides the effect. So the backend never learns what a pick ultimately does, the
--- Command pattern with the command encoded as data.

local obj = {}
obj.__index = obj

-- The backend name, used by the facade when it logs which backend it selected.
obj.name = "hammerspoon"

-- Injected via configure
obj._onInsert = nil          -- function(glyph), the effect of a chosen row

-- Owned state
obj._data = nil              -- the vendored emoji list, loaded once when this backend wins
obj._byGlyph = nil           -- glyph string -> entry, maps a remembered pick back to its row
obj._recency = nil           -- persisted pick memory, { n = tick, g = { [glyph] = { v, k } } }
obj._rowOf = nil             -- glyph string -> its row, built once per load, see _rowFor

-- Load the vendored dataset by absolute path, the loadfile pattern the spoons use, since a spoon
-- directory is not on package.path. The dataset is a Lua table for one measured reason,
-- hs.json.decode is quadratic in the number of objects in an array, so the same rows cost
-- three seconds as json against six milliseconds through loadfile, and this load runs on
-- every config reload. regenerate.sh is the one place that produces the file, and it writes
-- it from inside Hammerspoon so Lua escapes its own strings. This backend lives one level
-- below the spoon root under providers/, so the data file sits one directory up beside the
-- facade.
local providerPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local dataPath = providerPath .. "../data.lua"

-- How many of your most-used glyphs lead the empty browse view, ranked by the decaying
-- score below. Kept small so the recents sit at the top without pushing the browse list
-- far down, and small enough that rendering their icons is trivial next to the presentation's
-- rowLimit.
local RECENTS_MAX = 12

-- The recency memory is a decaying score, not a raw count, so a stale favorite can be
-- dethroned by a fresh one within reasonable use rather than never. On each pick the
-- glyph's score becomes score * DECAY ^ (picks since it was last touched) + 1, so a glyph
-- picked constantly converges to the geometric limit 1 / (1 - DECAY), which is the natural
-- ceiling. DECAY 0.9 sets that ceiling at 10, and a glyph left unused loses about a tenth
-- of its standing per pick of anything else. An entry whose decayed score falls below
-- PRUNE_FLOOR is dropped, so the memory stays tiny. The score is computed lazily from the
-- global pick tick, so a pick is one multiply and one add and never rewrites other rows.
local DECAY = 0.9
local PRUNE_FLOOR = 0.05

-- The hs.settings key holding the pick memory, persisted like the launcher's timeline so a
-- favorite survives a reload and a reboot.
local RECENCY_KEY = "emojiRecency"

--- Emoji.hammerspoon:isAvailable()
--- Method
--- Always available. This backend is built in and depends on nothing external, so it is
--- the safe fallback at the end of any priority order.
function obj:isAvailable()
  return true
end

--- Emoji.hammerspoon:_load()
--- Method
--- Load the vendored dataset and the pick memory. Folded out of a lifecycle init so the
--- facade only pays it on the backend it actually selects. No side effects beyond reading
--- the file and the settings, and an absent, unreadable, or malformed file degrades to an
--- empty list with one console line rather than an error, so a bad dataset costs the picker
--- its rows and never the config's load. A stored glyph the current dataset no longer
--- carries is skipped when the recents are built, so a regenerated data.lua never breaks
--- the list and the memory never has to be migrated.
function obj:_load()
  self._data = nil
  local chunk, loadErr = loadfile(dataPath)
  if not chunk then
    print("Emoji: the dataset failed to load, " .. tostring(loadErr))
  else
    local ok, loaded = pcall(chunk)
    if not ok then
      print("Emoji: the dataset failed to run, " .. tostring(loaded))
    elseif type(loaded) ~= "table" then
      print("Emoji: the dataset did not return a table, the picker will be empty")
    else
      self._data = loaded
    end
  end
  self._data = self._data or {}
  self._byGlyph = {}
  self._rowOf = {}
  for _, e in ipairs(self._data) do self._byGlyph[e.e] = e end
  local r = hs.settings.get(RECENCY_KEY)
  if type(r) ~= "table" or type(r.g) ~= "table" then r = { n = 0, g = {} } end
  self._recency = r
end

--- Emoji.hammerspoon:_recentGlyphs()
--- Method
--- The remembered glyphs that lead the empty browse view, highest decayed score first with
--- the most recent pick breaking a tie, capped at RECENTS_MAX. Each score is decayed to the
--- current tick on read, so no write is needed to rank them, and a glyph absent from the
--- current dataset is skipped so the list is always renderable.
function obj:_recentGlyphs()
  local n = self._recency.n or 0
  local ranked = {}
  for glyph, rec in pairs(self._recency.g) do
    if self._byGlyph[glyph] then
      local eff = (rec.v or 0) * (DECAY ^ (n - (rec.k or 0)))
      ranked[#ranked + 1] = { glyph = glyph, eff = eff, k = rec.k or 0 }
    end
  end
  table.sort(ranked, function(x, y)
    if x.eff ~= y.eff then return x.eff > y.eff end
    return x.k > y.k
  end)
  local out = {}
  for i = 1, math.min(RECENTS_MAX, #ranked) do out[#out + 1] = ranked[i].glyph end
  return out
end

--- Emoji.hammerspoon:_promote(glyph)
--- Method
--- Record a pick into the persisted memory, then save. This is the Observer feeding the
--- recents timeline, the same shape the launcher uses, and the only writer of the memory.
--- The picked glyph's own score is first decayed to the new tick and then bumped by one, so
--- it climbs toward the ceiling while every unpicked glyph decays only lazily at read. Any
--- entry whose decayed score has fallen below PRUNE_FLOOR is dropped so the table stays tiny.
function obj:_promote(glyph)
  if not glyph or glyph == "" then return end
  local mem = self._recency
  local n = (mem.n or 0) + 1
  mem.n = n
  local rec = mem.g[glyph]
  if rec then
    rec.v = (rec.v or 0) * (DECAY ^ (n - (rec.k or 0))) + 1
  else
    rec = { v = 1, k = n }
    mem.g[glyph] = rec
  end
  rec.k = n
  for g, r in pairs(mem.g) do
    if g ~= glyph and (r.v or 0) * (DECAY ^ (n - (r.k or 0))) < PRUNE_FLOOR then
      mem.g[g] = nil
    end
  end
  hs.settings.set(RECENCY_KEY, mem)
end

-- The words the generator folded into k after the name, aliases, tags and category for an
-- emoji, and the category word and hand added synonyms for a symbol, as comma separated
-- phrases. data.lua keeps them only inside k, lowered, with the name in front, so they are
-- read back from there rather than regenerated. Each word is its own phrase, except that an
-- ampersand joins its neighbours into one, so a category like smileys & emotion stays one
-- phrase and its words can be typed run together. A word repeated is kept once.
local function keywordsOf(entry)
  local k = entry.k or ""
  local name = (entry.n or ""):lower() .. " "
  if k:sub(1, #name) == name then k = k:sub(#name + 1) end
  local phrases, join = {}, false
  for w in k:gmatch("%S+") do
    if w == "&" and #phrases > 0 then
      phrases[#phrases] = phrases[#phrases] .. " &"
      join = true
    elseif join then
      phrases[#phrases] = phrases[#phrases] .. " " .. w
      join = false
    else
      phrases[#phrases + 1] = w
    end
  end
  local out, seen = {}, {}
  for _, ph in ipairs(phrases) do
    if not seen[ph] then
      seen[ph] = true
      out[#out + 1] = ph
    end
  end
  return table.concat(out, ", ")
end

-- One entry to a chooser row, built once per load and kept, since the supplier hands every
-- row to the shared search on every keystroke and the rows never change between loads. The
-- glyph is the row icon, the name is the title, the aliases ride in the subtitle as the
-- shortcodes you might type, the rest of the folded words are keywords, and the item is just
-- the glyph string, all the dispatcher needs. tier puts every emoji above every symbol that
-- matches, the generator's own t tag deciding the kind, so a broad word like arrow lists the
-- emoji arrows before the glyph arrows rather than weaving them together. The icon is a table
-- spec of the emoji and never a key, since the glyph is the content being picked, so changing
-- the icon set never changes which emoji a row shows. It has no sf entry by design, since an
-- SF Symbol cannot stand for the emoji being picked, and it is not in a manifest so the dry
-- gate's coverage report never counts it. Olm draws it.
function obj:_rowFor(entry)
  local row = self._rowOf[entry.e]
  if row then return row end
  row = {
    title = entry.n,
    subTitle = entry.a,
    keywords = keywordsOf(entry),
    tier = entry.t == "e" and 0 or 1,
    icon = { emoji = entry.e },
    item = entry.e,
  }
  self._rowOf[entry.e] = row
  return row
end

--- Emoji.hammerspoon:_rows()
--- Method
--- The row supplier, every entry in the resting order, for the shared search to filter and
--- rank. It reads no query. Your most used glyphs lead, highest decaying score first with the
--- most recent pick breaking a tie, then every other entry in upstream order with those
--- recents removed so none appears twice, which is emoji first since they lead the dataset.
--- An empty field shows that order, and the presentation's rowLimit cuts it after ranking,
--- so a typed query ranks the whole set and the limit keeps its best rows. The recents only
--- shape the empty view, since under a typed query the search orders by how well a row
--- matched and the index decides only between rows it calls equal.
function obj:_rows()
  local out = {}
  local seen = {}
  for _, glyph in ipairs(self:_recentGlyphs()) do
    out[#out + 1] = self:_rowFor(self._byGlyph[glyph])
    seen[glyph] = true
  end
  for i = 1, #self._data do
    local e = self._data[i]
    if not seen[e.e] then out[#out + 1] = self:_rowFor(e) end
  end
  return out
end

--- Emoji.hammerspoon:rows(query) -> rows
--- Method
--- Every row, for a surface other than our own chooser to present and rank. Public because
--- this backend's list is worth showing elsewhere, unlike a system picker's, which is why the
--- facade asks whether its chosen backend answers this at all. The query is accepted and
--- ignored, since filtering belongs to the shared search.
function obj:rows()
  return self:_rows()
end

--- Emoji.hammerspoon:insert(glyph)
--- Method
--- The effect of choosing a glyph, remembering the pick and inserting it. Paired with rows so
--- another surface can list and pick without knowing what a pick costs, and used by our own
--- chooser too, so both routes remember a pick identically.
function obj:insert(glyph)
  if not glyph then return end
  self:_promote(glyph)
  self._onInsert(glyph)
end

--- Emoji.hammerspoon:configure(opts)
--- Method
--- Wire onInsert, the closure that acts on the chosen glyph, and load the dataset and pick
--- memory. Both are loaded first, here rather than at facade load, so this cost is paid
--- only when the facade selects this backend. Migrated onto host/stage, this backend no
--- longer reads a Chooser factory, a theme, a placeholder, or the docked panel triple, none
--- of which it has anywhere left to hand to, the facade's own presentation carrying the
--- static matcher and placeholder now and host/stage owning the panel for the life of its
--- one instance.
function obj:configure(opts)
  opts = opts or {}
  self:_load()
  self._onInsert = opts.onInsert or function() end

  return self
end

-- show, isShowing, and surface are gone, the trickle migration, deleted along with the
-- Chooser.new block that gave them something to answer for. The facade's own show now
-- reaches the shared stage directly through cfg.stagePresent when this backend is the one
-- that won, host/stage's own surfaceFor(identity) answering the five generic navigation
-- verbs once plugins/emoji/manifest.lua's own presentation exists for the registrar to find.

return obj
