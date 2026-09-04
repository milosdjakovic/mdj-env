--- === Vpn ===
---
--- A VPN control tool. It presents a single merged list of the controls and the location
--- search as one flat list, into the shared stage every presenting tool now shows through.
--- The first row is the action that fits the live state, its title naming the place,
--- Disconnect from where the tunnel is when it is up and Connect to where it would go when it
--- is down, with the live state word and the provider in its subtitle. Every city the provider
--- offers follows below it, ordered most recently used first so the last place you connected
--- to leads and the action row stays pinned above them all. Typing filters the cities, and
--- once a filter is present the action row drops out so selecting the top row connects to the
--- top matching city rather than toggling the tunnel. Choosing a city connects to it. It never
--- names the keys that open or drive it, those live in config and the root.
---
--- The connect row names a place on either backend, and it does so because the place is an
--- argument this file hands to connect rather than something it reads back off a daemon. Where
--- that argument comes from is this file's own policy, three sources in order, the backend's
--- own published selection when it has one, this tool's own record of the last place it was
--- asked for, then the recency order it has always kept, so the wording no longer depends on a
--- backend happening to publish a reader that only one of them has.
---
--- This file is the composition root and the command policy. It loads the engine, loads
--- every provider, names them, and validates each one against the contract. One provider is
--- active at a time, chosen on a page reached from the list's own last row and remembered
--- across reloads. When the active provider's CLI is not installed it logs the reason and
--- still presents, to a row naming the missing backend and what provides it, both read from
--- that provider's own install metadata so the panel never learns the concrete tool, with
--- the provider page still beside it so the choice can be taken back. The engine is left
--- unwired in that state, so a machine missing a backend degrades to a self explaining row
--- rather than a dead key. That row is a label and not an action, since how to obtain a tool
--- is the concern of the layer above this config and no file here may answer it.
---
--- One backend at a time, not every backend merged. Two VPN daemons cannot usefully both
--- hold the routes, a single action row cannot carry two tunnel states, and choosing a
--- foreign city would then flip the daemon underneath somebody as a side effect of picking a
--- place. So the providers are a choice rather than a union.
---
--- One flat list, not a drill down, with the single exception of that page. The controls and
--- the locations live in the same list, so there is no mode to switch and no second level to
--- re-show. The location list is fetched on each open so a relay update is reflected, and
--- the list is refreshed once it lands. The navigation shortcuts are wired from the main
--- root, this spoon never names them.
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

--------------------------------------------------------------------------------
-- The backends (composition)
--------------------------------------------------------------------------------

-- The one place the concrete backends are named, in the order a machine with no stored
-- choice should prefer them. Adding a backend is a new file beside these two and one line
-- here, and nothing else in this plugin is touched.
--
-- A scan of the providers directory was considered and rejected. It would have made a
-- forgotten line here impossible, which is this list's only remaining failure, but the dry
-- contract gate loads this module against a permissive hs stub where hs.fs.dir answers
-- another stub rather than an iterator, so the scan would hang the one gate that exists to
-- catch mistakes of this kind. The provider page below covers most of what the scan would
-- have, since a file that never got a line here is a row that never appears in the one
-- place a person goes to look for it.
local PROVIDER_FILES = { "mullvad", "ivpn" }

-- The chosen backend, persisted so it survives a reload and a reboot. The provider's own
-- file stem is what is stored, not its display name, since the name is presentation and can
-- be reworded while the stem is the identity everything else here joins on.
local PROVIDER_KEY = "olm.vpn.provider"

-- Where the last place this tool was asked to connect to is remembered, per backend, so a
-- backend that cannot say where a bare connect would go still has a place to name. One key
-- holding a table under each provider's own file stem rather than a key per provider, since
-- the stems are whatever the roster happens to hold and this file mints no name for them.
--
-- This is the plugin's own record of what it did, not a read of the daemon, and the two are
-- worth keeping apart. A backend that publishes a selection of its own is still asked first,
-- since that one is authoritative and follows a change made in the backend's own app. This is
-- what answers when there is no such reader, and it is honest for a different reason, the row
-- hands its target to connect rather than hoping the daemon agrees, so what the title says is
-- what the action does.
local TARGET_KEY = "olm.vpn.target"

-- Every provider is loaded and validated at load, and a gap is a hard failure rather than
-- graceful degradation, since a file that cannot answer the contract is not a backend this
-- engine can drive at all. A missing tool is an entirely different thing, answered per
-- provider by available() and shown as a state on the page rather than raised here.
local providers = {}
for _, id in ipairs(PROVIDER_FILES) do
  local module = load("providers/" .. id .. ".lua")
  local ok, gap = contract.validate(module)
  if not ok then
    error("Vpn: the " .. id .. " provider does not satisfy the contract, " .. tostring(gap))
  end
  providers[#providers + 1] = { id = id, module = module }
end

local cfg = nil       -- injected: opts.recency required, the stage words optional
local provider = nil  -- the active backend, one of the modules loaded above
local activeId = nil  -- its file stem, the identity the page and the stored choice join on
local available = false -- whether the active provider's CLI was found
local cache = {}      -- the last fetched location list, filtered by the supplier
local current = { state = "unavailable" } -- status snapshot, refreshed on open and change
local target = nil    -- where a connect goes, { countryCode, cityCode }, nil for nowhere named
local fetching = false -- status, the selected relay, and the location list are all in
                        -- flight together, so a second ask does not start any of them again
local pending = {}    -- callbacks waiting on that fetch, so none of them is dropped

-- Bumped on every switch, and checked by every async answer before it writes anything. The
-- three reads prepare starts do not know which backend asked for them, so without this a
-- switch mid flight lets one provider's location list land in another's cache, and lets a
-- finished round's own countdown clear the fetching guard the new round is relying on. This
-- is the same fence the plugin contract already describes for an async answer landing on the
-- level that asked for it, applied to backends instead of levels.
local generation = 0

-- Defined further down, once onChange exists for them to wire, and forward declared here
-- because the provider page's own intercept closes over switchTo while being built above
-- the point where it can be written.
local activate, switchTo

-- The bound M.prepare gives each of its three reads before treating a leg that has not
-- answered as gone rather than merely slow. The phase three verification rider: none of the
-- three had a failure path before this, so a daemon that never calls back, wedged rather than
-- merely slow, left fetching stuck true forever with pending only ever growing, since nothing
-- was left to count that leg's own landed() down. Five seconds is a plain chosen bound rather
-- than a measured one, comfortably past what a live CLI read ever takes and short enough that
-- a person waiting on the picker is not left sitting for it.
local FETCH_TIMEOUT = 5

-- Held so the three timers a round schedules cannot be collected before they fire, a
-- Hammerspoon timer being userdata whose finalizer stops it the moment nothing refers to it.
-- Only one round is ever in flight at a time, guarded by fetching above, so reusing one table
-- across rounds is safe, a new round's own three timers simply overwrite whatever a finished
-- round left behind.
local fetchTimers = {}

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
-- The connect target (command policy)
--------------------------------------------------------------------------------

-- The remembered target for whichever backend is active, or nil when this tool has never
-- connected to a place on it. Shape checked rather than trusted, since a settings file is
-- editable by hand and a table with no countryCode would reach the label and the action as a
-- target that names nothing.
local function storedTarget()
  local all = hs.settings.get(TARGET_KEY)
  if type(all) ~= "table" then return nil end
  local t = all[activeId]
  if type(t) ~= "table" or not t.countryCode then return nil end
  return t
end

-- Remember a chosen location as the active backend's target. The label is kept beside the two
-- codes on purpose, since it was produced by the very row the person chose and the codes on
-- their own cannot be turned back into words until the location list has landed, which is
-- exactly the moment the action row is first drawn.
local function rememberTarget(loc)
  local all = hs.settings.get(TARGET_KEY)
  if type(all) ~= "table" then all = {} end
  all[activeId] = { countryCode = loc.countryCode, cityCode = loc.cityCode, label = loc.label }
  hs.settings.set(TARGET_KEY, all)
end

-- The last place chosen on this backend, recovered from the recency order rather than from the
-- store above. The two hold the same fact, a place this tool was asked for, and they differ
-- only in what they keep of it, an ordering of ids against a whole descriptor, so reading this
-- one is not a guess about the daemon any more than reading the other is.
--
-- It is filtered through the loaded locations, which is what keeps one backend's history out of
-- another's answer. The recency instance is shared across backends and no two of them spell a
-- location the same way, so a key stored by one simply never matches while the other is looking
-- at its own list, the same property the shared instance already relied on to be safe.
--
-- Answers nothing until the list has landed, since a remembered id is only a place once there
-- is something to match it against, which is why the list leg asks again when it arrives.
local function recentTarget()
  if not cfg.recency or #cache == 0 then return nil end
  local best, bestRank
  for _, loc in ipairs(cache) do
    local rank = cfg.recency.rankOf(loc.id)
    if rank and (not bestRank or rank < bestRank) then best, bestRank = loc, rank end
  end
  if not best then return nil end
  return { countryCode = best.countryCode, cityCode = best.cityCode, label = best.label }
end

-- Where a connect goes, from the three sources in order. A backend that publishes its own
-- selection wins, since that one is read live and follows a change made in the backend's own
-- app. The remembered choice answers for a backend that publishes none. The recency order
-- answers when neither does, which is a machine that used this tool before the store existed,
-- since the order it kept is a record of the same choices and there is no reason to make
-- somebody teach the tool a place it already knows.
--
-- Nil from all three is a machine that has never chosen a place here at all, which is the one
-- case left where the row cannot name one.
local function targetFrom(read)
  if read then return read end
  return storedTarget() or recentTarget()
end

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

-- The target resolved to a human label, from three sources in that order. The loaded city
-- list first, since a live match is the freshest wording and a country only target resolves
-- there to the country name. Then a label the target carries, which a remembered one does,
-- since it was taken off the very row that was chosen. Then the raw codes, so the title is
-- never blank. Nil only when there is no target at all.
--
-- The carried label is what makes this read properly before the city list has landed, which
-- is exactly when the action row is first drawn. Without it a backend whose cityCode is a
-- gateway host would spell that host into the title for the first moment of every open, and
-- upper cased at that, so the row would read as gibberish and then quietly correct itself.
local function targetLabel(t)
  if not t then return nil end
  for _, loc in ipairs(cache) do
    if loc.countryCode == t.countryCode and (not t.cityCode or loc.cityCode == t.cityCode) then
      return t.cityCode and loc.label or loc.country
    end
  end
  if t.label then return t.label end
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

-- The action glyphs. A green circle reads as go, a red one as stop. The rest are the
-- shared vocabulary the other pages in this config already use for the same meanings, so a
-- page here reads the way the settings and browser pages do rather than inventing its own
-- marks. Green is the live one, an empty circle is a choice that is there to be made, and
-- the warning triangle is something this machine cannot currently reach.
local ICON = {
  connect = "🟢",
  disconnect = "🔴",
  back = "⬅️",
  settings = "⚙️",
  active = "🟢",
  idle = "⚪",
  warn = "⚠️",
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
  if up then
    local where = connectedLabel(current)
    return {
      title = where and ("Disconnect from " .. where) or "Disconnect",
      subTitle = statusText(current),
      image = emojiImage(ICON.disconnect),
      item = { id = "disconnect" },
    }
  end
  -- The connect row carries the target it just named, so the place in the title and the place
  -- the action goes are one value rather than two reads of it. A live status change redraws
  -- this row anyway, so nothing goes stale, but reading the target a second time at the press
  -- would leave a window, however small, where the row promised one place and delivered
  -- another. Nil rides along as an absent field, which connect already reads as go wherever
  -- this backend would go on its own.
  local where = targetLabel(target)
  return {
    title = where and ("Connect to " .. where) or "Connect",
    subTitle = statusText(current),
    image = emojiImage(ICON.connect),
    item = { id = "connect", target = target },
  }
end

--------------------------------------------------------------------------------
-- The provider page (a child level)
--------------------------------------------------------------------------------

-- The row that opens the provider page, and the only way into it. Last in the list on
-- purpose. The city directly under the action row is the one used most recently, which is
-- the whole point of that ordering, so a settings row in second place would push the thing
-- a person actually came for down by one every single time. At the bottom it costs that
-- nothing, and it carries the words somebody would really type when looking for it, so any
-- of settings, config, or provider ranks it straight to the top and the placement stops
-- mattering the moment it is wanted.
local function settingsRow()
  return {
    title = "VPN provider",
    subTitle = (provider and provider.name) or "none",
    image = emojiImage(ICON.settings),
    item = { id = "providers" },
    filterText = "VPN provider providers backend settings config",
  }
end

-- The page's own rows, Back and then one per loaded provider.
--
-- Three states rather than two. Active is the one driving. Installed is present and one
-- press from driving. Not installed is a provider this config knows about and this machine
-- cannot reach, and it is shown rather than hidden because the difference between a backend
-- that was never written and one whose app is missing is worth being able to see. That row
-- is built disabled, so the stage never dispatches it and it reads as a label, which means
-- a person cannot switch to something that is not there.
local function providerRows()
  local out = {
    { title = "Back", subTitle = "", image = emojiImage(ICON.back),
      item = { nav = true, to = "back" } },
  }
  for _, entry in ipairs(providers) do
    local usable = entry.module.available()
    local mark, detail
    if entry.id == activeId then
      mark, detail = ICON.active, "Active"
    elseif usable then
      mark, detail = ICON.idle, "Installed"
    else
      local note = (entry.module.install or {}).note
      mark = ICON.warn
      detail = note and ("Not installed. " .. note) or "Not installed"
    end
    out[#out + 1] = {
      title = entry.module.name or entry.id,
      subTitle = detail,
      image = emojiImage(mark),
      enabled = usable,
      item = { provider = entry.id },
    }
  end
  return out
end

-- The page itself, a child presentation the stage pushes in place when the settings row is
-- chosen, so the list swaps without a second window and Backspace pops back to the
-- locations.
--
-- Choosing a provider answers "stay", so the page does not close and the highlight holds on
-- the row that was just pressed. A page of options a person flips is not somewhere they
-- should be ejected from, leaving is their own Backspace. Back is the one row that really is
-- a level change, so it pops and answers plain true.
--
-- The matcher is off because this is a short fixed menu rather than a list to search
-- through, and a filter here could rank the Back row away.
local function buildProviderChild()
  return {
    placeholder = "Which backend drives the VPN controls",
    matcher = false,
    rows = providerRows,
    -- Required on every presentation even though nothing reaches it, since both kinds of
    -- reachable row on this level are caught by intercept below and the disabled ones are
    -- never dispatched at all.
    onSelect = function() end,
    intercept = function(item)
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.provider then
        switchTo(item.provider)
        return "stay"
      end
      return false
    end,
  }
end

-- The single row shown when the active provider's CLI was not found. It names the missing
-- backend and what provides it, both read from the provider's install metadata, so the
-- panel explains the gap instead of opening empty and never names the concrete tool or the
-- platform.
--
-- This used to be the whole list and therefore a dead end. It is not one any more, because
-- the settings row is shown beside it, so a person who switches to a backend they have not
-- installed can always reach the page again and switch back. Making that reachable is the
-- reason this row is allowed to stay a label rather than having to grow an action.
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
  if not available then return { unavailableRow(), settingsRow() } end
  local out = {}
  if (query or "") == "" then out[#out + 1] = actionRow() end
  for _, loc in ipairs(cache) do
    out[#out + 1] = {
      title = loc.label,
      -- The provider's own description of the location when it offers one, since the two
      -- backends do not spell a place the same way and neither spelling is the general
      -- case. One names a country and a city code, the other a gateway host, so a caller
      -- assuming either shape would be reading one backend's vocabulary into every other.
      subTitle = loc.detail or (loc.countryCode .. " " .. loc.cityCode),
      image = flagImage(loc.countryCode),
      item = loc,
      filterText = loc.label .. " " .. loc.countryCode,
    }
  end
  out[#out + 1] = settingsRow()
  return out
end

--------------------------------------------------------------------------------
-- Selection dispatch (command policy)
--------------------------------------------------------------------------------

-- A row was chosen. Connect and Disconnect delegate to the engine, the provider row answers
-- a child presentation the stage pushes, and any other row is a city, so connect to it. Only
-- the provider row is a level change. The other three close the stage the whole way down to
-- whatever was below it, exactly as this tool's own standalone chooser used to close on any of
-- them before the migration.
--
-- Both connecting rows go through the one door and differ only in the target they hand it, the
-- action row passing the place it named and a city row passing itself. Choosing a city is also
-- what teaches this tool where a later bare connect should go, which is why the remember sits
-- beside the recency lift rather than inside the engine or a provider, both of which stay
-- ignorant of what was chosen last.
local function onSelect(sel)
  if not sel then return end
  -- The unavailable row is built disabled, so this never dispatches it and there is no
  -- branch for it here. Guarded anyway, since a row arriving without a live engine would
  -- otherwise reach an engine call.
  if sel.id == "unavailable" then return end
  -- Answering a table is what pushes a level, so this returns the page rather than opening
  -- anything itself.
  if sel.id == "providers" then return buildProviderChild() end
  if sel.id == "connect" then
    engine.connect(sel.target)
  elseif sel.id == "disconnect" then
    engine.disconnect()
  else
    -- A city was chosen, so lift it to the front of the recency order before connecting, so it
    -- leads the cities on the next open, and record it as where a bare connect goes from now on.
    cfg.recency.touch(sel.id)
    rememberTarget(sel)
    engine.connect({ countryCode = sel.countryCode, cityCode = sel.cityCode })
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
--- It names no backend and no availability any more, deliberately. This resolves once, when
--- the plugin registers, and the presentation contract wants a plain string rather than
--- something to call again later, so anything it said about which provider is driving or
--- whether that provider is installed would be frozen at the moment of registration and
--- would then quietly contradict the list the first time somebody switched. The rows say
--- both of those things and are rebuilt every time they are asked, which is where a claim
--- that can change belongs.
function M.placeholder()
  return "Search locations"
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
--- The provider page is deliberately not among these rows. A scope's own run door discards
--- whatever select answers, so the one row whose entire job is to answer a child
--- presentation would look live in the launcher and then do nothing at all when chosen. The
--- page stays reachable from this tool's own list, which is the surface that can actually
--- push a level.
function M.scopeRows(rest, redraw)
  if rest == "" or not M.ready() then
    M.prepare(redraw)
  end
  local out = rows(rest)
  for i = #out, 1, -1 do
    local item = out[i].item
    if item and item.id == "providers" then table.remove(out, i) end
  end
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
---
--- Each of the three legs races its own FETCH_TIMEOUT, the phase three verification rider.
--- Before this, nothing here answered a leg that never calls back, an hs.task that fails to
--- launch or a daemon that wedges mid answer, so fetching stayed true forever and every
--- request behind it queued into pending with nothing left to drain it, one stuck leg
--- silencing every future open of this tool. mullvad.lua's own async doors now check their
--- own start() return and answer the degraded value at once when a task never launches at
--- all, which closes the launch failure half of this on its own, but a task that DOES launch
--- and then never calls back, the daemon itself wedged, has no such signal, which is what the
--- timeout below is for. landedGate wraps each leg's own real answer and its own timeout in
--- one shared closure, so whichever of the two arrives first is the one that counts and the
--- other finds the gate already shut. A leg that times out never writes current, target, or
--- cache at all, which is the whole point, so this round degrades to whatever those already
--- held, the stale snapshot, rather than to a dead refresh nothing can ever finish.
function M.prepare(onReady)
  if not available then
    if onReady then onReady() end
    return
  end
  if onReady then pending[#pending + 1] = onReady end
  if fetching then return end
  fetching = true
  -- The backend this round belongs to. Every landing below is fenced against it, so a round
  -- whose provider has since been switched away from writes nothing and counts nothing.
  -- Both halves of that matter. Without the write fence one backend's locations land in
  -- another's cache, and without the count fence the old round's own countdown reaches zero
  -- and clears the fetching guard and flushes the pending list while the new round is still
  -- in flight, which would leave the new round unable to ever finish its own bookkeeping.
  local gen = generation
  local remaining = 3
  local function landed()
    if gen ~= generation then return end
    remaining = remaining - 1
    if remaining > 0 then return end
    fetching = false
    local waiting = pending
    pending = {}
    for _, cb in ipairs(waiting) do cb() end
  end
  -- One shared gate per leg, so its real answer and its own timeout can race without ever
  -- both counting. apply is called only by whichever wins, and only the real answer ever
  -- calls it, never the timeout, which is what leaves current, target, and cache untouched on
  -- a leg that gave up.
  --
  -- apply runs wrapped in pcall, adversarial review finding M5. Without it a raise inside
  -- apply, cfg.recency.order over a malformed relay row being the one the review named,
  -- reaches here having already set fired true and never calls landed(), which is word for
  -- word the failure this whole rider exists to close, fetching stuck true forever with
  -- pending only ever growing. landed() runs unconditionally on the line after, whether apply
  -- succeeded or not, so this leg always counts down. Calling landed() before apply instead,
  -- the rider's own other suggested close, does not hold here, since the last of the three
  -- legs to land is exactly the one whose own apply has not run yet at the moment its own
  -- landed() would fire, and that is also the moment landed() flushes pending, so a caller
  -- redrawing from that flush would read this leg's stale value for one redraw. pcall keeps
  -- apply before landed and only adds a floor under it.
  local function landedGate(apply)
    local fired = false
    local function onAnswer(...)
      if fired then return end
      fired = true
      -- A leg answering for a backend that is no longer the active one is dropped whole,
      -- neither applied nor counted, since landed() is fenced on the same generation.
      if gen ~= generation then return end
      local ok, err = pcall(apply, ...)
      if not ok then
        log.w(string.format("Vpn.prepare's own apply raised for one leg of a fetch round, %s, the round still completes with whatever this leg last held", tostring(err)))
      end
      landed()
    end
    local function onTimeout()
      if fired then return end
      fired = true
      landed()
    end
    return onAnswer, onTimeout
  end
  -- A timed out status leg leaves current exactly as it was, adversarial review finding L2,
  -- a deliberate choice named here rather than left to read as an oversight. The honest third
  -- answer, current = { state = "unavailable" } on timeout, exists and was not taken, because
  -- a daemon that answers everything except wedging mid connect would then have this file
  -- report Disconnected while the tunnel is actually up, trading a stale but plausible answer
  -- for a wrong and confident one. Stale beats hanging, which is the whole rider, and stale
  -- beats confidently wrong too.
  local onStatus, statusTimeout = landedGate(function(status) current = status end)
  local onTarget, targetTimeout = landedGate(function(loc) target = targetFrom(loc) end)
  local onList, listTimeout = landedGate(function(list)
    cache = cfg.recency.order(list or {}, function(loc) return loc.id end)
    -- The recency rung of the target can only answer once the list is here, since it recovers a
    -- place by matching a remembered id against this backend's own locations. The target leg
    -- races this one and may well land first, so a target still empty at this point is asked
    -- again now that there is something to match against. Guarded on being empty, so a real
    -- answer from either rung above is never overwritten by this one.
    if not target then target = recentTarget() end
  end)
  fetchTimers[1] = hs.timer.doAfter(FETCH_TIMEOUT, statusTimeout)
  fetchTimers[2] = hs.timer.doAfter(FETCH_TIMEOUT, targetTimeout)
  fetchTimers[3] = hs.timer.doAfter(FETCH_TIMEOUT, listTimeout)
  engine.statusAsync(onStatus)
  engine.selectedLocationAsync(onTarget)
  engine.listLocations(onList)
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
  target = targetFrom(engine.selectedLocation())
  if cfg.redrawPresented then cfg.redrawPresented("vpn") end
end

--------------------------------------------------------------------------------
-- Activation and switching
--------------------------------------------------------------------------------

-- Hand every provider the path the shared resolver found for it, by the name each provider
-- itself declares, so this file learns neither where a tool lives nor how it is obtained.
--
-- Every provider, not only the active one, and that distinction is load bearing. A provider
-- reports itself unavailable until it has been given a path, and both the provider page and
-- the initial choice ask each provider whether it can drive. Resolving only the active one
-- meant every other provider answered a confident false however installed it actually was,
-- so the page read Not installed for a working backend and the initial choice fell through
-- to the first entry in the roster rather than to the stored one. Resolving all of them once
-- here is what makes both of those questions answerable.
local function resolveAll()
  for _, entry in ipairs(providers) do
    local module = entry.module
    module.configure({ path = cfg.deps and cfg.deps.path(module.tool) or nil })
  end
end

-- Point everything at one backend. The paths are already resolved by the time this runs, so
-- this only decides which provider is driving and wires the engine to it. The engine is
-- wired only when that provider's tool is actually present, so an absent backend makes no
-- provider calls at all and cannot stall.
--
-- The engine is configured but not started here, and the caller decides whether to read
-- immediately. At load that read is wanted and costs nothing anyone is waiting on. On a
-- switch it would be a blocking CLI spawn on the keypress that flipped the row, and the
-- async round the switch already starts answers the same question without holding the page.
activate = function(entry)
  provider = entry.module
  activeId = entry.id
  available = provider.available()
  if available then
    engine.configure({ provider = provider, onChange = onChange })
  else
    local info = provider.install or {}
    local name = provider.name or entry.id
    local parts = { name .. " CLI not found, VPN controls disabled" }
    if info.note then parts[#parts + 1] = info.note end
    log.w(table.concat(parts, ". "))
  end
end

-- The backend to drive at load. The stored choice when it still names a provider that can
-- actually drive, otherwise the first one in the roster that can.
--
-- A fallback is deliberately not persisted. A stored choice whose app has since been
-- removed keeps standing, so reinstalling that app puts the tool back where the person left
-- it rather than silently making a temporary fallback permanent. When nothing at all is
-- available the first provider is still returned, so the list opens to that one's own
-- missing tool row with the provider page beside it rather than to nothing.
local function chooseInitial()
  local stored = hs.settings.get(PROVIDER_KEY)
  for _, entry in ipairs(providers) do
    if entry.id == stored and entry.module.available() then return entry end
  end
  for _, entry in ipairs(providers) do
    if entry.module.available() then return entry end
  end
  return providers[1]
end

-- Switch the active backend, from the provider page and nowhere else.
--
-- Everything the previous backend answered is dropped, the status snapshot, the selected
-- relay, and the whole location list, because none of it means anything under a different
-- daemon and showing one backend's cities under another one's name would be wrong rather
-- than merely stale. The generation bump is what makes dropping them safe while reads are
-- still in flight, and the fence itself is documented on prepare.
--
-- The waiting callbacks are dropped with the rest. Each one was asking to be told when the
-- previous backend's data landed, which is a question that no longer has an answer worth
-- giving, and the fresh round started here carries its own redraw, so nothing is left
-- waiting on a callback that will never come.
switchTo = function(id)
  if id == activeId then return end
  local entry
  for _, candidate in ipairs(providers) do
    if candidate.id == id then entry = candidate end
  end
  -- Both guards are unreachable through the page, which never builds a row for a provider
  -- it did not load and builds an unusable one disabled so the stage cannot dispatch it.
  -- Kept because this function is the seam a future caller would reach for.
  if not entry or not entry.module.available() then return end

  generation = generation + 1
  fetching = false
  pending = {}
  cache = {}
  current = { state = "unavailable" }
  target = nil

  activate(entry)
  hs.settings.set(PROVIDER_KEY, id)

  -- The redraw names the top level, so it lands once the person has left the page and does
  -- nothing while they are still on it. Nothing is lost either way, since popping back
  -- re-asks for the rows and by then this round has already written the cache.
  M.prepare(function()
    if cfg.redrawPresented then cfg.redrawPresented("vpn") end
  end)
end

--- M:configure(opts) - inject the shared theme, the ambient grant a surfaced plugin still
--- earns even though this file no longer reads chooser or theme from it, having no
--- Chooser.new call left to hand either to. Kept as the single wiring seam so the main root
--- stays the one place the atoms are handed in.
---
--- opts.deps is the per consumer dependency adapter, also from the root. Every activation
--- passes the path it holds to whichever provider is becoming active, by that provider's own
--- declared tool name, which is why nothing under this spoon probes for a CLI or names a
--- location.
---
--- opts.recency is an instance of the shared lift to front ordering service from
--- Olm.spoon, already built against this tool's own settings key. It is required, since
--- this copy no longer carries a recency block of its own, and a missing one is rejected
--- loudly rather than quietly ordering nothing.
---
--- One instance is shared across every backend rather than one per backend, which is safe
--- because the service partitions on whether a key is remembered and leaves everything else
--- in arrival order, and because no two backends spell a location the same way. One says
--- us/lax and the other says gb.wg.ivpn.net, so a key stored by one is simply never matched
--- while the other is ordering its own list. Sharing it also means the order somebody
--- already built up survives this change, which a per backend key would have discarded.
--- Nothing here may call the service's own prune, which would read one backend's ids as the
--- complete set and forget every other backend's.
---
--- opts.stagePresent, opts.redrawPresented, and opts.stagePop are root published words, all
--- optional, all no ops when absent. M.show, onChange, and the provider page's own Back row
--- say what each one degrades to without the other.
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
  -- Before chooseInitial, since choosing reads every provider's own availability and a
  -- provider that has not been handed its path yet cannot answer that honestly.
  resolveAll()
  activate(chooseInitial())
  -- The one read worth doing synchronously, since nothing is waiting on it at config load
  -- and it leaves the status line correct before the first open rather than on it.
  if available then engine.start() end
  return M
end

return M
