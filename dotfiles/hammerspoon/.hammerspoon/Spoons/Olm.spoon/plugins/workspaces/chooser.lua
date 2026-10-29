--- === Workspaces.chooser ===
---
--- The surface, the command policy over the engine and the store. Take a new snapshot, look at
--- the layouts and see which apply here, go into one to apply it, update it from what is open
--- now, prune the apps it should not speak for, rename it, or delete it.
---
--- Every level is a presentation table, built lazily and pushed the moment a row drills into it,
--- and the shared stage owns the one window all of them show into. Choosing New snapshot, a
--- layout, Apps, an app, Rename, or Delete returns the level it leads to from select and the
--- stage pushes it, swapping the list in place with no window ever closing. Leaving a level,
--- every Back row, the confirm's own Keep, and the pop a successful rename, delete, remove, or
--- include lands on, all ride each level's own intercept, since a child returned from select can
--- only ever push, never pop, and cfg.stagePop is the one word that expresses leaving.
---
--- Saving a new snapshot is the one row that both leaves and arrives. It pops the name level
--- from inside select and then answers the new layout's own level, so the stage lands on the
--- layout just taken with its apps one row away, ready to prune, and Backspace from there goes
--- to the list rather than back to a name field for a snapshot that already exists.
---
--- Apply is a completion rather than a level. It places the windows and answers nothing, so the
--- window goes away and the report drawn by the root is what is left on screen.
---
--- This file talks to the engine and the store only through the injected api table, so it is pure
--- policy. The plugin composition root in init.lua builds that api.

local M = { name = "Workspaces.chooser" }

local log = hs.logger.new("Workspaces", "info")

local cfg = {}  -- injected across two calls, api from the plugin root, stage words from the wiring step


--------------------------------------------------------------------------------
-- Small row builders
--------------------------------------------------------------------------------

-- Every row searches its title alone. A subtitle here is a status, a count or a sentence about
-- what the row does, "Applies here, 3 apps, taken on Studio", and searched it would let apps or
-- studio match every layout, so filterText is the title, the vocabulary in lib/chooser/rank.lua.
local function row(title, subTitle, icon, item, enabled, pinned)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled,
    filterText = title, pinned = pinned }
end

-- Back is pinned, so on a level that searches it is never scored or dropped, and under a typed
-- query it trails the matches so Enter takes the best one. Where a level keeps matcher false the
-- flag changes nothing.
local function backRow()
  return row("Back", "", "back", { nav = "back" }, true, true)
end

-- One app row, carrying the app's own icon from the api rather than the generic emoji mark, so
-- the Apps list reads at a glance the way the launcher and the other choosers already do. It
-- searches the app's name alone, since the subtitle says where its windows sit.
local function appRow(title, subTitle, icon, item)
  return { title = title, subTitle = subTitle, image = icon, icon = icon == nil and "app" or nil, item = item,
    enabled = true, filterText = title }
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function countLabel(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

local function pop()
  if cfg.stagePop then cfg.stagePop() end
end

--------------------------------------------------------------------------------
-- Per level row suppliers
--------------------------------------------------------------------------------

-- The top level. New snapshot leads, since taking one is the reason to open this at all on a
-- fresh machine, then every layout, the ones that apply here first. The shared search filters
-- and ranks the layouts by name. New snapshot is pinned, so no query drops it and the list is
-- never empty, which is why there is no row for a query that matches nothing. It leads the
-- resting list and trails the matches once something is typed, so Enter on a typed name opens
-- that layout rather than taking a snapshot.
local function topRows()
  local out = {}
  if not cfg.api.persists() then
    out[#out + 1] = row("Nothing can be stored", "No file was given for layouts to live in",
      "warn", { noop = true }, false, true)
    return out
  end
  out[#out + 1] = row("New snapshot", "Record where every window sits on " .. cfg.api.here(),
    "new", { nav = "new" }, true, true)
  for _, l in ipairs(cfg.api.list()) do
    local sub
    if l.available then
      sub = "Applies here, " .. countLabel(l.apps, "app", "apps") .. ", taken on " .. l.topology
    else
      sub = "Not here, it " .. l.reason .. ", taken on " .. l.topology
    end
    out[#out + 1] = row(l.name, sub, l.available and "available" or "unavailable",
      { nav = "layout", id = l.id }, true)
  end
  return out
end

-- The name level for a new snapshot. The search field is the name, and the top row morphs to
-- Save as the typed name, disabled while the name is empty or already used so a confirm can never
-- write a bad one. Then Back.
local function newRows(query)
  local name = trim(query)
  local out = {}
  if name == "" then
    out[#out + 1] = row("Type a name for this snapshot", "Everything open now on " .. cfg.api.here(),
      "hint", { noop = true }, false)
  elseif cfg.api.exists(name) then
    out[#out + 1] = row("Name already used", "Choose a name no other layout has", "warn",
      { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. name .. "'", "Record where every window sits now", "save",
      { act = "create", name = name }, true)
  end
  out[#out + 1] = backRow()
  return out
end

-- The apps of one layout, included first and the excluded as a tail, each saying where its
-- windows sit so an app recorded somewhere silly is visible as such before anybody prunes it.
local function appsRows(id)
  local out = { backRow() }
  local apps = cfg.api.apps(id)
  if #apps == 0 then
    out[#out + 1] = row("Nothing recorded here", "Update the snapshot with some windows open",
      "hint", { noop = true }, false, true)
    return out
  end
  for _, a in ipairs(apps) do
    local detail
    if a.excluded then
      detail = "Excluded, this layout leaves it alone"
    else
      detail = countLabel(a.windows, "window", "windows") .. " on " .. a.displays
    end
    out[#out + 1] = appRow(a.name, detail, a.icon, { nav = "app", bundle = a.bundle, name = a.name, excluded = a.excluded })
  end
  return out
end

-- One app. Back leads, so this level is safe to land on, and the one action it offers flips
-- whether the layout speaks for this app.
local function appRows(name, excluded)
  if excluded then
    return {
      backRow(),
      row("Include '" .. name .. "' again", "Place its windows when this layout is applied",
        "include", { act = "include" }, true),
    }
  end
  return {
    backRow(),
    row("Remove '" .. name .. "'", "Leave this app alone when this layout is applied",
      "remove", { act = "exclude" }, true),
  }
end

-- The rename level. Same shape as the name level for a new snapshot.
local function renameRows(id, query)
  local l = cfg.api.get(id)
  local current = l and l.name or ""
  local newName = trim(query)
  local out = {}
  if newName == "" then
    out[#out + 1] = row("Type a new name", "Rename '" .. current .. "'", "hint", { noop = true }, false)
  elseif newName ~= current and cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other layout has", "warn",
      { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. newName .. "'", "Rename '" .. current .. "'", "save",
      { act = "saveRename", newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

--------------------------------------------------------------------------------
-- Child levels, built lazily and pushed the moment a row drills into one
--------------------------------------------------------------------------------

-- Every child below shares one shape. rows reads whatever the level names, matcher is false
-- only where the field is input, a typed name or a confirm, and a level that is a list
-- inherits the shared search, and intercept is where a level that leaves for its parent answers for itself. The
-- disabled row guard is never written by hand, the stage's own gate answering for any row built
-- with enabled false before a presentation is ever asked.

local buildAppsChild, buildAppChild, buildRenameChild

-- The name level for a new snapshot, a child of the top level. Save leaves for the top level,
-- where the new layout is listed and everything it offers is in the action panel, so it answers
-- from intercept and pops like Back does.
local function buildNewChild()
  return {
    placeholder = "Name for this snapshot",
    -- search-exempt, the field is the new snapshot's name being typed, input and not a search
    matcher = false,
    rows = newRows,
    onSelect = function() end,
    intercept = function(item)
      if item and item.nav == "back" then
        pop()
        return true
      end
      if item and item.act == "create" then
        local id, err = cfg.api.create(item.name)
        if not id then log.e("snapshot failed, " .. tostring(err)) end
        pop()
        return true
      end
      return false
    end,
  }
end

-- The apps list, a child of a layout. Nothing here mutates, so an app row is an ordinary push
-- through select and only Back rides the intercept.
buildAppsChild = function(id)
  return {
    placeholder = "Search apps in this layout",
    rows = function() return appsRows(id) end,
    onSelect = function(item)
      if item and item.nav == "app" then return buildAppChild(id, item.bundle, item.name, item.excluded) end
      return nil
    end,
    intercept = function(item)
      if item and item.nav == "back" then
        pop()
        return true
      end
      return false
    end,
  }
end

-- One app, a child of the apps list. A successful remove or include pops once, landing back on
-- the apps list, which rebuilds with the app moved to or from the excluded tail.
buildAppChild = function(id, bundle, name, excluded)
  return {
    placeholder = "",
    -- search-exempt, Back and the one action for this app, a two row choice like a confirm with nothing to search
    matcher = false,
    rows = function() return appRows(name, excluded) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        pop()
        return true
      end
      if item.act == "exclude" or item.act == "include" then
        local ok, err = cfg.api[item.act](id, bundle)
        if ok then pop() else log.e(item.act .. " failed, " .. tostring(err)) end
        return true
      end
      return false
    end,
  }
end

-- The rename level, a child of a layout. Keyed on the id rather than on a name frozen when it was
-- built, so the level it pops back onto reads the new name off the api on its next rows call.
buildRenameChild = function(id)
  return {
    placeholder = "New name for this layout",
    -- search-exempt, the field is the layout's new name being typed, input and not a search
    matcher = false,
    rows = function(query) return renameRows(id, query) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        pop()
        return true
      end
      if item.act == "saveRename" then
        local ok, err = cfg.api.rename(id, item.newName)
        if ok then pop() else log.e("rename failed, " .. tostring(err)) end
        return true
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- Public control surface, dot called
--------------------------------------------------------------------------------

--- M.show() - present through the shared stage. cfg.stagePresent asks the registry for this
--- plugin's own presentation, the top level below, and hands it to the stage as a fresh stack, so
--- a reopen never resumes a previous drill.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("workspaces") end
end

--- M.rows(query) -> list. The top level's own row supplier, named on the manifest's presentation
--- block as the contract's rows.
M.rows = topRows

--- M.select(item) -> presentation or nil. The top level's own onSelect. New snapshot drills into
--- the name level, and a layout row applies the layout, since applying is what a layout is for and
--- everything else it offers is in the action panel, decided by Milos on 2026-10-29,
--- docs/PLAN-ACTION-PANEL.md. The disabled status rows never reach here.
function M.select(item)
  if not item then return nil end
  if item.nav == "new" then return buildNewChild() end
  if item.nav == "layout" then
    local ok, err = cfg.api.apply(item.id)
    if not ok then log.e("apply failed, " .. tostring(err)) end
  end
  return nil
end

--------------------------------------------------------------------------------
-- The action panel's verbs on a layout row, docs/PLAN-ACTION-PANEL.md
--------------------------------------------------------------------------------

-- The layout the highlighted row names, or nil. The panel runs a verb after putting the highlight
-- back on the row it was opened over, so this is the row the verb was chosen for.
local function highlightedLayout()
  local item = cfg.stageSelectedItem and cfg.stageSelectedItem()
  return type(item) == "table" and item.nav == "layout" and item.id or nil
end

local function redraw()
  if cfg.redrawPresented then cfg.redrawPresented("workspaces") end
end

--- M:isLayout(item) -> boolean. Whether the row the panel was opened over is a layout, which every
--- verb below needs. Colon called, since the root hands a surface method its module first.
function M:isLayout(item)
  return type(item) == "table" and item.nav == "layout"
end

--- M:updateLayout() - replaces what the highlighted layout records with the windows open now.
function M:updateLayout()
  local id = highlightedLayout()
  if not id then return end
  local ok, err = cfg.api.update(id)
  if not ok then log.e("update failed, " .. tostring(err)) end
  redraw()
end

--- M:editApps() - opens the highlighted layout's apps, where an app is left alone or taken back.
function M:editApps()
  local id = highlightedLayout()
  if id and cfg.stagePush then cfg.stagePush(buildAppsChild(id)) end
end

--- M:renameLayout() - opens the name field for the highlighted layout.
function M:renameLayout()
  local id = highlightedLayout()
  if id and cfg.stagePush then cfg.stagePush(buildRenameChild(id)) end
end

--- M:deleteLayout() - removes the highlighted layout, after the panel's own confirm.
function M:deleteLayout()
  local id = highlightedLayout()
  if not id then return end
  local ok, err = cfg.api.remove(id)
  if not ok then log.e("delete failed, " .. tostring(err)) end
  redraw()
end

--- M.placeholder() -> string. The field hint while the top level is current.
function M.placeholder()
  return "Search layouts"
end

--- M.scopeRows(rest) -> list. The launcher scoped to the layouts, the alias and a space, one
--- row per layout and choosing one applies it. This is the fast path, since applying is what a
--- layout is for and the manager above exists for everything else. A layout that cannot apply
--- here is still listed, disabled and saying what it needs, so the answer to why is it not
--- here is on the row rather than in a silence.
function M.scopeRows()
  local out = {}
  if not cfg.api.persists() then
    return { row("Nothing can be stored", "No place was given for layouts to live in", "warn", { noop = true }, false, true) }
  end
  for _, l in ipairs(cfg.api.list()) do
    if l.available then
      out[#out + 1] = row(l.name, "Apply, " .. countLabel(l.apps, "app", "apps") .. ", taken on " .. l.topology,
        "available", { id = l.id }, true)
    else
      out[#out + 1] = row(l.name, "Not here, it " .. l.reason, "unavailable", { noop = true }, false)
    end
  end
  if #out == 0 then
    out[#out + 1] = row("No layout to apply", "Open Workspaces and take a snapshot", "hint", { noop = true }, false, true)
  end
  return out
end

--- M.applyScoped(item) - the launcher's own scope.run, handed the item a scope row carries.
--- Identical to choosing Apply inside the manager, since a layout chosen through the scoped
--- list means exactly what Apply means there.
function M.applyScoped(item)
  if not item or not item.id then return end
  local ok, err = cfg.api.apply(item.id)
  if not ok then log.e("apply failed, " .. tostring(err)) end
end

--- M:configure(opts) - merge injected deps across the two callers. The plugin composition root
--- injects api, the one seam over the engine and the store. The wiring step injects the whole
--- options table, which is where stagePresent and stagePop arrive.
--
-- Colon here, not dot, because both callers reach this submodule as chooser:configure(opts), the
-- plugin root directly and lib/wire.lua through the declared step. self arrives as M and the body
-- never names it.
function M:configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

return M
