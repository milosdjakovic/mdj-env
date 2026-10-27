--- === Olm Theme ===
---
--- The colour theme, one row per theme file under config/themes, applied the moment it is chosen.
--- The mechanism lives in lib/ui/themes.lua and reaches this plugin as three root published
--- words, themeName, themeNames and setTheme.
---
--- It was the second page of the OLM settings plugin until 2026-10-27, when that plugin was split
--- into Olm Placement, this and Olm Plugins, so each opens its list straight from its launcher row.

local M = {}

local log = hs.logger.new("OlmTheme", "info")

-- This plugin's own identity, its directory name, so M.show asks the stage for itself without
-- spelling the name out.
local SELF = debug.getinfo(1, "S").source:sub(2):match("([^/]+)/[^/]+$")

local cfg = {}

-- Green marks the live theme and red every other, never a checkmark.
local ICON_SELECTED = "selected"
local ICON_NOT_SELECTED = "notSelected"

--- M.rows() -> rows
--- One row per theme the store found, rebuilt on every redraw, so a theme file added since the
--- list opened shows up on the next one and the circle follows whichever name is live.
function M.rows()
  local live = cfg.readTheme and cfg.readTheme()
  local rows = {}
  for _, name in ipairs((cfg.readThemeNames and cfg.readThemeNames()) or {}) do
    rows[#rows + 1] = { title = name,
      icon = name == live and ICON_SELECTED or ICON_NOT_SELECTED,
      item = { theme = name, key = name } }
  end
  return rows
end

--- M.select(item) -> nil
--- Every row is caught by intercept, but the field is required on every presentation.
function M.select()
  return nil
end

--- M.intercept(item) -> "stay" or false
--- Choosing a theme applies it and stays, since it mutates the policy the row stands beside, so
--- the highlight holds on the row just chosen and only the circle moves.
function M.intercept(item)
  if item and item.theme then
    if cfg.setTheme then cfg.setTheme(item.theme) end
    return "stay"
  end
  return false
end

function M.placeholder()
  return "Theme"
end

--- M.show()
--- The launcher door, registry.open. Asks the shared stage for this plugin's own registered
--- presentation.
function M.show()
  if cfg.stagePresent then cfg.stagePresent(SELF) end
end

function M:init()
  return self
end

--- M:configure(opts)
--- opts.themeName     required, a function of no arguments answering the live theme.
--- opts.themeNames    required, a function of no arguments answering the sorted names.
--- opts.setTheme      required, a function of a theme name, applying it at once and persisting
---                    it through lib/ui/themes.lua.
--- opts.stagePresent  optional, the shared stage door M.show asks through.
function M:configure(opts)
  opts = opts or {}
  cfg.readTheme = opts.themeName
  cfg.readThemeNames = opts.themeNames
  cfg.setTheme = opts.setTheme
  cfg.stagePresent = opts.stagePresent
  if not cfg.readTheme or not cfg.readThemeNames or not cfg.setTheme then
    log.w("configured with no theme reader or writer, the list will show and change nothing")
  end
  return self
end

return M
