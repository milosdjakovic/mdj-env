--- === BrowserTabs.chooser ===
---
--- The surface. Three levels shown through the shared stage, the same shape DisplayProfiles
--- uses, contract v3. The tab list, the settings list of browsers, and one browser's
--- own actions.
---
--- Migrated onto host/stage, contract v3, docs/BRIEF-CONTRACT-V3.md. Settings and a
--- browser's own level are each built lazily and pushed as a child the moment a row drills
--- into one, rather than one instance driven as a hand kept stack of frames. Leaving a
--- level, every Back row, rides each level's own intercept, decision three's reserved case,
--- a row that mutates the list it is on and stands, reached through cfg.stagePop. A
--- browser's own toggle and permission request mutate that same level in place through
--- intercept too, standing exactly as they always did, while opening a tab and opening
--- Automation settings both answer through select with nothing, the ordinary meaning this
--- contract gives nil, the whole tool closing exactly as chooser:hide() always did. The
--- private Return swallowing eventtap, the hand kept frame stack, and the zero timer
--- re-show the click path used to need are all gone, since intercept is asked before
--- Return, insertSelected, and a click alike are ever let through to a real completion, the
--- one gate capable of keeping the window open through a swap at all.
---
--- The tab list is the tool. Every open tab across every switched on browser, the ones this tool
--- has opened leading in the order it opened them, each row carrying its browser's icon so which
--- browser a tab belongs to reads at a glance rather than from the text. Choosing one selects that
--- tab in its window, raises the window, and brings the browser to the front.
---
--- Settings is the last row, and the only row that is not a tab. It is pinned rather than
--- ordered, so it never drifts up into the recency order, and a typed filter targets the tabs
--- and never has to filter it out. That is the same reason Vpn pins its action row above the
--- cities. Being last does not make it reachable though, since a hundred tabs put it a hundred
--- keystrokes away, so typing a word that means settings brings it back, still last.
---
--- A browser's own level shows a row only when that row asks something of you. The switch is
--- always there, and beyond it a state that reads fine is hidden rather than confirmed, so the
--- one thing that does need attention is never buried under three that do not. What is hidden
--- goes to the Hammerspoon console instead, because a quiet screen has to mean nothing was
--- wrong and not that nothing was noticed. Glancing at state belongs one level up, where every
--- browser already carries its own in a subtitle.
---
--- This file is pure policy over an injected api, so it reaches the engine, the recency
--- memory and the permission probe without naming any of them. The spoon composition root
--- builds that api. It names no keys either, rows say what selecting them does and never which
--- key does it, since the keys are config data that the shared shortcut panel surfaces.

local M = { name = "BrowserTabs.chooser" }

local log = hs.logger.new("BrowserTabs", "info")

local cfg = {}          -- injected across two calls, api from the spoon, view deps from the root
local tabs = nil        -- the last listing, so a reopen paints before the refresh lands
local listSig = nil     -- what that listing is made of, so an answer saying the same is not redrawn
local listErrors = {}   -- per bundle id reasons a browser did not answer
local loading = false   -- whether a listing is in flight
local waiting = {}      -- callbacks due when that listing lands, so none of them is dropped
-- Migrated onto host/stage, this plugin owns no Chooser instance of its own any more, so
-- isShowing lives here instead as a plain flag, set in M.onPresent, which fires only when
-- the tab list, never a child level, becomes current, and cleared in M.onClose, which fires
-- once for the whole stack tearing down regardless of which level was current at the time.
-- Kept declared and read by plugins/browsertabs/test/agent.lua's own commands.showing, the
-- integration harness's one direct reach into this submodule's state, left untouched per
-- the standing instruction that its own directory is not this migration's to edit.
local showing = false
local permState = {}    -- per bundle id permission state, filled asynchronously

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji to a small image so a row can carry it as its icon, an offscreen canvas
-- drawn once and cached by the string, since the supplier runs on every keystroke. The same
-- helper the other choosers use.
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

-- A browser's own application icon, cached by bundle id. This is what makes a tab row read as
-- belonging to a browser without saying so in words, and it is why the icon slot on a tab row
-- is never an emoji.
local appIconCache = {}
local function appIcon(bundleID)
  local hit = appIconCache[bundleID]
  if hit ~= nil then return hit or nil end
  local img = hs.image.imageFromAppBundle(bundleID)
  appIconCache[bundleID] = img or false
  return img
end

local ICON = {
  settings = "⚙️",
  back = "⬅️",
  active = "🟢",
  off = "⚪",
  warn = "⚠️",
  locked = "🔒",
  ask = "🔓",
  reading = "⏳",
  none = "🚫",
}

--------------------------------------------------------------------------------
-- Row helpers and wording
--------------------------------------------------------------------------------

local function row(title, subTitle, image, item, enabled)
  return { title = title, subTitle = subTitle, image = image, item = item, enabled = enabled }
end

local function glyphRow(title, subTitle, icon, item, enabled)
  return row(title, subTitle, emojiImage(icon), item, enabled)
end

local function backRow()
  return glyphRow("Back", "", ICON.back, { nav = true, to = "back" }, true)
end

-- The host of a URL, for a tab subtitle, so a long address still says where the tab is. Falls
-- back to the whole string when it does not parse as one.
local function hostOf(url)
  local host = (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
  if not host then return url or "" end
  return (host:gsub("^www%.", ""))
end

-- Arc's own words for where a tab sits in its sidebar, made readable. Every other browser
-- reports no group, so this is only ever reached for Arc.
local GROUP_LABEL = { topApp = "top app", pinned = "pinned", unpinned = "open" }

-- What a permission state means, as plain wording for a subtitle.
local PERMISSION_TEXT = {
  granted = "allowed",
  notDetermined = "not asked yet",
  denied = "refused",
  notRunning = "cannot be checked while it is closed",
  noTarget = "not answering",
  unknown = "unknown",
}

--------------------------------------------------------------------------------
-- The tab list
--------------------------------------------------------------------------------

-- What a tab is called, the page's own title with the address standing in when it has none.
-- One definition, because the row shows it and the query is scored against it, and two copies
-- would let the list rank on something other than what it displays.
local function titleOf(t)
  local title = t.title
  if title == nil or title == "" then title = t.url or "Untitled" end
  return title
end

-- One tab. The title is the page, the subtitle names the browser, Arc's sidebar group when it
-- has one, and the host. The icon is the browser's, so the tab's origin reads visually.
--
-- There is deliberately no `filterText`. That field is how a row tells the Chooser atom what to
-- search, and the atom does not filter for this tool, it is stood down both here and in the
-- launcher scope, so a row carrying one would be stating a searchable text nothing reads. What
-- a query is actually scored against is decided in `matchedTabs` below, field by field.
local function tabRow(t)
  local parts = { t.browser }
  local group = t.group and GROUP_LABEL[t.group]
  if group then parts[#parts + 1] = group end
  local host = hostOf(t.url)
  if host ~= "" then parts[#parts + 1] = host end
  return {
    title = titleOf(t),
    subTitle = table.concat(parts, " · "),
    image = appIcon(t.bundleID),
    item = { kind = "tab", tab = t },
  }
end

-- The rows shown when there are no tabs to list, each explaining the reason rather than
-- leaving the list empty, the same self explaining shape Vpn's missing CLI row takes. The
-- reasons are checked most actionable first. A browser refused permission is the one worth
-- naming per browser, since the fix differs per browser and lives in its settings row.
--
-- `where` names where the settings door is, because two of these rows tell you to go there and
-- the door is only ever a row below when this list is our own chooser. Scoped into another
-- surface there is no row below, so the caller says what to point at instead.
local function emptyRows(where)
  where = where or "in settings below"
  local out = {}
  if loading then
    out[#out + 1] = glyphRow("Reading tabs", "Asking the browsers that are open", ICON.reading,
      { noop = true }, false)
    return out
  end

  local refused = {}
  for _, s in ipairs(cfg.api.status()) do
    if listErrors[s.bundleID] == cfg.api.notPermitted then
      refused[#refused + 1] = s.name
    end
  end
  if #refused > 0 then
    out[#out + 1] = glyphRow("Hammerspoon may not read " .. table.concat(refused, ", "),
      "Allow it " .. where, ICON.locked, { noop = true }, false)
    return out
  end

  local anyEnabled, anyRunning = false, false
  for _, s in ipairs(cfg.api.status()) do
    if s.enabled and s.installed then
      anyEnabled = true
      if s.running then anyRunning = true end
    end
  end
  if not anyEnabled then
    out[#out + 1] = glyphRow("No browser is switched on", "Switch one on " .. where,
      ICON.none, { noop = true }, false)
  elseif not anyRunning then
    out[#out + 1] = glyphRow("No browser is open", "Nothing to list until one is running",
      ICON.none, { noop = true }, false)
  else
    out[#out + 1] = glyphRow("No open tabs", "The browsers that are open reported none",
      ICON.none, { noop = true }, false)
  end
  return out
end

-- The words that reach the settings door by typing. It answers to what someone would be
-- looking for when they want it, the browsers and the permission, not only its own name.
local SETTINGS_WORDS = {
  "settings", "browsers", "browser", "permission", "permissions",
  "allow", "enable", "disable", "toggle",
}

-- The settings door. Always the last row, never inside the ranking. It is reachable two ways
-- because last is not the same as visible. On an empty query it trails the tabs, which is where
-- it was asked to be. But a list of a hundred tabs puts it a hundred keystrokes away, so a
-- query that matches it brings it back, still last, appended after whatever tabs matched rather
-- than scored among them.
local function settingsRow()
  local on, total = 0, 0
  for _, s in ipairs(cfg.api.status()) do
    total = total + 1
    if s.enabled then on = on + 1 end
  end
  return glyphRow("Settings", on .. " of " .. total .. " browsers switched on", ICON.settings,
    { nav = true, to = "settings" }, true)
end

-- Whether a typed query is reaching for the settings door. This is a prefix test against a
-- fixed keyword list and deliberately not the injected matcher. The matcher is the right policy
-- for tab rows, which are the user's own content, but a fuzzy match against a keyword list is
-- lenient enough to surface this row on queries that never meant it, and a row that appears
-- unbidden below a tab list is noise. Two letters minimum, since one letter means nothing yet.
local function wantsSettings(query)
  if #query < 2 then return false end
  local q = query:lower()
  for _, word in ipairs(SETTINGS_WORDS) do
    if word:sub(1, #q) == q then return true end
  end
  return false
end

-- Whether a query is naming a browser rather than a page. A plain prefix test, deliberately not
-- the injected matcher, for the same reason the settings door uses one. A fuzzy test against a
-- short fixed name is lenient enough to fire on queries that never meant it, and here that would
-- pull a whole browser's worth of tabs into a list about something else. Two letters minimum,
-- since one letter names nothing yet.
local function namesBrowser(query, browser)
  if #query < 2 or browser == nil then return false end
  local q = query:lower()
  return browser:lower():sub(1, #q) == q
end

-- The three things a query is scored against, each on its own. Scoring them separately and
-- keeping the best is the whole point, because gluing them into one string lets a subsequence
-- matcher satisfy a query by taking a letter from the page title, a letter from the address and
-- a letter from whatever follows, which is a match no reader would call one. The host is scored
-- apart from the full address even though it sits inside it, since against the host alone a
-- query lands at the very start of a short string and earns what it is due, while against a
-- long address the same letters are buried and read as a weaker match.
--
-- The browser name is a fourth field, but only once the query is really naming it, which is
-- what `namesBrowser` gates. Scoring it unconditionally is what the old single string did and it
-- is the bug, since a subsequence matcher charges almost nothing for a gap at the end of a
-- string, so `far` reads as a contiguous run inside `Safari` and quietly lifted every Safari tab
-- in the list. Once the gate has passed, the name is scored by the same matcher as every other
-- field rather than given a made up weight, so typing a browser's name gathers its tabs and a
-- page that genuinely matches that word can still outrank them.
local function searchFields(t, query)
  local fields = { titleOf(t), hostOf(t.url), t.url or "" }
  if namesBrowser(query, t.browser) then fields[#fields + 1] = t.browser end
  return fields
end

local function bestFieldScore(matcher, query, t)
  local best = nil
  for _, field in ipairs(searchFields(t, query)) do
    if field ~= "" then
      local score = matcher(query, field)
      if score ~= nil and (best == nil or score > best) then best = score end
    end
  end
  return best
end

-- What recency is worth once something has been typed. It reorders and never overturns, the
-- same rule FileSearch's frecency follows, and the weight is set against the matcher's own
-- scale. A single better placed character is worth six points or more there, so no bonus here
-- can lift a tab above one that genuinely matched better, while two tabs matching the same
-- shape at different depths in their text differ by fractions of a point, which is exactly what
-- this settles. Beyond the span it is worth nothing, so the long tail is ranked on the query
-- alone.
--
-- The position counted is among the tabs in this listing, not the place in the remembered order,
-- and the difference is not a detail. The remembered order holds every address this tool has ever
-- opened, including each step of a redirect chain and everything since closed, so its most recent
-- stored keys are mostly tabs that are gone. Counting stored ranks made the bonus inert almost
-- every time it was asked for. Counted among the tabs on offer it means what it says, the tenth
-- most recently opened tab you still have open.
--
-- A tab this tool has never opened earns nothing and takes no position, rather than being treated
-- as infinitely old. That is the same honesty the resting order keeps, recency is only ever
-- claimed for what this tool actually did.
local RECENCY_WEIGHT = 3
local RECENCY_SPAN = 10
local function recencyBonus(position)
  if position == nil or position > RECENCY_SPAN then return 0 end
  return RECENCY_WEIGHT * (RECENCY_SPAN - position + 1) / RECENCY_SPAN
end

-- The matching tabs alone, no guidance row and no settings door, so this is the part worth
-- reusing. The atom does not filter for this tool, so the query is scored here, which is what
-- lets the settings row stay pinned outside the ranking wherever it is added. On an empty query
-- the recency order stands, already applied to the listing before it arrived.
--
local function matchedTabs(query)
  local list = tabs or {}
  if query == "" then
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = tabRow(t) end
    return out
  end

  local matcher = cfg.matcher
  local out = {}
  if type(matcher) ~= "function" then
    -- No matcher injected, so fall back to a plain case insensitive substring test over the
    -- same fields a matcher would have scored. The tool still filters, just without ranking.
    local q = query:lower()
    for _, t in ipairs(list) do
      for _, field in ipairs(searchFields(t, query)) do
        if field:lower():find(q, 1, true) then
          out[#out + 1] = tabRow(t)
          break
        end
      end
    end
    return out
  end

  -- The listing arrives with every observed tab ahead of every unobserved one and in recency
  -- order, so walking it and counting only the observed gives each of them its place among the
  -- tabs on offer. That is what the bonus is scaled against, and it is why the count is taken
  -- over the whole list rather than over the tabs that matched, since a tab's recency is a fact
  -- about the tab and must not change with what was typed.
  local ranked = {}
  local position = 0
  for i, t in ipairs(list) do
    local observed = cfg.api.recencyRank(t) ~= nil
    if observed then position = position + 1 end
    local score = bestFieldScore(matcher, query, t)
    if score ~= nil then
      ranked[#ranked + 1] = {
        tab = t,
        score = score + recencyBonus(observed and position or nil),
        idx = i,
      }
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)
  for _, e in ipairs(ranked) do out[#out + 1] = tabRow(e.tab) end
  return out
end

-- The tab list as our own chooser shows it, the matching tabs plus the settings door. The door
-- trails an empty query, where it was asked to be, and comes back on a query that reaches for
-- it, still last.
local function tabRows(query)
  if #(tabs or {}) == 0 then
    local out = emptyRows()
    out[#out + 1] = settingsRow()
    return out
  end
  local out = matchedTabs(query)
  if query == "" or wantsSettings(query) then out[#out + 1] = settingsRow() end
  return out
end

--------------------------------------------------------------------------------
-- The settings list
--------------------------------------------------------------------------------

-- One line describing everything true of a browser right now, so the list answers installed,
-- open, and allowed without drilling in. A browser that is switched off says only that, since
-- nothing else about it matters until it is switched on.
local function statusText(s)
  if not s.installed then return "not installed" end
  if not s.enabled then return "switched off" end
  local parts = { s.running and "open" or "closed" }
  local perm = permState[s.bundleID]
  if perm then parts[#parts + 1] = PERMISSION_TEXT[perm] or perm end
  return table.concat(parts, ", ")
end

-- The marker. A switched on browser carries the green circle every chooser here uses for the
-- live choice, and a switched off one a hollow circle, so the column reads as a set of
-- toggles. An uninstalled browser is warned rather than marked, since it cannot be switched on.
local function settingsIcon(s)
  if not s.installed then return emojiImage(ICON.warn) end
  return emojiImage(s.enabled and ICON.active or ICON.off)
end

local function settingsRows()
  local out = { backRow() }
  for _, s in ipairs(cfg.api.status()) do
    out[#out + 1] = row(s.name, statusText(s), settingsIcon(s),
      { nav = true, to = "browser", bundleID = s.bundleID }, s.installed)
  end
  return out
end

--------------------------------------------------------------------------------
-- One browser's actions
--------------------------------------------------------------------------------

local function statusFor(bundleID)
  for _, s in ipairs(cfg.api.status()) do
    if s.bundleID == bundleID then return s end
  end
  return nil
end

-- A browser's own screen. Back leads, per the chooser menu convention, so stepping out is the
-- default. The switch comes next and is always there, since it is what this level is for.
--
-- Everything after those two appears only when it asks something of you. A browser that is
-- installed, allowed, and switched on therefore shows exactly two rows, because a column of
-- facts that all read fine is a column nobody needs, and it buries the one row that might not.
-- Nothing is lost by hiding them, since the state of every browser is already in its subtitle
-- one level up, which is where glancing belongs.
--
-- The permission rows are gated on the browser being switched on. A switched off browser is
-- never scripted, so whether macOS would allow it is not a question yet, and offering to raise
-- a system prompt for a browser deliberately turned off would be asking for the wrong thing.
local function browserRows(bundleID)
  local s = statusFor(bundleID)
  if not s then
    return { backRow(), glyphRow("This browser is gone", "It may have been removed", ICON.warn,
      { noop = true }, false) }
  end

  local out = { backRow() }

  -- Not installed is the one obstacle the switch cannot answer, so it takes the switch's place
  -- rather than sitting under a control that would do nothing.
  if not s.installed then
    out[#out + 1] = glyphRow("Not installed", "There is nothing here to read tabs from",
      ICON.warn, { noop = true }, false)
    return out
  end

  out[#out + 1] = glyphRow(s.enabled and ("Switch " .. s.name .. " off") or ("Switch " .. s.name .. " on"),
    s.enabled and "Stop reading its tabs, and stop scripting it at all"
      or "Read its tabs along with the others",
    s.enabled and ICON.off or ICON.active,
    { act = "toggle", bundleID = bundleID }, true)

  if not s.enabled then return out end

  local perm = permState[bundleID]
  if perm == cfg.api.states.notDetermined then
    if s.running then
      out[#out + 1] = glyphRow("Ask for permission",
        "macOS will ask whether Hammerspoon may read " .. s.name,
        ICON.ask, { act = "request", bundleID = bundleID }, true)
    else
      -- Asking is impossible while it is closed, so the obstacle is named instead of a control
      -- that could only sit there greyed out.
      out[#out + 1] = glyphRow("Open " .. s.name .. " first",
        "Permission can only be asked while it runs", ICON.warn, { noop = true }, false)
    end
  elseif perm == cfg.api.states.denied then
    out[#out + 1] = glyphRow("Open Automation settings", "macOS never asks twice, so this is changed by hand",
      ICON.locked, { act = "openSettings" }, true)
  elseif perm == cfg.api.states.unknown or perm == cfg.api.states.noTarget then
    -- Nothing here can fix this one, so it is stated rather than offered, and the console
    -- carries the detail.
    out[#out + 1] = glyphRow("Permission cannot be read",
      "The tab list still works, see the Hammerspoon console", ICON.warn, { noop = true }, false)
  end

  return out
end

--------------------------------------------------------------------------------
-- Permission reads
--------------------------------------------------------------------------------

-- Read every browser's permission and redraw as each lands. Never prompts. Run when the
-- settings level is entered rather than on every tab list open, so the common path costs
-- nothing, and re-run after a request so the new state shows at once.
--
-- A state the surface cannot act on goes to the console. Since the rows now hide anything that
-- reads fine, a quiet screen has to mean nothing was wrong rather than nothing was noticed, and
-- the console is where the detail behind a hidden row belongs.
local function refreshPermissions()
  for _, s in ipairs(cfg.api.status()) do
    local bundleID, name = s.bundleID, s.name
    cfg.api.permissionStatus(bundleID, function(state)
      permState[bundleID] = state
      if state == cfg.api.states.unknown or state == cfg.api.states.noTarget then
        log.w("could not read the automation permission for " .. name .. ", the probe said " .. tostring(state))
      elseif state == cfg.api.states.denied then
        log.w(name .. " has refused automation, macOS will not ask again, change it in System Settings")
      end
      M.refresh()
    end)
  end
end

--------------------------------------------------------------------------------
-- Child levels, built lazily and pushed the moment a row drills into one
--------------------------------------------------------------------------------

-- Every child below shares the shape displayprofiles' own children settled, contract v3.
-- rows reads whatever this level names, matcher stands the shared strategy down for the
-- identical reason the retired single instance always did, and intercept is where a level
-- that mutates the list it is on, or leaves it for its parent, answers for itself. Drilling
-- into a genuine deeper level, settings to one browser, answers through onSelect instead,
-- the ordinary child push decision one describes.

-- A browser's own level, a child of settings. bundleID names the browser, frozen at
-- creation rather than a shared upvalue, since nothing here ever needs to correct which
-- browser this level is about the way displayprofiles' own rename corrects a shared name.
local function buildBrowserChild(bundleID)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return browserRows(bundleID) end,
    -- Opening Automation settings is a genuine completion, not a level, so it answers
    -- through select, calling the api and returning nothing, the ordinary meaning this
    -- contract has always given nil, the whole stack tears down, closing the tool for good
    -- exactly as the retired chooser:hide() always did for this one row.
    onSelect = function(item)
      if item and item.act == "openSettings" then
        cfg.api.openPermissionSettings()
      end
      return nil
    end,
    -- Back leaves. The switch and the permission request both mutate this same level in
    -- place and stand, decision three's reserved case, exactly as they always did, reading
    -- fine again on the very next line the moment the async answer they started lands.
    intercept = function(item)
      if not item or item.noop then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "toggle" then
        cfg.api.setEnabled(bundleID, not cfg.api.isEnabled(bundleID))
        -- Switching a browser on is only useful once its tabs appear, and switching one
        -- off should drop them, so the listing is redone straight away rather than on the
        -- next open. Reloads the tab list in the background regardless of which level is
        -- current, the identical unconditional call the retired applySelection made.
        M.reload()
        return true
      end
      if item.act == "request" then
        cfg.api.permissionRequest(bundleID, function(state)
          permState[bundleID] = state
          -- A grant makes tabs readable that were not a moment ago, so pick them up at once.
          if state == cfg.api.states.granted then
            M.reload()
          else
            log.w("the automation request for " .. tostring(bundleID) .. " ended as " .. tostring(state))
          end
          if cfg.redrawPresented then cfg.redrawPresented("browserTabs") end
        end)
        return true
      end
      return false
    end,
  }
end

-- The settings level, a child of the tab list. onPresent starts the permission reads the
-- moment this level becomes current, through either door, present or push, the identical
-- warmth VPN's own async fetch already gets, replacing the retired applySelection's own
-- special case for entering this one frame.
local function buildSettingsChild()
  return {
    placeholder = "Browsers",
    matcher = false,
    rows = settingsRows,
    onPresent = refreshPermissions,
    -- A browser row is a genuine deeper level, so it answers through select, host/stage
    -- pushing whatever comes back.
    onSelect = function(item)
      if item and item.nav and item.to == "browser" then
        return buildBrowserChild(item.bundleID)
      end
      return nil
    end,
    -- Back is the one row on this level that leaves rather than drills, decision three's
    -- reserved case, so it alone answers through intercept, cfg.stagePop leaving the level
    -- the row was pressed on and the parent, the tab list, standing in its place.
    intercept = function(item)
      if not item or item.noop then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.reload() - fetch the tabs again and redraw when they land. The previous listing stays on
--- screen meanwhile, so a reopen paints instantly and only updates once the fresh answer
--- arrives, the same shape Vpn's relay list takes.
function M.reload()
  M.prepare(nil)
end

-- Everything about a listing that a row is drawn from, as one string. Identity, what the row is
-- titled, and Arc's sidebar group, which is the one part of a subtitle not derived from the first
-- two. Order is in it too, since the rows are ordered by it, so this changes whenever what a
-- reader would see changes and not otherwise.
local function signatureOf(list)
  local parts = {}
  for _, t in ipairs(list or {}) do
    parts[#parts + 1] = table.concat({
      t.bundleID or "", t.url or "", t.title or "", t.group or "",
    }, "\0")
  end
  return table.concat(parts, "\1")
end

-- The listing and what it is made of move together, so the comparison below can never be made
-- against a signature belonging to some earlier list.
local function setTabs(list)
  tabs = list or {}
  listSig = signatureOf(tabs)
end

--- M.prepare(onReady) - the one listing path, for a surface that shows these tabs and needs to
--- know when they have landed. A second ask while one is in flight joins that flight rather than
--- starting another, and every waiter is called, so two surfaces asking at once cost one read of
--- the browsers and neither is dropped. Our own chooser goes through this too, which is what
--- keeps there being one in flight guard rather than one per caller.
---
--- What is already held is repainted at once and corrected when the answer lands, which is the
--- right trade and used to read as the list rearranging itself under you. The full read is 0.368
--- seconds on this machine, measured, and the cached order it paints over is stale by at least
--- one move every time, since opening a tab is what closed this list last and that is exactly
--- what changes the order. So the order is applied again before anything paints, and the answer
--- that lands a third of a second later then has nothing left to say unless a tab was genuinely
--- opened or closed in the browser meanwhile.
function M.prepare(onReady)
  if onReady then waiting[#waiting + 1] = onReady end
  if loading then return end
  if tabs then setTabs(cfg.api.order(tabs)) end
  loading = true
  cfg.api.listTabs(function(list, errors)
    local before = listSig
    setTabs(list)
    listErrors = errors or {}
    loading = false
    -- A redraw that changes nothing is not free, it rebuilds every row under a highlight that
    -- keeps only its number, so the row a reader was on becomes a different row. Skipped when the
    -- answer matches what is drawn. An empty list is always redrawn, since what is on screen then
    -- is the reading row and that has to come down whatever the answer was.
    if #tabs == 0 or listSig ~= before then M.refresh() end
    local due = waiting
    waiting = {}
    for _, cb in ipairs(due) do cb() end
  end)
end

--- M.ready() - whether a listing has landed, so a caller can tell an empty list from an
--- unread one and say which it is.
function M.ready()
  return tabs ~= nil
end

--- M.tabRows(query) - the matching tabs alone, for a surface other than our own chooser. No
--- settings door and no guidance row, since both are ours: the door is a step into a second
--- level only this chooser can show, and what to say about an empty list is the caller's to
--- decide. Nothing here is remembered, so this is safe to call on every keystroke.
function M.tabRows(query)
  return matchedTabs(query or "")
end

--- M.explain(where) - why the list is empty, as rows, with `where` naming where the browser
--- switches are since this list has no settings row of its own to point at.
function M.explain(where)
  return emptyRows(where)
end

--- M.activate(item) - open the tab a row from M.tabRows carries. A row of any other kind is
--- ignored, so a caller may hand back whatever it was given.
function M.activate(item)
  if item and item.kind == "tab" then cfg.api.activate(item.tab) end
end

--- M.scopeRows(rest, redraw) - the query scope's own rows, fetched on entry or while nothing
--- has landed, the same trigger M.show already uses, but redrawing through the caller's own
--- hook instead of this chooser's own M.refresh, since a scope has no chooser of its own to
--- redraw. redraw arrives from whoever is holding these rows for the scope, so this file still
--- never learns what that is. What to say about an empty list still comes from M.explain,
--- naming this tool's own settings rather than a settings row a scope cannot show.
function M.scopeRows(rest, redraw)
  if rest == "" or not M.ready() then
    M.prepare(redraw)
  end
  local out = M.tabRows(rest)
  if #out == 0 and (rest == "" or not M.ready()) then
    return M.explain("in Browser tabs settings")
  end
  return out
end

--- M.show() - present through the shared stage. cfg.stagePresent asks the registry for
--- this plugin's own presentation, the tab list below, and hands it to Stage:present,
--- always a fresh stack, so a reopen from the launcher or this plugin's own launcher row
--- never resumes a previous drill. The fresh listing used to be started here inline; it now
--- runs from M.onPresent below, so it is asked for through either door, present or push,
--- not only this one.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("browserTabs") end
end

--- M.rows(query) -> list. The tab list's own row supplier, named on the manifest's own
--- presentation block as the contract's rows.
M.rows = tabRows

--- M.intercept(item) -> bool. Named on the manifest's own presentation block. The tab list's
--- own guidance rows, emptyRows above, answer disabled and carry item.noop, the identical
--- shape every child level already guards against in its own intercept, and this is the
--- guard for this level, since a stray selection reaching one, a click the atom's own
--- enabled gate did not catch among them, must stand exactly as the retired
--- applySelection's own "if not item or item.noop then return stay" already promised rather
--- than falling to select below and answering nil, which would close the whole tool over a
--- row that was never meant to do anything.
function M.intercept(item)
  if item and item.noop then return true end
  return false
end

--- M.select(item) -> presentation or nil. The tab list's own onSelect, named on the
--- manifest's own presentation block. Opening a tab is a genuine completion, answering
--- nothing, the ordinary meaning this contract gives nil, the whole tool closing exactly as
--- chooser:hide() always did. The Settings row drills into a child of its own, host/stage
--- pushing whatever is answered.
function M.select(item)
  if not item then return nil end
  if item.kind == "tab" then
    cfg.api.activate(item.tab)
    return nil
  end
  if item.nav and item.to == "settings" then
    return buildSettingsChild()
  end
  return nil
end

--- M.placeholder() -> string. The field hint while the tab list is current, named on the
--- manifest's own presentation block. Resolved once, at register, since the presentation
--- contract wants a plain string a presentation carries rather than a function to call
--- again later. Every child below carries its own instead, a plain field on a table built
--- at runtime rather than something the registrar ever resolves.
function M.placeholder()
  return "Search open tabs"
end

--- M.onPresent() - the presentation contract's own onPresent, named on the manifest's own
--- presentation block, called by the stage whenever the tab list, never a child level,
--- becomes current, through present or push alike. Carries the fresh listing M.show used to
--- start inline before this plugin had a presentation to defer through instead, run on both
--- doors now rather than only the hotkey one, and marks showing for M.isShowing below.
function M.onPresent()
  showing = true
  M.reload()
end

--- M.onClose() - the presentation contract's own onClose, named on the manifest's own
--- presentation block, told once whenever the stage hides the whole stack this tool's own
--- levels sit on, never on a swap between them. Clears showing for M.isShowing below.
function M.onClose()
  showing = false
end

--- M.isShowing() - whether this tool's own tab list is current, plainly true from the first
--- M.onPresent until the next M.onClose, unaffected by drilling into or backing out of
--- settings or a browser's own level in between. Not part of the presentation contract and
--- not routed through by host/stage's own surfaceFor, which answers the identical question
--- for the nav registry by asking the stage directly, kept only for
--- plugins/browsertabs/test/agent.lua's own commands.showing, the integration harness's one
--- direct reach into this submodule's state, left untouched per the standing instruction
--- that its own directory is not this migration's to edit.
function M.isShowing()
  return showing
end

--- M.refresh() - redraw whichever level is current in place, so an async listing or
--- permission read updates the open picker without waiting for a keystroke. Migrated onto
--- host/stage, cfg.redrawPresented replacing the direct chooser:refresh() this used to call
--- on an instance it held itself, already a no op unless this presentation, and no other,
--- is what the stage is actually showing, and already redrawing whichever child is current
--- rather than only the tab list, the identical reach the retired chooser:refresh() always
--- had over whatever frame was on top.
function M.refresh()
  if cfg.redrawPresented then cfg.redrawPresented("browserTabs") end
end

-- hide, selectNext, selectPrev, enter, and insertSelected are gone, the trickle
-- migration, deleted along with the Chooser.new block, the private Return swallowing
-- eventtap, the hand kept frame stack, and the zero timer re-show that gave them something
-- to answer for. The composition root now routes this plugin's own navigation through
-- host/stage's own surfaceFor once wiredRegistry.presentationFor("browserTabs") answers a
-- presentation, which answers insertSelected directly, reaching the atom's own real
-- completion path, intercept asked first exactly as every other row on every level already
-- is.

--- M:configure(opts) - merge injected deps across two callers. The spoon composition root
--- injects `api`, its merged view over the engine, the recency memory and the permission
--- probe. The main root injects the `matcher` this tool scores its tab rows with,
--- stagePresent, stagePop, and redrawPresented, the root published words this migration
--- needs. Builds no chooser any more, the trickle migration, so theme and the Chooser
--- factory are no longer read here.
--
-- Colon here, not dot, because every caller, the plugin root's own configure, the live top
-- level init.lua, and the shared wiring pipeline in lib/wire.lua, reaches this submodule as
-- chooser:configure(opts). self arrives as M and the body below never names it.
function M:configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- M:start() - nothing left to build. Builds no chooser any more, the trickle migration.
--- Whatever this plugin used to hand a Chooser.new call, theme, a field mode, the matcher,
--- rows, onSelect, and the panel triple, is now either read straight off this module by the
--- registrar, rows and select through the manifest's own presentation block, or owned by
--- the stage as fixed, atom level policy. Kept as a callable no op rather than deleted,
--- since manifest.lua's own wiring still names it and a step this file no longer needs is
--- cheaper to leave inert than to go edit the manifest over.
function M:start()
  return M
end

return M
