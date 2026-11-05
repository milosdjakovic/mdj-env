--- === Olm Plugins ===
---
--- Lists every plugin with Olm's checkbox pair, checked when on, and stages a switch on or off, over the
--- three root words pluginCatalog, pluginCascade and stagePluginSwitch. A choice is only staged,
--- the page stays open, and the root applies the staged set with one reload when the stage goes
--- away. There is no apply row, Milos's call on 2026-11-05. A preview pane describes the
--- highlighted plugin, its description first.
---
--- It was the third page of the Olm Settings plugin until 2026-10-27, when that plugin was split
--- into Olm Placement, Olm Theme and this, so each is one launcher row that opens its list
--- directly rather than a level under a menu of three.

local M = {}

-- Siblings in this directory are loaded by path, the spoon directory is not on the module path.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local page = loadfile(here .. "pluginspage.lua")()

-- The preview pane beside the list, made in configure from the root's grant. The shared piece
-- owns the canvas, the dock, the empty state and the teardown, and this file hands it only what
-- to draw. Nil when no pane was granted, and every use below asks first.
local pane = nil

local log = hs.logger.new("OlmPlugins", "info")

-- This plugin's own identity, which is its directory name since the manifest declares no other,
-- so the page can refuse to switch itself off. Read from where this file loaded, the one thing
-- this plugin knows without being told, rather than spelled out as a literal.
local SELF = here:match("([^/]+)/$")

local cfg = {}

-- filterText is what the row is searched by, lib/chooser/rank.lua. pluginspage.lua hands its own
-- through this same constructor, the title and the identity.
local function row(title, subTitle, icon, item, enabled, filterText)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled,
    filterText = filterText }
end

local function available()
  return cfg.pluginCatalog ~= nil and cfg.pluginCascade ~= nil and cfg.stagePluginSwitch ~= nil
end

local function catalog()
  return (cfg.pluginCatalog and cfg.pluginCatalog()) or {}
end

--- M.rows() -> rows
--- One row per plugin. A row filters on its title and identity alone and never on its state
--- words, so staging a row never changes whether it matches the query being typed.
function M.rows()
  return page.rows(catalog(), row, SELF)
end

-- The pane follows the highlight. A row that is not a plugin, or no row at all, paints
-- the shared empty state rather than leaving the reserved rect bare.
local function describe(item)
  if not pane then return end
  if not (item and item.plugin) then
    pane.clear()
    return
  end
  local list = catalog()
  local entry = page.find(list, item.plugin)
  if not entry then
    pane.clear()
    return
  end
  local cascade = cfg.pluginCascade(item.plugin)
  -- A function of the kit, so a redock or a change of appearance repaints from the same
  -- description. There is no scroll, since a plugin's block is short, and anything taller than
  -- the pane is cut at its edge.
  pane.show(function(ui) return page.detail(ui, entry, list, cascade, SELF) end)
end

local function describeHighlighted()
  describe(cfg.stageSelectedItem and cfg.stageSelectedItem())
end

M.onHighlight = describe

function M.onPositioned(_, previewPaneFrame)
  if not pane then return end
  if previewPaneFrame then
    pane.dock(previewPaneFrame)
    -- The stage seeds the highlight before it positions anything, so this is what fills the
    -- pane on open.
    describeHighlighted()
  else
    pane.hide()
  end
end

function M.onClose()
  if pane then pane.destroy() end
end

--- M.previewPaneWidth() -> true or nil
--- True only when the pane can really draw, so a root that injected no pane surface opens the
--- page with no preview pane rect instead of reserving one nothing can draw in. Resolved at register.
function M.previewPaneWidth()
  return (pane and pane.isEnabled()) and true or nil
end

--- M.select(item) -> nil
--- Every reachable row is caught by intercept, but the field is required on every presentation.
function M.select()
  return nil
end

--- M.intercept(item) -> "stay" or false
--- Choosing a plugin stages the opposite of what the row shows and answers stay, since it mutates
--- the list it stands on and the person keeps the row they chose, and a row that cannot be
--- switched answers stay too, doing nothing. Nothing is applied here.
function M.intercept(item)
  if not item then return false end
  if item.plugin then
    if not item.toggle or item.plugin == SELF then return "stay" end
    local entry = page.find(catalog(), item.plugin)
    if not entry then return "stay" end
    local ok, why = cfg.stagePluginSwitch(item.plugin, not page.isOff(entry))
    if ok then
      -- The marker moves on the redraw this answer causes, and the pane is repainted by hand so
      -- the cascade line is measured against the new staged set at once.
      describeHighlighted()
    elseif cfg.notify then
      cfg.notify(why or "That plugin could not be switched")
    end
    return "stay"
  end
  return false
end

function M.placeholder()
  return "Search plugins"
end

--- M.show()
--- The launcher door, registry.open. Asks the shared stage for this plugin's own registered
--- presentation.
function M.show()
  if cfg.stagePresent then cfg.stagePresent(SELF) end
end

function M:init()
  return self
end

--- M:configure(opts)
--- opts.pluginCatalog        required, a function of no arguments answering the plugin list.
--- opts.pluginCascade        required, a function of an identity answering what else changes.
--- opts.stagePluginSwitch    required, a function of an identity and an off flag answering ok
---                           and why, staging the choice and writing nothing.
--- opts.notify               optional, one line of routine feedback, used for a refusal.
--- opts.stageSelectedItem    optional, the highlighted row, which the pane follows.
--- opts.previewPane           optional, the root's preview pane grant.
--- opts.stagePresent         optional, the shared stage door M.show asks through.
function M:configure(opts)
  opts = opts or {}
  cfg.pluginCatalog = opts.pluginCatalog
  cfg.pluginCascade = opts.pluginCascade
  cfg.stagePluginSwitch = opts.stagePluginSwitch
  cfg.notify = opts.notify
  cfg.stageSelectedItem = opts.stageSelectedItem
  cfg.stagePresent = opts.stagePresent
  if not pane and opts.previewPane then pane = opts.previewPane() end
  if not available() then
    log.w("configured with no plugin switch words, the page will list nothing")
  end
  return self
end

return M
