--- === SystemSettings ===
---
--- The reusable mechanism for reaching macOS System Settings. It owns all the
--- System Settings domain knowledge and nothing about how it is surfaced, so the
--- launcher can consume it without either side learning the other. This is the same
--- split apps.lua already uses, pure data on one side, the mechanism
--- on the other, wired together only in the composition root.
---
--- It does three things. It turns an injected pane catalog into serializable row
--- descriptors the launcher can render and dispatch. It opens a pane by building the
--- x-apple.systempreferences URL for that pane's id. And it focuses the System
--- Settings search field through Accessibility, so a single row can drop the user
--- into Apple's own per setting search for everything the pane list does not reach.
---
--- The catalog is injected, never read from disk here, so the spoon names no config
--- file and stays reusable. init.lua names config/settingsPanes and passes it in.

local obj = {}
obj.__index = obj

obj.name = "SystemSettings"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- The one piece of fixed domain knowledge, the URL scheme every pane shares. A
-- pane's id from the catalog is appended to open it, so General and the extension
-- based panes all open through the same call.
local SCHEME = "x-apple.systempreferences:"

-- The bundle id of the System Settings app itself, used to launch it and to read
-- its Accessibility tree when focusing the search field.
local SETTINGS_BUNDLE = "com.apple.systempreferences"

function obj:init()
  self.panes = self.panes or {}
  return self
end

--- SystemSettings:configure(opts)
--- Method
--- Injects the pane catalog. opts.panes is the list from config/settingsPanes, each
--- entry a table with name, id, glyph, and keywords. Called once from the
--- composition root. Returns self so it can chain after loadSpoon.
function obj:configure(opts)
  opts = opts or {}
  self.panes = opts.panes or {}
  return self
end

--- SystemSettings:rows()
--- Method
--- Turns the injected catalog into launcher row descriptors. Each row is pure data,
--- title, subTitle, glyph, keywords, and a serializable item carrying only the
--- pane's URL, never a function, so it survives the native chooser round trip the
--- launcher relies on. Drawing the glyph into an icon and matching the keywords is
--- the launcher's job, this only supplies the values.
function obj:rows()
  local out = {}
  for _, p in ipairs(self.panes) do
    out[#out + 1] = {
      title = p.name,
      subTitle = "System Settings",
      glyph = p.glyph,
      keywords = p.keywords,
      item = { kind = "settingsPane", url = SCHEME .. p.id },
    }
  end
  return out
end

--- SystemSettings:open(url)
--- Method
--- Opens a pane by its x-apple.systempreferences URL, the url from a row's item.
--- Navigates System Settings straight to that pane, launching it if needed.
--- Dispatched through the open binary rather than hs.urlevent.openURL, which
--- rejects this scheme because it carries no :// authority. open handles it, and
--- passing the URL as a task argument needs no shell quoting.
function obj:open(url)
  if url and url ~= "" then
    hs.task.new("/usr/bin/open", nil, { url }):start()
  end
end

-- Walk the Accessibility tree for the search field. System Settings renders its
-- sidebar search field near the top of the tree, so a depth limited search finds it
-- quickly and never wanders the whole SwiftUI hierarchy. A text field or a search
-- field role both count, since the sidebar search reports as one of the two across
-- macOS versions. Every Accessibility call is guarded, the tree is built lazily and
-- a node can vanish mid walk, so an error on one branch must not abort the search.
local function findSearchField(el, depth)
  if not el or depth > 14 then return nil end
  local okRole, role = pcall(function() return el:attributeValue("AXRole") end)
  if okRole and (role == "AXSearchField" or role == "AXTextField") then
    return el
  end
  local okKids, kids = pcall(function() return el:attributeValue("AXChildren") end)
  if okKids and kids then
    for _, child in ipairs(kids) do
      local found = findSearchField(child, depth + 1)
      if found then return found end
    end
  end
  return nil
end

--- SystemSettings:focusSearch()
--- Method
--- Opens System Settings and puts the cursor in its own search field, so the user
--- types into Apple's native search and gets the per setting results the flat pane
--- list cannot produce. The field appears only after the window is built, so this
--- polls the Accessibility tree for a short while rather than assuming it is ready.
--- If the field never appears the app is at least open and focused, which is the
--- graceful fallback, open plus one manual click rather than nothing.
---
--- Each step of the poll is held in a field on the spoon, and that is what keeps the poll
--- alive. A Hammerspoon timer is userdata whose finalizer stops it, so a pending step
--- nothing refers to can be collected and the chain simply stops partway with the window
--- open and the cursor nowhere. A field on the spoon outlives this method, where a local
--- would be reachable only from the timer that holds the closure, which is a cycle the
--- collector is free to take. One step is pending at a time, so one field is enough, and a
--- second call supersedes an earlier poll rather than racing it.
function obj:focusSearch()
  hs.application.launchOrFocusByBundleID(SETTINGS_BUNDLE)
  local attempts = 0
  local function try()
    attempts = attempts + 1
    local app = hs.application.get(SETTINGS_BUNDLE)
    if app then
      local ax = hs.axuielement.applicationElement(app)
      local field = ax and findSearchField(ax, 0)
      if field then
        pcall(function() field:setAttributeValue("AXFocused", true) end)
        return
      end
    end
    if attempts < 25 then self._searchRetry = hs.timer.doAfter(0.15, try) end
  end
  if self._searchRetry then self._searchRetry:stop() end
  self._searchRetry = hs.timer.doAfter(0.25, try)
end

return obj
