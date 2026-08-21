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
--- One native chooser, driven as a nested menu stack, not a chain of separate chooser
--- instances. A stack of frames names where you are, the row supplier reads the top frame
--- and the live query, and selecting a row either navigates (push or pop a frame) or runs a
--- terminal action. The native chooser closes itself whenever a row is chosen, which is why
--- a drill in cannot keep it open, so a navigation selection re-shows the one instance at
--- the new level. This is the same re-show a flat list would avoid, done on
--- purpose here because the tool is genuinely a menu. Escape and a click away close for
--- real, which resets the stack to the top for the next open.
---
--- The attached display set is cached in the engine and cleared on a screen change, so the
--- row supplier, which asks the engine which profile is active on every keystroke, never
--- shells out to displayplacer while you type.
---
--- This file talks to the engine and the store only through the injected api table, so it
--- is pure policy. The spoon composition root in init.lua builds that api by merging the
--- curated profiles with the captured ones and owns the rebuild after a write. The theme,
--- the Chooser factory, and the docked shortcut panel callbacks are injected by the main
--- root, the same way the other choosers receive them.

local M = { name = "DisplayProfiles.chooser" }

local log = hs.logger.new("DisplayProfiles", "info")

local cfg = {}        -- injected across two calls: api from the spoon, view deps from the root
local chooser = nil   -- the one native Chooser instance
local stack = nil     -- the menu stack, stack[#stack] is the current frame
local reopen = false  -- set by a click selection so onClose re-shows instead of ending
local returnTap = nil -- swallows Return while open so a menu step stays in place, no re-show
-- The pending re-show, held until it fires. A Hammerspoon timer is userdata whose finalizer
-- stops it, so one nothing refers to can be collected before it runs, and the menu would
-- then close on a click that was meant to step into it. Only one re-show is ever pending,
-- because the reopen flag above is cleared before this is armed.
local reopenTimer = nil

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
  local q = query:lower()
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

-- The one supplier the chooser calls, dispatched on the current frame.
local function rows(query)
  query = query or ""
  local top = stack[#stack]
  if top.kind == "profile" then return profileRows(top.name) end
  if top.kind == "rename" then return renameRows(top.name, query) end
  if top.kind == "delete" then return deleteRows(top.name) end
  if top.kind == "capture" then return captureRows(query) end
  return topRows(query)
end

--------------------------------------------------------------------------------
-- Placeholder chrome, set per frame after each show
--------------------------------------------------------------------------------

local function placeholderFor(top)
  if top.kind == "rename" then return "New name for '" .. top.name .. "'" end
  if top.kind == "capture" then return "Name this arrangement" end
  if top.kind == "top" then return "Search profiles" end
  return ""
end

--------------------------------------------------------------------------------
-- Selection dispatch, shared by the in-place path and the click fallback
--------------------------------------------------------------------------------

local function frameFor(item)
  if item.to == "profile" then return { kind = "profile", name = item.name } end
  if item.to == "rename" then return { kind = "rename", name = item.name } end
  if item.to == "delete" then return { kind = "delete", name = item.name } end
  if item.to == "capture" then return { kind = "capture" } end
  return { kind = "top" }
end

-- Apply the chosen item to the stack and return where the chooser should go next, "stay" to
-- remain open at the resulting frame or "close" to end. A disabled hint stays. A navigation
-- row pushes or pops a frame. A terminal action calls the api, and on success sends the stack
-- to where it should land, the top after a capture or delete, the renamed profile's menu
-- after a rename, and Reapply closes for good. A failed write logs and stays on the screen so
-- nothing is lost. This decides only the stack, the two callers decide how to move there.
local function applySelection(item)
  if not item or item.noop then return "stay" end

  if item.nav then
    if item.to == "back" then
      if #stack > 1 then table.remove(stack) end
    else
      stack[#stack + 1] = frameFor(item)
    end
    return "stay"
  end

  if item.act == "reapply" then
    cfg.api.reapply()
    return "close"
  end

  if item.act == "capture" then
    local ok, err = cfg.api.capture(item.newName)
    if ok then stack = { { kind = "top" } } else log.e("capture failed, " .. tostring(err)) end
    return "stay"
  end

  if item.act == "saveRename" then
    local ok, err = cfg.api.rename(item.name, item.newName)
    if ok then
      table.remove(stack) -- pop the rename frame
      stack[#stack] = { kind = "profile", name = item.newName } -- the profile menu, renamed
    else
      log.e("rename failed, " .. tostring(err))
    end
    return "stay"
  end

  if item.act == "delete" then
    local ok, err = cfg.api.remove(item.name)
    if ok then stack = { { kind = "top" } } else log.e("delete failed, " .. tostring(err)) end
    return "stay"
  end

  return "stay"
end

-- Redraw the current frame in place, no re-show, so a menu step is instant. The query is
-- cleared so a new level is not narrowed by a filter typed at the previous one, and the
-- highlight jumps back to the first row of the new list.
local function drawFrame()
  chooser:setQuery("")
  chooser:refresh(true)
  chooser:setPlaceholder(placeholderFor(stack[#stack]))
end

--------------------------------------------------------------------------------
-- Return interceptor, so a menu step never re-shows
--------------------------------------------------------------------------------

-- The native chooser closes on any Return, which would force a re-show to keep a menu open.
-- To keep every step in place, a passive tap swallows Return and the keypad enter while this
-- chooser is up and routes them through the in-place enter instead, so the native completion
-- never fires. Plain typing and the arrows pass straight through. Started on show, stopped on
-- close. Hyper+i routes to the same in-place enter, so both confirm keys behave identically.
local RETURN_CODES = { [36] = true, [76] = true }
local function startReturnTap()
  if returnTap then returnTap:stop() end
  returnTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if not (chooser and chooser:isShowing()) then return false end
    if RETURN_CODES[e:getKeyCode()] then
      M.enter()
      return true
    end
    return false
  end)
  returnTap:start()
end
local function stopReturnTap()
  if returnTap then returnTap:stop(); returnTap = nil end
end

-- Show the one instance at the current frame, set its placeholder to match, and arm the
-- Return tap. The first open and the click fallback's re-show route through here.
local function present()
  if not chooser then return end
  chooser:show()
  chooser:setPlaceholder(placeholderFor(stack[#stack]))
  startReturnTap()
end

-- A row was chosen by mouse click, the one path that still reaches the native completion, so
-- the chooser has already closed. A stay result re-shows at the new frame on the next tick,
-- after the native chooser finishes hiding, a close just lets it end.
local function onSelect(item)
  if applySelection(item) == "stay" then reopen = true end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.show() - open at the top level. The list reads the live state itself, so there is
--- nothing to fetch first.
function M.show()
  stack = { { kind = "top" } }
  present()
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

--- M.refresh() - redraw the current frame in place, so a screen change that lands while the
--- chooser is open updates the active marker without waiting for a keystroke. A no-op when
--- the chooser is closed.
function M.refresh()
  if chooser and chooser:isShowing() then chooser:refresh() end
end

function M.hide()
  if chooser then chooser:hide() end
end

function M.selectNext()
  if chooser then chooser:selectNext() end
end

function M.selectPrev()
  if chooser then chooser:selectPrev() end
end

--- M.enter() - the in-place confirm, from Hyper+i and from the Return tap. Reads the
--- highlighted row, applies it to the stack, and either redraws the new frame in place with
--- no re-show, or closes on a terminal action like Reapply.
function M.enter()
  if not (chooser and chooser:isShowing()) then return end
  if applySelection(chooser:selectedItem()) == "close" then
    chooser:hide()
  else
    drawFrame()
  end
end

--- M.insertSelected() - alias for enter, so any generic routing that names the shared
--- insertSelected action still confirms the highlighted row in place.
function M.insertSelected()
  M.enter()
end

--- M:configure(opts) - merge injected deps across the two callers. The spoon composition
--- root injects `api`, the merged view over the engine and the store. The main root injects
--- `theme`, the Chooser factory as `chooser`, and the docked shortcut panel callbacks
--- (onPositioned, onActivity, onClose), the same seams the other choosers receive.
--
-- Colon here, not dot, because every caller, the plugin root's own configure, the live top
-- level init.lua, and the shared wiring pipeline in lib/wire.lua, reaches this submodule as
-- chooser:configure(opts). self arrives as M and the body below never names it.
function M:configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- M:start() - build the one native chooser. Called by the main root once both configures
--- have run, so the factory and the api are both present.
function M:start()
  stack = { { kind = "top" } }
  chooser = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = "Search profiles",
    fieldMode = cfg.chooser.fieldModes.filter,
    -- Opt out of the shared matcher. This is a stack of frames, not a plain list: the field
    -- filters at the top but is a name entry on the rename and capture screens, and the
    -- supplier morphs its rows from the query and the frame. Letting the atom filter and rank
    -- those rows would drop the Save row while a name is typed and hide the Back row. The
    -- supplier owns the query.
    matcher = false,
    rows = rows,
    onSelect = onSelect,
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    -- Compose the root's panel teardown with the menu stack behavior. The Return tap is
    -- stopped first, since the chooser is down. A click fallback set reopen, so re-show at
    -- the new frame on the next tick (present re-arms the tap), after the native chooser has
    -- finished hiding. Any real dismissal resets the stack for the next open.
    onClose = function()
      stopReturnTap()
      if cfg.onClose then cfg.onClose() end
      if reopen then
        reopen = false
        reopenTimer = hs.timer.doAfter(0, present)
      else
        stack = { { kind = "top" } }
      end
    end,
  })
  return M
end

return M
