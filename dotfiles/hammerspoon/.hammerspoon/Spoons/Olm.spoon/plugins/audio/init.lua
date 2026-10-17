--- === Audio ===
---
--- Every sound output and every input this Mac can use right now, as one searchable list,
--- outputs first. The device in use on each side carries a check. Choosing a row makes that
--- device the default for its side, and the list stays open with the check moved, so an
--- output and an input can both be switched in one visit.
---
--- The list is what CoreAudio reports, so a Bluetooth device that is paired but not connected
--- is not in it, since the system has nothing to route sound to until it connects.

local M = { name = "Audio", version = "1.0", author = "Milos Djakovic", license = "MIT" }

local cfg = {}

-- How long a read of the devices stays good for the launcher scope, which is asked on every
-- keystroke and has no onPresent to read them once.
local FRESH = 2

local held = {}
local readAt = 0

local function side(devices, current, kind)
  local currentUID = current and current:uid()
  local out = {}
  for _, dev in ipairs(devices or {}) do
    out[#out + 1] = { uid = dev:uid(), name = dev:name(), kind = kind, current = dev:uid() == currentUID }
  end
  -- The device in use first, then the rest by name, so the answer to what is playing now sits
  -- at the top of its side.
  table.sort(out, function(a, b)
    if a.current ~= b.current then return a.current end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

local function read()
  local list = {}
  for _, d in ipairs(side(hs.audiodevice.allOutputDevices(), hs.audiodevice.defaultOutputDevice(), "output")) do
    list[#list + 1] = d
  end
  for _, d in ipairs(side(hs.audiodevice.allInputDevices(), hs.audiodevice.defaultInputDevice(), "input")) do
    list[#list + 1] = d
  end
  held = list
  readAt = hs.timer.secondsSinceEpoch()
end

local function rows()
  local out = {}
  for _, d in ipairs(held) do
    local label = d.kind == "output" and "Output" or "Input"
    local icon = d.current and "current" or (d.kind == "output" and "output" or "input")
    out[#out + 1] = {
      title = d.name,
      subTitle = label .. (d.current and ", in use" or ""),
      icon = icon,
      -- The side is part of what a search matches, so typing input narrows to inputs.
      filterText = d.name .. " " .. label,
      item = { id = "device", kind = d.kind, uid = d.uid, name = d.name },
    }
  end
  if #out == 0 then
    out[1] = { title = "No audio devices", subTitle = "CoreAudio reported none",
               icon = "warn", enabled = false, pinned = true, item = { id = "none" } }
  end
  return out
end

-- Makes the chosen device the default for its side. Looked up again by uid rather than kept
-- from the read, since a device can disappear between the read and the choice.
local function switch(item)
  if not (item and item.id == "device") then return false end
  local dev = hs.audiodevice.findDeviceByUID(item.uid)
  if not dev then return false end
  if item.kind == "output" then
    return dev:setDefaultOutputDevice()
  end
  return dev:setDefaultInputDevice()
end

function M.show()
  if cfg.stagePresent then cfg.stagePresent("audio") end
end

function M.onPresent()
  read()
end

M.rows = rows

function M.scopeRows()
  if hs.timer.secondsSinceEpoch() - readAt > FRESH then read() end
  return rows()
end

-- The launcher scope path, which has no intercept, so choosing there switches and closes.
function M.select(item)
  switch(item)
end

-- The tool's own list. Answering stay rebuilds the rows with the check on the row just
-- chosen and keeps the highlight there.
function M.intercept(item)
  if not (item and item.id == "device") then return false end
  switch(item)
  read()
  return "stay"
end

function M.placeholder()
  return "Audio devices"
end

function M:configure(opts)
  cfg = opts or {}
  return M
end

return M
