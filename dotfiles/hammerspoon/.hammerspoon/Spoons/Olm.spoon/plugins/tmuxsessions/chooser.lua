--- === TmuxSessions.chooser ===
---
--- One native chooser with two levels. The top lists every WINDOW across every session,
--- one row each, title the window name and subtitle the session it belongs to, so a
--- window with a common name (several sessions keep a plain "zsh" window) still reads
--- unambiguously and is searchable by either name, or both together, a word at a time in
--- any order ("vic zsh" finds the zsh window inside vicert), matchesQuery below. Choosing
--- one jumps straight to that window and closes like any ordinary row. The last row is a
--- Settings door, the shape
--- BrowserTabs already uses for choosing which browsers are scripted, leading to a second
--- level that names which terminal a fresh attach opens into. Both levels share the one
--- chooser instance through the atom's intercept and back hooks, so entering and leaving
--- Settings never flickers a close and reopen.
---
--- The list is ordered by recency, not by session then index, the engine's own doing
--- (windows() returns it already ordered), so this file only ever filters what it is
--- handed and never reorders it itself.
---
--- This file talks to tmux and to the terminal providers only through the injected api
--- table, so it is pure command policy, the same split DisplayProfiles keeps between its
--- engine and its own chooser.

local M = { name = "TmuxSessions.chooser" }

local log = hs.logger.new("TmuxSessions", "info")

local cfg = {}       -- injected across two calls: api from the spoon, view deps from the root
local chooser = nil  -- the one native Chooser instance
local level = "top"  -- "top" | "settings"

-- Render an emoji string to a small image so a row can carry it as its icon, an offscreen
-- canvas drawn once and cached by the string, the same helper the other menu choosers use.
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

local ICON = {
  active = "🟢",   -- the window currently on screen, or the currently chosen terminal
  window = "🪟",
  terminal = "💻",
  settings = "⚙️",
  back = "⬅️",
}

local function row(title, subTitle, icon, item, enabled)
  return { title = title, subTitle = subTitle, image = emojiImage(icon), item = item,
    enabled = enabled ~= false }
end

-- A window is what is genuinely on screen right now, not merely the window that happens
-- to be highlighted inside a detached session, so the green dot marks a window only when
-- its own session is attached and this is the window that session is currently showing.
local function isLive(w)
  return w.sessionAttached and w.active
end

-- Word matching over the window name and the session name combined, the same strategy
-- the clipboard and Local Servers already use over their own two-plus fields, and for the
-- same reason: a query here is a real remembered fragment of more than one thing, a piece
-- of the window and a piece of the session, not a single guess at one label. Splitting the
-- query on whitespace and requiring every word to be a substring somewhere in the combined
-- text, in any order, is what lets "vic zsh" find the zsh window inside vicert even though
-- neither word alone names the whole row. This stays a hand written check rather than the
-- shared matcher because the Settings level below still needs to opt out of it entirely,
-- the same reason DisplayProfiles and BrowserTabs each write their own filter by hand.
local function matchesQuery(body, query)
  if query == "" then return true end
  for word in query:gmatch("%S+") do
    if not body:find(word, 1, true) then return false end
  end
  return true
end

-- The matching window rows alone, shared between this chooser's own top level and the
-- launcher scope below, so the two can never rank or filter differently. No Settings door
-- here, since that is a step into a second level only this chooser's own native instance
-- can show, the browserTabs precedent for the identical reason.
local function windowRows(query)
  local q = (query or ""):lower()
  local out = {}
  for _, w in ipairs(cfg.api:windows()) do
    local body = (w.name .. " " .. w.session):lower()
    if matchesQuery(body, q) then
      out[#out + 1] = row(w.name, w.session, isLive(w) and ICON.active or ICON.window,
        { go = w.target, label = w.name .. " in " .. w.session }, true)
    end
  end
  return out
end

local function topRows(query)
  local out = windowRows(query)
  out[#out + 1] = row("Settings", "Choose which terminal opens a fresh attach", ICON.settings,
    { nav = "settings" }, true)
  return out
end

local function settingsRows()
  local out = { row("Back", "", ICON.back, { nav = "top" }, true) }
  local current = cfg.api:currentProviderName()
  for _, p in ipairs(cfg.api:providers()) do
    local isActive = p.name == current
    local sub = p.available() and "Installed" or "Not installed"
    out[#out + 1] = row(p.name, sub, isActive and ICON.active or ICON.terminal,
      { setProvider = p.name }, p.available())
  end
  return out
end

local function rows(query)
  if level == "settings" then return settingsRows() end
  return topRows(query)
end

local function onSelect(item)
  if not item or not item.go then return end
  local ok, err = cfg.api:goTo(item.go)
  if not ok then
    local message = "Could not reach " .. (item.label or item.go) .. ", " .. tostring(err)
    log.w(message)
    if cfg.onMessage then cfg.onMessage(message) end
  end
end

-- Asked before Return is allowed to complete. A nav row means this list becomes another
-- list, the Settings door or its own Back, and answering true keeps the one instance open
-- and rebuilds it instead of closing and reshowing. Choosing a terminal in the Settings
-- level is the same shape, it changes what is persisted and stays open so the moved green
-- circle is what confirms the choice, rather than a reopen.
local function intercept(item)
  if not item then return false end
  if item.nav then
    level = item.nav
    chooser:refresh(true)
    return true
  end
  if item.setProvider then
    cfg.api:setProviderName(item.setProvider)
    chooser:refresh(true)
    return true
  end
  return false
end

local function back()
  if level == "settings" then
    level = "top"
    chooser:refresh(true)
    return true
  end
  return false
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

--- M.hostRows(query) - the matching window rows alone, for the launcher's own scope rather
--- than this chooser's native instance. No Settings door, since hosting shows one list and
--- a door is a step into a second one only the native picker can show; Hyper+U still opens
--- that picker directly when the terminal needs changing. Reuses windowRows exactly, so a
--- hosted list and this chooser's own top level can never disagree about what matched.
function M.hostRows(query)
  return windowRows(query or "")
end

--- M.explain(where) - why the hosted list is empty, as a single row naming it, for the rare
--- case tmux is running with no session at all. `where` names where a session would be
--- started, since a hosted list has no row of its own to point at, the browserTabs shape.
function M.explain(where)
  return { row("No tmux sessions", "Start one, then search " .. where, ICON.window,
    { noop = true }, false) }
end

--- M.scopeRows(rest) - the hosted rows with the empty case already answered, which is what a
--- scope actually wants. The retired root wrote this wrapper itself, reaching in for hostRows
--- and for explain and then naming this tool's own description out of the key catalog to fill
--- in where. It lives here now for the reason the browserTabs one does, this file is the only
--- thing that knows what an empty list means, and a root assembling the answer had to know two
--- of this file's members plus a field inside somebody else's data to manage it.
---
--- Where is stated plainly rather than read from a catalog, since the settings level it points
--- at is this tool's own and its name does not move when a key binding does.
function M.scopeRows(rest)
  local out = M.hostRows(rest)
  if #out == 0 then
    return M.explain("in Tmux Manager settings")
  end
  return out
end

--- M.activate(item) - open the window a row from M.hostRows carries, the launcher's own
--- scope.run. Identical to onSelect, since a row chosen through the hosted list means
--- exactly what a row chosen through this chooser's own native instance means.
function M.activate(item)
  onSelect(item)
end

function M.selectNext() if chooser then chooser:selectNext() end end
function M.selectPrev() if chooser then chooser:selectPrev() end end
function M.insertSelected() if chooser then chooser:insertSelected() end end
-- The root's shared contextActions table dispatches a hyperContext action by calling a
-- method of that exact name on the active surface (routeNav), and the two names it
-- expects are enter and hide, not insertSelected and close. DisplayProfiles and
-- BrowserTabs each expose enter as their own hand rolled confirm, since they predate the
-- atom's real intercept and back hooks and dispatch through a homemade applySelection
-- instead. This chooser already goes through those atom hooks correctly via
-- insertSelected, so enter is simply the name contextActions needs for the very same
-- call, not a second implementation. hide is close under the name routeNav("hide")
-- expects; nothing here reads M.close, so it is renamed rather than kept alongside it.
function M.enter() if chooser then chooser:insertSelected() end end
function M.hide() if chooser then chooser:hide() end end
-- Thin passthroughs to the atom's own public contract, not bound to any key, kept for
-- the same reason the atom exposes them itself, restoring a highlight by row number.
function M.selectRow(n) if chooser then chooser:selectRow(n) end end
function M.selectedItem() return chooser and chooser:selectedItem() end
function M.setQuery(text) if chooser then chooser:setQuery(text) chooser:refresh(true) end end

function M.show()
  level = "top"
  -- Once per open rather than on every keystroke, since a session or window can only
  -- disappear between opens, and prune() itself is cheap enough either way, this is
  -- simply the natural place a maintenance pass belongs rather than the hot filter path.
  cfg.api:pruneRecency()
  if not chooser then
    chooser = cfg.chooser.new({
      theme = cfg.theme,
      placeholder = "Search sessions and windows",
      fieldMode = "filter",
      -- Owns its own filtering, the DisplayProfiles shape, since the shared matcher would
      -- rank and could hide the Settings door and the Back row on the second level.
      matcher = false,
      rows = rows,
      onSelect = onSelect,
      intercept = intercept,
      back = back,
      onPositioned = cfg.onPositioned,
      onActivity = cfg.onActivity,
      onClose = cfg.onClose,
    })
  end
  chooser:show()
end

function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

function M.start()
  return M
end

return M
