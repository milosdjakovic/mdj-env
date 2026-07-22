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
--- the new level. This is the same re-show the Vpn spoon avoided by staying flat, done on
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
--- root, the same way the VPN and keep awake choosers receive them.

local M = { name = "DisplayProfiles.chooser" }

local cfg = {}        -- injected across two calls: api from the spoon, view deps from the root
local chooser = nil   -- the one native Chooser instance
local stack = nil     -- the menu stack, stack[#stack] is the current frame
local reopen = false  -- set by a navigation selection so onClose re-shows instead of ending

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an offscreen
-- canvas drawn once and cached by the string, since the supplier runs on every keystroke. A
-- false marks a string that cannot render, so it is attempted only once. This is the same
-- helper the VPN and keep awake choosers use.
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
      local kind = p.editable and "Captured" or "Curated"
      local sub = (isActive and "Active. " or "") .. kind .. ", " .. displayCount(p) .. " displays"
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

-- A profile's menu. List displays always, Reapply only on the active profile, Rename and
-- Delete only when the profile is captured, then Back. A curated profile shows neither
-- Rename nor Delete, since the tool never rewrites the hand maintained config/displays.lua.
local function profileRows(name)
  local p = profileByName(name)
  if not p then return { row("Profile is gone", "It may have been removed", ICON.warn, { noop = true }, false), backRow() } end
  local out = {}
  out[#out + 1] = row("List displays", displayCount(p) .. " displays", ICON.displays,
    { nav = true, to = "displays", name = name }, true)
  if name == cfg.api.active() then
    out[#out + 1] = row("Reapply this arrangement", "Force it back if macOS scrambled the layout",
      ICON.reapply, { act = "reapply" }, true)
  end
  if p.editable then
    out[#out + 1] = row("Rename", "Change the name of this captured profile", ICON.rename,
      { nav = true, to = "rename", name = name }, true)
    out[#out + 1] = row("Delete", "Remove this captured profile", ICON.delete,
      { nav = true, to = "delete", name = name }, true)
  else
    out[#out + 1] = row("Curated profile", "Edit config/displays.lua to change it", ICON.warn,
      { noop = true }, false)
  end
  out[#out + 1] = backRow()
  return out
end

-- A profile's displays, read only. Back leads, unlike the other screens where it trails,
-- so the default highlight on this screen is an action, since the native chooser closes on
-- any Return and the monitor rows below are disabled. So Return here steps back rather than
-- dismissing, and Escape is still the way to close everything. Each monitor row shows its
-- resolution, id, refresh, and origin, the main display marked.
local function displaysRows(name)
  local p = profileByName(name)
  if not p then return { backRow() } end
  local out = { backRow() }
  for _, d in ipairs(cfg.api.displays(p.command)) do
    local title = (d.res or "?") .. (d.main and "   (main)" or "")
    local sub = "id " .. d.id .. (d.hz and (", " .. d.hz .. "hz") or "") .. ", origin (" .. d.origin .. ")"
    out[#out + 1] = row(title, sub, ICON.displays, { noop = true }, false)
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
  if top.kind == "displays" then return displaysRows(top.name) end
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

-- Show the one instance at the current frame and set its placeholder to match. Every level
-- transition and the first open route through here, so the field hint always fits the frame.
local function present()
  if not chooser then return end
  chooser:show()
  chooser:setPlaceholder(placeholderFor(stack[#stack]))
end

--------------------------------------------------------------------------------
-- Navigation and selection dispatch
--------------------------------------------------------------------------------

local function frameFor(item)
  if item.to == "profile" then return { kind = "profile", name = item.name } end
  if item.to == "displays" then return { kind = "displays", name = item.name } end
  if item.to == "rename" then return { kind = "rename", name = item.name } end
  if item.to == "delete" then return { kind = "delete", name = item.name } end
  if item.to == "capture" then return { kind = "capture" } end
  return { kind = "top" }
end

-- A row was chosen. A disabled hint does nothing. A navigation row pushes or pops a frame
-- and asks onClose to re-show at the new level. A terminal action calls the api, and on
-- success sends the stack where it should land next, the top after a capture or delete, the
-- renamed profile's menu after a rename, and closes for good after a reapply. A failed write
-- logs and re-shows the same screen, so nothing is lost.
local function onSelect(item)
  if not item or item.noop then return end

  if item.nav then
    if item.to == "back" then
      if #stack > 1 then table.remove(stack) end
    else
      stack[#stack + 1] = frameFor(item)
    end
    reopen = true
    return
  end

  if item.act == "reapply" then
    cfg.api.reapply()
    return -- terminal, let it close
  end

  if item.act == "capture" then
    local ok, err = cfg.api.capture(item.newName)
    if ok then stack = { { kind = "top" } } else print("DisplayProfiles: capture failed, " .. tostring(err)) end
    reopen = true
    return
  end

  if item.act == "saveRename" then
    local ok, err = cfg.api.rename(item.name, item.newName)
    if ok then
      table.remove(stack) -- pop the rename frame
      stack[#stack] = { kind = "profile", name = item.newName } -- the profile menu, renamed
    else
      print("DisplayProfiles: rename failed, " .. tostring(err))
    end
    reopen = true
    return
  end

  if item.act == "delete" then
    local ok, err = cfg.api.remove(item.name)
    if ok then stack = { { kind = "top" } } else print("DisplayProfiles: delete failed, " .. tostring(err)) end
    reopen = true
    return
  end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard, VPN, and keep awake)
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

--- M.insertSelected() - choose the highlighted row, exactly as Return does, routed here from
--- the displayProfiles Hyper context.
function M.insertSelected()
  if chooser then chooser:insertSelected() end
end

--- M.configure(opts) - merge injected deps across the two callers. The spoon composition
--- root injects `api`, the merged view over the engine and the store. The main root injects
--- `theme`, the Chooser factory as `chooser`, and the docked shortcut panel callbacks
--- (onPositioned, onActivity, onClose), the same seams the other choosers receive.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- M.start() - build the one native chooser. Called by the main root once both configures
--- have run, so the factory and the api are both present.
function M.start()
  stack = { { kind = "top" } }
  chooser = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = "Search profiles",
    fieldMode = "filter",
    rows = rows,
    onSelect = onSelect,
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    -- Compose the root's panel teardown with the menu stack behavior. A navigation
    -- selection set reopen, so re-show at the new frame on the next tick, after the native
    -- chooser has finished hiding itself. Any real dismissal resets the stack for next open.
    onClose = function()
      if cfg.onClose then cfg.onClose() end
      if reopen then
        reopen = false
        hs.timer.doAfter(0, present)
      else
        stack = { { kind = "top" } }
      end
    end,
  })
  return M
end

return M
