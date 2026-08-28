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
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an offscreen
-- canvas drawn once and cached by the string, since the supplier runs on every keystroke. A
-- false marks a string that cannot render, so it is attempted only once. This is the same
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

local ICON = {
  active = "🟢",
  profile = "🖥️",
  displays = "📺",
  reapply = "🔄",
  rename = "✏️",
  delete = "🗑️",
  capture = "➕",
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
  return row("Back", "", ICON.back, { nav = true, to = "back" }, true)
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
-- when the current arrangement matches no profile, which is the tool's notion of add new. A
-- typed query filters the profiles by a case insensitive substring on the name.
local function topRows(query)
  local q = (query or ""):lower()
  local out = {}
  local active = cfg.api.active()
  if not active then
    out[#out + 1] = row("Capture current arrangement", "The displays attached now match no profile",
      ICON.capture, { nav = true, to = "capture" }, true)
  end
  for _, p in ipairs(cfg.api.list()) do
    if q == "" or p.name:lower():find(q, 1, true) then
      local isActive = p.name == active
      local n = displayCount(p)
      local sub = (isActive and "Active, " or "") .. n .. (n == 1 and " display" or " displays")
      out[#out + 1] = row(p.name, sub, isActive and ICON.active or ICON.profile,
        { nav = true, to = "profile", name = p.name }, true)
    end
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

-- A profile screen. Back leads, per the chooser menu convention, so stepping out is the
-- default and Return on the fresh highlight steps back. Then the displays show straight away,
-- one read only row per monitor with resolution, id, refresh, and origin, the main display
-- marked, so there is no extra list displays step. The actions follow, Reapply only on the
-- active profile, and Rename and Delete only when the profile is captured. A curated profile
-- shows neither Rename nor Delete, since the tool never rewrites the hand maintained
-- config/displays.lua. The monitor rows are disabled, and a stray confirm on one stays put
-- rather than closing, since the Return tap routes even a disabled row through the in-place
-- enter.
local function profileRows(name)
  local p = profileByName(name)
  if not p then return { backRow(), row("Profile is gone", "It may have been removed", ICON.warn, { noop = true }, false) } end
  local out = { backRow() }
  for _, d in ipairs(cfg.api.displays(p.command)) do
    local title = (d.res or "?") .. (d.main and "   (main)" or "")
    local sub = "id " .. d.id .. (d.hz and (", " .. d.hz .. "hz") or "") .. ", origin (" .. d.origin .. ")"
    out[#out + 1] = row(title, sub, ICON.displays, { noop = true }, false)
  end
  if name == cfg.api.active() then
    out[#out + 1] = row("Reapply this arrangement", "Force it back if macOS scrambled the layout",
      ICON.reapply, { act = "reapply" }, true)
  end
  if p.editable then
    out[#out + 1] = row("Rename", "Change the name of this captured profile", ICON.rename,
      { nav = true, to = "rename", name = name }, true)
    out[#out + 1] = row("Delete", "Remove this captured profile", ICON.delete,
      { nav = true, to = "delete", name = name }, true)
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
    out[#out + 1] = row("Type a new name", "Rename '" .. name .. "'", ICON.hint, { noop = true }, false)
  elseif newName ~= name and cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other profile has", ICON.warn, { noop = true }, false)
  else
    out[#out + 1] = row("Save as '" .. newName .. "'", "Rename '" .. name .. "'", ICON.save,
      { act = "saveRename", name = name, newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

-- The delete confirm screen. The safe choice leads, so the default highlight and a stray
-- Return keep the profile rather than remove it, and deleting takes a deliberate move down.
-- The names ride in the titles since there is no room for a disabled header at the top, which
-- would otherwise catch the default Return and close the chooser.
local function deleteRows(name)
  return {
    row("Keep '" .. name .. "'", "Leave it as it is", ICON.no, { nav = true, to = "back" }, true),
    row("Delete '" .. name .. "'", "Remove this captured profile for good", ICON.delete, { act = "delete", name = name }, true),
  }
end

-- The capture screen. The search field names the new profile, and the top row morphs to
-- Capture as the typed name, disabled while the name is empty or already used. Then Back.
local function captureRows(query)
  local newName = trim(query)
  local out = {}
  if newName == "" then
    out[#out + 1] = row("Type a name", "Name this display arrangement", ICON.hint, { noop = true }, false)
  elseif cfg.api.exists(newName) then
    out[#out + 1] = row("Name already used", "Choose a name no other profile has", ICON.warn, { noop = true }, false)
  else
    out[#out + 1] = row("Capture as '" .. newName .. "'", "Save the arrangement attached now", ICON.save,
      { act = "capture", newName = newName }, true)
  end
  out[#out + 1] = backRow()
  return out
end

--------------------------------------------------------------------------------
-- Child levels, built lazily and pushed the moment a row drills into one
--------------------------------------------------------------------------------

-- Every child below shares this one shape. rows reads whatever this level names, matcher
-- stands the shared strategy down for the identical reason the retired single instance
-- always did, its own supplier morphing rows from the query and the level rather than
-- filtering a fixed list, and intercept is where a level that mutates the list it is on, or
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

-- The delete confirm screen, a child of a profile screen. Keep leaves exactly like Back,
-- both being the same { nav = true, to = "back" } item, so one branch answers both. A
-- successful delete pops twice in the same press, past the delete frame and past the
-- profile screen naming a profile that no longer exists, landing on top the identical place
-- the retired stack = { { kind = "top" } } always did.
local function buildDeleteChild(state)
  return {
    placeholder = "",
    matcher = false,
    rows = function() return deleteRows(state.name) end,
    onSelect = function() end,
    intercept = function(item)
      if not item then return true end
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "delete" then
        local ok, err = cfg.api.remove(item.name)
        if ok then
          -- Review finding L2, rework, counted honestly rather than left silent. Each
          -- Stage:pop below runs _show's own swap branch, setQuery("") then refresh(true),
          -- and this atom's own key watcher runs a further refresh(true) of its own once
          -- this whole intercept answers true, native.lua:_intercept's documented contract
          -- for any consumer that answers yes. So landing on top from here costs three
          -- rebuilds for one keypress, not the two an ordinary single pop already costs
          -- every other Back row in this file. All three are correct, cheap, and no
          -- reader would see the difference, so this stays as it is rather than being
          -- reworked to save microseconds nothing measures, but the true count belongs in
          -- the comment rather than the two either call would suggest alone.
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

-- The profile screen, a child of the top level. state is the one mutable table this level's
-- own rows reads, { name = ... }, which its own rename child corrects in place on success
-- rather than this level being rebuilt, so popping back after a rename lands on a level that
-- already answers for the new name.
local function buildProfileChild(name)
  local state = { name = name }
  return {
    placeholder = "",
    matcher = false,
    rows = function() return profileRows(state.name) end,
    -- Rename and Delete are genuine levels, so each answers through select, the ordinary
    -- child push decision one describes, host/stage pushing whatever comes back. Reapply is
    -- a genuine completion instead, not a level, calling the engine and returning nothing,
    -- the ordinary meaning this contract has always given nil, the whole stack tears down,
    -- closing the tool for good exactly as the retired chooser:hide() always did.
    onSelect = function(item)
      if not item then return nil end
      if item.act == "reapply" then
        cfg.api.reapply()
        return nil
      end
      if item.nav and item.to == "rename" then return buildRenameChild(state) end
      if item.nav and item.to == "delete" then return buildDeleteChild(state) end
      return nil
    end,
    -- Back is the one row on this level that leaves rather than drills or completes, decision
    -- three's reserved case, so it alone answers through intercept, cfg.stagePop leaving the
    -- level the row was pressed on and the parent, the top level, standing in its place.
    intercept = function(item)
      -- The disabled row guard once written here by hand is gone, review findings H1 and
      -- H2, rework, host/stage's own _intercept answering true and doing nothing for any
      -- disabled row before this is ever asked.
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
  if item.nav and item.to == "profile" then return buildProfileChild(item.name) end
  if item.nav and item.to == "capture" then return buildCaptureChild() end
  return nil
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
