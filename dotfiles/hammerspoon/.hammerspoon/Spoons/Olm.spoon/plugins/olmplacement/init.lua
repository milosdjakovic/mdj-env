--- === Olm Placement ===
---
--- Where the Olm launcher and every stage window appear, cursor or active window. The mechanism
--- already lives in lib/overlaydisplay.lua, and this list is the only surface a person sees or
--- changes it through. It reads and writes the resolver's live mode through two root published
--- words, overlayPlacementMode and setOverlayPlacementMode, so lib/overlaydisplay.lua stays the
--- one file that ever calls hs.settings for this policy.
---
--- The two modes are named here as the bare literals cursor and activeWindow rather than read off
--- lib/overlaydisplay.lua's own M.modes, since the two closures above are all this plugin ever
--- receives. A mode renamed inside the resolver leaves the writer refusing the old literal with a
--- log line, while the green marker here goes quietly blank.
---
--- It was the first page of the OLM settings plugin until 2026-10-27, when that plugin was split
--- into this, Olm Theme and Olm Plugins, so each opens its list straight from its launcher row.

local M = {}

local log = hs.logger.new("OlmPlacement", "info")

-- This plugin's own identity, its directory name, so M.show asks the stage for itself without
-- spelling the name out.
local SELF = debug.getinfo(1, "S").source:sub(2):match("([^/]+)/[^/]+$")

local cfg = {}

-- The two option rows carry only a circle each, never a checkmark, the one marker convention
-- this codebase uses for which of these is current right now.
local ICON_SELECTED = "selected"
local ICON_NOT_SELECTED = "notSelected"

local OPTIONS = {
  { mode = "cursor", title = "Where the mouse cursor is" },
  { mode = "activeWindow", title = "With the active window" },
}

--- M.rows() -> rows
--- The two options, the live one marked green. Rebuilt on every redraw, so the circle follows the
--- choice just made.
function M.rows()
  local live = cfg.readMode and cfg.readMode()
  local rows = {}
  for _, option in ipairs(OPTIONS) do
    rows[#rows + 1] = { title = option.title,
      icon = option.mode == live and ICON_SELECTED or ICON_NOT_SELECTED,
      item = { commit = option.mode, key = option.mode } }
  end
  return rows
end

--- M.select(item) -> nil
--- Every row is caught by intercept, but the field is required on every presentation.
function M.select()
  return nil
end

--- M.intercept(item) -> "stay" or false
--- Choosing an option writes it and stays, since it mutates the policy the row stands beside and
--- the person switches back and forth without leaving, so the highlight holds on the row just
--- chosen and only the circle moves.
function M.intercept(item)
  if item and item.commit then
    if cfg.setMode then cfg.setMode(item.commit) end
    return "stay"
  end
  return false
end

function M.placeholder()
  return "Where Olm appears"
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
--- opts.overlayPlacementMode     required, a function of no arguments answering the live mode.
--- opts.setOverlayPlacementMode  required, a function of one mode string, writing it through
---                               lib/overlaydisplay.lua's own persisted path.
--- opts.stagePresent             optional, the shared stage door M.show asks through.
function M:configure(opts)
  opts = opts or {}
  cfg.readMode = opts.overlayPlacementMode
  cfg.setMode = opts.setOverlayPlacementMode
  cfg.stagePresent = opts.stagePresent
  if not cfg.readMode or not cfg.setMode then
    log.w("configured with no overlay placement reader or writer, the list will show and change nothing")
  end
  return self
end

return M
