--- === Vpn ===
---
--- A VPN control tool. It opens a single native chooser that merges the controls and the
--- location search into one flat list. The first row is the action that fits the live
--- state, its title naming the place, Disconnect from where the tunnel is when it is up
--- and Connect to the selected relay when it is down, with the live state word and the
--- provider in its subtitle. Every city the provider offers follows below it. Typing
--- filters the cities, and once a filter is present the action row drops out so selecting
--- the top row connects to the top matching city rather than toggling the tunnel. Choosing
--- a city sets the relay and connects. It never names the keys that open or drive it, those
--- live in config and the root.
---
--- This file is the composition root and the command policy. It loads the engine and the
--- Mullvad provider, names them, validates the provider against the contract, and builds
--- one Chooser instance pinned to the native hs.chooser backend. It turns a chosen row
--- into an engine call. When the CLI is not
--- installed it logs the reason and still builds the chooser, which then opens to a single
--- row naming the missing backend and its install command, both read from the provider's
--- own install metadata so the panel never learns the concrete tool. The engine is left
--- unstarted in that state, so a machine without Mullvad degrades to a self explaining
--- panel rather than a dead key. Selecting the row copies the install command.
---
--- One flat list, not a drill down. The controls and the locations live in the same list,
--- so there is no mode to switch and no second level to re-show. The location list is
--- fetched on each open so a relay update is reflected, and the list is refreshed once it
--- lands. The navigation shortcuts are wired from the main root, this spoon never names
--- them, and the root also docks its shared deferred shortcut hint panel below the list
--- through the onPositioned, onActivity, and onClose seams this spoon forwards to its
--- chooser.

local M = { name = "Vpn", version = "3.0", author = "Milos Djakovic", license = "MIT" }

local log = hs.logger.new("Vpn", "info")

-- Load the siblings by absolute path off this file's own location (loadfile, not require,
-- since a spoon dir is not on package.path). The load helper wraps loadfile so a broken
-- sibling fails with a Vpn-prefixed message rather than a bare Lua error.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Vpn: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local engine = load("engine.lua")
local contract = load("contract.lua")
-- The provider line is the one place the concrete backend is named. It is validated
-- against the contract at load, and since the single provider is not optional a gap is
-- a hard failure here rather than graceful degradation.
local provider = load("providers/mullvad.lua")
do
  local ok, missing = contract.validate(provider)
  if not ok then
    error("Vpn: mullvad provider does not implement " .. missing .. "()")
  end
end

local cfg = nil       -- injected: the shared theme and the Chooser factory
local chooser = nil   -- the one native Chooser instance
local available = false -- whether the provider's CLI was found at start
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

-- The single row shown when the provider's CLI was not found at start. It names the
-- missing backend and its install command, both read from the provider's install
-- metadata, so the panel explains the gap instead of opening empty and never names the
-- concrete tool or the platform. Title and subtitle are plain data, the command as the
-- subtitle, with no hint about which key operates the row, since how the row is driven is
-- the root's concern and shows through the shared shortcut panel. A provider that carries
-- no install metadata still gets a titled row, just without a command.
local function unavailableRow()
  local info = provider.install or {}
  local name = provider.name or "VPN"
  return {
    title = name .. " CLI not found",
    subTitle = info.command or info.note or "The provider CLI is not installed",
    image = emojiImage("⚠️"),
    item = { id = "install", command = info.command },
  }
end

-- The merged supplier. When the provider is unavailable the whole list is the one
-- self explaining install row, and typing has nothing to filter. Otherwise the action
-- row leads only on the empty query, then every city follows, and the atom's shared
-- matcher filters and ranks the cities against the query. Each city carries filterText
-- of its label plus country code, so typing London, USA, or gb all narrow it. The action
-- row appears only when the field is empty, so a query never has to filter it out. Each
-- city row carries its country flag as the icon.
local function rows(query)
  if not available then return { unavailableRow() } end
  local out = {}
  if (query or "") == "" then out[#out + 1] = actionRow() end
  for _, loc in ipairs(cache) do
    out[#out + 1] = {
      title = loc.label,
      subTitle = loc.countryCode .. " " .. loc.cityCode,
      image = flagImage(loc.countryCode),
      item = loc,
      filterText = loc.label .. " " .. loc.countryCode,
    }
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
  if sel.id == "install" then
    -- The unavailable row. Copy the install command to the clipboard so the fix is one
    -- paste away, and confirm with a short alert. No command means nothing to copy.
    if sel.command then
      hs.pasteboard.setContents(sel.command)
      hs.alert.show("Copied: " .. sel.command)
    end
    return
  end
  if sel.id == "connect" then
    engine.connect()
  elseif sel.id == "disconnect" then
    engine.disconnect()
  else
    engine.setLocation(sel.countryCode, sel.cityCode)
  end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.show() - read the state and the selected relay once, fetch the relay list, and open
--- the chooser. The status lives on the action row, not the placeholder, so the field just
--- prompts the location filter. The list is refreshed once the relays land, which also
--- resolves the selected relay's codes to its human label in the title.
function M.show()
  if not chooser then return end
  -- When the provider is unavailable the engine was never started, so skip the live
  -- reads and just open the chooser on its single install row.
  if available then
    current = engine.status()
    target = engine.selectedLocation()
    engine.listLocations(function(list)
      cache = list or {}
      if chooser then chooser:refresh() end
    end)
  end
  chooser:show()
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

function M.hide()
  if chooser then chooser:hide() end
end

-- List navigation, routed here from the vpn context by the main root. The spoon exposes
-- the methods and never names the keys bound to them.
function M.selectNext()
  if chooser then chooser:selectNext() end
end

function M.selectPrev()
  if chooser then chooser:selectPrev() end
end

--- M.insertSelected() - apply the highlighted row, the same as choosing it, routed here
--- from the navigation shortcut the root binds.
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

--- M.configure(opts) - inject the shared theme, the Chooser factory, and the optional
--- docked panel callbacks (onPositioned, onActivity, onClose) the root wires to its
--- deferred shortcut hint panel. The spoon forwards those straight to its chooser without
--- learning what they drive, so the panel stays the root's concern. Kept as the single
--- wiring seam so the main root stays the one place the atoms are handed in.
function M.configure(opts)
  cfg = opts or {}
  return M
end

--- M.start() - resolve availability, wire the engine when the CLI is present, and build
--- the one native chooser either way. When the CLI is missing it logs the reason, read
--- from the provider's install metadata, and leaves the engine unstarted, so the chooser
--- opens to the self explaining install row instead of the tool being a dead key.
function M.start()
  available = provider.available()
  if available then
    engine.configure({ provider = provider, onChange = onChange })
    engine.start()
  else
    local info = provider.install or {}
    local name = provider.name or "VPN"
    local parts = { name .. " CLI not found, VPN controls disabled" }
    if info.note then parts[#parts + 1] = info.note end
    if info.command then parts[#parts + 1] = "install with: " .. info.command end
    log.w(table.concat(parts, ". "))
  end
  chooser = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = available and "Search locations" or ((provider.name or "VPN") .. " not installed"),
    fieldMode = "filter",
    rows = rows,
    onSelect = onSelect,
    -- The root's deferred shortcut hint panel, wired through the chooser's own seams so
    -- the spoon stays ignorant of the panel. All optional; nil when no panel is injected.
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    onClose = cfg.onClose,
  })
  return M
end

return M
