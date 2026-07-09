--- === WindowCheatSheet ===
---
--- Content builder for the window-management overlay: the bindings of one leader
--- key. Meant to be triggered from WindowLeader.spoon's onHold hook: hold SUPER
--- (or META) with no other key and its actions appear, mirroring how HyperKey +
--- HyperCheatSheet reveal the app toggles on Caps Lock.
---
--- Reads the same windowManagement config that WindowManager binds, so it never
--- drifts from the real bindings. The label is the action name humanized
--- (`nextDisplay` -> "Next Display") unless the entry carries an explicit
--- `description`. Drawing is delegated to the shared CheatSheet.spoon renderer
--- (injected via configure); this spoon owns only the glyph/label logic.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowCheatSheet"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._byLeader = nil    -- leaderKeyCode -> { name = "SUPER", rows = { {badge,label,when} } }
obj._cheatSheet = nil  -- shared CheatSheet renderer
obj._predicates = nil  -- name -> function() -> bool, for conditional bindings

-- Layout knobs for this overlay: two columns, wide badge (fits "⇧←"), no icons.
local LAYOUT = {
  columns = 2,
  colWidth = 250,
  rowHeight = 44,
  badgeWidth = 44,
  badgeHeight = 28,
  gap = 12,
}

-- Key names -> display glyph. Anything not listed is uppercased (letters, =, -).
local KEY_GLYPH = {
  left = "←", right = "→", up = "↑", down = "↓",
  ["return"] = "↩", space = "␣", escape = "⎋", tab = "⇥", delete = "⌫",
}
-- Sub-modifier names -> glyph, prefixed onto the key glyph (e.g. Shift+Left).
local MOD_GLYPH = { shift = "⇧", ctrl = "⌃", alt = "⌥", cmd = "⌘" }

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

--- WindowCheatSheet:init()
function obj:init()
  self._byLeader = {}
  self._predicates = {}
  return self
end

--- WindowCheatSheet:_active(when)
--- Is a binding carrying this `when` predicate name currently active? A binding
--- with no `when` is always active. An unknown name is treated as active so a
--- typo fails visibly (row shown) rather than silently hiding a binding. Called
--- per row at show time, so it tracks live state such as the display count.
function obj:_active(when)
  if not when then return true end
  local p = self._predicates[when]
  if not p then
    print("WindowCheatSheet: unknown predicate '" .. tostring(when) .. "'")
    return true
  end
  return p() and true or false
end

--- WindowCheatSheet:configure(opts)
--- opts.windowManagement - the ordered windowManagement list (config/keys.lua)
--- opts.leaders          - leaderKeyCode -> display name, e.g. { [64]="SUPER" }
--- opts.cheatSheet       - shared CheatSheet renderer to draw with
--- opts.predicates       - name -> function() -> bool, for entries with `when`
function obj:configure(opts)
  opts = opts or {}
  local wm = opts.windowManagement or {}
  local names = opts.leaders or {}
  self._cheatSheet = opts.cheatSheet or self._cheatSheet
  self._predicates = opts.predicates or self._predicates

  -- windowManagement is an ordered list, so each leader's rows keep that
  -- sequence -- the overlay renders in the exact order authored in keys.lua
  -- (filled row-major across the columns).
  self._byLeader = {}
  for _, b in ipairs(wm) do
    local lc = b.leader
    if lc then
      self._byLeader[lc] = self._byLeader[lc] or { name = names[lc] or "", rows = {} }
      table.insert(self._byLeader[lc].rows, {
        badge = glyphFor(b.key, b.mods),
        label = b.description or humanize(b.action),
        when = b.when,
      })
    end
  end
  return self
end

--- WindowCheatSheet:show(leaderKeyCode)
--- Build the model for one leader's bindings and hand it to the renderer
function obj:show(leaderKeyCode)
  if not self._cheatSheet then return self end
  local group = self._byLeader[leaderKeyCode]
  if not group then return self end

  -- Drop rows whose `when` predicate is false right now. The renderer fills
  -- row-major, so a shorter list just yields a shorter grid, no layout change.
  local rows = {}
  for _, row in ipairs(group.rows) do
    if self:_active(row.when) then
      table.insert(rows, row)
    end
  end
  if #rows == 0 then return self end

  self._cheatSheet:show({
    columns = LAYOUT.columns,
    colWidth = LAYOUT.colWidth,
    rowHeight = LAYOUT.rowHeight,
    badgeWidth = LAYOUT.badgeWidth,
    badgeHeight = LAYOUT.badgeHeight,
    gap = LAYOUT.gap,
    sections = {
      { title = group.name, alpha = 1.0, rows = rows },
    },
  })
  return self
end

--- WindowCheatSheet:hide()
function obj:hide()
  if self._cheatSheet then self._cheatSheet:hide() end
  return self
end

return obj
