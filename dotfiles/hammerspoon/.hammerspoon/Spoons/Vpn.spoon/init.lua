--- === Vpn ===
---
--- A VPN control tool. Hyper+Y opens a small panel with the live connection state at
--- the top and the two actions that make sense for that state. When disconnected it
--- offers Connect and Search locations, when connected it offers Disconnect and Search
--- locations. Search locations opens a filterable picker of every city the provider
--- offers, and choosing one sets the relay and connects.
---
--- This file is the composition root and the command policy. It loads the engine and
--- the Mullvad provider, names them, validates the provider against the contract, and
--- wires the engine to the two views injected by the main root, the shared Panel atom
--- for the control panel and the shared Chooser atom for the location search. It turns
--- a chosen row into an engine call. When the CLI is not installed it logs the reason
--- and the tool does nothing, so a machine without Mullvad degrades quietly.
---
--- Two views, not one, because the two jobs differ. The control panel is a short fixed
--- list, right for the Panel atom, and the location search is a long filterable list,
--- right for the Chooser atom the clipboard also uses. The panel exposes the same small
--- control surface the clipboard and caffeinate do, isShowing and hide and the two
--- navigation methods, so the shared control in the main root drives whichever tool is
--- open.

local M = { name = "Vpn", version = "1.0", author = "mdj-env" }

-- Load the siblings by absolute path, the Capture idiom (a spoon dir is not on
-- package.path). The provider line is the one place the concrete backend is named,
-- validated against the contract at load so a missing method fails visibly here.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local engine = dofile(spoonPath .. "engine.lua")
local contract = dofile(spoonPath .. "contract.lua")
local provider = contract.validate(dofile(spoonPath .. "providers/mullvad.lua"))

local cfg = nil       -- injected: the shared theme, the Panel factory, the Chooser factory
local panel = nil     -- the control panel, a Panel instance
local locations = nil -- the location search, a Chooser instance
local cache = {}      -- the last fetched location list, filtered by the supplier
local current = { state = "unavailable" } -- status read once per open, read by both suppliers

--------------------------------------------------------------------------------
-- Status wording (command policy)
--------------------------------------------------------------------------------

local function statusText(s)
  if not s or s.state == "unavailable" then return "Mullvad is not responding" end
  local st = s.state
  if st == "connected" then
    if s.city and s.country then return "Connected, " .. s.city .. ", " .. s.country end
    return s.hostname and ("Connected, " .. s.hostname) or "Connected"
  elseif st == "connecting" then
    return "Connecting"
  elseif st == "disconnecting" then
    return "Disconnecting"
  elseif st == "disconnected" then
    return "Disconnected"
  end
  return tostring(st)
end

--------------------------------------------------------------------------------
-- The control panel rows and their meaning
--------------------------------------------------------------------------------

-- The rows depend on the state read at open. When the tunnel is up the primary action
-- is Disconnect, otherwise it is Connect, and Search locations is always offered.
-- Connecting counts as up so the action cancels it, and every other state, including a
-- daemon that is not answering, offers Connect. The panel calls this on each show.
local function panelRows()
  local up = current.state == "connected" or current.state == "connecting"
  local primary = up
    and { id = "disconnect", label = "Disconnect" }
    or { id = "connect", label = "Connect" }
  return {
    primary,
    { id = "locations", label = "Search locations" },
  }
end

-- A row was applied. The actions delegate to the engine and close the panel. Search
-- locations closes the panel and opens the location picker just after, so the panel's
-- focus restore settles before the picker takes focus. Returns nil so the panel closes
-- in every case.
local function onApply(sel)
  local id = sel.id
  if id == "connect" then
    engine.connect()
  elseif id == "disconnect" then
    engine.disconnect()
  elseif id == "locations" then
    hs.timer.doAfter(0.08, function() M.showLocations() end)
  end
  return nil
end

-- The daemon state changed while the panel may be open. Redraw the status line.
local function onChange()
  if panel then panel:refresh() end
end

--------------------------------------------------------------------------------
-- Location search (the Chooser consumer)
--------------------------------------------------------------------------------

-- A country flag rendered to a small image, so each city row carries a flag rather
-- than the chooser's default icon. The flag emoji is built from the two letter country
-- code as a pair of regional indicator symbols, drawn once on an offscreen canvas and
-- cached by code, since the supplier runs on every keystroke. A false marks a code that
-- cannot render, so it is attempted only once.
local flagCache = {}
local function flagImage(cc)
  if not cc or #cc ~= 2 then return nil end
  local hit = flagCache[cc]
  if hit ~= nil then return hit or nil end
  local base, a = 0x1F1E6, string.byte("a")
  local c1, c2 = cc:sub(1, 1):byte() - a, cc:sub(2, 2):byte() - a
  if c1 < 0 or c1 > 25 or c2 < 0 or c2 > 25 then
    flagCache[cc] = false
    return nil
  end
  local size = 28
  local cv = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  cv[1] = {
    type = "text",
    text = utf8.char(base + c1, base + c2),
    textSize = 21,
    textAlignment = "center",
    frame = { x = 0, y = 0, w = size, h = size },
  }
  local img = cv:imageFromCanvas()
  cv:delete()
  flagCache[cc] = img or false
  return img
end

-- The supplier the chooser calls in filter mode. It receives the query and returns
-- the matching cities, a case insensitive substring match on the label or the country
-- code, so typing London, USA, or gb all narrow the list. Each row carries its country
-- flag as the icon.
local function locationRows(query)
  local q = (query or ""):lower()
  local out = {}
  for _, loc in ipairs(cache) do
    if q == "" or loc.label:lower():find(q, 1, true) or loc.countryCode:find(q, 1, true) then
      out[#out + 1] = {
        title = loc.label,
        subTitle = loc.countryCode .. " " .. loc.cityCode,
        image = flagImage(loc.countryCode),
        item = loc,
      }
    end
  end
  return out
end

-- A city was chosen. Set the relay to that country and city, which connects.
local function onLocationPick(loc)
  if loc then engine.setLocation(loc.countryCode, loc.cityCode) end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard and caffeinate)
--------------------------------------------------------------------------------

--- M.show() - read the state once, then open the VPN control panel. Both the rows and
--- the status line read this one snapshot, so a single status call drives the open.
function M.show()
  if not panel then return end
  current = engine.status()
  panel:show()
end

--- M.showLocations() - open the location picker. The relay list is fetched fresh each
--- open so a relay update is reflected, and the picker is refreshed once it lands.
function M.showLocations()
  if not locations then return end
  engine.listLocations(function(list)
    cache = list or {}
    locations:refresh()
  end)
  locations:show()
end

function M.isShowing()
  return panel ~= nil and panel:isShowing()
end

function M.hide()
  if panel then panel:close() end
end

-- Vim style navigation, routed here from Hyper+j and Hyper+k by the main root, the
-- same shared control the clipboard and caffeinate use.
function M.selectNext()
  if panel then panel:selectNext() end
end

function M.selectPrev()
  if panel then panel:selectPrev() end
end

--- M.configure(opts) - inject the shared theme, the Panel factory, and the Chooser
--- factory.
function M.configure(opts)
  cfg = opts or {}
  return M
end

--- M.start() - validate availability, wire the engine, and build the two views. When
--- the CLI is missing it logs and returns without building, so the tool is inert.
function M.start()
  if not provider.available() then
    print("[Vpn] mullvad CLI not found, VPN controls disabled. Install the Mullvad app or run brew install --cask mullvad-vpn")
    return M
  end
  engine.configure({ provider = provider, onChange = onChange })
  engine.start()
  panel = cfg.panel.new({
    name = "vpn",
    theme = cfg.theme,
    options = panelRows,
    status = function() return statusText(current) end,
    onApply = onApply,
  })
  locations = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = "Search locations",
    fieldMode = "filter",
    rows = locationRows,
    onSelect = onLocationPick,
  })
  return M
end

return M
