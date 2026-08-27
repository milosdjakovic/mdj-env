--- === Vpn ===
---
--- A VPN control tool. It presents a single merged list of the controls and the location
--- search as one flat list, into the shared stage every presenting tool now shows through.
--- The first row is the action that fits the live state, its title naming the place,
--- Disconnect from where the tunnel is when it is up and Connect to the selected relay when
--- it is down, with the live state word and the provider in its subtitle. Every city the
--- provider offers follows below it, ordered most recently used first so the last place you
--- connected to leads and the action row stays pinned above them all. Typing filters the
--- cities, and once a filter is present the action row drops out so selecting the top row
--- connects to the top matching city rather than toggling the tunnel. Choosing a city sets
--- the relay and connects. It never names the keys that open or drive it, those live in
--- config and the root.
---
--- This file is the composition root and the command policy. It loads the engine and the
--- Mullvad provider, names them, and validates the provider against the contract. When the
--- CLI is not installed it logs the reason and still presents, to a single row naming the
--- missing backend and what provides it, both read from the provider's own install metadata
--- so the panel never learns the concrete tool. The engine is left unstarted in that state,
--- so a machine without Mullvad degrades to a self explaining row rather than a dead key.
--- That row is a label and not an action, since how to obtain a tool is the concern of the
--- layer above this config and no file here may answer it.
---
--- One flat list, not a drill down. The controls and the locations live in the same list,
--- so there is no mode to switch and no second level to re-show. The location list is
--- fetched on each open so a relay update is reflected, and the list is refreshed once it
--- lands. The navigation shortcuts are wired from the main root, this spoon never names them.
---
--- Migrated onto host/stage, phase three of the chooser stage build, docs/BRIEF-HANDOFF.md
--- decision eight. This file owns no chooser instance and builds no window any more. Its
--- rows and its selection dispatch are exactly what they always were, M.rows and M.select
--- below, now named on the manifest's own presentation block instead of handed to a
--- Chooser.new call this file no longer makes. Its own leader key still opens it, through
--- cfg.stagePresent, the root published word for the hotkey door every presenting plugin
--- shares, and its own async status refresh, onChange below, now asks for a redraw through
--- cfg.redrawPresented rather than reaching for a chooser instance directly.
---
--- This is the olm side copy of Vpn, converted to use the shared recency service at
--- Olm.spoon/lib/recency.lua instead of a hand rolled block, and the original this was
--- copied from lived at Spoons/Vpn.spoon.

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

local cfg = nil       -- injected: opts.recency required, stagePresent and redrawPresented optional
local available = false -- whether the provider's CLI was found at start
local cache = {}      -- the last fetched location list, filtered by the supplier
local current = { state = "unavailable" } -- status snapshot, refreshed on open and change
local target = nil    -- the selected relay to connect to, { countryCode, cityCode }
local fetching = false -- status, the selected relay, and the location list are all in
                        -- flight together, so a second ask does not start any of them again
local pending = {}    -- callbacks waiting on that fetch, so none of them is dropped

--------------------------------------------------------------------------------
-- Location recency (command policy, ordering lifted from the shared service)
--------------------------------------------------------------------------------

-- The cities are shown most recently used first, so the last place you connected to sits
-- right below the action row and the ones before it follow. The action row is never part
-- of this, it is added ahead of the list and always leads, so only the cities reorder.
--
-- Ordering itself now comes from an instance of the shared lift to front service, handed
-- in through configure as cfg.recency, rather than a block hand rolled here. The settings
-- key it persists under is the same one the original spoon used, so the remembered order a
-- person already has carries across a flip between the two copies. Identity here is the
-- location id, and building that id from a row stays this file's own policy, the service
-- only ever sees the finished key. The calls sit directly at the two places that need
-- them, connecting a chosen city and ordering a fetched list, rather than behind a wrapper
-- with nothing else to say.

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
-- missing backend and what provides it, both read from the provider's install metadata,
-- so the panel explains the gap instead of opening empty and never names the concrete
-- tool or the platform.
--
-- Disabled on purpose, so it reads as a label rather than an action. It deliberately does
-- not offer to install anything, because how a tool is obtained belongs to the layer above
-- this config, and a row here that copied an install command would put that answer in the
-- one layer that must not hold it. Naming the gap is this panel's whole job, and
-- src/check-dependencies.sh in the repository answers where the tool comes from.
local function unavailableRow()
  local info = provider.install or {}
  local name = provider.name or "VPN"
  return {
    title = name .. " CLI not found",
    subTitle = info.note or "The provider CLI is not installed",
    image = emojiImage("⚠️"),
    enabled = false,
    item = { id = "unavailable" },
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
-- a city, so set that relay and connect. None of the three is a presentation swap, this
-- plugin's own presentation declares no intercept, so the shared stage has already closed
-- the whole way down to whatever was below it, exactly as VPN's own standalone chooser used
-- to close on any of these three before the migration.
local function onSelect(sel)
  if not sel then return end
  -- The unavailable row is built disabled, so this never dispatches it and there is no
  -- branch for it here. Guarded anyway, since a row arriving without a live engine would
  -- otherwise reach an engine call.
  if sel.id == "unavailable" then return end
  if sel.id == "connect" then
    engine.connect()
  elseif sel.id == "disconnect" then
    engine.disconnect()
  else
    -- A city was chosen, so lift it to the front of the recency order before connecting,
    -- so it leads the cities on the next open.
    cfg.recency.touch(sel.id)
    engine.setLocation(sel.countryCode, sel.cityCode)
  end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.show() - present through the shared stage. This is the hotkey door, decision one of the
--- handoff brief, reached only from this plugin's own leader key. A launcher row choosing VPN
--- never calls this at all, it pushes the registry's own presentation straight from the
--- root's rowIntercept, decision two, so this function's only remaining caller is the key
--- registry.open binds directly. cfg.stagePresent asks the registry for this plugin's own
--- presentation and hands it to Stage:present, the fresh stack door, exactly what opening VPN
--- from cold has always meant.
---
--- Fetches nothing itself any more. Stage:present calls the presentation's own onPresent
--- once p becomes current, M.onPresent below, which is what both doors, this one and the
--- launcher's own push, now share for the read and the fetch that used to live only here,
--- phase three review finding two, a launcher row choosing VPN used to swap onto a list with
--- no cities at all until something else had warmed the cache.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("vpn") end
end

--- M.onPresent() - the presentation contract's own lifecycle member, phase three review
--- finding two, called by the stage whenever this plugin's presentation becomes current,
--- through present or push alike, before the window itself is shown or swapped into. Starts
--- the same fetch M.show used to start directly, redrawing through cfg.redrawPresented once
--- it lands, the identical word onChange already asks for its own async status refresh,
--- rather than a fresh mechanism this one hook alone would need. Named on the manifest's own
--- presentation block as onPresent.
---
--- Never blocks the swap that is about to happen, phase three review finding eleven. Every
--- read M.prepare below now starts is off the main thread, so this call returns the instant
--- the reads and the fetch have been asked for rather than after they answer, which is what
--- lets the stage go on to swap the window in on the same keypress that reached here.
function M.onPresent()
  M.prepare(function()
    if cfg.redrawPresented then cfg.redrawPresented("vpn") end
  end)
end

--- M.rows(query) -> list. The merged control and location rows, named on the manifest's own
--- presentation block as the contract's rows, and exposed here under this plain name so a
--- scope can ask for the identical data through provides.rows without a second copy to
--- disagree with. Says nothing about where the rows are shown.
M.rows = rows

--- M.select(item) - apply one of those rows, taking the descriptor its own rows produced.
--- Named on the manifest's own presentation block as the contract's onSelect.
M.select = onSelect

--- M.placeholder() -> string. The field hint while this plugin's own presentation is
--- current, named on the manifest's own presentation block. Resolved once, when this plugin
--- registers, since the presentation contract wants a plain string rather than something to
--- call again later, and by then this plugin's own start has already resolved available, so
--- the answer already reflects it.
function M.placeholder()
  return available and "Search locations" or ((provider.name or "VPN") .. " not installed")
end

--- M.ready() -> boolean. Whether any locations have landed. They arrive from a process, so a
--- surface presenting these rows needs to tell no locations yet from no locations at all.
function M.ready()
  return #cache > 0
end

--- M.scopeRows(rest, redraw) -> list. The query scope's own rows, asked fresh on entry or
--- while nothing has landed, exactly the way M.show already asks through M.prepare either
--- side of presenting. A scope has no list of its own to refresh once the fetch answers, so
--- redraw is a plain callback the caller hands in for that one moment rather than this spoon
--- reaching for whatever is showing these rows, which is the whole reason this spoon still
--- names no launcher and no host. Unchanged by the migration, decision eight, this scope
--- stays exactly as is. The typed text rides along as the filter text on the one placeholder
--- row below, so the matcher can never rank away the only row there is while the real list
--- is still in flight.
function M.scopeRows(rest, redraw)
  if rest == "" or not M.ready() then
    M.prepare(redraw)
  end
  local out = rows(rest)
  if #out == 0 and not M.ready() then
    return { { title = "Reading the locations", subTitle = "one moment",
               image = emojiImage("⏳"), enabled = false, filterText = rest } }
  end
  return out
end

--- M.prepare(onReady) - make the rows current without presenting anything, reading the live
--- state and fetching the locations, then calling back once they land. This is what show does
--- either side of presenting, factored out so a presentation that is already up gets the same
--- fresh data and redraws itself. A fetch already in flight is not started again, since
--- the first one's callback redraws anyway, which is what keeps a keystroke from spawning a
--- process. Unavailable calls back at once, so a caller never waits on a fetch that cannot
--- happen and the single self explaining row is what gets shown.
---
--- Every caller waiting on the same fetch is called back, rather than the second one being
--- dropped along with the fetch it did not need to start. Dropping it would mean a surface
--- opening while another one's fetch was in flight never learned the list had landed.
---
--- All three reads run off the main thread now, phase three review finding eleven. current
--- and target used to be read synchronously here, straight into two CLI spawns, before this
--- function ever reached the already async relay list. M.onPresent below calls this before
--- the swap that reveals it, decision two, so a blocking read here used to be a blocking read
--- on the keypress itself, the row completing only once the shell had answered twice. rows
--- below draws from whatever current and target already hold the instant it is asked, the
--- last snapshot or the { state = "unavailable" } default neither has ever been read past,
--- and this function only ever updates them once the async answer actually lands, landing
--- through the identical fetching and pending guard the relay list already shared this
--- function with, so a bounce between the launcher and VPN while a read is already in flight
--- spawns nothing extra and every caller still waiting is still called back exactly once,
--- after all three reads have landed rather than after whichever lands first.
function M.prepare(onReady)
  if not available then
    if onReady then onReady() end
    return
  end
  if onReady then pending[#pending + 1] = onReady end
  if fetching then return end
  fetching = true
  local remaining = 3
  local function landed()
    remaining = remaining - 1
    if remaining > 0 then return end
    fetching = false
    local waiting = pending
    pending = {}
    for _, cb in ipairs(waiting) do cb() end
  end
  engine.statusAsync(function(status)
    current = status
    landed()
  end)
  engine.selectedLocationAsync(function(loc)
    target = loc
    landed()
  end)
  engine.listLocations(function(list)
    cache = cfg.recency.order(list or {}, function(loc) return loc.id end)
    landed()
  end)
end

-- isShowing, hide, selectNext, selectPrev, and insertSelected are gone, phase three,
-- deleted along with the Chooser.new block that gave them something to answer for. The
-- composition root now routes this plugin's own navigation through host/stage's own
-- surfaceFor once wiredRegistry.presentationFor("vpn") answers a presentation, root/
-- compose.lua's own surface adapters loop, so there is nothing left for this file to
-- expose under those five names.

-- The daemon state changed while this plugin's own presentation may be up. Refresh the
-- snapshot and the selected relay, then ask to be redrawn, which is a no op unless this
-- plugin's own presentation, and no other, is what the stage is actually showing, decision
-- eight of the handoff brief.
local function onChange()
  current = engine.status()
  target = engine.selectedLocation()
  if cfg.redrawPresented then cfg.redrawPresented("vpn") end
end

--- M:configure(opts) - inject the shared theme, the ambient grant a surfaced plugin still
--- earns even though this file no longer reads chooser or theme from it, having no
--- Chooser.new call left to hand either to. Kept as the single wiring seam so the main root
--- stays the one place the atoms are handed in.
---
--- opts.deps is the per consumer dependency adapter, also from the root. start passes the
--- path it holds to the provider, which is why nothing under this spoon probes for a CLI
--- or names a location.
---
--- opts.recency is an instance of the shared lift to front ordering service from
--- Olm.spoon, already built against this tool's own settings key. It is required, since
--- this copy no longer carries a recency block of its own, and a missing one is rejected
--- loudly rather than quietly ordering nothing.
---
--- opts.stagePresent and opts.redrawPresented are the two root published words phase three
--- adds, both optional, both no ops when absent, M.show and onChange above say what each
--- one degrades to without the other.
-- Colon here, not dot, because the composition root and the live top level init.lua both
-- reach this through the ordinary method call spoon.Vpn:configure(opts), and the shared
-- wiring pipeline in lib/wire.lua calls every plugin's configure the same way. self arrives
-- as M and is not otherwise used in the body below.
function M:configure(opts)
  cfg = opts or {}
  if not cfg.recency then
    error("Vpn configure requires opts.recency, an instance of the shared recency service")
  end
  return M
end

--- M:start() - resolve availability and wire the engine when the CLI is present. When the
--- CLI is missing it logs the reason, read from the provider's install metadata, and leaves
--- the engine unstarted, so a presentation of this plugin opens to the self explaining
--- unavailable row instead of the tool being a dead key. The log line names what is missing
--- and stops there, since the repository is what knows how to obtain it.
---
--- Builds no chooser any more, phase three. Whatever this plugin used to hand a Chooser.new
--- call, theme, a field mode, rows, onSelect, and the panel triple, is now either read
--- straight off this module by the registrar, rows and select through the manifest's own
--- presentation block, or owned by the stage as fixed, atom level policy that never varied
--- per presentation in the first place.
function M:start()
  -- Hand the provider the path the shared resolver found, by the name the provider itself
  -- declares, so this spoon learns neither the tool's location nor how it is obtained.
  provider.configure({ path = cfg.deps and cfg.deps.path(provider.tool) or nil })
  available = provider.available()
  if available then
    engine.configure({ provider = provider, onChange = onChange })
    engine.start()
  else
    local info = provider.install or {}
    local name = provider.name or "VPN"
    local parts = { name .. " CLI not found, VPN controls disabled" }
    if info.note then parts[#parts + 1] = info.note end
    log.w(table.concat(parts, ". "))
  end
  return M
end

return M
