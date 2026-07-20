--- === Vpn ===
---
--- A VPN control tool. Hyper+Y opens a native chooser that works as a two level menu.
--- The top level, the menu mode, shows the one action that fits the live state,
--- Disconnect when the tunnel is up and Connect when it is down, with the full status
--- spelled out in its subtitle, plus a Choose location row. Choosing that drops into the
--- locations mode, a filterable list of every city the provider offers, with a Back row
--- at the top of the unfiltered list that returns to the menu. Choosing a city sets the
--- relay and connects.
---
--- This file is the composition root and the command policy. It loads the engine and the
--- Mullvad provider, names them, validates the provider against the contract, and builds
--- one Chooser instance pinned to the native hs.chooser backend, the snappy one the menu
--- search also uses. It turns a chosen row into an engine call. When the CLI is not
--- installed it logs the reason and the tool does nothing, so a machine without Mullvad
--- degrades quietly.
---
--- One instance, two modes, not two instances. The native chooser dismisses its window on
--- any selection, so a drill down cannot keep one window open and repopulate it. Both
--- levels therefore re-show the same chooser, and a single `mode` field decides what the
--- row supplier returns and what a selection means. This is the State pattern living
--- inside one widget. The menu-to-locations and locations-to-menu hops re-show after a
--- short delay so the closing chooser's focus restore settles before the next open takes
--- focus, the same idiom the panel version used.
---
--- Native, so no footer and no Hyper navigation context: the chooser is driven by its own
--- arrow keys, type-to-filter, Return, and Escape once Hyper is released. Hyper+Y only
--- opens it.

local M = { name = "Vpn", version = "2.0", author = "mdj-env" }

-- Load the siblings by absolute path, the Capture idiom (a spoon dir is not on
-- package.path). The provider line is the one place the concrete backend is named,
-- validated against the contract at load so a missing method fails visibly here.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local engine = dofile(spoonPath .. "engine.lua")
local contract = dofile(spoonPath .. "contract.lua")
local provider = contract.validate(dofile(spoonPath .. "providers/mullvad.lua"))

local cfg = nil       -- injected: the shared theme and the Chooser factory
local chooser = nil   -- the one native Chooser instance, re-shown in either mode
local mode = "menu"   -- "menu" (the two actions) or "locations" (the city list)
local cache = {}      -- the last fetched location list, filtered by the supplier
local current = { state = "unavailable" } -- status snapshot, refreshed on each menu open

--------------------------------------------------------------------------------
-- Status wording (command policy)
--------------------------------------------------------------------------------

-- The provider name labels the status line, so it is clear which VPN app this is
-- driving. It comes from the provider itself (the one place that knows the backend),
-- shown in parentheses after the live state, and named directly in the not responding
-- line since there is no state to pair it with.
local function statusText(s)
  local name = provider.name or "VPN"
  if not s or s.state == "unavailable" then return name .. " is not responding" end
  local st = s.state
  local base
  if st == "connected" then
    if s.city and s.country then base = "Connected, " .. s.city .. ", " .. s.country
    elseif s.hostname then base = "Connected, " .. s.hostname
    else base = "Connected" end
  elseif st == "connecting" then
    base = "Connecting"
  elseif st == "disconnecting" then
    base = "Disconnecting"
  elseif st == "disconnected" then
    base = "Disconnected"
  else
    base = tostring(st)
  end
  return base .. " (" .. name .. ")"
end

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an
-- offscreen canvas drawn once and cached by the string, since a supplier runs on every
-- keystroke. The flags and the menu glyphs both go through this one path. A false marks
-- a string that cannot render, so it is attempted only once.
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

-- The menu glyphs. Green and red circles read as go and stop at a glance, the globe
-- marks the location list, and the arrow marks the way back.
local ICON = {
  connect = "🟢",
  disconnect = "🔴",
  locations = "🌍",
  back = "⬅️",
}

--------------------------------------------------------------------------------
-- Row suppliers, one per mode
--------------------------------------------------------------------------------

-- The menu rows depend on the state read at open. When the tunnel is up the primary
-- action is Disconnect, otherwise it is Connect, and its subtitle carries the full live
-- status since the native chooser has no separate status line. Connecting counts as up
-- so the action cancels it, and every other state, including a daemon that is not
-- answering, offers Connect. Choose location is always the second row. The query is
-- ignored here, the menu is only two rows.
local function menuRows()
  local up = current.state == "connected" or current.state == "connecting"
  local primary = up
    and { title = "Disconnect", subTitle = statusText(current), image = emojiImage(ICON.disconnect), item = { id = "disconnect" } }
    or { title = "Connect", subTitle = statusText(current), image = emojiImage(ICON.connect), item = { id = "connect" } }
  return {
    primary,
    { title = "Choose location", subTitle = "Browse all locations", image = emojiImage(ICON.locations), item = { id = "locations" } },
  }
end

-- The locations supplier, a case insensitive substring match on the label or the country
-- code, so typing London, USA, or gb all narrow the list. Each row carries its country
-- flag as the icon. The Back row leads the unfiltered list so it is the first thing seen
-- on entering, but it is dropped the moment a query is typed, so Return on a filtered list
-- connects to the top matching city rather than bouncing back to the menu.
local function locationRows(query)
  local q = (query or ""):lower()
  local out = {}
  if q == "" then
    out[#out + 1] = { title = "Back", subTitle = "Return to VPN menu", image = emojiImage(ICON.back), item = { back = true } }
  end
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

-- The one supplier the chooser calls, branching on the live mode.
local function rows(query)
  if mode == "menu" then return menuRows() end
  return locationRows(query)
end

--------------------------------------------------------------------------------
-- Re-show, the mechanism behind both levels
--------------------------------------------------------------------------------

-- Show the chooser for the current mode. The menu reads a fresh status snapshot each
-- open so both rows reflect the live state, and the placeholder names the mode. The atom
-- resets the query to empty on show, so entering a level always starts unfiltered.
local function showChooser()
  if not chooser then return end
  if mode == "menu" then
    current = engine.status()
    chooser:setPlaceholder(provider.name or "VPN")
  else
    chooser:setPlaceholder("Search locations")
  end
  chooser:show()
end

-- Enter the locations mode: fetch the relay list fresh so an update is reflected, show
-- the list, and refresh it once the list lands.
local function enterLocations()
  mode = "locations"
  engine.listLocations(function(list)
    cache = list or {}
    if chooser then chooser:refresh() end
  end)
  showChooser()
end

-- Return to the menu.
local function enterMenu()
  mode = "menu"
  showChooser()
end

--------------------------------------------------------------------------------
-- Selection dispatch (command policy)
--------------------------------------------------------------------------------

-- A row was chosen; the native chooser has already closed. In menu mode Connect and
-- Disconnect delegate to the engine and the tool is done, while Choose location re-shows
-- in locations mode after a short delay so the closing chooser's focus restore settles
-- first. In locations mode Back re-shows the menu the same way, and a city sets the relay
-- and connects. The mode is left as it is; the next Hyper+Y resets it to menu via M.show.
local function onSelect(sel)
  if not sel then return end
  if mode == "menu" then
    if sel.id == "connect" then
      engine.connect()
    elseif sel.id == "disconnect" then
      engine.disconnect()
    elseif sel.id == "locations" then
      hs.timer.doAfter(0.08, enterLocations)
    end
  else
    if sel.back then
      hs.timer.doAfter(0.08, enterMenu)
    else
      engine.setLocation(sel.countryCode, sel.cityCode)
    end
  end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard and caffeinate)
--------------------------------------------------------------------------------

--- M.show() - open the VPN control chooser at the menu level. Resetting the mode here
--- means every fresh open starts at the menu regardless of how the last one ended, an
--- Escape out of the locations list included.
function M.show()
  if not chooser then return end
  mode = "menu"
  showChooser()
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

function M.hide()
  if chooser then chooser:hide() end
end

-- The daemon state changed while the chooser may be open. Redraw the menu rows so the
-- action and its status subtitle follow. Only the menu shows status, so a locations-mode
-- refresh is harmless.
local function onChange()
  current = engine.status()
  if chooser and chooser:isShowing() and mode == "menu" then chooser:refresh() end
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
    placeholder = provider.name or "VPN",
    fieldMode = "filter",
    rows = rows,
    onSelect = onSelect,
  })
  return M
end

return M
