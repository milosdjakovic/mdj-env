--- === Emoji.hammerspoon backend ===
---
--- The emoji picker built over the Chooser atom, one of the backends the Emoji facade
--- can select. It owns the vendored emoji dataset loaded when this backend is configured,
--- plus a small persisted pick memory that floats your most used glyphs to the top of the
--- empty browse view, and the chooser instance built over both. It owns only a transient
--- prewarm timer that self stops once the leading icons are warmed, and no watcher or
--- eventtap, and the pick memory lives in hs.settings, so nothing needs an explicit start
--- or stop, matching the lifecycle contract.
---
--- The match is keyword based, not exact name. Each entry carries a lowercased haystack
--- folding its name, its shortcode aliases, its tags, and its category, so a word like
--- happy or money or a group word like food or animal finds the right glyphs without the
--- precise Unicode name. The decision trail, the data source, and the tradeoffs live in
--- CLAUDE.md beside this file.
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
obj._chooser = nil          -- the Chooser factory (has .new)
obj._theme = nil
obj._placeholder = nil
obj._shortcutPanel = nil     -- { onPositioned, onActivity, onClose }
obj._onInsert = nil          -- function(glyph), the effect of a chosen row

-- Owned state
obj._data = nil              -- the vendored emoji list, loaded once when this backend wins
obj._instance = nil          -- the built Chooser instance
obj._surface = nil           -- dot-called navigation adapter over the instance
obj._iconCache = nil         -- glyph -> hs.image, each rendered once and reused
obj._iconCanvas = nil        -- one reused canvas the glyph icons are drawn through
obj._prewarmTimer = nil      -- transient, warms the empty-state icons after configure
obj._byGlyph = nil           -- glyph string -> entry, maps a remembered pick back to its row
obj._recency = nil           -- persisted pick memory, { n = tick, g = { [glyph] = { v, k } } }

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

-- The most rows a query returns. The match runs over the whole set, so any glyph is
-- still findable by typing, this only bounds the visible list. It matters more than
-- cosmetics, since a first view renders one icon per visible row on the main thread,
-- so this is the ceiling on that per keystroke render cost, kept modest so even a
-- broad one letter query stays responsive over the several thousand row set. It also
-- bounds how many distinct icons a view can render, which paces the icon memory below,
-- since a narrow query renders far fewer than a broad one.
local MAX_RESULTS = 100

-- How many of your most-used glyphs lead the empty browse view, ranked by the decaying
-- score below. Kept small so the recents sit at the top without pushing the browse list
-- far down, and small enough that rendering their icons is trivial next to MAX_RESULTS.
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

-- The glyph icon geometry. The canvas is rendered only about as large as the chooser row
-- actually shows the icon, times the retina scale, since hs.chooser scales whatever we give it
-- into that fixed slot and any extra resolution is memory we hold until reload for nothing. 44
-- keeps a row crisp on a 2x display while costing several times less per glyph than the old 72,
-- measured at about 30KB versus 143KB. The text size is the glyph within that square, nudged
-- down a touch to center it.
local ICON_SIZE = 44
local ICON_TEXT_SIZE = 32

-- Split a query into whitespace tokens. A multi word query narrows with AND, so
-- every token must be found for an entry to match, which is how "smiling cat"
-- reaches the cat faces rather than every smile.
local function tokenize(q)
  local t = {}
  for w in q:gmatch("%S+") do t[#t + 1] = w end
  return t
end

-- Score a matched entry so the closest name floats up within its kind. An exact alias
-- or an exact name is the strongest signal, then a name that starts with the whole
-- query, then the count of tokens found anywhere in the haystack. This score never
-- crosses the emoji and symbol tiers, the sort puts every matching emoji above every
-- matching symbol first and only then applies this score, so score orders like against
-- like. Ties keep the upstream order, which is grouped and roughly common first.
local function score(entry, q, toks)
  local s = 0
  local name = (entry.n or ""):lower()
  for alias in (entry.a or ""):gmatch("%S+") do
    if alias == q then s = s + 100 break end
  end
  if name == q then s = s + 80 end
  if name:sub(1, #q) == q then s = s + 40 end
  for _, tok in ipairs(toks) do
    if entry.k:find(tok, 1, true) then s = s + 5 end
  end
  return s
end

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

--- Emoji.hammerspoon:_glyphIcon(glyph)
--- Method
--- The row icon for a glyph. hs.chooser has no emoji rendering, so the glyph is drawn
--- once through one reused canvas into an hs.image and cached, so it sits in the icon
--- slot like an app icon rather than inline in the title. A glyph is rendered at most
--- once ever and kept, so a glyph costs its render and its memory at most one time, and
--- false marks a glyph that produced no image so it is not retried. The render is not
--- reclaimable until a reload, so caching each glyph exactly once is the leanest option,
--- a re-render would only allocate more that never comes back. MAX_RESULTS bounds how
--- many distinct glyphs a session can reach, which is what keeps the total in hand.
function obj:_glyphIcon(glyph)
  local cache = self._iconCache
  local img = cache[glyph]
  if img == nil then
    local c = self._iconCanvas
    c[1].text = glyph
    img = c:imageFromCanvas() or false
    cache[glyph] = img
  end
  return img or nil
end

-- One entry to a chooser row. The glyph is the row icon, the name is the title, the
-- aliases ride in the subtitle as the shortcodes you might type, and the item is just
-- the glyph string, all the dispatcher needs.
function obj:_rowFor(entry)
  return { title = entry.n, subTitle = entry.a, image = self:_glyphIcon(entry.e), item = entry.e }
end

--- Emoji.hammerspoon:_rows(query)
--- Method
--- The row supplier. An empty field leads with your most used glyphs, highest decaying
--- score first with the most recent pick breaking a tie, then fills the rest of the leading
--- slice in upstream order with those recents removed so none appears twice, which is emoji
--- first since they lead the dataset. A query keeps every entry whose
--- haystack contains all of the query tokens, then orders them with emoji ranked above
--- symbols and by relevance within each. Either way the list is capped at MAX_RESULTS, which
--- bounds the icons rendered per open, the match itself still runs over the whole set
--- so any glyph stays findable by typing. The haystack is already lowercased by the
--- generator, so only the query is folded here.
function obj:_rows(query)
  local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local out = {}
  if q == "" then
    local seen = {}
    for _, glyph in ipairs(self:_recentGlyphs()) do
      out[#out + 1] = self:_rowFor(self._byGlyph[glyph])
      seen[glyph] = true
    end
    for i = 1, #self._data do
      if #out >= MAX_RESULTS then break end
      local e = self._data[i]
      if not seen[e.e] then out[#out + 1] = self:_rowFor(e) end
    end
    return out
  end
  local toks = tokenize(q)
  local matched = {}
  for i, e in ipairs(self._data) do
    local ok = true
    for _, tok in ipairs(toks) do
      if not e.k:find(tok, 1, true) then ok = false break end
    end
    if ok then matched[#matched + 1] = { e = e, i = i, s = score(e, q, toks) } end
  end
  -- Emoji win the top tier, so a query lists every matching emoji before the first
  -- matching symbol rather than interleaving the two by score. The row's own t tag from
  -- the generator decides the kind, e for emoji, so the ranking never guesses it. Within
  -- a tier the text score orders, then upstream order breaks a tie.
  table.sort(matched, function(x, y)
    local xEmoji = x.e.t == "e"
    local yEmoji = y.e.t == "e"
    if xEmoji ~= yEmoji then return xEmoji end
    if x.s ~= y.s then return x.s > y.s end
    return x.i < y.i
  end)
  for i = 1, math.min(MAX_RESULTS, #matched) do out[#out + 1] = self:_rowFor(matched[i].e) end
  return out
end

--- Emoji.hammerspoon:rows(query) -> rows
--- Method
--- The rows for a query, for a surface other than our own chooser to present. Public because
--- this backend's list is worth showing elsewhere, unlike a system picker's, which is why the
--- facade asks whether its chosen backend answers this at all.
function obj:rows(query)
  return self:_rows(query)
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
--- Wire the injected collaborators and build the chooser. opts carries the Chooser
--- factory, the shared theme, the placeholder, the docked shortcut panel callbacks,
--- and onInsert, the closure that acts on the chosen glyph. The dataset and pick memory
--- are loaded first, here rather than at facade load, so this cost is paid only when the
--- facade selects this backend.
function obj:configure(opts)
  opts = opts or {}
  self:_load()
  self._chooser = opts.chooser
  self._theme = opts.theme
  self._placeholder = opts.placeholder or "Search by name or keyword"
  self._shortcutPanel = opts.shortcutPanel or {}
  self._onInsert = opts.onInsert or function() end

  -- One reused canvas draws every glyph icon, far cheaper than a canvas per glyph,
  -- and the cache keeps each glyph rendered once. See _glyphIcon.
  self._iconCache = {}
  self._iconCanvas = hs.canvas.new({ x = 0, y = 0, w = ICON_SIZE, h = ICON_SIZE })
  self._iconCanvas[1] = { type = "text", text = "", textSize = ICON_TEXT_SIZE,
    textAlignment = "center", frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }

  local sp = self._shortcutPanel
  self._instance = self._chooser.new({
    theme = self._theme,
    placeholder = self._placeholder,
    -- Opt out of the shared matcher. This tool filters over a hidden haystack, the folded
    -- name, aliases, tags, and category in k, with its own token AND scan and ranking, not
    -- over the visible title and subtitle the shared matcher would see, so letting the atom
    -- filter would drop a glyph matched only by a tag. It also caps the visible rows to bound
    -- the icon render, which the atom styling every survivor would undo. So _rows owns the
    -- query end to end and the atom does no second pass.
    matcher = false,
    rows = function(query) return self:_rows(query) end,
    onSelect = function(glyph)
      self:insert(glyph)
    end,
    onPositioned = sp.onPositioned,
    onActivity = sp.onActivity,
    onClose = sp.onClose,
  })

  -- Dot-called navigation adapter over the colon-called Chooser instance, so the
  -- root's shared activeChooser and routeNav registry drives it like the others.
  local instance = self._instance
  self._surface = {
    isShowing = function() return instance:isShowing() end,
    selectNext = function() instance:selectNext() end,
    selectPrev = function() instance:selectPrev() end,
    insertSelected = function() instance:insertSelected() end,
    hide = function() instance:hide() end,
  }

  -- Warm the empty-state icons in the background so the first open is instant. The
  -- match runs over everything but only MAX_RESULTS show at once, so warming that
  -- leading slice covers the first open, and typed queries render any remainder on
  -- demand, each cached after.
  self:_prewarm(MAX_RESULTS)
  return self
end

--- Emoji.hammerspoon:_prewarm(count)
--- Method
--- Render the first count glyph icons into the cache in small background batches, so
--- the render cost is paid before the first open rather than during it, and never in
--- one blocking pass. Self stopping when done, and it replaces any prior run.
function obj:_prewarm(count)
  if self._prewarmTimer then self._prewarmTimer:stop() end
  -- Warm the remembered glyphs first, they lead the empty view and may sit outside the
  -- leading slice below. There are at most RECENTS_MAX of them so the extra render is trivial.
  for _, glyph in ipairs(self:_recentGlyphs()) do self:_glyphIcon(glyph) end
  local data = self._data
  local target = math.min(count, #data)
  local i = 0
  self._prewarmTimer = hs.timer.doEvery(0.03, function()
    local stop = math.min(i + 25, target)
    while i < stop do i = i + 1; self:_glyphIcon(data[i].e) end
    if i >= target and self._prewarmTimer then
      self._prewarmTimer:stop()
      self._prewarmTimer = nil
    end
  end)
end

--- Emoji.hammerspoon:show()
--- Method
--- Open the picker.
function obj:show()
  if self._instance then self._instance:show() end
end

--- Emoji.hammerspoon:isShowing()
--- Method
--- Whether the picker is open. Safe before configure.
function obj:isShowing()
  return self._instance ~= nil and self._instance:isShowing()
end

--- Emoji.hammerspoon:surface()
--- Method
--- The dot-called navigation adapter, for the facade to hand the root's shared
--- choosers list.
function obj:surface()
  return self._surface
end

return obj
