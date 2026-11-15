--- === BrowserTabs.chooser ===
---
--- The surface, one level shown through the shared stage. The tab list is the tool. Every open
--- tab across every switched on browser, the ones this tool has opened leading in the order it
--- opened them, each row carrying its browser's icon so which browser a tab belongs to reads at
--- a glance rather than from the text. Choosing one selects that tab in its window, raises the
--- window, and brings the browser to the front.
---
--- Which browsers are read is the Browsers action in the actions pane, one switch per browser,
--- stated by Milos on 2026-11-16, replacing the settings row and the page it led to. A browser
--- that needs its permission asked, or changed by hand, gets one row leading the tab list, and
--- only then. A state that reads fine is hidden rather than confirmed, and what is hidden goes to
--- the Hammerspoon console instead, because a quiet screen has to mean nothing was wrong and not
--- that nothing was noticed.
---
--- This file is pure policy over an injected api, so it reaches the engine, the recency
--- memory and the permission probe without naming any of them. The spoon composition root
--- builds that api. It names no keys either, rows say what selecting them does and never which
--- key does it, since the keys are config data that the bottom bar surfaces.

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

--------------------------------------------------------------------------------
-- Row helpers and wording
--------------------------------------------------------------------------------

local function row(title, subTitle, image, item, enabled)
  return { title = title, subTitle = subTitle, image = image, item = item, enabled = enabled }
end

-- A row whose icon is one of the manifest's declared keys, drawn by Olm. The tab rows keep row
-- above because their image is the browser's own application icon, a real picture.
local function glyphRow(title, subTitle, icon, item, enabled)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled }
end

-- The host of a URL, for a tab subtitle, so a long address still says where the tab is. Falls
-- back to the whole string when it does not parse as one.
local function hostOf(url)
  local host = (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
  if not host then return url or "" end
  return (host:gsub("^www%.", ""))
end

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

-- One tab. The title is the page, the subtitle names the browser and the host. The icon is the
-- browser's, so the tab's origin reads visually, the picture for the Lua list and the browser's
-- bundle id for Olm.app's, which draws an application's icon from the system by its id.
--
-- What a query is matched against is declared here and applied by the shared search, which
-- phase three of docs/PLAN-UNIFIED-SEARCH.md moved this list onto. The subtitle is a status
-- like line, browser and host joined, so filterText is the title and the subtitle is not
-- searched. The host and the
-- full address are names, matched at the title's own levels, so a tab on github.com answers to
-- git whatever its page is called and github pull finds a page titled Pull request on it. The
-- browser name is a keyword, matched only at the start of one of its words and below every
-- name, so far never finds Safari, safari gathers its tabs, and a page genuinely named after a
-- browser still outranks them.
--
-- bonus is recency, worth something only between tabs the search calls equally good. Its
-- position is counted among the tabs in this listing, see tabRows below.
local function tabRow(t, bonus)
  local parts = { t.browser }
  local host = hostOf(t.url)
  if host ~= "" then parts[#parts + 1] = host end
  local title = titleOf(t)
  local names = {}
  if host ~= "" then names[#names + 1] = host end
  if t.url and t.url ~= "" and t.url ~= host then names[#names + 1] = t.url end
  return {
    title = title,
    subTitle = table.concat(parts, " · "),
    filterText = title,
    names = names,
    keywords = t.browser,
    bonus = bonus,
    image = appIcon(t.bundleID),
    icon = { app = t.bundleID },
    item = { kind = "tab", tab = t },
  }
end

-- The rows shown when there are no tabs to list, each explaining the reason rather than
-- leaving the list empty, the same self explaining shape Vpn's missing CLI row takes. The
-- reasons are checked most actionable first. A browser refused permission is the one worth
-- naming per browser, since the fix differs per browser.
--
-- `where` names where the Browsers action is, because the switch is in this tool's own actions
-- pane, and a scope in the launcher shows the launcher's, so the caller says what to point at.
--
-- Every one is pinned, since each says why there is nothing to search and must stay whatever is
-- typed, which is what it did while this list ranked its own query.
local function pinnedAll(list)
  for _, r in ipairs(list) do r.pinned = true end
  return list
end

local function emptyRows(where)
  where = where or "with Browsers in Actions"
  local out = {}
  if loading then
    out[#out + 1] = glyphRow("Reading tabs", "Asking the browsers that are open", "reading",
      { noop = true }, false)
    return pinnedAll(out)
  end

  local refused = {}
  for _, s in ipairs(cfg.api.status()) do
    if listErrors[s.bundleID] == cfg.api.notPermitted then
      refused[#refused + 1] = s.name
    end
  end
  if #refused > 0 then
    out[#out + 1] = glyphRow("Hammerspoon may not read " .. table.concat(refused, ", "),
      "macOS is holding its tabs back", "permission", { noop = true }, false)
    return pinnedAll(out)
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
      "none", { noop = true }, false)
  elseif not anyRunning then
    out[#out + 1] = glyphRow("No browser is open", "Nothing to list until one is running",
      "none", { noop = true }, false)
  else
    out[#out + 1] = glyphRow("No open tabs", "The browsers that are open reported none",
      "none", { noop = true }, false)
  end
  return pinnedAll(out)
end

-- Every tab, in the listing's own order, which is the resting order, for the shared search to
-- filter and rank. Nothing here reads the query, so a scope and this chooser hand the engine
-- the same rows.
--
-- The listing arrives with every tab this tool has opened ahead of every other one, in recency
-- order, so walking it and counting only those gives each its place among the tabs on offer,
-- and the bonus is that place scaled into zero to one, the most recent highest at one and the
-- least recent at one over their count. A tab this tool never opened earns nothing. The count is
-- taken over the whole listing and not over the tabs that match, since a tab's recency is a fact
-- about the tab and must not change with what was typed, and it is never counted in the
-- remembered order, whose newest keys are mostly tabs since closed.
local function allTabRows()
  local list = tabs or {}
  local observed = {}
  local count = 0
  for i, t in ipairs(list) do
    if cfg.api.recencyRank(t) ~= nil then
      count = count + 1
      observed[i] = count
    end
  end
  local out = {}
  for i, t in ipairs(list) do
    local position = observed[i]
    out[i] = tabRow(t, position and (count - position + 1) / count or nil)
  end
  return out
end

--------------------------------------------------------------------------------
-- Each browser's state, for the Browsers action and the permission rows
--------------------------------------------------------------------------------

-- One line describing everything true of a browser right now, so the list answers installed,
-- open, and allowed at a glance. A browser that is switched off says only that, since
-- nothing else about it matters until it is switched on.
local function statusText(s)
  if not s.installed then return "Not installed" end
  if not s.enabled then return "Off" end
  local parts = { "On", s.running and "open" or "closed" }
  local perm = permState[s.bundleID]
  if perm then parts[#parts + 1] = PERMISSION_TEXT[perm] or perm end
  return table.concat(parts, ", ")
end

-- A browser's permission row, leading the tab list, only for a switched on browser and only
-- when the permission asks something. A state that reads fine is hidden rather than confirmed, so
-- the one thing that does need attention is never buried, and what is hidden goes to the
-- Hammerspoon console instead, because a quiet screen has to mean nothing was wrong and not that
-- nothing was noticed. The browser is named in every title, since a row reading Ask for
-- permission alone would not say which browser it is for. Pinned, so a typed query keeps it,
-- and keyed, so the stage holds the highlight on a tab when one appears above it.
--
-- The permission rows are gated on the browser being switched on. A switched off browser is
-- never scripted, so whether macOS would allow it is not a question yet, and offering to raise
-- a system prompt for a browser deliberately turned off would be asking for the wrong thing.
local function attentionRow(s)
  local perm = permState[s.bundleID]
  local key = s.bundleID .. ".permission"
  local function attention(title, subTitle, icon, item, enabled)
    item.key = key
    item.bundleID = s.bundleID
    local r = glyphRow(title, subTitle, icon, item, enabled)
    r.pinned = true
    return r
  end
  if perm == cfg.api.states.notDetermined then
    if s.running then
      return attention("Ask " .. s.name .. " for permission",
        "macOS will ask whether Hammerspoon may read " .. s.name,
        "ask", { act = "request" }, true)
    end
    -- Asking is impossible while it is closed, so the obstacle is named instead of a control
    -- that could only sit there greyed out.
    return attention("Open " .. s.name .. " first",
      "Permission can only be asked while it runs", "warn", { noop = true }, false)
  elseif perm == cfg.api.states.denied then
    return attention("Open Automation settings for " .. s.name,
      "macOS never asks twice, so this is changed by hand", "permission", { act = "openSettings" }, true)
  elseif perm == cfg.api.states.unknown or perm == cfg.api.states.noTarget then
    -- Nothing here can fix this one, so it is stated rather than offered, and the console
    -- carries the detail.
    return attention("Permission for " .. s.name .. " cannot be read",
      "The tab list still works, see the Hammerspoon console", "warn", { noop = true }, false)
  end
  return nil
end

-- Every switched on browser's permission row that asks something, in the browsers' order.
local function permissionRows()
  local out = {}
  for _, s in ipairs(cfg.api.status()) do
    if s.installed and s.enabled then
      local r = attentionRow(s)
      if r then out[#out + 1] = r end
    end
  end
  return out
end

-- The tab list as our own chooser shows it, the permission rows first and then every tab. With no
-- tabs the guidance rows follow them, all pinned, since both are what the person needs whatever
-- is typed.
local function tabRows()
  local out = permissionRows()
  local rest = #(tabs or {}) == 0 and emptyRows() or allTabRows()
  for _, r in ipairs(rest) do out[#out + 1] = r end
  return out
end

--------------------------------------------------------------------------------
-- Permission reads
--------------------------------------------------------------------------------

-- Read every switched on browser's permission and redraw as each lands. Never prompts. Run on
-- every open of the tab list, since its permission rows lead it now that no settings page holds
-- them, one probe call per browser off the main thread, and again after a request or a switch so
-- the new state shows at once.
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
      if cfg.redrawPresented then cfg.redrawPresented("browserTabs") end
    end)
  end
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

-- Everything about a listing that a row is drawn from, as one string, identity and what the row
-- is titled. Order is in it too, since the rows are ordered by it, so this changes whenever what a
-- reader would see changes and not otherwise.
local function signatureOf(list)
  local parts = {}
  for _, t in ipairs(list or {}) do
    parts[#parts + 1] = table.concat({
      t.bundleID or "", t.url or "", t.title or "",
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

--- M.tabRows() - every tab alone, in the resting order, for a surface other than our own
--- chooser, which ranks them through the shared search. No permission row and no guidance row,
--- since both are ours, and what to say about an empty list is the caller's to decide. A query argument is accepted and
--- ignored, since filtering belongs to the engine. Nothing here is remembered, so this is safe
--- to call on every keystroke.
function M.tabRows()
  return allTabRows()
end

--- M.explain(where) - why the list is empty, as rows, with `where` naming where the browser
--- switches are, since a scope shows another list's actions pane.
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
--- never learns what that is. Every tab comes back and the query scope ranks them against rest
--- through the shared search. What to say about an empty list still comes from M.explain,
--- naming this tool's own Browsers action, which the launcher's actions pane does not carry, and those
--- rows are pinned so a typed rest keeps them while the tabs are still being read.
function M.scopeRows(rest, redraw)
  if rest == "" or not M.ready() then
    M.prepare(redraw)
  end
  local out = M.tabRows()
  if #out == 0 and (rest == "" or not M.ready()) then
    return M.explain("with Browsers in Browser Tabs")
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

--- M.rows() -> list. The tab list's own row supplier, named on the manifest's own
--- presentation block as the contract's rows. It ignores the query, the shared search filters.
M.rows = tabRows

-- M.intercept, the disabled row guard this level once carried by hand, is gone, review
-- findings H1 and H2, rework. host/stage's own _intercept now answers true and does nothing
-- for any disabled row, before asking any presentation anything, legacy.lua passing the
-- row's own enabled state through as intercept's second argument, so this level, and every
-- other, gets that guard for free rather than writing one. The stray selection that used to
-- reach here through a keyboard path the atom's own click guard never covered cannot reach
-- select below any more either.

--- M.select(item) -> nil. The tab list's own onSelect, named on the manifest's own presentation
--- block. Opening a tab and opening Automation settings are genuine completions, answering
--- nothing, the whole tool closing.
function M.select(item)
  if not item then return nil end
  if item.kind == "tab" then
    cfg.api.activate(item.tab)
  elseif item.act == "openSettings" then
    cfg.api.openPermissionSettings()
  end
  return nil
end

--- M.intercept(item) -> "stay" or false. A permission request stays on the list while macOS
--- asks, the person belonging on the row they acted on, and redraws once it is answered, a grant
--- reading the tabs at once.
function M.intercept(item)
  if not (item and item.act == "request") then return false end
  local bundleID = item.bundleID
  cfg.api.permissionRequest(bundleID, function(state)
    permState[bundleID] = state
    if state == cfg.api.states.granted then
      M.reload()
    else
      log.w("the automation request for " .. tostring(bundleID) .. " ended as " .. tostring(state))
    end
    if cfg.redrawPresented then cfg.redrawPresented("browserTabs") end
  end)
  return "stay"
end

--- M:browserChoices() -> list. The Browsers action's choices, one switch per browser, each
--- saying on, so Olm draws its checkbox and flips it where it stands. The subtitle says
--- installed, open and allowed at a glance. A browser that is not installed cannot be switched
--- on, so it is dimmed with a warning rather than a box. Colon called, since the root hands a
--- surface method its module first.
function M:browserChoices()
  local out = {}
  for _, s in ipairs(cfg.api.status()) do
    local c = { title = s.name, subtitle = statusText(s), value = s.bundleID, enabled = s.installed == true }
    if s.installed then c.on = s.enabled == true else c.icon = "warn" end
    out[#out + 1] = c
  end
  return out
end

--- M:toggleBrowser(bundleID) - switch one browser on or off, then read the tabs again and the
--- permissions, so a browser switched on shows its tabs or the permission it needs at once and
--- one switched off drops them.
function M:toggleBrowser(bundleID)
  if type(bundleID) ~= "string" then return end
  cfg.api.setEnabled(bundleID, not cfg.api.isEnabled(bundleID))
  M.reload()
  refreshPermissions()
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
  refreshPermissions()
end

--- M.onClose() - the presentation contract's own onClose, named on the manifest's own
--- presentation block, told once whenever the stage hides the whole stack this tool's own
--- levels sit on, never on a swap between them. Clears showing for M.isShowing below.
function M.onClose()
  -- The integration harness reads this to learn what closed the list, so it is recorded before
  -- the showing flag clears.
  M.lastClose = { at = hs.timer.secondsSinceEpoch(), trace = debug.traceback("", 2) }
  showing = false
end

--- M.isShowing() - whether this tool's own tab list is current, plainly true from the first
--- M.onPresent until the next M.onClose. Not part of the presentation contract and
--- not routed through by host/stage's own surfaceFor, which answers the identical question
--- for the nav registry by asking the stage directly, kept only for
--- plugins/browsertabs/test/agent.lua's own commands.showing, the integration harness's one
--- direct reach into this submodule's state, left untouched per the standing instruction
--- that its own directory is not this migration's to edit.
function M.isShowing()
  return showing
end

--- M.refresh() - redraw the tab list in place, so an async listing updates the open picker
--- without waiting for a keystroke. Migrated onto host/stage, cfg.redrawPresented replacing
--- the direct chooser:refresh() this used to call on an instance it held itself. Named with
--- no token, review finding M2, rework, so it targets the tab list specifically, host/stage
--- comparing by table identity against the registrar's own stored presentation for
--- "browserTabs" rather than matching the shared name at any depth.
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

--- M.live() - what the shared stage holds right now, the field text and the item under the
--- highlight, both read live through the root's own words. Present for the integration harness,
--- which needs the one reading that sees a query that never landed. Nothing in the tool calls it.
function M.live()
  return {
    query = cfg.stageQuery and cfg.stageQuery() or "",
    item = cfg.stageSelectedItem and cfg.stageSelectedItem() or nil,
    leaderHeld = M.leaderHeld(),
  }
end

--- M.leaderHeld() answers whether the Hyper leader is believed held right now, read through the
--- root's own word. Present for the integration harness only. False when the root hands no word.
function M.leaderHeld()
  return cfg.leaderHeld ~= nil and cfg.leaderHeld() == true
end

--- M.leaderWired() answers whether the root handed the word at all, so a missing wire is told
--- apart from a leader that is never held. Present for the integration harness only.
function M.leaderWired()
  return cfg.leaderHeld ~= nil
end

--- M:configure(opts) - merge injected deps across two callers. The spoon composition root
--- injects `api`, its merged view over the engine, the recency memory and the permission
--- probe. The main root injects stagePresent and redrawPresented, the root
--- published words this migration needs. It also hands over the shared matcher every surface
--- earns, which nothing here reads since the shared search ranks the rows. Builds no chooser any more, the trickle migration, so theme and the Chooser
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
