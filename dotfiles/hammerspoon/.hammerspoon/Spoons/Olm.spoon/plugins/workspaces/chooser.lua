--- === Workspaces.chooser ===
---
--- The inspect and prune surface, the command policy over the engine and the store. It is not
--- how windows get restored, the engine does that unasked, so this list exists to show what was
--- remembered and to let a person correct it. Look at the configurations, see which one you are
--- standing in, give one a name that means something, forget an app that is remembered somewhere
--- silly, drop a whole configuration you will never be at again, and force a restore on the
--- active one for the rare case where the geometry never changed so no episode ever opened.
---
--- Every level is a presentation table, built lazily and pushed the moment a row drills into it,
--- and the shared stage owns the one window all of them show into. Choosing a configuration,
--- Rename, Delete, Apps, or an app returns the level it leads to from select and the stage pushes
--- it, swapping the list in place with no window ever closing. Leaving a level, every Back row,
--- the confirm's own Keep, and the pop a successful rename, delete, or forget lands on, all ride
--- each level's own intercept instead, since a child returned from select can only ever push,
--- never pop, and cfg.stagePop is the one word that expresses leaving.
---
--- Delete pops twice in the same press, because a removed configuration leaves both the confirm
--- level and the configuration level naming it behind, stale, and a single pop would clear only
--- half of that. Forget pops once, landing back on the apps list, which rebuilds without the app
--- that was just dropped.
---
--- This file talks to the engine and the store only through the injected api table, so it is pure
--- policy. The plugin composition root in init.lua builds that api and owns everything the two
--- layers have to agree about.

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
  active = "🟢",
  config = "🖥️",
  apps = "📦",
  app = "🪟",
  restore = "🔄",
  rename = "✏️",
  delete = "🗑️",
  forget = "🚫",
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

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function countLabel(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

-- One configuration by fingerprint, read live off the api rather than carried as a stale copy, so
-- a rename lands on every level that names it without any of them being rebuilt.
local function configByFingerprint(fingerprint)
  for _, c in ipairs(cfg.api.list()) do
    if c.fingerprint == fingerprint then return c end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Per level row suppliers
--------------------------------------------------------------------------------

-- The top level, the configurations. The active one leads and is marked, since it is the one
-- every other level's actions are most likely meant for. A typed query filters by a case
-- insensitive substring on the name.
local function topRows(query)
  local q = (query or ""):lower()
  local out = {}
  if not cfg.api.persists() then
    out[#out + 1] = row("Nothing is being remembered across restarts",
      "Windows still return to place while this login lasts", ICON.warn, { noop = true }, false)
    return out
  end
  local list = cfg.api.list()
  if #list == 0 then
    out[#out + 1] = row("No configuration yet",
      "The first one appears once the displays have been read", ICON.hint, { noop = true }, false)
    return out
  end
  for _, c in ipairs(list) do
    if q == "" or c.name:lower():find(q, 1, true) then
      local sub = (c.active and "Attached now, " or "") .. countLabel(c.apps, "app remembered", "apps remembered")
      out[#out + 1] = row(c.name, sub, c.active and ICON.active or ICON.config,
        { nav = "configuration", fingerprint = c.fingerprint }, true)
    end
  end
  return out
end

-- A configuration. Back leads, per the chooser menu convention, so stepping out is the default and
-- a stray confirm on the fresh highlight steps back rather than doing anything. Restore now appears
-- only on the configuration attached right now, since replaying frames measured for a different
-- geometry onto this one would place windows nowhere useful.
local function configurationRows(fingerprint)
  local c = configByFingerprint(fingerprint)
  if not c then
    return { backRow(), row("Configuration is gone", "It may have been removed", ICON.warn, { noop = true }, false) }
  end
  local out = { backRow() }
  out[#out + 1] = row("Rename", "Give this configuration a name you will recognise", ICON.rename,
    { nav = "rename" }, true)
  out[#out + 1] = row("Delete", "Forget this configuration and everything remembered for it", ICON.delete,
    { nav = "delete" }, true)
  out[#out + 1] = row("Apps", countLabel(c.apps, "app remembered here", "apps remembered here"), ICON.apps,
    { nav = "apps" }, true)
  if c.active then
    out[#out + 1] = row("Restore now", "Put every window back where this configuration remembers it",
      ICON.restore, { act = "restore" }, true)
  end
  return out
end

-- The rename level. The search field is the new name, and the top row morphs to Save as the typed
-- name, disabled while the name is empty or already used so a confirm can never write a bad one.
-- Then Back.
local function renameRows(fingerprint, query)
  local c = configByFingerprint(fingerprint)
  local current = c and c.name or ""
  local newName = trim(query)
  local out = {}
  if newName == "" then
    out[#out + 1] = row("Type a new name", "Rename '" .. current .. "'", ICON.hint, { noop = true }, false)
  elseif newName ~= current and cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other configuration has", ICON.warn,
      { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. newName .. "'", "Rename '" .. current .. "'", ICON.save,
      { act = "saveRename", newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

-- The delete confirm. The safe choice leads, so the default highlight and a stray confirm keep the
-- configuration rather than remove it, and deleting takes a deliberate move down. Both names ride
-- in the titles, since a disabled header at the top would only be another row to move past.
local function deleteRows(fingerprint)
  local c = configByFingerprint(fingerprint)
  local name = c and c.name or ""
  return {
    row("Keep '" .. name .. "'", "Leave it as it is", ICON.no, { nav = "back" }, true),
    row("Delete '" .. name .. "'", "Forget this configuration and every app remembered for it",
      ICON.delete, { act = "delete" }, true),
  }
end

-- The apps of one configuration, each with the frame it is remembered at, so a window remembered
-- somewhere silly is visible as such before anybody decides to forget it.
local function appsRows(fingerprint)
  local out = { backRow() }
  local apps = cfg.api.apps(fingerprint)
  if #apps == 0 then
    out[#out + 1] = row("Nothing remembered here yet",
      "Move a window while this configuration is attached", ICON.hint, { noop = true }, false)
    return out
  end
  for _, a in ipairs(apps) do
    local f = a.frame
    local sub = string.format("%d by %d at %d, %d", f.w or 0, f.h or 0, f.x or 0, f.y or 0)
    out[#out + 1] = row(a.name, sub, ICON.app, { nav = "app", bundleID = a.bundleID, name = a.name }, true)
  end
  return out
end

-- One app. Back leads, so this level is safe to land on, and the one action it offers is the
-- destructive one, which is why it is a level of its own rather than a row on the list above.
local function appRows(name)
  return {
    backRow(),
    row("Forget '" .. name .. "'", "Stop remembering where this app's window goes here",
      ICON.forget, { act = "forget" }, true),
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

local buildRenameChild, buildDeleteChild, buildAppsChild, buildAppChild

-- The rename level, a child of a configuration. Keyed on the fingerprint rather than on a name
-- frozen when it was built, so nothing has to be corrected after a successful rename, the level
-- it pops back onto reads the new name off the api on its next rows call.
buildRenameChild = function(fingerprint)
  return {
    placeholder = "New name for this configuration",
    matcher = false,
    rows = function(query) return renameRows(fingerprint, query) end,
    -- select never actually answers here, every reachable row on this level is caught by
    -- intercept below, but the field is required on every presentation.
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "saveRename" then
        local ok, err = cfg.api.rename(fingerprint, item.newName)
        if ok then
          if cfg.stagePop then cfg.stagePop() end
        else
          log.e("rename failed, " .. tostring(err))
        end
        return true
      end
      return false
    end,
  }
end

-- The delete confirm, a child of a configuration. Keep leaves exactly like Back, both being the
-- same item, so one branch answers both. A successful delete pops twice in the same press, past
-- the confirm and past the configuration level naming something that no longer exists, landing on
-- the top level.
buildDeleteChild = function(fingerprint)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return deleteRows(fingerprint) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "delete" then
        local ok, err = cfg.api.remove(fingerprint)
        if ok then
          if cfg.stagePop then cfg.stagePop() end
          if cfg.stagePop then cfg.stagePop() end
        else
          log.e("delete failed, " .. tostring(err))
        end
        return true
      end
      return false
    end,
  }
end

-- The apps list, a child of a configuration. Nothing here mutates, so an app row is an ordinary
-- push through select and only Back rides the intercept.
buildAppsChild = function(fingerprint)
  return {
    placeholder = "Search remembered apps",
    matcher = false,
    rows = function() return appsRows(fingerprint) end,
    onSelect = function(item)
      if item and item.nav == "app" then return buildAppChild(fingerprint, item.bundleID, item.name) end
      return nil
    end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
end

-- One app, a child of the apps list. A successful forget pops once, landing back on the apps list,
-- which rebuilds without the app that was just dropped.
buildAppChild = function(fingerprint, bundleID, name)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return appRows(name) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "forget" then
        local ok, err = cfg.api.forget(fingerprint, bundleID)
        if ok then
          if cfg.stagePop then cfg.stagePop() end
        else
          log.e("forget failed, " .. tostring(err))
        end
        return true
      end
      return false
    end,
  }
end

-- A configuration, a child of the top level. Rename, Delete, and Apps are genuine levels, so each
-- answers through select and the stage pushes whatever comes back. Restore now is a completion
-- rather than a level, calling the engine and returning nothing, which is the meaning nil has
-- always had here, the whole stack tears down and the window goes away.
local function buildConfigurationChild(fingerprint)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return configurationRows(fingerprint) end,
    onSelect = function(item)
      if not item then return nil end
      if item.act == "restore" then
        cfg.api.restore()
        return nil
      end
      if item.nav == "rename" then return buildRenameChild(fingerprint) end
      if item.nav == "delete" then return buildDeleteChild(fingerprint) end
      if item.nav == "apps" then return buildAppsChild(fingerprint) end
      return nil
    end,
    intercept = function(item)
      if not item then return true end
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
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

--- M.select(item) -> presentation or nil. The top level's own onSelect. A configuration row drills
--- into a child of its own and every other row at this level, all of them disabled status rows,
--- never reaches here at all.
function M.select(item)
  if item and item.nav == "configuration" then return buildConfigurationChild(item.fingerprint) end
  return nil
end

--- M.placeholder() -> string. The field hint while the top level is current. Resolved once, at
--- register, since the presentation contract wants a plain string. Every child carries its own
--- instead, a plain field on a table built at runtime.
function M.placeholder()
  return "Search configurations"
end

--- M.refresh() - redraw the top level in place, so a configuration change landing while the list is
--- showing corrects the marker without waiting for a keystroke. Named with no token, so it targets
--- the top level specifically and is a silent no op while any child is what is actually showing,
--- which is correct, since no child reads the marker this redraw exists to correct and each is
--- rebuilt fresh the next time it is shown.
function M.refresh()
  if cfg.redrawPresented then cfg.redrawPresented("workspaces") end
end

--- M:configure(opts) - merge injected deps across the two callers. The plugin composition root
--- injects api, the one seam over the engine and the store. The wiring step injects the whole
--- options table, which is where stagePresent, stagePop, and redrawPresented arrive.
--
-- Colon here, not dot, because both callers reach this submodule as chooser:configure(opts), the
-- plugin root directly and lib/wire.lua through the declared step. self arrives as M and the body
-- never names it.
function M:configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

return M
