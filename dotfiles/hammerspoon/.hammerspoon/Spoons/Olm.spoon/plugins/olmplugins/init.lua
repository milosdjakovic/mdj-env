--- === Olm Plugins ===
---
--- Lists every plugin with a green or red circle and stages a switch on or off, over the four
--- root words pluginCatalog, pluginCascade, stagePluginSwitch and applyPluginSwitches. A choice
--- is only staged, the page stays open, and the root applies the staged set with one reload when
--- the stage goes away or the Apply now row is chosen. A docked pane describes the highlighted
--- plugin, its description first.
---
--- It was the third page of the OLM settings plugin until 2026-10-27, when that plugin was split
--- into Olm Placement, Olm Theme and this, so each is one launcher row that opens its list
--- directly rather than a level under a menu of three.

local M = {}

-- Siblings in this directory are loaded by path, the spoon directory is not on the module path.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local page = loadfile(here .. "pluginspage.lua")()

-- The docked pane beside the list, made in configure from the root's grant. The shared piece
-- owns the canvas, the dock, the empty state and the teardown, and this file hands it only what
-- to draw. Nil when no pane was granted, and every use below asks first.
local pane = nil

local log = hs.logger.new("OlmPlugins", "info")

-- This plugin's own identity, which is its directory name since the manifest declares no other,
-- so the page can refuse to switch itself off. Read from where this file loaded, the one thing
-- this plugin knows without being told, rather than spelled out as a literal.
local SELF = here:match("([^/]+)/$")

local cfg = {}

-- The plugin last staged, so Apply now can ask for the highlight back on it after the reload.
-- Not the highlight, which this plugin never caches, only the last thing chosen.
local lastStaged = nil

local ICON_APPLY = "apply"

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
--- Apply now while anything is staged, then one row per plugin. Apply now is pinned, so the
--- shared search never drops it, and it trails the matching plugins under a typed query, so Enter
--- on clip stages the clipboard. A row filters on its title and identity alone and never on its
--- state words, so staging a row never changes whether it matches the query being typed.
function M.rows()
  local list = catalog()
  local rows = {}
  local summary = page.pendingSummary(list)
  if summary and cfg.applyPluginSwitches then
    local apply = row("Apply now", summary, ICON_APPLY, { apply = true, key = "apply" }, true)
    apply.pinned = true
    rows[#rows + 1] = apply
  end
  for _, r in ipairs(page.rows(list, row, SELF)) do rows[#rows + 1] = r end
  return rows
end

-- The pane follows the highlight. A row that is not a plugin, Apply now or no row at all, paints
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

function M.onPositioned(_, companionFrame)
  if not pane then return end
  if companionFrame then
    pane.dock(companionFrame)
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

function M.onPresent()
  lastStaged = nil
end

--- M.paneWidth() -> true or nil
--- True only when the pane can really draw, so a root that injected no pane surface opens the
--- page with no companion rect instead of reserving one nothing can draw in. Resolved at register.
function M.paneWidth()
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
  if item.apply and cfg.applyPluginSwitches then
    -- The place to come back to, described by this plugin about itself, its own registered name
    -- and the plugin last chosen. The list is the top level, so there is no path to walk.
    cfg.applyPluginSwitches({
      tool = SELF,
      highlight = lastStaged and { key = lastStaged } or nil,
    })
    return "stay"
  end
  if item.plugin then
    if not item.toggle or item.plugin == SELF then return "stay" end
    local entry = page.find(catalog(), item.plugin)
    if not entry then return "stay" end
    local ok, why = cfg.stagePluginSwitch(item.plugin, not page.isOff(entry))
    if ok then
      lastStaged = item.plugin
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
  return "Plugins"
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
--- opts.applyPluginSwitches  optional, a function of a place to reopen, the Apply now row.
--- opts.notify               optional, one line of routine feedback, used for a refusal.
--- opts.stageSelectedItem    optional, the highlighted row, which the pane follows.
--- opts.dockedPane           optional, the root's docked pane grant.
--- opts.stagePresent         optional, the shared stage door M.show asks through.
function M:configure(opts)
  opts = opts or {}
  cfg.pluginCatalog = opts.pluginCatalog
  cfg.pluginCascade = opts.pluginCascade
  cfg.stagePluginSwitch = opts.stagePluginSwitch
  cfg.applyPluginSwitches = opts.applyPluginSwitches
  cfg.notify = opts.notify
  cfg.stageSelectedItem = opts.stageSelectedItem
  cfg.stagePresent = opts.stagePresent
  lastStaged = nil
  if not pane and opts.dockedPane then pane = opts.dockedPane() end
  if not available() then
    log.w("configured with no plugin switch words, the page will list nothing")
  end
  return self
end

return M
