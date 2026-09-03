--- === WindowSize ===
---
--- Turns a typed pair of dimensions into one launcher row that sizes the focused window to
--- exactly that and centers it. It is a query row source, not a picker, so it owns no
--- chooser, no key, and no window, and it answers one question, does what was typed name a
--- window size worth offering.
---
--- The resize is not here. Window geometry belongs to the window manager, which already
--- sizes a window to exact pixels and centers it in one call, so this plugin holds the
--- grammar and the wording and nothing else. It asks that plugin what a request would
--- actually do before offering it, so a size the display cannot hold reads as trimmed on the
--- row rather than surprising a person after they have pressed return.
---
--- The row does not act either. It carries the size it means as a plain descriptor and the
--- launcher's own window dispatch runs the window manager's action with it, once focus is
--- back on the application the list was covering. That is what keeps the acting window the
--- one a person was looking at rather than whatever the chooser left focused.
---
--- THE GRAMMAR IS DELIBERATELY NARROW. Two whole numbers with an x between them and nothing
--- else in the field, so an ordinary search that happens to contain a number never grows a
--- row nobody asked for. A capital X and the multiplication sign are the same separator,
--- since a person typing a size may reach for either. An asterisk is not one, because
--- 1920*1080 is arithmetic and already answers with a product, and one query answering two
--- things that mean different things is worse than a separator nobody misses.

local obj = {}
obj.__index = obj

obj.name = "WindowSize"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Injected via configure
obj._plan = nil          -- the window manager's own answer for what a request would do
obj._glyph = nil         -- the row glyph, rendered to an icon by whatever presents the row
obj._category = nil      -- the subtitle category word, so the visible wording stays config
obj._smallestEdge = nil  -- the shortest edge worth a row

-- A width, a separator, a height, and nothing else. Anchored at both ends, so a size inside
-- a longer query is deliberately ignored rather than pulled out of a sentence.
--
-- Only the two ASCII letters are in the class, and the multiplication sign is normalised into
-- one before this ever runs. A Lua character class matches a single BYTE, and that sign is two
-- of them in UTF-8, so putting it in the class would let a stray half of it match while the
-- other half went unconsumed, and the anchored pattern would then fail on the very input the
-- class was widened to accept.
local PATTERN = "^(%d+)%s*[xX]%s*(%d+)$"

--- WindowSize:init()
--- Method
--- Initialize. Nothing to build, the parser is pure.
function obj:init()
  return self
end

--- WindowSize:configure(opts)
--- Method
--- opts.plan         the window manager's exactSizePlan, asked what a request would land as.
--- opts.glyph        the character shown as the row icon, rendered by the presenter.
--- opts.category     the word leading the row subtitle, so the visible wording is config
---                   rather than something this plugin decides for a surface it cannot see.
--- opts.smallestEdge the shortest edge this plugin will offer a row for.
function obj:configure(opts)
  opts = opts or {}
  self._plan = opts.plan
  self._glyph = opts.glyph or "📐"
  self._category = opts.category or "Window size"
  self._smallestEdge = tonumber(opts.smallestEdge) or 200
  return self
end

--- WindowSize:parse(query) -> width, height or nil
--- Method
--- The whole grammar, exposed on its own so it can be checked from the console without going
--- through a row. Returns nil for anything that is not a complete pair of dimensions, which
--- is the overwhelmingly common case, since every app search contains letters and fails the
--- anchor on its first character.
function obj:parse(query)
  local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
  -- One separator from here down. See PATTERN above for why this cannot be a character class.
  q = q:gsub("×", "x")
  local w, h = q:match(PATTERN)
  if not w then return nil end
  w, h = tonumber(w), tonumber(h)
  if not w or not h then return nil end
  if w < self._smallestEdge or h < self._smallestEdge then return nil end
  return w, h
end

--- WindowSize:rows(query) -> list
--- Method
--- The query row source contract. Returns at most one row, or an empty list when the query
--- is not a pair of dimensions.
---
--- The row is plain data like every other launcher row, carrying a glyph rather than a
--- rendered image so the presenter draws it with its own cache, and a serializable descriptor
--- rather than a function, since a function cannot survive being handed to a native chooser.
--- filterText is the raw query, so a presenter that filters its list with a matcher keeps
--- this row rather than scoring the size it produced against the size that was typed.
---
--- The descriptor carries the size AS TYPED and not the size the plan says would land. The
--- plan is read here, while the list is up and there is no ordinary focused window to read a
--- screen from, and the action runs a tenth of a second later against the real one. Handing
--- over an already trimmed size would freeze this moment's guess about which display is
--- involved into the thing that acts, so the size travels untouched and the action trims it
--- against the screen it actually finds.
function obj:rows(query)
  local w, h = self:parse(query)
  if not w then return {} end
  if not self._plan then return {} end

  local plan = self._plan(w, h)
  if not plan then return {} end

  local asked = w .. " x " .. h
  local lands = plan.width .. " x " .. plan.height
  local detail = plan.clamped
    and (asked .. " is larger than the display, so this is the largest that fits")
    or "size the window to that and center it"

  return {
    {
      title = lands,
      subTitle = self._category .. " · " .. detail,
      glyph = self._glyph,
      filterText = query,
      -- The window kind the launcher already dispatches, naming the window manager's own
      -- exact size action and carrying the size that action needs. A window row that carries
      -- a size is computed rather than catalogued, which is also how the launcher knows to
      -- keep it out of the recency timeline.
      item = { kind = "window", name = "exactSize", size = { width = w, height = h } },
    },
  }
end

return obj
