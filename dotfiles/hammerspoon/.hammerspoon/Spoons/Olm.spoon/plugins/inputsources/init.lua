--- === InputSources ===
---
--- The keyboard layouts enabled in System Settings, as one list ordered by recent use, the
--- layout in use first and marked. Choosing a row makes that layout the current one.
---
--- This file answers the rows and the choice and nothing else. How the list is shown is Olm's.
--- Opened from its launcher row or its alias it is the full list, searched like any other. Its
--- cycle key, a tap of fn as the manifest suggests it, shows the same list bare and steps down it
--- the way Command and Tab does, which the stage does for any list a cycle row names, so this file
--- holds no key, no timer and no highlight.

local M = { name = "InputSources", version = "2.0", author = "Milos Djakovic", license = "MIT" }

local cfg = {}

-- How long a read of the sources stays good for the launcher scope, which is asked on every
-- keystroke and has no onPresent to read them once.
local FRESH = 2

local held = {}
local readAt = 0

-- The enabled sources, the recently used ones first in the order they were used and the rest
-- after them in the order System Settings lists them. The layout in use is touched on every read,
-- so one switched from the menu bar or by macOS itself still leads. Without the shared recency
-- service the layout in use leads and the rest keep the System Settings order.
local function read()
  local ids = hs.keycodes.layouts(true) or {}
  local names = hs.keycodes.layouts() or {}
  local current = hs.keycodes.currentSourceID()
  local recency = cfg.recency
  if recency and current then recency.touch(current) end
  local list = {}
  for i, id in ipairs(ids) do
    list[#list + 1] = { id = id, name = names[i] or id, current = id == current }
  end
  if recency then
    list = recency.order(list, function(s) return s.id end)
  else
    for i, s in ipairs(list) do
      if s.current then
        table.insert(list, 1, table.remove(list, i))
        break
      end
    end
  end
  held = list
  readAt = hs.timer.secondsSinceEpoch()
  return list
end

local function rows()
  local out = {}
  for _, s in ipairs(held) do
    out[#out + 1] = {
      title = s.name,
      subTitle = s.current and "In use" or "Keyboard layout",
      icon = s.current and "current" or "layout",
      filterText = s.name,
      key = s.id,
      item = { id = "source", sourceID = s.id, name = s.name },
    }
  end
  if #out == 0 then
    out[1] = { title = "No keyboard layouts", subTitle = "System Settings lists none",
               icon = "layout", enabled = false, pinned = true, item = { id = "none" } }
  end
  return out
end

-- quiet is for a switch the list already showed, where a toast after the list closed would
-- only linger over a change the person just watched happen.
local function use(sourceID, name, quiet)
  if not hs.keycodes.currentSourceID(sourceID) then return false end
  if cfg.recency then cfg.recency.touch(sourceID) end
  if cfg.notify and not quiet then cfg.notify(name) end
  return true
end

-- The layout used before this one, the one the first press of the cycle key lands on.
function M.previous()
  local list = read()
  if #list < 2 then return false end
  return use(list[2].id, list[2].name)
end

function M:actions()
  return {
    { name = "previous", run = function() M.previous() end,
      description = "Previous Input Source", subtitle = "Keyboard", icon = "inputsources",
      keywords = "switch layout, globe, fn, toggle" },
  }
end

function M.show()
  if cfg.stagePresent then cfg.stagePresent("inputsources") end
end

function M.onPresent()
  read()
end

M.rows = rows

-- One row per enabled layout, so the window is as tall as the list and no taller. The stage
-- caps it at its own default.
function M.rowCount()
  return math.max(1, #read())
end

function M.scopeRows()
  if hs.timer.secondsSinceEpoch() - readAt > FRESH then read() end
  return rows()
end

-- Choosing a row switches to it and the list closes, however the list was shown and from the
-- launcher scope alike. The row the person chose is the confirmation, so no toast follows.
function M.select(item)
  if item and item.id == "source" then use(item.sourceID, item.name, true) end
end

function M.placeholder()
  return "Input sources"
end

function M:configure(opts)
  cfg = opts or {}
  return M
end

return M
