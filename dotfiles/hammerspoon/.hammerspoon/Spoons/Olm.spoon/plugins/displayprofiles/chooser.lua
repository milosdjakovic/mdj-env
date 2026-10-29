--- === DisplayProfiles.chooser ===
---
--- The inspect and manage surface, the command policy over the engine and the store. It is
--- not an applier. The engine already reapplies the matching profile on every screen change
--- and only one profile ever matches the attached displays, so there is nothing to switch
--- between. This surface lets you look at what exists, capture a new arrangement when the
--- current one is unsaved, rename and delete the captured ones, and force a reapply on the
--- active profile for the rare case where macOS scrambled the layout with no hardware change
--- so no screen event fired.
---
--- Migrated onto host/stage, contract v3, docs/BRIEF-CONTRACT-V3.md. Each level of the menu
--- is now its own presentation table, built lazily and pushed as a child the moment a row
--- drills into it, rather than one instance driven as a hand kept stack of frames. Choosing a
--- profile, Rename, Delete, or Capture returns the level it leads to from select, and
--- host/stage pushes it, swapping the shared window in place with no window ever closing.
--- Leaving a level, the Back row, the delete confirm's own Keep, and the pop a successful
--- rename, delete, or capture lands on, all ride each level's own intercept instead, decision
--- three's reserved case, a row that mutates the list it is on and stands, the mutation here
--- being that the level standing after the row runs is the parent rather than the child,
--- reached through cfg.stagePop, contract v3's own addition for exactly this. Delete pops
--- twice in the same press, since a removed profile leaves both the delete frame and the
--- profile screen naming it behind, stale, in the same motion a single pop would only clear
--- half of. The private Return swallowing eventtap, the hand kept frame stack, and the zero
--- timer re-show the click path used to need are all gone, since intercept is asked before
--- Return, insertSelected, and a click alike are ever let through to a real completion, the
--- one gate capable of keeping the window open through a swap at all, so nothing here has to
--- reimplement what that gate already promises.
---
--- The attached display set is cached in the engine and cleared on a screen change, so the
--- row supplier, which asks the engine which profile is active on every keystroke, never
--- shells out to displayplacer while you type.
---
--- This file talks to the engine and the store only through the injected api table, so it
--- is pure policy. The spoon composition root in init.lua builds that api by merging the
--- curated profiles with the captured ones and owns the rebuild after a write.

local M = { name = "DisplayProfiles.chooser" }

local log = hs.logger.new("DisplayProfiles", "info")

local cfg = {}        -- injected across two calls: api from the spoon, view deps from the root


--------------------------------------------------------------------------------
-- Small row builders
--------------------------------------------------------------------------------

-- Every row searches its title alone. A subtitle here is a status or a sentence about what the
-- row does, "Active, 2 displays", and searched it would let active or displays match rows that
-- are not named so, so filterText is the title, the vocabulary in lib/chooser/rank.lua.
local function row(title, subTitle, icon, item, enabled, pinned)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled,
    filterText = title, pinned = pinned }
end

-- Back is pinned, so on a level that searches it is never scored or dropped, and under a typed
-- query it trails the matches so Enter takes the best one. Where a level keeps matcher false the
-- flag changes nothing.
local function backRow()
  return row("Back", "", "back", { nav = true, to = "back" }, true, true)
end

-- A profile's display count, read from its command, for the list subtitles.
local function displayCount(p)
  return #cfg.api.displays(p.command)
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--------------------------------------------------------------------------------
-- Per screen row suppliers
--------------------------------------------------------------------------------

-- Top level, the profile list. The active profile is marked, and a capture row appears only
-- when the current arrangement matches no profile, which is the tool's notion of add new. It
-- is pinned, so no query drops it, and it leads the resting list and trails the matches once
-- something is typed, so Enter on a typed name opens that profile. The shared search filters
-- and ranks the profiles by name, so this supplier returns every one.
local function topRows()
  local out = {}
  local active = cfg.api.active()
  if not active then
    out[#out + 1] = row("Capture current arrangement", "The displays attached now match no profile",
      "capture", { nav = true, to = "capture" }, true, true)
  end
  for _, p in ipairs(cfg.api.list()) do
    local isActive = p.name == active
    local n = displayCount(p)
    local sub = (isActive and "Active, " or "") .. n .. (n == 1 and " display" or " displays")
    out[#out + 1] = row(p.name, sub, isActive and "active" or "profile",
      { nav = true, to = "profile", name = p.name }, true)
  end
  return out
end

-- Find a merged profile by name, so a menu frame can read its command and editability from
-- the live list rather than carrying a stale copy.
local function profileByName(name)
  for _, p in ipairs(cfg.api.list()) do
    if p.name == name then return p end
  end
  return nil
end

-- The displays of one profile, opened by the Displays verb of the action panel. Back leads, then
-- one read only row per monitor with resolution, id, refresh, and origin, the main display marked.
-- The monitor rows are disabled, so a stray Return on one stays put.
local function displaysRows(name)
  local p = profileByName(name)
  if not p then return { backRow(), row("Profile is gone", "It may have been removed", "warn", { noop = true }, false, true) } end
  local out = { backRow() }
  for _, d in ipairs(cfg.api.displays(p.command)) do
    local title = (d.res or "?") .. (d.main and "   (main)" or "")
    local sub = "id " .. d.id .. (d.hz and (", " .. d.hz .. "hz") or "") .. ", origin (" .. d.origin .. ")"
    out[#out + 1] = row(title, sub, "displays", { noop = true }, false)
  end
  return out
end

-- The rename screen. The search field is the new name entry, and the top row morphs to
-- Save as the typed name, disabled while the name is empty or already used so Return can
-- never write a bad rename. Then Back.
local function renameRows(name, query)
  local newName = trim(query)
  local out = {}
  if newName == "" then
    out[#out + 1] = row("Type a new name", "Rename '" .. name .. "'", "hint", { noop = true }, false)
  elseif newName ~= name and cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other profile has", "warn", { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. newName .. "'", "Rename '" .. name .. "'", "save",
      { act = "saveRename", name = name, newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

-- The capture screen. The search field names the new profile, and the top row morphs to
-- Capture as the typed name, disabled while the name is empty or already used. Then Back.
local function captureRows(query)
  local newName = trim(query)
  local out = {}
  if newName == "" then
    out[#out + 1] = row("Type a name", "Name this display arrangement", "hint", { noop = true }, false)
  elseif cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other profile has", "warn", { noop = true }, false)
  else
    out[#out + 1] = row("Capture as '" .. newName .. "'", "Save the arrangement attached now", "save",
      { act = "capture", newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

--------------------------------------------------------------------------------
-- Child levels, built lazily and pushed the moment a row drills into one
--------------------------------------------------------------------------------

-- Every child below shares this one shape. rows reads whatever this level names, matcher is
-- false only on a level whose field is input, a typed name or a confirm, and a level that is
-- a list inherits the shared search, and intercept is where a level that mutates the list it is on, or
-- leaves it for its parent, answers for itself. A level with nothing to mutate and nowhere
-- to leave from a row, profile and top among them, simply declares no intercept, exactly as
-- an ordinary presentation with none already does, backspace still reaching the parent
-- through host/stage's own Stage:pop.

-- The rename screen, a child of a profile screen. name is the profile being renamed, over a
-- shared upvalue rather than a value frozen at creation, so a successful rename can correct
-- what the profile screen it pops back onto reads without rebuilding that screen's own
-- presentation table.
local function buildRenameChild(state)
  return {
    placeholder = "New name for '" .. state.name .. "'",
    -- search-exempt, the field is the profile's new name being typed, input and not a search
    matcher = false,
    rows = function(query) return renameRows(state.name, query) end,
    -- select never actually answers, every reachable row on this level is caught by
    -- intercept below, back and the one real action alike, but the field is required on
    -- every presentation, host/stage's own isPresentation refusing one without it.
    onSelect = function() end,
    intercept = function(item)
      -- The disabled row guard once written here by hand is gone, review findings H1 and
      -- H2, rework, host/stage's own _intercept answering true and doing nothing for any
      -- disabled row before this is ever asked.
      if not item then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "saveRename" then
        local ok, err = cfg.api.rename(item.name, item.newName)
        if ok then
          -- Corrects the shared upvalue so the profile screen this pops back onto, which
          -- reads state.name on every rows() call rather than a name frozen when it was
          -- built, shows the renamed profile at once rather than answering "Profile is
          -- gone" for a name that no longer resolves.
          state.name = item.newName
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

-- The displays screen, pushed by the Displays verb of the action panel. Nothing here acts, so
-- Back is the one row that answers, leaving for the top level.
local function buildDisplaysChild(name)
  return {
    placeholder = "",
    rows = function() return displaysRows(name) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
end

-- The capture screen, a child of the top level.
local function buildCaptureChild()
  return {
    placeholder = "Name this arrangement",
    -- search-exempt, the field is the captured arrangement's name being typed, input and not a search
    matcher = false,
    rows = captureRows,
    onSelect = function() end,
    intercept = function(item)
      -- The disabled row guard once written here by hand is gone, review findings H1 and
      -- H2, rework, host/stage's own _intercept answering true and doing nothing for any
      -- disabled row before this is ever asked.
      if not item then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "capture" then
        local ok, err = cfg.api.capture(item.newName)
        if ok then
          if cfg.stagePop then cfg.stagePop() end
        else
          log.e("capture failed, " .. tostring(err))
        end
        return true
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.show() - present through the shared stage. cfg.stagePresent asks the registry for
--- this plugin's own presentation, the top level below, and hands it to Stage:present,
--- always a fresh stack, so a reopen from the launcher or this plugin's own launcher row
--- never resumes a previous drill.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("displayProfiles") end
end

--- M.rows(query) -> list. The top level's own row supplier, named on the manifest's own
--- presentation block as the contract's rows.
M.rows = topRows

--- M.select(item) -> presentation or nil. The top level's own onSelect, named on the
--- manifest's own presentation block. A profile row or the capture row drills into a child
--- of its own, host/stage pushing whatever is answered, and every other row, none existing
--- at this level, answers nothing.
function M.select(item)
  if not item then return nil end
  -- Return on a profile applies it, decided by Milos on 2026-10-29, docs/PLAN-ACTION-PANEL.md,
  -- and what else a profile offers is in the action panel. Only the profile matching the attached
  -- displays can take effect, so Return reapplies that one, what Reapply did, and on any other it
  -- runs nothing against monitors that are not there and says why in the console.
  if item.nav and item.to == "profile" then
    if item.name == cfg.api.active() then
      cfg.api.reapply()
    else
      log.i("'" .. tostring(item.name) .. "' was not applied, its displays are not the ones attached")
    end
    return nil
  end
  if item.nav and item.to == "capture" then return buildCaptureChild() end
  return nil
end

--------------------------------------------------------------------------------
-- The action panel's verbs on a profile row, docs/PLAN-ACTION-PANEL.md
--------------------------------------------------------------------------------

-- The profile the highlighted row names, or nil. The panel runs a verb after putting the
-- highlight back on the row it was opened over, so this is the row the verb was chosen for.
local function highlightedProfile()
  local item = cfg.stageSelectedItem and cfg.stageSelectedItem()
  return type(item) == "table" and item.to == "profile" and item.name or nil
end

--- M:isProfile(item) -> boolean. Whether the panel was opened over a profile row. Colon called,
--- since the root hands a surface method its module first.
function M:isProfile(item)
  return type(item) == "table" and item.to == "profile"
end

--- M:isCaptured(item) -> boolean. Whether that profile was captured here and so can be renamed
--- or deleted. A curated one never is, since the tool never rewrites config/displays.lua.
function M:isCaptured(item)
  if not M:isProfile(item) then return false end
  local p = profileByName(item.name)
  return p ~= nil and p.editable == true
end

--- M:showDisplays() - opens the highlighted profile's displays.
function M:showDisplays()
  local name = highlightedProfile()
  if name and cfg.stagePush then cfg.stagePush(buildDisplaysChild(name)) end
end

--- M:renameProfile() - opens the name field for the highlighted captured profile.
function M:renameProfile()
  local name = highlightedProfile()
  if name and cfg.stagePush then cfg.stagePush(buildRenameChild({ name = name })) end
end

--- M:deleteProfile() - removes the highlighted captured profile, after the panel's own confirm.
function M:deleteProfile()
  local name = highlightedProfile()
  if not name then return end
  local ok, err = cfg.api.remove(name)
  if not ok then log.e("delete failed, " .. tostring(err)) end
  M.refresh()
end

--- M.placeholder() -> string. The field hint while the top level is current, named on the
--- manifest's own presentation block. Resolved once, at register, since the presentation
--- contract wants a plain string a presentation carries rather than a function to call
--- again later. Every child below carries its own instead, a plain field on a table built
--- at runtime rather than something the registrar ever resolves.
function M.placeholder()
  return "Search profiles"
end

--- M.refresh() - redraw the top level in place, so a screen change that lands while the
--- profile list itself is showing updates the active marker without waiting for a
--- keystroke. Migrated onto host/stage, cfg.redrawPresented replacing the direct
--- chooser:refresh() this used to call on an instance it held itself. Named with no token,
--- review finding M2, rework, so it targets the top level specifically, host/stage
--- comparing by table identity against the registrar's own stored presentation for
--- "displayProfiles" rather than matching the shared name at any depth, and it is a silent
--- no op while a child, a profile, rename, delete, or capture screen, is what is actually
--- showing, narrower than before this rework, since none of those screens reads the marker
--- this redraw exists to correct, and each is rebuilt fresh the moment it is next shown
--- regardless.
function M.refresh()
  if cfg.redrawPresented then cfg.redrawPresented("displayProfiles") end
end

-- isShowing, hide, selectNext, selectPrev, insertSelected, and enter are gone, the trickle
-- migration, deleted along with the Chooser.new block, the private Return swallowing
-- eventtap, the hand kept frame stack, and the zero timer re-show that gave them something
-- to answer for. The composition root now routes this plugin's own navigation through
-- host/stage's own surfaceFor once wiredRegistry.presentationFor("displayProfiles") answers
-- a presentation, which answers insertSelected directly, reaching the atom's own real
-- completion path, intercept asked first exactly as every other row on every level already
-- is.

--- M:configure(opts) - merge injected deps across the two callers. The spoon composition
--- root injects `api`, the merged view over the engine and the store. The main root injects
--- stagePresent, stagePop, and redrawPresented, the root published words this
--- migration needs. Builds no chooser any more, the trickle migration, so theme and the
--- Chooser factory are no longer read here.
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
