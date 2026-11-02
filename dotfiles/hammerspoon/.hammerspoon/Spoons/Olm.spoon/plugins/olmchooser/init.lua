--- === Olm Chooser ===
---
--- Which chooser draws every list, the glass or the canvas. Each chooser provider declares its own
--- title and how far it can be themed, and this list only reads the titles through three root
--- published words, chooserName, chooserNames and setChooser, so it never learns a provider's
--- name and a provider never learns this list exists. Choosing one persists it and Olm reloads,
--- since the chooser is decided once per load. What each chooser then offers to change is the Olm
--- Theme list's business.

local M = {}

local log = hs.logger.new("OlmChooser", "info")

-- This plugin's own identity, its directory name, so M.show asks the stage for itself without
-- spelling the name out.
local SELF = debug.getinfo(1, "S").source:sub(2):match("([^/]+)/[^/]+$")

local cfg = {}

--- M.rows() -> rows
--- One row per chooser a person can pick, the one in use chosen. Rebuilt on every redraw.
function M.rows()
  local live = cfg.readName and cfg.readName()
  local rows = {}
  for _, title in ipairs((cfg.readNames and cfg.readNames()) or {}) do
    rows[#rows + 1] = { title = title,
      subTitle = title == live and "In use" or "Olm reloads to switch",
      filterText = title,
      chosen = title == live,
      item = { chooser = title, key = title } }
  end
  return rows
end

--- M.select(item) -> nil
--- Every row is caught by intercept, but the field is required on every presentation.
function M.select()
  return nil
end

--- M.intercept(item) -> "stay" or false
--- Choosing a chooser writes it and stays. Choosing the one in use changes nothing, and choosing
--- another reloads Olm, which closes the list on its own.
function M.intercept(item)
  if item and item.chooser then
    if cfg.setChooser then cfg.setChooser(item.chooser) end
    return "stay"
  end
  return false
end

function M.placeholder()
  return "Chooser"
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
--- opts.chooserName   required, a function of no arguments answering the title in use.
--- opts.chooserNames  required, a function of no arguments answering every title on offer.
--- opts.setChooser    required, a function of a title, persisting it and reloading Olm.
--- opts.stagePresent  optional, the shared stage door M.show asks through.
function M:configure(opts)
  opts = opts or {}
  cfg.readName = opts.chooserName
  cfg.readNames = opts.chooserNames
  cfg.setChooser = opts.setChooser
  cfg.stagePresent = opts.stagePresent
  if not cfg.readName or not cfg.readNames or not cfg.setChooser then
    log.w("configured with no chooser reader or writer, the list will show and change nothing")
  end
  return self
end

return M
