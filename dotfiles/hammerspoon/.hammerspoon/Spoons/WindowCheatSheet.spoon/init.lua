--- === WindowCheatSheet ===
---
--- On-screen overlay of the window-management bindings for one leader key.
--- Meant to be triggered from WindowLeader.spoon's onHold hook: hold SUPER (or
--- META) with no other key and its actions appear, mirroring how HyperKey +
--- HyperCheatSheet reveal the app toggles on Caps Lock.
---
--- Reads the same windowManagement config that WindowManager binds, so it never
--- drifts from the real bindings. Each row is a key glyph badge plus a label.
--- The label is the action name humanized (`nextDisplay` -> "Next Display")
--- unless the entry carries an explicit `description`, which overrides it.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowCheatSheet"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._byLeader = nil -- leaderKeyCode -> { name = "SUPER", rows = { {glyph, label}, ... } }
obj._canvas = nil

-- Layout constants (tuned for 16px text, shared visual language with
-- HyperCheatSheet: dark rounded panel, translucent key badges).
local TEXT = 16     -- font size for every text element
local LINE_H = 20   -- line box used to vertically center TEXT
local COLS = 2
local COL_W = 250
local ROW_H = 44
local MARGIN = 28
local TITLE_H = 32  -- section header line + gap below it
local BADGE_W = 44  -- wide enough for two glyphs like "⇧←"
local BADGE_H = 28
local GAP = 12      -- horizontal gap around the badge

-- Key names -> display glyph. Anything not listed is uppercased (letters, =, -).
local KEY_GLYPH = {
  left = "←", right = "→", up = "↑", down = "↓",
  ["return"] = "↩", space = "␣", escape = "⎋", tab = "⇥", delete = "⌫",
}
-- Sub-modifier names -> glyph, prefixed onto the key glyph (e.g. Shift+Left).
local MOD_GLYPH = { shift = "⇧", ctrl = "⌃", alt = "⌥", cmd = "⌘" }

-- Vertical top for a LINE_H text box centered in a container of height h
local function centerY(top, h)
  return top + (h - LINE_H) / 2
end

-- Render "shift+left" style bindings as "⇧←"
local function glyphFor(key, mods)
  local k = tostring(key):lower()
  local g = KEY_GLYPH[k] or tostring(key):upper()
  local prefix = ""
  for _, m in ipairs(mods or {}) do
    prefix = prefix .. (MOD_GLYPH[m] or "")
  end
  return prefix .. g
end

-- camelCase action name -> "Title Case" label
local function humanize(name)
  local s = name:gsub("(%l)(%u)", "%1 %2") -- split camelCase into words
  s = s:gsub("^%l", string.upper)          -- capitalize the first letter
  return s
end

local function rowsFor(n)
  return math.ceil(n / COLS)
end

--- WindowCheatSheet:init()
function obj:init()
  self._byLeader = {}
  return self
end

--- WindowCheatSheet:configure(opts)
--- opts.windowManagement - the ordered windowManagement list (config/keys.lua)
--- opts.leaders          - leaderKeyCode -> display name, e.g. { [64]="SUPER" }
function obj:configure(opts)
  opts = opts or {}
  local wm = opts.windowManagement or {}
  local names = opts.leaders or {}

  -- windowManagement is an ordered list, so each leader's rows keep that
  -- sequence -- the overlay renders in the exact order authored in keys.lua
  -- (filled row-major across COLS columns).
  self._byLeader = {}
  for _, b in ipairs(wm) do
    local lc = b.leader
    if lc then
      self._byLeader[lc] = self._byLeader[lc] or { name = names[lc] or "", rows = {} }
      table.insert(self._byLeader[lc].rows, {
        glyph = glyphFor(b.key, b.mods),
        label = b.description or humanize(b.action),
      })
    end
  end
  return self
end

--- WindowCheatSheet:show(leaderKeyCode)
--- Build and display the overlay for one leader's bindings
function obj:show(leaderKeyCode)
  self:hide()

  local group = self._byLeader[leaderKeyCode]
  if not group or #group.rows == 0 then
    return
  end

  local rows = group.rows
  local nrows = rowsFor(#rows)
  local w = COLS * COL_W + MARGIN * 2
  local h = MARGIN + TITLE_H + nrows * ROW_H + MARGIN

  local screen = hs.screen.mainScreen():frame()
  local x = screen.x + (screen.w - w) / 2
  local y = screen.y + (screen.h - h) / 2

  local elements = {}
  -- background panel
  elements[#elements + 1] = {
    type = "rectangle",
    action = "fill",
    fillColor = { red = 0.09, green = 0.09, blue = 0.11, alpha = 0.92 },
    roundedRectRadii = { xRadius = 16, yRadius = 16 },
    frame = { x = 0, y = 0, w = w, h = h },
  }
  -- leader name as the section title
  elements[#elements + 1] = {
    type = "text",
    text = group.name,
    textColor = { white = 1.0, alpha = 0.5 },
    textSize = TEXT,
    frame = { x = MARGIN, y = MARGIN, w = COLS * COL_W, h = LINE_H },
  }

  local contentY = MARGIN + TITLE_H
  for i, r in ipairs(rows) do
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local rx = MARGIN + col * COL_W
    local ry = contentY + row * ROW_H
    local badgeTop = ry + (ROW_H - BADGE_H) / 2

    -- key glyph badge
    elements[#elements + 1] = {
      type = "rectangle",
      action = "fill",
      fillColor = { white = 1.0, alpha = 0.12 },
      roundedRectRadii = { xRadius = 6, yRadius = 6 },
      frame = { x = rx, y = badgeTop, w = BADGE_W, h = BADGE_H },
    }
    elements[#elements + 1] = {
      type = "text",
      text = r.glyph,
      textColor = { white = 1.0, alpha = 1.0 },
      textSize = TEXT,
      textAlignment = "center",
      frame = { x = rx, y = centerY(badgeTop, BADGE_H), w = BADGE_W, h = LINE_H },
    }

    -- action label
    local labelX = rx + BADGE_W + GAP
    elements[#elements + 1] = {
      type = "text",
      text = r.label,
      textColor = { white = 1.0, alpha = 0.9 },
      textSize = TEXT,
      frame = { x = labelX, y = centerY(ry, ROW_H), w = COL_W - BADGE_W - GAP - GAP, h = LINE_H },
    }
  end

  self._canvas = hs.canvas.new({ x = x, y = y, w = w, h = h })
  self._canvas:level(hs.canvas.windowLevels.overlay)
  self._canvas:appendElements(elements)
  self._canvas:show()
  return self
end

--- WindowCheatSheet:hide()
--- Remove the overlay
function obj:hide()
  if self._canvas then
    self._canvas:delete()
    self._canvas = nil
  end
  return self
end

return obj
