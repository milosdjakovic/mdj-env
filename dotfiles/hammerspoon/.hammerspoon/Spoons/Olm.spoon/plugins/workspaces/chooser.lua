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
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an offscreen canvas
-- drawn once and cached by the string, since the supplier runs on every keystroke. A false marks
-- a string that cannot render, so it is attempted only once. This is the same helper the other
-- choosers use.
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
  available = "🟢",
  unavailable = "⚪",
  new = "📸",
  apply = "🪟",
  apps = "📦",
  app = "🪟",
  update = "🔄",
  rename = "✏️",
  delete = "🗑️",
  remove = "🚫",
  include = "✅",
  save = "💾",
  no = "↩️",
  back = "⬅️",
  hint = "⌨️",
  warn = "⚠️",
}

--------------------------------------------------------------------------------
-- Small row builders
--------------------------------------------------------------------------------

local function row(title, subTitle, icon, item, enabled)
  return { title = title, subTitle = subTitle, image = emojiImage(icon), item = item, enabled = enabled }
end

local function backRow()
  return row("Back", "", ICON.back, { nav = "back" }, true)
end

-- One app row, carrying the app's own icon from the api rather than the generic emoji mark, so
-- the Apps list reads at a glance the way the launcher and the other choosers already do.
local function appRow(title, subTitle, icon, item)
  return { title = title, subTitle = subTitle, image = icon or emojiImage(ICON.app), item = item, enabled = true }
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function countLabel(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

local function matches(text, q)
  return q == "" or text:lower():find(q, 1, true) ~= nil
end

local function pop()
  if cfg.stagePop then cfg.stagePop() end
end

--------------------------------------------------------------------------------
-- Per level row suppliers
--------------------------------------------------------------------------------

-- The top level. New snapshot leads, since taking one is the reason to open this at all on a
-- fresh machine, then every layout, the ones that apply here first. A typed query filters by a
-- case insensitive substring on the name, and the snapshot row stays while it matches too.
local function topRows(query)
  local q = trim(query):lower()
  local out = {}
  if not cfg.api.persists() then
    out[#out + 1] = row("Nothing can be stored", "No file was given for layouts to live in",
      ICON.warn, { noop = true }, false)
    return out
  end
  if matches("New snapshot", q) then
    out[#out + 1] = row("New snapshot", "Record where every window sits on " .. cfg.api.here(),
      ICON.new, { nav = "new" }, true)
  end
  for _, l in ipairs(cfg.api.list()) do
    if matches(l.name, q) then
      local sub
      if l.available then
        sub = "Applies here, " .. countLabel(l.apps, "app", "apps") .. ", taken on " .. l.topology
      else
        sub = "Not here, it " .. l.reason .. ", taken on " .. l.topology
      end
      out[#out + 1] = row(l.name, sub, l.available and ICON.available or ICON.unavailable,
        { nav = "layout", id = l.id }, true)
    end
  end
  if #out == 0 then
    out[#out + 1] = row("No layout matches", "", ICON.hint, { noop = true }, false)
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
      ICON.hint, { noop = true }, false)
  elseif cfg.api.exists(name) then
    out[#out + 1] = row("Name already used", "Choose a name no other layout has", ICON.warn,
      { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. name .. "'", "Record where every window sits now", ICON.save,
      { act = "create", name = name }, true)
  end
  out[#out + 1] = backRow()
  return out
end

-- A layout. Back leads, per the chooser menu convention, so a stray confirm on the fresh
-- highlight steps back rather than doing anything. Apply is next, since that is what a layout is
-- for, and it is a disabled row saying why when the displays it needs are not attached.
local function layoutRows(id)
  local l = cfg.api.get(id)
  if not l then
    return { backRow(), row("Layout is gone", "It may have been deleted", ICON.warn, { noop = true }, false) }
  end
  local out = { backRow() }
  if l.available then
    out[#out + 1] = row("Apply", "Place the windows that are open now, closed apps stay closed",
      ICON.apply, { act = "apply" }, true)
  else
    out[#out + 1] = row("Cannot apply here", "It " .. l.reason .. ", taken on " .. l.topology,
      ICON.warn, { noop = true }, false)
  end
  local appsSub = countLabel(l.apps, "app", "apps")
  if l.excluded > 0 then appsSub = appsSub .. ", " .. countLabel(l.excluded, "excluded", "excluded") end
  out[#out + 1] = row("Apps", appsSub, ICON.apps, { nav = "apps" }, true)
  out[#out + 1] = row("Update snapshot", "Replace what is recorded with the windows open now, taken " .. (l.taken or "?"),
    ICON.update, { act = "update" }, true)
  out[#out + 1] = row("Rename", "Give this layout a different name", ICON.rename, { nav = "rename" }, true)
  out[#out + 1] = row("Delete", "Remove this layout for good", ICON.delete, { nav = "delete" }, true)
  return out
end

-- The apps of one layout, included first and the excluded as a tail, each saying where its
-- windows sit so an app recorded somewhere silly is visible as such before anybody prunes it.
local function appsRows(id)
  local out = { backRow() }
  local apps = cfg.api.apps(id)
  if #apps == 0 then
    out[#out + 1] = row("Nothing recorded here", "Update the snapshot with some windows open",
      ICON.hint, { noop = true }, false)
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
        ICON.include, { act = "include" }, true),
    }
  end
  return {
    backRow(),
    row("Remove '" .. name .. "'", "Leave this app alone when this layout is applied",
      ICON.remove, { act = "exclude" }, true),
  }
end

-- The rename level. Same shape as the name level for a new snapshot.
local function renameRows(id, query)
  local l = cfg.api.get(id)
  local current = l and l.name or ""
  local newName = trim(query)
  local out = {}
  if newName == "" then
    out[#out + 1] = row("Type a new name", "Rename '" .. current .. "'", ICON.hint, { noop = true }, false)
  elseif newName ~= current and cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other layout has", ICON.warn,
      { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. newName .. "'", "Rename '" .. current .. "'", ICON.save,
      { act = "saveRename", newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

-- The delete confirm. The safe choice leads, so the default highlight and a stray confirm keep
-- the layout rather than remove it, and deleting takes a deliberate move down.
local function deleteRows(id)
  local l = cfg.api.get(id)
  local name = l and l.name or ""
  return {
    row("Keep '" .. name .. "'", "Leave it as it is", ICON.no, { nav = "back" }, true),
    row("Delete '" .. name .. "'", "Remove this layout for good", ICON.delete, { act = "delete" }, true),
  }
end

--------------------------------------------------------------------------------
-- Child levels, built lazily and pushed the moment a row drills into one
--------------------------------------------------------------------------------

-- Every child below shares one shape. rows reads whatever the level names, matcher stands the
-- shared strategy down because each supplier either filters itself or morphs its rows from the
-- query, and intercept is where a level that leaves for its parent answers for itself. The
-- disabled row guard is never written by hand, the stage's own gate answering for any row built
-- with enabled false before a presentation is ever asked.

local buildLayoutChild, buildAppsChild, buildAppChild, buildRenameChild, buildDeleteChild

-- The name level for a new snapshot, a child of the top level. Save is answered from select
-- rather than intercept, because it is the one row that leaves this level and arrives at another
-- in the same press. The pop happens first, so the layout child returned below stacks on the top
-- level rather than on a name field that no longer has a purpose.
local function buildNewChild()
  return {
    placeholder = "Name for this snapshot",
    matcher = false,
    rows = newRows,
    onSelect = function(item)
      if item and item.act == "create" then
        local id, err = cfg.api.create(item.name)
        if not id then
          log.e("snapshot failed, " .. tostring(err))
          return nil
        end
        pop()
        return buildLayoutChild(id)
      end
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

-- A layout, a child of the top level. Apps, Rename, and Delete are genuine levels, so each
-- answers through select and the stage pushes whatever comes back. Apply is a completion, it
-- places the windows and returns nothing, so the window goes away and the report is what is
-- left. Update mutates the list it stands on, the app count and the taken time both change, so
-- it answers stay from intercept and the highlight holds on the row just chosen.
buildLayoutChild = function(id)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return layoutRows(id) end,
    onSelect = function(item)
      if not item then return nil end
      if item.act == "apply" then
        local ok, err = cfg.api.apply(id)
        if not ok then log.e("apply failed, " .. tostring(err)) end
        return nil
      end
      if item.nav == "apps" then return buildAppsChild(id) end
      if item.nav == "rename" then return buildRenameChild(id) end
      if item.nav == "delete" then return buildDeleteChild(id) end
      return nil
    end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        pop()
        return true
      end
      if item.act == "update" then
        local ok, err = cfg.api.update(id)
        if not ok then log.e("update failed, " .. tostring(err)) end
        return "stay"
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
    matcher = false,
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

-- The delete confirm, a child of a layout. Keep leaves exactly like Back. A successful delete
-- pops twice in the same press, past the confirm and past the layout level naming something that
-- no longer exists, landing on the top level.
buildDeleteChild = function(id)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return deleteRows(id) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        pop()
        return true
      end
      if item.act == "delete" then
        local ok, err = cfg.api.remove(id)
        if ok then
          pop()
          pop()
        else
          log.e("delete failed, " .. tostring(err))
        end
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

--- M.select(item) -> presentation or nil. The top level's own onSelect. New snapshot and each
--- layout row drill into a child of their own, and the disabled status rows never reach here.
function M.select(item)
  if not item then return nil end
  if item.nav == "new" then return buildNewChild() end
  if item.nav == "layout" then return buildLayoutChild(item.id) end
  return nil
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
function M.scopeRows(rest)
  local q = trim(rest):lower()
  local out = {}
  if not cfg.api.persists() then
    return { row("Nothing can be stored", "No place was given for layouts to live in", ICON.warn, { noop = true }, false) }
  end
  for _, l in ipairs(cfg.api.list()) do
    if matches(l.name, q) then
      if l.available then
        out[#out + 1] = row(l.name, "Apply, " .. countLabel(l.apps, "app", "apps") .. ", taken on " .. l.topology,
          ICON.available, { id = l.id }, true)
      else
        out[#out + 1] = row(l.name, "Not here, it " .. l.reason, ICON.unavailable, { noop = true }, false)
      end
    end
  end
  if #out == 0 then
    out[#out + 1] = row("No layout to apply", "Open Workspaces and take a snapshot", ICON.hint, { noop = true }, false)
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
