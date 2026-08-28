--- === TmuxSessions.chooser ===
---
--- Two levels shown through the shared stage. The top lists every WINDOW across every
--- session, one row each, title the window name and subtitle the session it belongs to, so
--- a window with a common name (several sessions keep a plain "zsh" window) still reads
--- unambiguously and is searchable by either name, or both together, a word at a time in
--- any order ("vic zsh" finds the zsh window inside vicert), matchesQuery below. Choosing
--- one jumps straight to that window and closes like any ordinary row. The last row is a
--- Settings door, the shape BrowserTabs still uses for choosing which browsers are
--- scripted, leading to a second level that names which terminal a fresh attach opens
--- into. Both levels share the one shared instance through the presentation contract's own
--- intercept and back, exactly the drill down pair the atom always asked for, so entering
--- and leaving Settings never flickers a close and reopen.
---
--- The list is ordered by recency, not by session then index, the engine's own doing
--- (windows() returns it already ordered), so this file only ever filters what it is
--- handed and never reorders it itself.
---
--- This file talks to tmux and to the terminal providers only through the injected api
--- table, so it is pure command policy, the same split DisplayProfiles keeps between its
--- engine and its own chooser.
---
--- Migrated onto host/stage, the trickle migration. This file owns no chooser instance and
--- builds no window any more. Its rows, its selection dispatch, and its drill down pair are
--- exactly what they always were, now named on the manifest's own presentation block
--- instead of handed to a Chooser.new call this file no longer makes. The primary action
--- renamed from enter to insertSelected in the manifest, since that naming existed only to
--- match a hand rolled surface method name a private mechanism this file never actually
--- used would have answered to, and host/stage's own surfaceFor answers insertSelected
--- directly, closing the atom's real completion path the identical way this file's own
--- intercept and back always did.

local M = { name = "TmuxSessions.chooser" }

local log = hs.logger.new("TmuxSessions", "info")

local cfg = {}       -- injected across two calls: api from the spoon, view deps from the root
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
--
-- Migrated onto host/stage. Neither branch calls refresh any more, since the atom's own
-- key watcher already calls refresh(true) on the shared instance once this handler
-- returns true, lib/chooser/providers/native.lua's own contract for intercept, unchanged
-- by which presentation's own hook is what answered it.
local function intercept(item)
  if not item then return false end
  if item.nav then
    level = item.nav
    return true
  end
  if item.setProvider then
    cfg.api:setProviderName(item.setProvider)
    return true
  end
  return false
end

-- Migrated onto host/stage, the identical reason intercept above no longer calls refresh.
local function back()
  if level == "settings" then
    level = "top"
    return true
  end
  return false
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

-- isShowing, hide, selectNext, selectPrev, and insertSelected are gone, the trickle
-- migration, deleted along with the Chooser.new block that gave them something to answer
-- for. The composition root now routes this plugin's own navigation through host/stage's
-- own surfaceFor once wiredRegistry.presentationFor("tmuxSessions") answers a
-- presentation, which answers all five, insertSelected among them, so nothing here binds a
-- verb beyond them any more and registry.surface is no longer declared. selectRow,
-- selectedItem, and setQuery are gone too, unused passthroughs onto an instance this file
-- no longer holds, kept only for the reason the atom exposed them itself before this
-- migration, which is no longer a reason anything here needs.

--- M.rows(query) -> list. The row supplier, named on the manifest's own presentation block
--- as the contract's rows, exposing the file local rows already defined above without a
--- second copy to disagree with.
M.rows = rows

--- M.select(item) - apply a row, named on the manifest's own presentation block as the
--- contract's onSelect, exposing the file local onSelect already defined above.
M.select = onSelect

--- M.intercept, M.back - the presentation contract's own drill down pair, named on the
--- manifest's own presentation block, exposing the file local functions already defined
--- above without a second copy to disagree with.
M.intercept = intercept
M.back = back

--- M.placeholder() -> string. The field hint while this plugin's own presentation is
--- current, named on the manifest's own presentation block. Resolved once, at register,
--- since the presentation contract wants a plain string a presentation carries rather than
--- a function to call again later.
function M.placeholder()
  return "Search sessions and windows"
end

--- M.onPresent() - the presentation contract's own onPresent, named on the manifest's own
--- presentation block, called by the stage whenever this presentation becomes current,
--- through present or push alike, before the window itself is shown or swapped into.
--- Carries the three things M.show used to do inline before this plugin had a presentation
--- to defer through instead. The level always resets to top, since a fresh appearance from
--- either door means the window list rather than wherever a previous visit to Settings left
--- it. A deliberate open is exactly the moment a person expects to be shown what is true
--- right now, so the engine's held read is dropped here and the first question of this open
--- goes to the tmux server, and prune runs once per open rather than on every keystroke,
--- since a session or window can only disappear between opens.
function M.onPresent()
  level = "top"
  cfg.api:invalidate()
  cfg.api:pruneRecency()
end

--- M.show() - present through the shared stage. This is the hotkey door, reached from this
--- plugin's own leader key through the plugin root's own show, which still delegates here.
--- cfg.stagePresent asks the registry for this plugin's own presentation and hands it to
--- Stage:present, which is what runs onPresent above before showing anything, exactly what
--- this function used to do inline before this plugin had a presentation to defer through
--- instead.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("tmuxSessions") end
end

function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

function M.start()
  return M
end

return M
