--- === TmuxSessions.chooser ===
---
--- One list shown through the shared stage. It lists every WINDOW across every
--- session, one row each, title the window name and subtitle the session it belongs to, so
--- a window with a common name (several sessions keep a plain "zsh" window) still reads
--- unambiguously and is searchable by either name, or both together, a word at a time in
--- any order ("vic zsh" finds the zsh window inside vicert), by the shared search reading the
--- window name first and the session as the secondary field. Choosing
--- one jumps straight to that window and closes like any ordinary row.
---
--- Which terminal a fresh attach opens into is Terminal, a verb of the action panel with
--- choices, docs/PLAN-ACTION-PANEL.md. Until 2026-10-30 it was a second level behind a
--- Settings row at the foot of the list, and it moved into the panel because a terminal is a
--- setting of the tool rather than a place in it, so the list now holds windows and nothing
--- else.
---
--- The list is ordered by recency, not by session then index, the engine's own doing
--- (windows() returns it already ordered), so this file hands it over as it is and the shared
--- search filters and ranks it, recency standing as the order of an empty query.
---
--- This file talks to tmux and to the terminal providers only through the injected api
--- table, so it is pure command policy, the same split DisplayProfiles keeps between its
--- engine and its own chooser.

local M = { name = "TmuxSessions.chooser" }

local log = hs.logger.new("TmuxSessions", "info")

local cfg = {}       -- injected across two calls: api from the spoon, view deps from the root


local function row(title, subTitle, icon, item, enabled, pinned)
  return { title = title, subTitle = subTitle, icon = icon, item = item,
    enabled = enabled ~= false, pinned = pinned }
end

-- A window is what is genuinely on screen right now, not merely the window that happens
-- to be highlighted inside a detached session, so the green dot marks a window only when
-- its own session is attached and this is the window that session is currently showing.
local function isLive(w)
  return w.sessionAttached and w.active
end

-- Every window row, shared between this chooser's own list and the launcher scope
-- below, so the two can never rank or filter differently. The title is the window name and
-- the subtitle the session, which is what the search reads, a query being a remembered
-- fragment of more than one thing, a piece of the window and a piece of the session, so
-- "vic zsh" finds the zsh window inside vicert.
local function windowRows()
  local out = {}
  for _, w in ipairs(cfg.api:windows()) do
    out[#out + 1] = row(w.name, w.session, isLive(w) and "active" or "window",
      { go = w.target, label = w.name .. " in " .. w.session }, true)
  end
  return out
end

-- The terminal choices, one per provider, for the action panel's Terminal verb. The one in
-- force carries the panel's current marker, and a terminal this machine does not have is
-- answered disabled, drawn dimmed and choosing nothing.
local function terminalChoices()
  local out = {}
  local current = cfg.api:currentProviderName()
  for _, p in ipairs(cfg.api:providers()) do
    local usable = p.available()
    out[#out + 1] = { title = p.name, subtitle = usable and "Installed" or "Not installed",
      icon = "terminal", value = p.name, current = p.name == current, enabled = usable }
  end
  return out
end

-- The list's own select. Choosing a window is a genuine completion, jumping there and
-- answering nothing, the ordinary meaning this contract gives nil, the whole tool closing.
local function onSelect(item)
  if not item then return nil end
  if item.go then
    local ok, err = cfg.api:goTo(item.go)
    if not ok then
      local message = "Could not reach " .. (item.label or item.go) .. ", " .. tostring(err)
      log.w(message)
      if cfg.onMessage then cfg.onMessage(message) end
    end
    return nil
  end
  return nil
end

--- M.hostRows() - the window rows, for the launcher's own scope rather than this chooser's
--- native instance. Reuses windowRows exactly, so a hosted list and this chooser's own list can
--- never disagree about what matched. The terminal is changed from the tool's own list, since a
--- hosted list offers only the verbs its scope declares.
function M.hostRows()
  return windowRows()
end

--- M.explain(where) - why the hosted list is empty, as a single row naming it, for the rare
--- case tmux is running with no session at all. `where` names where a session would be
--- started, since a hosted list has no row of its own to point at, the browserTabs shape.
function M.explain(where)
  return { row("No tmux sessions", "Start one, then search " .. where, "window",
    { noop = true }, false, true) }
end

--- M.scopeRows(rest) - the hosted rows with the empty case already answered, which is what a
--- scope actually wants. The retired root wrote this wrapper itself, reaching in for hostRows
--- and for explain and then naming this tool's own description out of the key catalog to fill
--- in where. It lives here now for the reason the browserTabs one does, this file is the only
--- thing that knows what an empty list means, and a root assembling the answer had to know two
--- of this file's members plus a field inside somebody else's data to manage it.
---
--- Where is stated plainly rather than read from a catalog, since it names no key and no tool
--- whose name could move.
function M.scopeRows()
  local out = M.hostRows()
  if #out == 0 then
    return M.explain("again")
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

--- M.rows(query) -> list. The list's own row supplier, named on the manifest's own
--- presentation block as the contract's rows, exposing the file local windowRows already
--- defined above without a second copy to disagree with.
M.rows = windowRows

--- M.select(item) -> nil. The list's own onSelect, named on the manifest's own presentation
--- block, exposing the file local onSelect already defined above. A window row is a genuine
--- completion, answering nothing.
M.select = onSelect

--- M:terminalChoices() -> list. The choices of the action panel's Terminal verb. Colon called,
--- since the root hands a surface method its module first.
function M:terminalChoices()
  return terminalChoices()
end

--- M:setTerminal(name) - open a fresh attach in the terminal a Terminal choice names.
function M:setTerminal(name)
  if name then cfg.api:setProviderName(name) end
end

-- M.intercept and M.back, this file's own hand kept drill down pair, are gone, contract
-- v3, docs/BRIEF-CONTRACT-V3.md. The list never mutates itself or leaves anywhere by
-- itself, so it carries neither hook and the manifest names neither.

--- M.placeholder() -> string. The field hint, named on the manifest's own presentation
--- block. Resolved once, at register, since the presentation contract wants a plain string a
--- presentation carries rather than a function to call again later.
function M.placeholder()
  return "Search sessions and windows"
end

--- M.onPresent() - the presentation contract's own onPresent, named on the manifest's own
--- presentation block, called by the stage whenever the top level becomes current, through
--- present or push alike, before the window itself is shown or swapped into. A deliberate
--- open is exactly the moment a person expects to be shown what is true right now, so the
--- engine's held read is dropped here and the first question of this open goes to the tmux
--- server, and prune runs once per open rather than on every keystroke, since a session or
--- window can only disappear between opens. The level reset this used to do, level = "top",
--- is gone along with the flag it reset, a fresh M.show always presenting the top level
--- fresh now regardless, host/stage's own Stage:present starting a new stack of one every
--- time.
function M.onPresent()
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
