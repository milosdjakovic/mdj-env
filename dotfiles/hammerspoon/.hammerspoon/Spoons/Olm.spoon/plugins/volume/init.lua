--- === Volume ===
---
--- The output volume of the current default device, read and set from one typed field that
--- shows a single row, its subtitle always saying what the volume is now. A whole number from
--- 0 to 100 sets the volume to that percentage. The words mute and unmute are matched by their
--- start and never fuzzily, so m, mu, mut and mute all mean mute and only mute, and u through
--- unmute mean unmute. Anything else is a disabled row saying what the field accepts, so Return can
--- never apply a value that is out of range or not a number.
---
--- Setting a number above zero also unmutes, since a person asking for a level wants to hear
--- it, and a muted device holding a new level would sound exactly as it did before.

local M = { name = "Volume", version = "1.0", author = "Milos Djakovic", license = "MIT" }

local cfg = {}

local ACCEPTS = "Type a number from 0 to 100, mute, or unmute"

local function icon(glyph)
  if not (cfg.glyphIcon and glyph) then return nil end
  return cfg.glyphIcon.icon(glyph)
end

-- The device sound goes to right now, read on every call, since headphones or a display can
-- take over between two openings.
local function device()
  return hs.audiodevice.defaultOutputDevice()
end

-- The level rounded to a whole percentage, or nil when the device has no volume control of its
-- own, which is how some displays and digital outputs answer.
local function level(dev)
  local v = dev and dev:outputVolume()
  if type(v) ~= "number" then return nil end
  return math.floor(v + 0.5)
end

-- The level now, worn by every row as its subtitle lead, so the field always says what it is
-- about to change.
local function now(dev)
  return "Now " .. level(dev) .. "%" .. (dev:outputMuted() and ", muted" or "")
end

local function muteRow(dev)
  return { title = "Mute", subTitle = now(dev), image = icon("🔇"), item = { id = "mute" } }
end

local function unmuteRow(dev)
  return { title = "Unmute", subTitle = now(dev), image = icon("🔊"), item = { id = "unmute" } }
end

local function invalidRow(title, dev)
  return { title = title, subTitle = now(dev) .. ". " .. ACCEPTS, image = icon("⚠️"),
           enabled = false, item = { id = "none" } }
end

-- What the typed text asks for, as one row. Digits alone are a level, and only a whole number
-- from 0 to 100 earns a row that acts. A word acts only while it is the start of mute or of
-- unmute, a prefix test rather than a fuzzy one, so a stray letter never lands on either. An
-- empty field is a disabled row saying what to type.
local function queryRow(q, dev)
  if q == "" then
    return { title = "Volume " .. level(dev) .. "%" .. (dev:outputMuted() and ", muted" or ""),
             subTitle = ACCEPTS, image = icon(dev:outputMuted() and "🔇" or "🔊"),
             enabled = false, item = { id = "none" } }
  end

  if q:match("^%d+$") then
    local n = tonumber(q)
    if n > 100 then return invalidRow(q .. " is above 100", dev) end
    return { title = "Set volume to " .. n .. "%", subTitle = now(dev),
             image = icon(n == 0 and "🔈" or "🔊"), item = { id = "set", level = n } }
  end

  local word = q:lower()
  if ("mute"):sub(1, #word) == word then return muteRow(dev) end
  if ("unmute"):sub(1, #word) == word then return unmuteRow(dev) end

  if q:match("^%-%d") then return invalidRow(q .. " is below 0", dev) end
  if q:match("^%d*[.,]%d*$") then return invalidRow(q .. " is not a whole number", dev) end
  return invalidRow("Not a volume", dev)
end

-- One row rather than a status line above an action, since this field has no highlight to
-- move and a disabled first row would hold Return on a row that does nothing.
local function rows(query)
  local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local dev = device()
  if not level(dev) then
    local name = dev and dev:name() or "No output device"
    return { { title = name .. " has no volume control", subTitle = "Choose another output in Sound settings",
               image = icon("⚠️"), enabled = false, item = { id = "none" } } }
  end
  return { queryRow(q, dev) }
end

local function select(sel)
  if not sel then return end
  local dev = device()
  if not level(dev) then return end
  if sel.id == "mute" then
    dev:setOutputMuted(true)
  elseif sel.id == "unmute" then
    dev:setOutputMuted(false)
  elseif sel.id == "set" and type(sel.level) == "number" and sel.level >= 0 and sel.level <= 100 then
    dev:setOutputVolume(sel.level)
    if sel.level > 0 then dev:setOutputMuted(false) end
  end
end

function M.show()
  if cfg.stagePresent then cfg.stagePresent("volume") end
end

M.rows = rows
M.select = select

function M.placeholder()
  return "Volume"
end

function M:configure(opts)
  cfg = opts or {}
  return M
end

return M
