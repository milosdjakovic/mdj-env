--- === OLM settings ===
---
--- A friendly settings surface, opened from the launcher only, with three nested pages today.
--- The first is where the OLM launcher appears, deciding which display the launcher and every
--- stage window land on. The mechanism it controls already lives in lib/overlaydisplay.lua,
--- two modes, activeWindow and cursor, and this page is the only surface a person sees or
--- changes either one through. The second is the colour theme, one row per theme file under
--- config/themes, applied the moment it is chosen. That mechanism lives in lib/ui/themes.lua
--- and reaches this plugin as three root published words, themeName, themeNames and setTheme.
--- The third lists every plugin with a green or red circle and stages a switch on or off, over
--- the four root words pluginCatalog, pluginCascade, stagePluginSwitch and applyPluginSwitches.
--- A choice is only staged, the page stays open, and the root applies the staged set with one
--- reload when the stage goes away or the Apply now row is chosen. That page alone reserves a
--- docked pane describing the highlighted plugin, and its row on the top level appears only when
--- the root delivered those words.
---
--- No engine and contract ceremony, this plugin has no moving parts of its own. It reads and
--- writes the resolver's live mode through two root published words, overlayPlacementMode and
--- setOverlayPlacementMode, so lib/overlaydisplay.lua stays the one file that ever calls
--- hs.settings for this policy.
---
--- This page names the two modes as the bare literals cursor and activeWindow rather than
--- reading them off lib/overlaydisplay.lua's own M.modes, since the two closures above are all
--- this plugin ever receives, not the modes table itself. That coupling by spelling rather
--- than by shared reference is deliberate, forced by the architecture this plugin is built
--- against rather than an oversight, and it carries one real failure mode worth knowing. A
--- mode renamed inside the resolver leaves self.setMode refusing the old literal with a log
--- line, while this page's own green marker goes quietly blank instead, with nothing here to
--- raise the mismatch any louder than that.
---
--- Migrated onto host/stage, contract v3, docs/BRIEF-CONTRACT-V3.md. The top level is one
--- row, Where the OLM launcher appears, its subtitle naming the live choice, and choosing
--- it pushes the child below, decision one, host/stage pushing whatever select answers. The
--- child's own rows, Back then the two options, are decided by the same live mode on every
--- rebuild, and the green circle marks whichever option is current, the one marker this
--- codebase uses for that question, never a checkmark. Choosing an option is decision
--- three's reserved case, a row that mutates the policy it is standing beside and stays,
--- reached through intercept and the write path above rather than through select, since a
--- completion here would close the whole tool on every flip and Milos wants to switch back
--- and forth without leaving. Back leaves through cfg.stagePop, the one thing this child
--- pushed from select cannot express on its own.

local M = {}

-- Siblings in this directory are loaded by path, the spoon directory is not on the module path.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local page = loadfile(here .. "pluginspage.lua")()

-- The docked pane beside the Plugins page, made in configure from the root's grant. The shared
-- piece owns the canvas, the dock, the empty state and the teardown, and this file hands it only
-- what to draw. Nil when no pane was granted, and every use below asks first.
local pane = nil

local log = hs.logger.new("Settings", "info")

-- This plugin's own identity, which is its directory name since the manifest declares no other,
-- so the Plugins page can refuse to switch itself off. Read from where this file loaded, the
-- one thing this plugin knows without being told, rather than spelled out as a literal.
local SELF = here:match("([^/]+)/$")

-- Injected via configure, the trickle migration's own root published words. readMode and
-- setMode back the whole page, both required, since a page whose reason is showing and
-- changing a policy has nothing honest left to do without either. stagePresent and stagePop
-- are optional, degrading to an inert press rather than a crash.
local cfg = {}

-- The plugin last staged on the Plugins page, so Apply now can ask for the highlight back on it
-- after the reload. The Apply row itself will not be there, since nothing is staged by then, and
-- the row the person last chose is the one they were working on. Not the highlight, which this
-- plugin never caches, only the last thing chosen.
local lastStaged = nil

--------------------------------------------------------------------------------
-- Row building
--------------------------------------------------------------------------------

-- The icon keys, declared with their glyphs in the manifest.
local ICON_PLACEMENT = "placement"
local ICON_THEME = "theme"
local ICON_BACK = "back"
local ICON_PLUGINS = "plugins"
local ICON_APPLY = "apply"
-- The two option rows carry only a circle each, never a checkmark, the one marker
-- convention this codebase uses for "which of these is current right now". Green marks
-- whichever option is current and red marks the other one, so the pair together says which
-- is live without either row needing a glyph of its own to describe what it does.
local ICON_SELECTED = "selected"
local ICON_NOT_SELECTED = "notSelected"

local function row(title, subTitle, icon, item, enabled, filterText)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled,
    filterText = filterText }
end

local function backRow()
  return row("Back", nil, ICON_BACK, { nav = true, to = "back" }, true)
end

-- Plain words for the top level's own subtitle, one per mode this resolver knows.
local MODE_WORDS = {
  cursor = "where the mouse cursor is",
  activeWindow = "with the active window",
}

local function liveMode()
  return cfg.readMode and cfg.readMode()
end

--------------------------------------------------------------------------------
-- The child page for Where the OLM launcher appears, a page of Back plus the two everyday
-- options
--------------------------------------------------------------------------------

local function placementRows()
  local mode = liveMode()
  local rows = { backRow() }
  rows[#rows + 1] = row("Where the mouse cursor is", nil,
    mode == "cursor" and ICON_SELECTED or ICON_NOT_SELECTED, { commit = "cursor" }, true)
  rows[#rows + 1] = row("With the active window", nil,
    mode == "activeWindow" and ICON_SELECTED or ICON_NOT_SELECTED, { commit = "activeWindow" }, true)
  return rows
end

-- matcher is false for the identical reason every other menu style page in this tree opts
-- out, a fixed set of rows that already answers the query in full rather than a list a
-- shared strategy should filter, and a filter here would risk hiding the Back row on a typed
-- character.
local function buildPlacementChild()
  return {
    placeholder = "Where the OLM launcher appears",
    matcher = false,
    rows = placementRows,
    -- select never actually answers, both reachable rows on this level are caught by
    -- intercept below, back and the two options alike, but the field is required on every
    -- presentation, host/stage's own isPresentation refusing one without it.
    onSelect = function() end,
    intercept = function(item)
      if item.nav and item.to == "back" then
        -- Answers true, not "stay", since leaving this level is a level change, not a
        -- mutation of the row standing here, and cfg.stagePop already resets the parent
        -- through the stage's own show, so this level asking to hold a highlight it is
        -- about to leave would mean nothing.
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.commit then
        -- Writes through the one path lib/overlaydisplay.lua already keeps for self.setMode,
        -- so this file never calls hs.settings itself. Answering "stay" rather than true
        -- keeps the page open, rebuilds the rows so the circles move to the row just
        -- chosen, and holds the highlight on that row instead of resetting it to the top,
        -- since this row mutated the policy it already stood on rather than swapping to a
        -- different list. That is the whole reason this is intercept rather than select,
        -- Milos switching back and forth and leaving by Backspace or Escape when done,
        -- looking at the option he just picked rather than back at the top of the page.
        if cfg.setMode then cfg.setMode(item.commit) end
        return "stay"
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- The child page for Theme, Back plus one row per theme file
--------------------------------------------------------------------------------

local function liveTheme()
  return cfg.readTheme and cfg.readTheme()
end

-- The rows are rebuilt from the store's own names on every redraw, so a theme file that was
-- added since the page opened shows up on the next one, and the circle follows whichever
-- name is live. Same circles as the placement page, green for the live one.
local function themeRows()
  local live = liveTheme()
  local rows = { backRow() }
  for _, name in ipairs((cfg.readThemeNames and cfg.readThemeNames()) or {}) do
    rows[#rows + 1] = row(name, nil, name == live and ICON_SELECTED or ICON_NOT_SELECTED,
      { theme = name }, true)
  end
  return rows
end

-- Built exactly as the placement child is, a fixed list that answers the query in full and
-- so opts out of the shared matcher, and choosing a theme answers stay for the same reason
-- choosing a placement does. A theme is a mutation of the policy the row stands beside, so
-- the page keeps the highlight on the row just chosen and only the circle moves.
local function buildThemeChild()
  return {
    placeholder = "Theme",
    matcher = false,
    rows = themeRows,
    -- Every reachable row is caught by intercept below, but the field is required on every
    -- presentation, host/stage's own isPresentation refusing one without it.
    onSelect = function() end,
    intercept = function(item)
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.theme then
        if cfg.setTheme then cfg.setTheme(item.theme) end
        return "stay"
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- The child page for Plugins, Back plus one row per plugin, with a docked pane
--------------------------------------------------------------------------------

-- Whether the root delivered the three words the page reads. They are optional, so a root
-- without them simply has no Plugins row rather than a page that lists nothing. Apply now needs
-- the fourth as well and is left out without it, since dismissing the stage applies anyway.
local function pluginsAvailable()
  return cfg.pluginCatalog ~= nil and cfg.pluginCascade ~= nil and cfg.stagePluginSwitch ~= nil
end

-- Where this page sits inside this plugin's own presentation, the step from the top level, so
-- the root can reopen it after a reload without knowing this plugin. The same item the top
-- level row carries.
local PLUGINS_STEP = { nav = true, to = "plugins" }

local function catalog()
  return (cfg.pluginCatalog and cfg.pluginCatalog()) or {}
end

-- Back, then Apply now while anything is staged, then one row per plugin. Apply now is optional,
-- dismissing the stage applies too, so it is a shortcut that keeps the person here rather than a
-- confirm step.
local function pluginRows()
  local list = catalog()
  -- Back and Apply now carry an empty filterText, which the matcher scores as nothing, so any
  -- typed text hides them and they never sit above a chosen row while a query is typed.
  local back = backRow()
  back.filterText = ""
  local rows = { back }
  local summary = page.pendingSummary(list)
  if summary and cfg.applyPluginSwitches then
    rows[#rows + 1] = row("Apply now", summary, ICON_APPLY, { apply = true, key = "apply" }, true, "")
  end
  for _, r in ipairs(page.rows(list, row, SELF)) do rows[#rows + 1] = r end
  return rows
end

-- The pane follows the highlight. A row that is not a plugin, Back, or no row at all, paints
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

-- Unlike the other two children, this page declares no matcher and so filters on the shared
-- default. Those two pages are two fixed option rows a query cannot usefully narrow, while this
-- is a list of every plugin a person picks from, and typing a title or a state word such as off
-- has to narrow it. Choosing a plugin stages the opposite of what the row shows and answers
-- stay, since it mutates the list it stands on and the person keeps the row they chose, and a
-- row that cannot be switched answers stay too, doing nothing, so a press on it never leaves
-- the page. Nothing is applied here, the page stays open however many rows are flipped.
local function buildPluginsChild()
  lastStaged = nil
  return {
    placeholder = "Plugins",
    rows = pluginRows,
    onSelect = function() end,
    -- True only when the pane can really draw, so a root that injected no pane surface opens
    -- the page with no companion rect instead of reserving one nothing can draw in.
    paneWidth = (pane and pane.isEnabled()) and true or nil,
    onHighlight = describe,
    onPositioned = function(_, companionFrame)
      if not pane then return end
      if companionFrame then
        pane.dock(companionFrame)
        -- The stage seeds the highlight before it positions anything, so this is what fills
        -- the pane on open.
        describeHighlighted()
      else
        pane.hide()
      end
    end,
    onClose = function() if pane then pane.destroy() end end,
    intercept = function(item)
      if item.nav and item.to == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.apply and cfg.applyPluginSwitches then
        -- The place to come back to, described by this plugin about itself, this plugin's own
        -- registered name, the step to this page and the plugin last chosen.
        cfg.applyPluginSwitches({
          tool = SELF,
          path = { PLUGINS_STEP },
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
          -- The marker moves on the redraw this answer causes, and the pane is repainted by
          -- hand so the cascade line is measured against the new staged set at once.
          describeHighlighted()
        elseif cfg.notify then
          cfg.notify(why or "That plugin could not be switched")
        end
        return "stay"
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- The top level, up to three rows, named on the manifest's own presentation block
--------------------------------------------------------------------------------

--- M.rows() -> rows
--- The top level's own row supplier. Where the OLM launcher appears, its subtitle naming the
--- live choice in words, Theme, its subtitle naming the live theme, and Plugins, only when the
--- root delivered the plugin switch words, its subtitle counting what is off. No matcher
--- declared in the manifest, the shared default fuzzy strategy is more than enough over so few
--- rows.
function M.rows()
  local mode = liveMode()
  local words = MODE_WORDS[mode] or MODE_WORDS.cursor
  local rows = {
    row("Where the OLM launcher appears", words, ICON_PLACEMENT, { nav = true, to = "placement" }, true),
    row("Theme", liveTheme(), ICON_THEME, { nav = true, to = "theme" }, true),
  }
  if pluginsAvailable() then
    local list = catalog()
    local off = 0
    for _, entry in ipairs(list) do
      if page.isOff(entry) then off = off + 1 end
    end
    local words = off == 0 and "all on" or (off .. " off")
    if page.pendingSummary(list) then words = words .. " after apply" end
    rows[#rows + 1] = row("Plugins", words, ICON_PLUGINS, { nav = true, to = PLUGINS_STEP.to }, true)
  end
  return rows
end

--- M.select(item) -> presentation or nil
--- The top level's own onSelect. Choosing either row is a genuine child, decision one,
--- host/stage pushing whatever comes back, so this level never completes the whole tool by
--- itself.
function M.select(item)
  if not item then return nil end
  if item.nav and item.to == "placement" then return buildPlacementChild() end
  if item.nav and item.to == "theme" then return buildThemeChild() end
  if item.nav and item.to == PLUGINS_STEP.to and pluginsAvailable() then return buildPluginsChild() end
  return nil
end

--- M.placeholder() -> string
--- The field hint while the top level is current, named on the manifest's own presentation
--- block. Resolved once, at register, since the presentation contract wants a plain string a
--- presentation carries rather than a function to call again later.
function M.placeholder()
  return "OLM settings"
end

--- M.show()
--- The hotkey and launcher door, registry.open. Asks the shared stage for this plugin's own
--- registered presentation, the identical shape DisplayProfiles' launcher only entry already
--- takes, since this plugin proposes no key of its own.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("settings") end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:init()
  return self
end

--- M:configure(opts)
--- opts.overlayPlacementMode     required, a function of no arguments answering the live mode.
--- opts.setOverlayPlacementMode  required, a function of one mode string, writing it through
---                               lib/overlaydisplay.lua's own persisted path.
--- opts.themeName                required, a function of no arguments answering the live theme.
--- opts.themeNames               required, a function of no arguments answering the sorted names.
--- opts.setTheme                 required, a function of a theme name, applying it at once and
---                               persisting it through lib/ui/themes.lua.
--- opts.pluginCatalog            optional, a function of no arguments answering the plugin list.
--- opts.pluginCascade            optional, a function of an identity answering what else changes.
--- opts.stagePluginSwitch        optional, a function of an identity and an off flag answering
---                               ok and why, staging the choice and writing nothing.
--- opts.applyPluginSwitches      optional, a function of a place to reopen, applying what is
---                               staged with one reload, the Apply now row. The Plugins page
---                               exists with the first three, and Apply now needs this too.
--- opts.notify                   optional, one line of routine feedback, used for a refusal.
--- opts.stageSelectedItem        optional, the highlighted row, which the pane follows.
--- opts.dockedPane               optional, the root's docked pane grant, a function answering
---                               a pane. Without it the Plugins page has no pane.
--- opts.stagePresent             optional, the shared stage door M.show asks through.
--- opts.stagePop                 optional, the door the placement child's own Back row asks
---                                through.
function M:configure(opts)
  opts = opts or {}
  cfg.readMode = opts.overlayPlacementMode
  cfg.setMode = opts.setOverlayPlacementMode
  cfg.readTheme = opts.themeName
  cfg.readThemeNames = opts.themeNames
  cfg.setTheme = opts.setTheme
  cfg.stagePresent = opts.stagePresent
  cfg.stagePop = opts.stagePop
  cfg.pluginCatalog = opts.pluginCatalog
  cfg.pluginCascade = opts.pluginCascade
  cfg.stagePluginSwitch = opts.stagePluginSwitch
  cfg.applyPluginSwitches = opts.applyPluginSwitches
  cfg.notify = opts.notify
  cfg.stageSelectedItem = opts.stageSelectedItem
  lastStaged = nil
  if not pane and opts.dockedPane then pane = opts.dockedPane() end
  if not cfg.readMode or not cfg.setMode then
    log.w("configured with no overlay placement reader or writer, the Where the OLM "
      .. "launcher appears page will show and change nothing")
  end
  if not cfg.readTheme or not cfg.readThemeNames or not cfg.setTheme then
    log.w("configured with no theme reader or writer, the Theme page will show and change nothing")
  end
  return self
end

return M
