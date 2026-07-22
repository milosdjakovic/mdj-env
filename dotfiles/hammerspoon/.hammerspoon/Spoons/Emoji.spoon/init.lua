--- === Emoji ===
---
--- A semantic emoji picker, the built in Hyper+J chooser.
---
--- It is a small coordinator over the Chooser atom. It owns one thing of its own,
--- the vendored emoji dataset loaded once at init, plus the chooser instance built
--- over it, so it earns a spoon rather than inline wiring in the composition root.
--- It owns no watcher, timer, or eventtap, so it has no start or stop, matching the
--- lifecycle contract.
---
--- The match is keyword based, not exact name. Each entry carries a lowercased
--- haystack folding its name, its shortcode aliases, its tags, and its category, so
--- a word like happy or money or a group word like food or animal finds the right
--- glyphs without the precise Unicode name. The decision trail, the data source, and
--- the tradeoffs live in CLAUDE.md beside this file.
---
--- Rows are data, never functions. Each row carries only the glyph string as its
--- item, which the Chooser serialises and hands back to onSelect, and the injected
--- onInsert decides the effect. So the spoon never learns what a pick ultimately
--- does, the Command pattern with the command encoded as data.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Emoji"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Injected via configure
obj._chooser = nil          -- the Chooser factory (has .new)
obj._theme = nil
obj._placeholder = nil
obj._shortcutPanel = nil     -- { onPositioned, onActivity, onClose }
obj._onInsert = nil          -- function(glyph), the effect of a chosen row

-- Owned state
obj._data = nil              -- the vendored emoji list, loaded once at init
obj._instance = nil          -- the built Chooser instance
obj._surface = nil           -- dot-called navigation adapter over the instance
obj._iconCache = nil         -- glyph -> hs.image, each rendered once and reused
obj._iconCanvas = nil        -- one reused canvas the glyph icons are drawn through
obj._prewarmTimer = nil      -- transient, warms the empty-state icons after configure

-- Load the vendored dataset by absolute path, the Capture idiom, since a spoon
-- directory is not on package.path. hs.json.read parses it natively, so there is no
-- Lua escaping to get wrong, and regenerate.sh is the one place that produces it.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

-- The most rows a query returns. The match runs over the whole set, so any glyph is
-- still findable by typing, this only bounds the visible list. It matters more than
-- cosmetics, since a first view renders one icon per visible row on the main thread,
-- so this is the ceiling on that per keystroke render cost, kept modest so even a
-- broad one letter query stays responsive over the several thousand row set. It also
-- bounds how many distinct icons a view can render, which paces the icon memory below,
-- since a narrow query renders far fewer than a broad one.
local MAX_RESULTS = 100

-- The glyph icon geometry, matching the launcher's glyph icons so an emoji row lines
-- up with an app row, a large glyph centered in a square, nudged down a touch.
local ICON_SIZE = 72
local ICON_TEXT_SIZE = 52

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

--- Emoji:init()
--- Method
--- Load the vendored dataset. No side effects beyond reading the file, and an
--- absent or unreadable file degrades to an empty list rather than an error.
function obj:init()
  self._data = hs.json.read(spoonPath .. "data.json") or {}
  return self
end

--- Emoji:_glyphIcon(glyph)
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

--- Emoji:_rows(query)
--- Method
--- The row supplier. An empty field lists a leading slice in upstream order to browse,
--- which is emoji first since they lead the dataset. A query keeps every entry whose
--- haystack contains all of the query tokens, then orders them with emoji ranked above
--- symbols and by relevance within each. Either way the list is capped at MAX_RESULTS, which
--- bounds the icons rendered per open, the match itself still runs over the whole set
--- so any glyph stays findable by typing. The haystack is already lowercased by the
--- generator, so only the query is folded here.
function obj:_rows(query)
  local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local out = {}
  if q == "" then
    for i = 1, math.min(MAX_RESULTS, #self._data) do out[#out + 1] = self:_rowFor(self._data[i]) end
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

--- Emoji:configure(opts)
--- Method
--- Wire the injected collaborators and build the chooser. opts carries the Chooser
--- factory, the shared theme, the placeholder, the docked shortcut panel callbacks,
--- and onInsert, the closure that acts on the chosen glyph.
function obj:configure(opts)
  opts = opts or {}
  self._chooser = opts.chooser
  self._theme = opts.theme
  self._placeholder = opts.placeholder or "Search emoji by name or keyword"
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
    -- query, the same opt out caffeinate and the display profiles menu take.
    matcher = false,
    rows = function(query) return self:_rows(query) end,
    onSelect = function(glyph)
      if glyph then self._onInsert(glyph) end
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

--- Emoji:_prewarm(count)
--- Method
--- Render the first count glyph icons into the cache in small background batches, so
--- the render cost is paid before the first open rather than during it, and never in
--- one blocking pass. Self stopping when done, and it replaces any prior run.
function obj:_prewarm(count)
  if self._prewarmTimer then self._prewarmTimer:stop() end
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

--- Emoji:show()
--- Method
--- Open the picker.
function obj:show()
  if self._instance then self._instance:show() end
end

--- Emoji:isShowing()
--- Method
--- Whether the picker is open. Safe before configure.
function obj:isShowing()
  return self._instance ~= nil and self._instance:isShowing()
end

--- Emoji:surface()
--- Method
--- The dot-called navigation adapter, for the root to register in its shared
--- choosers list.
function obj:surface()
  return self._surface
end

return obj
