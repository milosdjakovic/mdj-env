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
--- actually do before offering it, so the subtitle names the size that will land, and says
--- which limit trimmed it, before a person has pressed return.
---
--- The row does not act either. It carries the size it means as a plain descriptor and the
--- launcher's own window dispatch runs the window manager's action with it, once focus is
--- back on the application the list was covering. That is what keeps the acting window the
--- one a person was looking at rather than whatever the chooser left focused, and it is why
--- the title names that application. The root publishes it as coveredApp, captured by the
--- launcher before its list took focus, since asking macOS for the focused window while the
--- list is up answers the list itself.
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
obj._windowActions = nil -- the window manager's action descriptors, for running a chosen row
obj._coveredApp = nil    -- function() -> the app the launcher opened over, which the row acts on
obj._icon = nil          -- the row icon, a key into this plugin's manifest icons, drawn by Olm
obj._smallestEdge = nil  -- the shortest edge a row will size a window to

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
--- opts.coveredApp   the root's closure answering the app the launcher opened over, which is
---                   the app whose window the row resizes, so the title can name it.
--- opts.icon         the key into this plugin's manifest icons shown as the row icon, drawn by Olm.
--- opts.smallestEdge the shortest edge a row will size a window to, raising a smaller one.
function obj:configure(opts)
  opts = opts or {}
  self._plan = opts.plan
  self._windowActions = opts.windowActions
  self._coveredApp = opts.coveredApp
  self._icon = opts.icon or "windowsize"
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
  return w, h
end

-- The name of the application the row will act on, or nil when none can be named truthfully.
-- The action resizes the focused window once the launcher has closed, so the title names the
-- covered app only when that app has a focused window to receive it, and otherwise reads as a
-- plain window. Asking for the window happens here, after the size has parsed, so an ordinary
-- query that is not a size never touches the app.
--
-- The launcher keeps the earlier app when Hammerspoon is frontmost alone, which is its own
-- policy and is left as it is, so in that one case this reads the name of the earlier app.
--
-- The app object can outlive the app it names, one that quit while the list was up, and a query
-- row source runs on every keystroke, so any failed read answers nil rather than raising into
-- the launcher's own rebuild.
local function coveredAppName(self)
  if not self._coveredApp then return nil end
  local app = self._coveredApp()
  if not app then return nil end
  local ok, name = pcall(function()
    if not app:focusedWindow() then return nil end
    return app:name()
  end)
  if ok and type(name) == "string" and name ~= "" then return name end
  return nil
end

--- WindowSize:rows(query) -> list
--- Method
--- The query row source contract. Returns at most one row, or an empty list when the query
--- is not a pair of dimensions.
---
--- The row is plain data like every other launcher row, carrying a glyph rather than a
--- rendered image so the presenter draws it with its own cache, and a serializable descriptor
--- rather than a function, since a function cannot survive being handed to a native chooser.
--- The row is fromQuery, made from what was typed, so a presenter that filters its list with a
--- matcher keeps this row at the top rather than scoring the size it produced against the size
--- that was typed.
---
--- Two limits can change the size, and they are applied differently on purpose. The floor,
--- smallestEdge, does not depend on any screen, so an edge under it is raised here and the
--- descriptor carries the raised size, which is exactly what the action will be handed. The
--- display ceiling does depend on a screen, and the plan is read while the list is up and
--- there is no ordinary focused window to read one from, while the action runs a tenth of a
--- second later against the real one. So the descriptor carries the size before that ceiling,
--- and the action trims it against the screen it actually finds, which is what the window
--- manager's exactSizePlan comment asks of a caller.
---
--- The subtitle is the size that will land and nothing else, plus the limit that trimmed it
--- when one did. When both did, it names the size limit, since that one holds wherever the
--- window is, while the display limit is this moment's guess about which screen is involved
--- and the action may find another.
function obj:rows(query)
  local w, h = self:parse(query)
  if not w then return {} end
  if not self._plan then return {} end

  local floor = self._smallestEdge
  local floored = w < floor or h < floor
  local fw, fh = math.max(w, floor), math.max(h, floor)

  local plan = self._plan(fw, fh)
  if not plan then return {} end

  local lands = plan.width .. " x " .. plan.height
  local subTitle = lands
  if floored then
    subTitle = lands .. ", size limit"
  elseif plan.clamped then
    subTitle = lands .. ", display limit"
  end

  local name = coveredAppName(self)

  return {
    {
      title = name and ("Resize " .. name) or "Resize window",
      subTitle = subTitle,
      icon = self._icon,
      fromQuery = true,
      -- The window kind, naming the window manager's own exact size action and carrying the
      -- size that action needs, run by launcherRun below once the root has stamped this
      -- plugin as the row's owner. The row is computed rather than catalogued.
      -- remember false keeps it out of the launcher's recency and its query memory, since it
      -- exists only for the size that was typed and has no identity to remember.
      item = { kind = "window", name = "exactSize", size = { width = fw, height = fh },
        remember = false },
    },
  }
end

--- WindowSize:launcherRun(item)
--- Method
--- Run a chosen row, declared as provides.launcherRun. The launcher calls this after its
--- chooser has closed and focus has gone back to the window that was in front, and the window
--- manager's exact size action trims the size as typed against the screen that window is on.
function obj:launcherRun(item)
  if not (item and self._windowActions) then return end
  local action = self._windowActions()[item.name]
  if action and type(action.run) == "function" then action.run(item.size) end
end

return obj
