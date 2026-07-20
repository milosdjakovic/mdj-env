--- === Vpn ===
---
--- A VPN control tool. Hyper+Y opens a single native chooser that merges the controls
--- and the location search into one flat list. The first row is the action that fits the
--- live state, its title naming the place, Disconnect from where the tunnel is when it is
--- up and Connect to the selected relay when it is down, with the live state word and the
--- provider in its subtitle. Every city the provider offers follows below it. Typing
--- filters the cities, and once a filter is present the action row drops out so Return
--- connects to the top matching city rather than toggling the tunnel. Choosing a city sets
--- the relay and connects.
---
--- This file is the composition root and the command policy. It loads the engine and the
--- Mullvad provider, names them, validates the provider against the contract, and builds
--- one Chooser instance pinned to the native hs.chooser backend, the snappy one the menu
--- search also uses. It turns a chosen row into an engine call. When the CLI is not
--- installed it logs the reason and the tool does nothing, so a machine without Mullvad
--- degrades quietly.
---
--- One flat list, not a drill down. The controls and the locations live in the same list,
--- so there is no mode to switch and no second level to re-show. The location list is
--- fetched on each open so a relay update is reflected, and the list is refreshed once it
--- lands. The Hyper navigation shortcuts are wired from the main root (j, k, i, x), but no
--- canvas hint pane is drawn, so the shortcuts work without an overlay.

local M = { name = "Vpn", version = "3.0", author = "mdj-env" }

-- Load the siblings by absolute path, the Capture idiom (a spoon dir is not on
-- package.path). The provider line is the one place the concrete backend is named,
-- validated against the contract at load so a missing method fails visibly here.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local engine = dofile(spoonPath .. "engine.lua")
local contract = dofile(spoonPath .. "contract.lua")
local provider = contract.validate(dofile(spoonPath .. "providers/mullvad.lua"))

local cfg = nil       -- injected: the shared theme and the Chooser factory
local chooser = nil   -- the one native Chooser instance
local cache = {}      -- the last fetched location list, filtered by the supplier
local current = { state = "unavailable" } -- status snapshot, refreshed on open and change
local target = nil    -- the selected relay to connect to, { countryCode, cityCode }

--------------------------------------------------------------------------------
-- Status wording and location labels (command policy)
--------------------------------------------------------------------------------

-- The status line is just the live state word with the provider in parentheses, so it
-- reads Connected, Connecting, Disconnecting, or Disconnected without the location, which
-- the action title carries instead. The provider name comes from the provider itself, the
-- one place that knows the backend, and is named directly in the not responding line since
-- there is no state to pair it with.
local STATE_WORD = {
  connected = "Connected",
  connecting = "Connecting",
  disconnecting = "Disconnecting",
  disconnected = "Disconnected",
}
local function statusText(s)
  local name = provider.name or "VPN"
  if not s or s.state == "unavailable" then return name .. " is not responding" end
  return (STATE_WORD[s.state] or tostring(s.state)) .. " (" .. name .. ")"
end

-- The place the live tunnel exits, from the connected status, as a City, Country label
-- or the hostname when that is all there is. Nil when the status carries no location.
local function connectedLabel(s)
  if s.city and s.country then return s.city .. ", " .. s.country end
  return s.hostname
end

-- The selected relay resolved to a human label. The constraint gives only codes, so it is
-- matched against the loaded city list to recover the City, Country name, a country only
-- constraint resolving to the country name. Before the list lands, or when no match is
-- found, the raw codes stand in so the title is never blank. Nil when nothing is selected.
local function targetLabel(t)
  if not t then return nil end
  for _, loc in ipairs(cache) do
    if loc.countryCode == t.countryCode and (not t.cityCode or loc.cityCode == t.cityCode) then
      return t.cityCode and loc.label or loc.country
    end
  end
  if t.cityCode then return t.cityCode:upper() .. ", " .. t.countryCode:upper() end
  return t.countryCode:upper()
end

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an
-- offscreen canvas drawn once and cached by the string, since a supplier runs on every
-- keystroke. The flags and the action glyphs both go through this one path. A false
-- marks a string that cannot render, so it is attempted only once.
local glyphCache = {}
local function emojiImage(str)
  local hit = glyphCache[str]
  if hit ~= nil then return hit or nil end
  local size = 28
  local cv = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  cv[1] = {
    type = "text",
    text = str,
    textSize = 21,
    textAlignment = "center",
    frame = { x = 0, y = 0, w = size, h = size },
  }
  local img = cv:imageFromCanvas()
  cv:delete()
  glyphCache[str] = img or false
  return img
end

-- A country flag image built from the two letter country code as a pair of regional
-- indicator symbols, then rendered through the shared emoji path.
local function flagImage(cc)
  if not cc or #cc ~= 2 then return nil end
  local base, a = 0x1F1E6, string.byte("a")
  local c1, c2 = cc:sub(1, 1):byte() - a, cc:sub(2, 2):byte() - a
  if c1 < 0 or c1 > 25 or c2 < 0 or c2 > 25 then return nil end
  return emojiImage(utf8.char(base + c1, base + c2))
end

-- The action glyphs. A green circle reads as go, a red one as stop.
local ICON = {
  connect = "🟢",
  disconnect = "🔴",
}

--------------------------------------------------------------------------------
-- Row supplier (one flat list)
--------------------------------------------------------------------------------

-- The one row that toggles the tunnel. When up the title names where the tunnel is,
-- Disconnect from City, Country, and when down it names where a connect would go, Connect
-- to City, Country from the selected relay. The location falls off the title when it is
-- unknown, leaving a bare Connect or Disconnect. Connecting counts as up so the action
-- cancels it, and every other state, including a daemon that is not answering, offers
-- Connect. The status word plus provider sits in the subtitle. Shown only on the
-- unfiltered list, so a typed filter targets the cities below and Return connects to the
-- top match rather than toggling the tunnel.
local function actionRow()
  local up = current.state == "connected" or current.state == "connecting"
  local title, id, icon
  if up then
    local where = connectedLabel(current)
    title = where and ("Disconnect from " .. where) or "Disconnect"
    id, icon = "disconnect", ICON.disconnect
  else
    local where = targetLabel(target)
    title = where and ("Connect to " .. where) or "Connect"
    id, icon = "connect", ICON.connect
  end
  return { title = title, subTitle = statusText(current), image = emojiImage(icon), item = { id = id } }
end

-- The merged supplier. On the unfiltered list the action row leads, then the cities. A
-- query narrows the cities by a case insensitive substring match on the label or the
-- country code, so typing London, USA, or gb all narrow the list, and it drops the action
-- row so the top match is a city. Each city row carries its country flag as the icon.
local function rows(query)
  local q = (query or ""):lower()
  local out = {}
  if q == "" then out[#out + 1] = actionRow() end
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

--------------------------------------------------------------------------------
-- Selection dispatch (command policy)
--------------------------------------------------------------------------------

-- A row was chosen. Connect and Disconnect delegate to the engine, and any other row is
-- a city, so set that relay and connect. The native chooser has already closed either
-- way.
local function onSelect(sel)
  if not sel then return end
  if sel.id == "connect" then
    engine.connect()
  elseif sel.id == "disconnect" then
    engine.disconnect()
  else
    engine.setLocation(sel.countryCode, sel.cityCode)
  end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard and caffeinate)
--------------------------------------------------------------------------------

--- M.show() - read the state and the selected relay once, fetch the relay list, and open
--- the chooser. The status lives on the action row, not the placeholder, so the field just
--- prompts the location filter. The list is refreshed once the relays land, which also
--- resolves the selected relay's codes to its human label in the title.
function M.show()
  if not chooser then return end
  current = engine.status()
  target = engine.selectedLocation()
  engine.listLocations(function(list)
    cache = list or {}
    if chooser then chooser:refresh() end
  end)
  chooser:show()
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

function M.hide()
  if chooser then chooser:hide() end
end

-- Vim style navigation, routed here from the vpn Hyper context by the main root, the same
-- shared control the clipboard and caffeinate use.
function M.selectNext()
  if chooser then chooser:selectNext() end
end

function M.selectPrev()
  if chooser then chooser:selectPrev() end
end

--- M.insertSelected() - apply the highlighted row, exactly as Return does, routed here
--- from Hyper+i.
function M.insertSelected()
  if chooser then chooser:insertSelected() end
end

-- The daemon state changed while the chooser may be open. Refresh the snapshot and the
-- selected relay, then redraw so the action row's title and status follow the live state.
local function onChange()
  current = engine.status()
  target = engine.selectedLocation()
  if chooser and chooser:isShowing() then chooser:refresh() end
end

--- M.configure(opts) - inject the shared theme and the Chooser factory. Kept as the
--- single wiring seam so the main root stays the one place the atoms are handed in.
function M.configure(opts)
  cfg = opts or {}
  return M
end

--- M.start() - validate availability, wire the engine, and build the one native chooser.
--- When the CLI is missing it logs and returns without building, so the tool is inert.
function M.start()
  if not provider.available() then
    print("[Vpn] mullvad CLI not found, VPN controls disabled. Install the Mullvad app or run brew install --cask mullvad-vpn")
    return M
  end
  engine.configure({ provider = provider, onChange = onChange })
  engine.start()
  chooser = cfg.chooser.new({
    -- Pinned to the native hs.chooser backend, the snappy one the menu search uses,
    -- which also drops the footer and themed rendering the web surface adds.
    provider = "native",
    theme = cfg.theme,
    placeholder = "Search locations",
    fieldMode = "filter",
    rows = rows,
    onSelect = onSelect,
  })
  return M
end

return M
