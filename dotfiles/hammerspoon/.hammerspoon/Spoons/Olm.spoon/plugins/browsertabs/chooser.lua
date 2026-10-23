--- === BrowserTabs.chooser ===
---
--- The surface. Two levels shown through the shared stage, the same shape DisplayProfiles
--- uses, contract v3. The tab list and the settings list of browsers, where a browser is
--- switched on or off in place.
---
--- Migrated onto host/stage, contract v3, docs/BRIEF-CONTRACT-V3.md. Settings is built lazily
--- and pushed as a child the moment its row is chosen, rather than one instance driven as a
--- hand kept stack of frames. Leaving a level, every Back row, rides each level's own
--- intercept, decision three's reserved case, a row that mutates the list it is on and stands,
--- reached through cfg.stagePop. A browser's toggle and permission request mutate the settings
--- level in place through intercept too, standing exactly as they always did, while opening a
--- tab and opening Automation settings both answer through select with nothing, the ordinary
--- meaning this contract gives nil, the whole tool closing exactly as chooser:hide() always
--- did. The private Return swallowing eventtap, the hand kept frame stack, and the zero timer
--- re-show the click path used to need are all gone, since intercept is asked before
--- Return, insertSelected, and a click alike are ever let through to a real completion, the
--- one gate capable of keeping the window open through a swap at all.
---
--- The tab list is the tool. Every open tab across every switched on browser, the ones this tool
--- has opened leading in the order it opened them, each row carrying its browser's icon so which
--- browser a tab belongs to reads at a glance rather than from the text. Choosing one selects that
--- tab in its window, raises the window, and brings the browser to the front.
---
--- Settings is the only row that is not a tab. On an empty query it is the last row, outside the
--- recency order. Last does not make it reachable though, since a hundred tabs put it a hundred
--- keystrokes away, so once something is typed the shared search scores it like any tab against
--- its own title, with no recency, and typing settings brings it back while an unrelated word
--- drops it.
---
--- Settings has no level beneath it. Each browser is one row, and choosing it switches that
--- browser on or off where it stands. A permission row sits directly under a switched on browser,
--- and only when the permission asks something of you. A state that reads fine is hidden rather
--- than confirmed, so the one thing that does need attention is never buried under rows that do
--- not. What is hidden goes to the Hammerspoon console instead, because a quiet screen has to
--- mean nothing was wrong and not that nothing was noticed.
---
--- This file is pure policy over an injected api, so it reaches the engine, the recency
--- memory and the permission probe without naming any of them. The spoon composition root
--- builds that api. It names no keys either, rows say what selecting them does and never which
--- key does it, since the keys are config data that the action bar surfaces.

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

-- Back is pinned, so the shared search never scores or drops it. It leads the settings level on
-- an empty query and trails the matching browsers once something is typed, so Enter takes the
-- browser that matched.
local function backRow()
  local r = glyphRow("Back", "", "back", { nav = true, to = "back" }, true)
  r.pinned = true
  return r
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
-- What a query is matched against is declared here and applied by the shared search, which
-- phase three of docs/PLAN-UNIFIED-SEARCH.md moved this list onto. The subtitle is a status
-- like line, browser, group and host joined, so filterText is the title and the subtitle is not
-- searched, which keeps a query from matching the word open in Arc's group. The host and the
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
  local group = t.group and GROUP_LABEL[t.group]
  if group then parts[#parts + 1] = group end
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
--
-- Every one is pinned, since each says why there is nothing to search and must stay whatever is
-- typed, which is what it did while this list ranked its own query.
local function pinnedAll(list)
  for _, r in ipairs(list) do r.pinned = true end
  return list
end

local function emptyRows(where)
  where = where or "in settings below"
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
      "Allow it " .. where, "locked", { noop = true }, false)
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

-- The settings door. On an empty query it trails the tabs, which is where it was asked to be.
-- Once something is typed it is an ordinary row, scored by the shared search against its own
-- title, with no recency, so typing settings brings it back above a hundred tabs and an
-- unrelated word drops it. Its subtitle is a count, so filterText is the title. A tie leaves it
-- after a tab, since it comes last in the supplier's order.
local function settingsRow()
  local on, total = 0, 0
  for _, s in ipairs(cfg.api.status()) do
    total = total + 1
    if s.enabled then on = on + 1 end
  end
  local r = glyphRow("Settings", on .. " of " .. total .. " browsers switched on", "settings",
    { nav = true, to = "settings" }, true)
  r.filterText = r.title
  return r
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

-- The tab list as our own chooser shows it, every tab and then the settings door. With no tabs
-- the guidance rows stand alone with the door after them, all pinned, since both are what the
-- person needs whatever is typed and the guidance points at the door.
local function tabRows()
  if #(tabs or {}) == 0 then
    local out = emptyRows()
    local door = settingsRow()
    door.pinned = true
    out[#out + 1] = door
    return out
  end
  local out = allTabRows()
  out[#out + 1] = settingsRow()
  return out
end

--------------------------------------------------------------------------------
-- The settings list
--------------------------------------------------------------------------------

-- One line describing everything true of a browser right now, so the list answers installed,
-- open, and allowed at a glance. A browser that is switched off says only that, since
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
  if not s.installed then return "warn" end
  return s.enabled and "active" or "off"
end

-- A browser's permission row, the one extra line under a switched on browser, and only when
-- the permission asks something. A state that reads fine is hidden rather than confirmed, so the
-- one thing that does need attention is never buried under rows that do not, and what is hidden
-- goes to the Hammerspoon console instead, because a quiet screen has to mean nothing was wrong
-- and not that nothing was noticed. The browser is named in every title, since this is one flat
-- list and a row reading Ask for permission alone would not say which browser it is for.
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
    -- The browser's name alone, the same text its browser row filters on, so the two always
    -- match together and score the same, and the permission row stays under its browser
    -- rather than showing alone on a state word or ranking above it.
    r.filterText = s.name
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
      "macOS never asks twice, so this is changed by hand", "locked", { act = "openSettings" }, true)
  elseif perm == cfg.api.states.unknown or perm == cfg.api.states.noTarget then
    -- Nothing here can fix this one, so it is stated rather than offered, and the console
    -- carries the detail.
    return attention("Permission for " .. s.name .. " cannot be read",
      "The tab list still works, see the Hammerspoon console", "warn", { noop = true }, false)
  end
  return nil
end

-- The settings level is the whole of the settings. Selecting a browser row switches it on or off
-- where it stands, there is no level beneath it, so a person flips a browser and sees the answer
-- on the same screen. Back is the first row and pinned, so a typed query never drops it and
-- moves it below the matches. Every other row, a permission row included, filters on the
-- browser's name alone, so a toggle never changes whether a row matches, and a
-- permission row matches exactly when its browser does, sits right under it in a ranked list
-- and never shows on its own. Every row carries a key, the bundle id for a browser and the
-- bundle id with a suffix for its permission row, because the stage holds the highlight on the
-- item with the same key across every repaint of this level, a toggle, a permission read
-- landing late, or either under a typed query, so a permission row appearing above the browser
-- the person is on never moves them onto it.
local function settingsRows()
  local out = { backRow() }
  for _, s in ipairs(cfg.api.status()) do
    local r = glyphRow(s.name, statusText(s), settingsIcon(s),
      s.installed and { act = "toggle", bundleID = s.bundleID, key = s.bundleID }
        or { noop = true, key = s.bundleID },
      s.installed)
    r.filterText = s.name
    out[#out + 1] = r
    if s.installed and s.enabled then
      local extra = attentionRow(s)
      if extra then out[#out + 1] = extra end
    end
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
--
-- token, review finding M2, rework, is the settings child's own presentation table, handed
-- to cfg.redrawPresented so an answer landing here repaints the settings level specifically
-- rather than whatever the shared name would otherwise match at any depth, docs/BRIEF-
-- CONTRACT-V3.md's own rule that an async answer lands on its own level or not at all.
local function refreshPermissions(token)
  for _, s in ipairs(cfg.api.status()) do
    local bundleID, name = s.bundleID, s.name
    cfg.api.permissionStatus(bundleID, function(state)
      permState[bundleID] = state
      if state == cfg.api.states.unknown or state == cfg.api.states.noTarget then
        log.w("could not read the automation permission for " .. name .. ", the probe said " .. tostring(state))
      elseif state == cfg.api.states.denied then
        log.w(name .. " has refused automation, macOS will not ask again, change it in System Settings")
      end
      if cfg.redrawPresented then cfg.redrawPresented("browserTabs", nil, token) end
    end)
  end
end

--------------------------------------------------------------------------------
-- The settings level, built lazily and pushed the moment the Settings row is chosen
--------------------------------------------------------------------------------

-- The settings level, a child of the tab list, and the only level beneath it. onPresent starts
-- the permission reads the moment this level becomes current, through either door, present or
-- push, the identical warmth VPN's own async fetch already gets. Self referential, review
-- finding M2, rework, so refreshPermissions and the permission request can hand their landing
-- redraw this exact table as a token rather than the shared name every level of this tool still
-- answers to.
--
-- The list filters on the shared matcher like every other list of items, so no matcher is
-- declared. Back is pinned in settingsRows, and every other row states its own filterText, which
-- keeps a state word from deciding whether a browser matches.
--
-- A browser's switch and a permission request both mutate this level in place and stand, so
-- both answer "stay" from intercept, the stage holding the highlight on the pressed item by its
-- key and the list repainting with the new state. Back is the one row that leaves, through cfg.stagePop.
-- Opening Automation settings is a genuine completion, not a level, so it answers through
-- onSelect, calling the api and returning nothing, the ordinary meaning this contract has always
-- given nil, the whole stack tears down and the tool closes for good.
local function buildSettingsChild()
  local child
  child = {
    placeholder = "Browsers",
    rows = settingsRows,
    onPresent = function() refreshPermissions(child) end,
    onSelect = function(item)
      if item and item.act == "openSettings" then
        cfg.api.openPermissionSettings()
      end
      return nil
    end,
    intercept = function(item)
      -- The disabled row guard is host/stage's own, _intercept answering true and doing nothing
      -- for any disabled row before this is ever asked, so an uninstalled browser never gets here.
      if not item then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "toggle" then
        cfg.api.setEnabled(item.bundleID, not cfg.api.isEnabled(item.bundleID))
        -- Switching a browser on is only useful once its tabs appear, and switching one off
        -- should drop them, so the listing is redone straight away rather than on the next
        -- open. M.reload's own landing redraw targets the tab list alone, so it correctly
        -- touches nothing while this level is what is showing.
        M.reload()
        return "stay"
      end
      if item.act == "request" then
        local bundleID = item.bundleID
        cfg.api.permissionRequest(bundleID, function(state)
          permState[bundleID] = state
          -- A grant makes tabs readable that were not a moment ago, so pick them up at once.
          if state == cfg.api.states.granted then
            M.reload()
          else
            log.w("the automation request for " .. tostring(bundleID) .. " ended as " .. tostring(state))
          end
          -- token is this level's own table, so the redraw lands here specifically, or not at
          -- all once the person has moved on.
          if cfg.redrawPresented then cfg.redrawPresented("browserTabs", nil, child) end
        end)
        -- Answers "stay" immediately even though the mutation itself is asynchronous and has
        -- not landed yet, since the person just acted on this row and belongs on it while the
        -- request is outstanding, the redraw above catching up once the callback fires.
        return "stay"
      end
      return false
    end,
  }
  return child
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

--- M.tabRows() - every tab alone, in the resting order, for a surface other than our own
--- chooser, which ranks them through the shared search. No settings door and no guidance row,
--- since both are ours, the door is a step into a second level only this chooser can show, and
--- what to say about an empty list is the caller's to decide. A query argument is accepted and
--- ignored, since filtering belongs to the engine. Nothing here is remembered, so this is safe
--- to call on every keystroke.
function M.tabRows()
  return allTabRows()
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
--- never learns what that is. Every tab comes back and the query scope ranks them against rest
--- through the shared search. What to say about an empty list still comes from M.explain,
--- naming this tool's own settings rather than a settings row a scope cannot show, and those
--- rows are pinned so a typed rest keeps them while the tabs are still being read.
function M.scopeRows(rest, redraw)
  if rest == "" or not M.ready() then
    M.prepare(redraw)
  end
  local out = M.tabRows()
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
  -- The integration harness reads this to learn what closed the list, so it is recorded before
  -- the showing flag clears.
  M.lastClose = { at = hs.timer.secondsSinceEpoch(), trace = debug.traceback("", 2) }
  showing = false
end

--- M.isShowing() - whether this tool's own tab list is current, plainly true from the first
--- M.onPresent until the next M.onClose, unaffected by drilling into or backing out of
--- settings in between. Not part of the presentation contract and
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
--- "browserTabs" rather than matching the shared name at any depth, and it is a silent no op
--- while the settings child is what is actually showing, since
--- the tab list has nothing to say about it. M.reload's own landing callback is the one
--- caller, so this is never asked to redraw a child's own answer, each child's own async
--- work redrawing itself through its own token instead, buildSettingsChild above.
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
--- probe. The main root injects stagePresent, stagePop, and redrawPresented, the root
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
