--- === MenuSearch ===
---
--- Lists every enabled menu bar item of the frontmost app and runs the chosen one. Like the
--- launcher this is pure composition root policy over the shared Chooser atom, so it added no
--- spoon of its own before this extraction. macOS exposes each app's menus through the
--- Accessibility API, which hs.application:getMenuItems reads, the callback form doing the
--- tree walk off the main thread so a large menu never blocks Hammerspoon. The app frontmost
--- when the open action runs is captured as the target, since showing the chooser takes
--- focus, and the chosen item is dispatched back to that app once focus returns to it.
---
--- Each row carries only a serializable descriptor, its menu path as a list of titles, never
--- a function, since hs.chooser serialises each row and would silently drop a function. The
--- menu tree is fetched per open, since it changes with the app and its state, so the rows
--- supplier reads a module local list the fetch fills, and the chooser is shown only once the
--- fetch has built the rows.
---
--- init returns self with no side effects. configure takes every collaborator this plugin
--- needs and returns self, the Chooser atom whose new builds the picker, the chooser theme
--- table, a table carrying the three docked shortcut panel callbacks, a function answering
--- the app the launcher covers, a function poking the launcher when async rows land, and the
--- root's deferred call helper. It names no spoon global, reads no config file, and learns
--- nothing about which key opens it, so a caller reaches it only through the surface, the
--- open action, and the two scope functions this file hands back.
---
--- This is the olm side extraction of menu search, made the seventh of August 2026. The
--- original lives inline in the root init.lua, behind a toggle, rather than in a spoon
--- directory of its own, since that is where a reader must look for the other side.

local obj = {}
obj.__index = obj

obj.name = "MenuSearch"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local cfg = nil        -- the injected collaborators, chooser atom, theme, panel callbacks, coveredApp, refreshLauncher, after
local menuSearch = nil -- the one native Chooser instance

-- hs decodes AXMenuItemCmdModifiers into a list of modifier names (e.g. { "cmd" }
-- or { "cmd", "shift" }). Turn it plus the command char into a readable glyph for
-- the row subtitle, in the canonical ⌃⌥⇧⌘ order, or nil when the item has no
-- keyboard shortcut. Both alt/option and ctrl/control spellings are accepted.
local function menuShortcutGlyph(char, mods)
  if not char or char == "" then return nil end
  local has = {}
  for _, m in ipairs(mods or {}) do has[tostring(m):lower()] = true end
  local g = ""
  if has.ctrl or has.control then g = g .. "⌃" end
  if has.alt or has.option then g = g .. "⌥" end
  if has.shift then g = g .. "⇧" end
  if has.cmd or has.command then g = g .. "⌘" end
  return g .. char:upper()
end

-- Flatten the nested AX menu tree into leaf rows. An entry's submenu is its
-- AXChildren[1] (a list); an entry with one is a container we recurse into, an
-- entry without is a runnable leaf. Blank-title entries (separators) are skipped,
-- and disabled items are dropped so the list stays actionable. Each leaf keeps the
-- full title path for selectMenuItem, plus its parent path and shortcut for display.
local function flattenMenus(entries, path, out)
  for _, e in ipairs(entries) do
    local title = e.AXTitle
    if title and title ~= "" then
      local kids = e.AXChildren and e.AXChildren[1]
      local newPath = {}
      for i = 1, #path do newPath[i] = path[i] end
      newPath[#newPath + 1] = title
      if type(kids) == "table" and #kids > 0 then
        flattenMenus(kids, newPath, out)
      elseif e.AXEnabled ~= false then
        local parents = {}
        for i = 1, #newPath - 1 do parents[i] = newPath[i] end
        out[#out + 1] = {
          title = title,
          path = newPath,
          parents = table.concat(parents, " ▸ "),
          shortcut = menuShortcutGlyph(e.AXMenuItemCmdChar, e.AXMenuItemCmdModifiers),
        }
      end
    end
  end
end

local menuRows = {}   -- filled by the async fetch on each open
local menuTargetApp   -- the app frontmost when the open action fired, the dispatch target
local menuAppIcon     -- the target app's icon, shown on every row (one app per open)
local menuAppKey      -- a stable icon key so that icon is encoded once, not per row

-- Rows supplier. Returns every menu item and lets the atom's shared matcher filter and
-- rank, so typing a parent menu name (File, Format) narrows too since the path rides in
-- filterText. The shortcut glyph rides in the subtitle after the path.
-- The row shape, shared by this chooser and the launcher's menu scope below, so the two
-- present a menu item identically and cannot drift. Every item belongs to the one captured
-- app, so each row shows that app's icon, and the stable key memoizes the encoded icon once
-- rather than per row.
local function buildMenuRows(list, icon, iconKey)
  local out = {}
  for _, r in ipairs(list or {}) do
    local subtitle = r.parents
    if r.shortcut then
      subtitle = (subtitle ~= "" and (subtitle .. "   ") or "") .. r.shortcut
    end
    out[#out + 1] = { title = r.title, subTitle = subtitle, image = icon,
                      iconKey = iconKey, item = { path = r.path },
                      filterText = r.title .. " " .. r.parents }
  end
  return out
end

local function menuSearchRows(_)
  return buildMenuRows(menuRows, menuAppIcon, menuAppKey)
end

-- Open the built-in menu search: capture the frontmost app, fetch its menus
-- asynchronously so a large tree never blocks, then show the chooser once the rows
-- are built. Does nothing if no app is frontmost, the app exposes no menus, or focus
-- moved before the fetch returned (so we never target the wrong app).
local function openBuiltinMenuSearch()
  local app = hs.application.frontmostApplication()
  if not app then return end
  menuTargetApp = app
  local bundleID = app:bundleID()
  menuAppIcon = bundleID and hs.image.imageFromAppBundle(bundleID) or nil
  menuAppKey = bundleID and ("menuapp:" .. bundleID) or nil
  app:getMenuItems(function(menus)
    if not menus then return end
    if hs.application.frontmostApplication() ~= app then return end
    menuRows = {}
    flattenMenus(menus, {}, menuRows)
    menuSearch:show()
  end)
end

-- The launcher's menu scope. It lists the menus of the app the launcher covered rather than
-- the frontmost one, since once the chooser is up the frontmost app is this one, which is why
-- the launcher hands over both that app and an id for the open. The tree is read once per open.
-- Re-reading it on every keystroke would be unusable, since the accessibility walk is the slow
-- part of menu search, and caching it across opens would go stale as an app enables and
-- disables its items. A read in flight shows as one disabled row, so the list says what it is
-- doing rather than briefly claiming nothing matched, and that row carries the typed text as
-- its filter text so the matcher cannot rank it away while it is the only thing to show.
local scopeMenu = { app = nil, openId = nil, list = nil, icon = nil, key = nil, reading = false }

local function scopeMenuRows(rest)
  local app, openId = cfg.coveredApp()
  if not app then return {} end
  if app ~= scopeMenu.app or openId ~= scopeMenu.openId then
    local bundleID = app:bundleID()
    scopeMenu = {
      app = app, openId = openId, list = nil, reading = false,
      icon = bundleID and hs.image.imageFromAppBundle(bundleID) or nil,
      key = bundleID and ("menuapp:" .. bundleID) or nil,
    }
  end
  if not scopeMenu.list and not scopeMenu.reading then
    scopeMenu.reading = true
    local forApp, forOpen = app, openId
    app:getMenuItems(function(menus)
      -- The answer can arrive after another open has moved on, so it is kept only for the
      -- read that asked for it and dropped otherwise.
      if scopeMenu.app ~= forApp or scopeMenu.openId ~= forOpen then return end
      scopeMenu.reading = false
      local flat = {}
      if menus then flattenMenus(menus, {}, flat) end
      scopeMenu.list = flat
      cfg.refreshLauncher()
    end)
  end
  if not scopeMenu.list then
    return { {
      title = "Reading the menus",
      subTitle = (app:name() or "this app") .. ", one moment",
      glyph = "⏳",
      enabled = false,
      filterText = rest,
    } }
  end
  return buildMenuRows(scopeMenu.list, scopeMenu.icon, scopeMenu.key)
end

-- Acts on the app the read was for, not on whatever is frontmost when the row runs, so a menu
-- item can never be sent to the wrong app. selectMenuItem addresses that app directly, so this
-- does not depend on focus having returned, though the launcher defers it anyway.
local function scopeMenuRun(payload)
  local app = scopeMenu.app
  if app and payload and payload.path then app:selectMenuItem(payload.path) end
end

--- MenuSearch:init()
--- Method
--- Initialize the plugin. Returns self and does no side effects.
function obj:init()
  return self
end

--- MenuSearch:configure(opts)
--- Method
--- Configure with every collaborator this plugin needs. opts.chooser is the Chooser atom
--- table whose new builds the picker. opts.theme is the chooser theme table. opts.panel is a
--- table carrying the three docked shortcut panel callbacks onPositioned, onActivity and
--- onClose. opts.coveredApp is a function answering the app the launcher covers.
--- opts.refreshLauncher is a function poking the launcher when async rows land. opts.after is
--- the root's deferred call helper. Builds the one native chooser, assigns the public
--- surface, the open action, and the launcher's two menu scope functions. Returns self.
function obj:configure(opts)
  cfg = opts or {}

  -- The chosen item runs deferred, after the chooser tears down and macOS restores
  -- focus to the captured app, since a menu action acts on that app. The shortcut
  -- panel is wired in through onPositioned/onActivity/onClose, so it complements the
  -- native chooser without the chooser knowing about it.
  local panel = cfg.panel or {}
  menuSearch = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = "Search menu items",
    rows = menuSearchRows,
    onSelect = function(item)
      if item and item.path and menuTargetApp then
        local app = menuTargetApp
        cfg.after(0.1, function() app:selectMenuItem(item.path) end)
      end
    end,
    onPositioned = panel.onPositioned,
    onActivity = panel.onActivity,
    onClose = panel.onClose,
  })

  -- Dot-called navigation adapter over the Chooser instance, so the shared
  -- activeChooser / routeNav registry drives it exactly like the other pickers.
  self.surface = {
    isShowing = function() return menuSearch:isShowing() end,
    selectNext = function() menuSearch:selectNext() end,
    selectPrev = function() menuSearch:selectPrev() end,
    insertSelected = function() menuSearch:insertSelected() end,
    hide = function() menuSearch:hide() end,
  }

  self.open = openBuiltinMenuSearch
  self.scopeRows = scopeMenuRows
  self.scopeRun = scopeMenuRun

  return self
end

return obj
