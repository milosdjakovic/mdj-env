--- === BrowserTabs.chooser ===
---
--- The surface. One native chooser driven as a menu stack, the same shape DisplayProfiles
--- uses, with three levels. The tab list, the settings list of browsers, and one browser's
--- own actions.
---
--- The tab list is the tool. Every open tab across every switched on browser, most recently
--- looked at first, each row carrying its browser's icon so which browser a tab belongs to
--- reads at a glance rather than from the text. Choosing one selects that tab in its window,
--- raises the window, and brings the browser to the front.
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
local chooser = nil     -- the one native Chooser instance
local stack = nil       -- the menu stack, stack[#stack] is the current frame
local reopen = false    -- set by a click selection so onClose re-shows instead of ending
local returnTap = nil   -- swallows Return while open so a menu step stays in place, no re-show
local tabs = nil        -- the last listing, so a reopen paints before the refresh lands
local listErrors = {}   -- per bundle id reasons a browser did not answer
local loading = false   -- whether a listing is in flight
local waiting = {}      -- callbacks due when that listing lands, so none of them is dropped
local permState = {}    -- per bundle id permission state, filled asynchronously

-- The pending re-show, held until it fires. A Hammerspoon timer is userdata whose finalizer
-- stops it, so one nothing refers to can be collected before it runs, and the menu would then
-- close on a click that was meant to step into it. Only one re-show is ever pending, because
-- the reopen flag above is cleared before this is armed.
local reopenTimer = nil

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

-- One tab. The title is the page, the subtitle names the browser, Arc's sidebar group when it
-- has one, and the host. The icon is the browser's, so the tab's origin reads visually. The
-- searchable text folds in the URL and the browser name, so typing part of an address or a
-- browser narrows the list even though neither is the title.
local function tabRow(t)
  local parts = { t.browser }
  local group = t.group and GROUP_LABEL[t.group]
  if group then parts[#parts + 1] = group end
  local host = hostOf(t.url)
  if host ~= "" then parts[#parts + 1] = host end
  local title = t.title
  if title == nil or title == "" then title = t.url or "Untitled" end
  return {
    title = title,
    subTitle = table.concat(parts, " · "),
    image = appIcon(t.bundleID),
    item = { kind = "tab", tab = t },
    filterText = title .. " " .. (t.url or "") .. " " .. (t.browser or ""),
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

-- The matching tabs alone, no guidance row and no settings door, so this is the part worth
-- reusing. The atom does not filter for this tool, so the query is scored here, which is what
-- lets the settings row stay pinned outside the ranking wherever it is added. On an empty query
-- the recency order stands.
local function matchedTabs(query)
  local list = tabs or {}
  if query == "" then
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = tabRow(t) end
    return out
  end

  local matcher = cfg.matcher
  local built = {}
  for i, t in ipairs(list) do built[#built + 1] = { r = tabRow(t), idx = i } end
  local out = {}
  if type(matcher) ~= "function" then
    -- No matcher injected, so fall back to a plain case insensitive substring test over the
    -- same text a matcher would have searched. The tool still filters, just without ranking.
    local q = query:lower()
    for _, b in ipairs(built) do
      if b.r.filterText:lower():find(q, 1, true) then out[#out + 1] = b.r end
    end
    return out
  end

  local ranked = {}
  for _, b in ipairs(built) do
    local score = matcher(query, b.r.filterText)
    if score ~= nil then
      ranked[#ranked + 1] = { r = b.r, score = score, idx = b.idx }
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)
  for _, e in ipairs(ranked) do out[#out + 1] = e.r end
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
  if perm == "notDetermined" then
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
  elseif perm == "denied" then
    out[#out + 1] = glyphRow("Open Automation settings", "macOS never asks twice, so this is changed by hand",
      ICON.locked, { act = "openSettings" }, true)
  elseif perm == "unknown" or perm == "noTarget" then
    -- Nothing here can fix this one, so it is stated rather than offered, and the console
    -- carries the detail.
    out[#out + 1] = glyphRow("Permission cannot be read",
      "The tab list still works, see the Hammerspoon console", ICON.warn, { noop = true }, false)
  end

  return out
end

--------------------------------------------------------------------------------
-- The one supplier, dispatched on the current frame
--------------------------------------------------------------------------------

local function rows(query)
  query = query or ""
  local top = stack[#stack]
  if top.kind == "settings" then return settingsRows() end
  if top.kind == "browser" then return browserRows(top.bundleID) end
  return tabRows(query)
end

local function placeholderFor(top)
  if top.kind == "settings" then return "Browsers" end
  if top.kind == "browser" then return "" end
  return "Search open tabs"
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
      if state == "unknown" or state == "noTarget" then
        log.w("could not read the automation permission for " .. name .. ", the probe said " .. tostring(state))
      elseif state == "denied" then
        log.w(name .. " has refused automation, macOS will not ask again, change it in System Settings")
      end
      M.refresh()
    end)
  end
end

--------------------------------------------------------------------------------
-- Selection dispatch
--------------------------------------------------------------------------------

local function frameFor(item)
  if item.to == "settings" then return { kind = "settings" } end
  if item.to == "browser" then return { kind = "browser", bundleID = item.bundleID } end
  return { kind = "tabs" }
end

-- Apply the chosen item and say where the chooser should go, "stay" to remain open at the
-- resulting frame or "close" to end. A disabled hint stays. A navigation row pushes or pops a
-- frame. Opening a tab is the one terminal action, everything in settings keeps the menu open
-- so several browsers can be set in a row.
local function applySelection(item)
  if not item or item.noop then return "stay" end

  if item.kind == "tab" then
    cfg.api.activate(item.tab)
    return "close"
  end

  if item.nav then
    if item.to == "back" then
      if #stack > 1 then table.remove(stack) end
    else
      stack[#stack + 1] = frameFor(item)
      if item.to == "settings" then refreshPermissions() end
    end
    return "stay"
  end

  if item.act == "toggle" then
    cfg.api.setEnabled(item.bundleID, not cfg.api.isEnabled(item.bundleID))
    -- Switching a browser on is only useful once its tabs appear, and switching one off should
    -- drop them, so the listing is redone straight away rather than on the next open.
    M.reload()
    return "stay"
  end

  if item.act == "request" then
    cfg.api.permissionRequest(item.bundleID, function(state)
      permState[item.bundleID] = state
      -- A grant makes tabs readable that were not a moment ago, so pick them up at once.
      if state == "granted" then
        M.reload()
      else
        log.w("the automation request for " .. tostring(item.bundleID) .. " ended as " .. tostring(state))
      end
      M.refresh()
    end)
    return "stay"
  end

  if item.act == "openSettings" then
    cfg.api.openPermissionSettings()
    return "close"
  end

  return "stay"
end

-- Redraw the current frame in place, no re-show, so a menu step is instant. The query is
-- cleared so a new level is not narrowed by a filter typed at the previous one, and the
-- highlight jumps back to the first row.
local function drawFrame()
  chooser:setQuery("")
  chooser:refresh(true)
  chooser:setPlaceholder(placeholderFor(stack[#stack]))
end

--------------------------------------------------------------------------------
-- Return interceptor, so a menu step never re-shows
--------------------------------------------------------------------------------

-- The native chooser closes on any Return, which would force a re-show to keep a menu open.
-- A passive tap swallows Return and the keypad enter while this chooser is up and routes them
-- through the in-place enter instead, so a drill in stays put and only opening a tab closes.
-- The same trick DisplayProfiles uses. Plain typing and the arrows pass straight through.
local RETURN_CODES = { [36] = true, [76] = true }
local function startReturnTap()
  if returnTap then returnTap:stop() end
  returnTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if not (chooser and chooser:isShowing()) then return false end
    if RETURN_CODES[e:getKeyCode()] then
      M.enter()
      return true
    end
    return false
  end)
  returnTap:start()
end
local function stopReturnTap()
  if returnTap then returnTap:stop(); returnTap = nil end
end

local function present()
  if not chooser then return end
  chooser:show()
  chooser:setPlaceholder(placeholderFor(stack[#stack]))
  startReturnTap()
end

local function onSelect(item)
  if applySelection(item) == "stay" then reopen = true end
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

--- M.prepare(onReady) - the one listing path, for a surface that shows these tabs and needs to
--- know when they have landed. A second ask while one is in flight joins that flight rather than
--- starting another, and every waiter is called, so two surfaces asking at once cost one read of
--- the browsers and neither is dropped. Our own chooser goes through this too, which is what
--- keeps there being one in flight guard rather than one per caller.
function M.prepare(onReady)
  if onReady then waiting[#waiting + 1] = onReady end
  if loading then return end
  loading = true
  cfg.api.listTabs(function(list, errors)
    tabs = list or {}
    listErrors = errors or {}
    loading = false
    M.refresh()
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

--- M.show() - open on the tab list and start a fresh listing.
function M.show()
  stack = { { kind = "tabs" } }
  M.reload()
  present()
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

--- M.refresh() - redraw in place, so an async listing or permission read updates the open
--- chooser without waiting for a keystroke. A no op when it is closed.
function M.refresh()
  if chooser and chooser:isShowing() then chooser:refresh() end
end

function M.hide()
  if chooser then chooser:hide() end
end

function M.selectNext()
  if chooser then chooser:selectNext() end
end

function M.selectPrev()
  if chooser then chooser:selectPrev() end
end

--- M.enter() - the in-place confirm, from the navigation shortcut and from the Return tap.
--- Applies the highlighted row and either redraws the new frame with no re-show, or closes
--- when the row was a tab to open.
function M.enter()
  if not (chooser and chooser:isShowing()) then return end
  if applySelection(chooser:selectedItem()) == "close" then
    chooser:hide()
  else
    drawFrame()
  end
end

--- M.insertSelected() - alias for enter, so the shared navigation action confirms in place.
function M.insertSelected()
  M.enter()
end

--- M.configure(opts) - merge injected deps across two callers. The spoon composition root
--- injects `api`, its merged view over the engine, the recency memory and the permission
--- probe. The main root injects `theme`, the Chooser factory as `chooser`, the `matcher` this
--- tool scores its tab rows with, and the docked shortcut panel callbacks.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- M.start() - build the one native chooser. Called by the main root once both configures have
--- run, so the factory and the api are both present.
function M.start()
  stack = { { kind = "tabs" } }
  chooser = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = "Search open tabs",
    fieldMode = "filter",
    -- Opt out of the shared matcher. This is a stack of frames, not one plain list. The atom
    -- filtering uniformly would rank away the Back row on the settings levels and would pull
    -- the pinned Settings row into the tab ranking. So the supplier owns the query and scores
    -- the tab rows itself with the injected matcher, which keeps the shared matching policy
    -- while leaving the pinned rows outside it.
    matcher = false,
    rows = rows,
    onSelect = onSelect,
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    -- Compose the root's panel teardown with the menu stack behaviour, the same shape
    -- DisplayProfiles uses. A click selection set reopen, so re-show at the new frame on the
    -- next tick once the native chooser has finished hiding. Any real dismissal resets the
    -- stack for the next open.
    onClose = function()
      stopReturnTap()
      if cfg.onClose then cfg.onClose() end
      if reopen then
        reopen = false
        reopenTimer = hs.timer.doAfter(0, present)
      else
        stack = { { kind = "tabs" } }
      end
    end,
  })
  return M
end

return M
