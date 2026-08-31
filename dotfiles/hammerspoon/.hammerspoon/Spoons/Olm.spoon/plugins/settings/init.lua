--- === OLM settings ===
---
--- A friendly settings surface, opened from the launcher only, with one nested page today,
--- where the OLM launcher appears, deciding which display the launcher and every stage
--- window land on. The mechanism this page controls already lives in
--- lib/overlaydisplay.lua, two modes, activeWindow and cursor, and this page is the only
--- surface a person sees or changes either one through.
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

local log = hs.logger.new("Settings", "info")

-- Injected via configure, the trickle migration's own root published words. readMode and
-- setMode back the whole page, both required, since a page whose reason is showing and
-- changing a policy has nothing honest left to do without either. stagePresent and stagePop
-- are optional, degrading to an inert press rather than a crash.
local cfg = {}

--------------------------------------------------------------------------------
-- Row building
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an offscreen
-- canvas drawn once and cached by the string, the same helper every other menu style chooser
-- in this tree already builds for itself rather than sharing, since each one is five lines.
-- The manifest stays pure and touches no hs, this module is free to draw.
local glyphCache = {}
local function emojiImage(str)
  if not str then return nil end
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

local ICON_PLACEMENT = "🖥️"
local ICON_BACK = "⬅️"
-- The green circle marks the active row, never a checkmark, the one marker this codebase
-- uses for "which of these is current right now".
local ICON_SELECTED = "🟢"
local ICON_CURSOR = "🖱️"
local ICON_ACTIVE_WINDOW = "🎯"

local function row(title, subTitle, icon, item, enabled)
  return { title = title, subTitle = subTitle, image = emojiImage(icon), item = item, enabled = enabled }
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
  rows[#rows + 1] = row("Where the mouse cursor is", nil, mode == "cursor" and ICON_SELECTED or ICON_CURSOR,
    { commit = "cursor" }, true)
  rows[#rows + 1] = row("With the active window", nil, mode == "activeWindow" and ICON_SELECTED or ICON_ACTIVE_WINDOW,
    { commit = "activeWindow" }, true)
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
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.commit then
        -- Writes through the one path lib/overlaydisplay.lua already keeps for self.setMode,
        -- so this file never calls hs.settings itself. Answering true keeps the
        -- page open and rebuilds it from the top, the green circle moving to the row just
        -- chosen, which is the whole reason this is intercept rather than select, Milos
        -- switching back and forth and leaving by Backspace or Escape when done.
        if cfg.setMode then cfg.setMode(item.commit) end
        return true
      end
      return false
    end,
  }
end

--------------------------------------------------------------------------------
-- The top level, one row, named on the manifest's own presentation block
--------------------------------------------------------------------------------

--- M.rows() -> rows
--- The top level's own row supplier. One row today, Where the OLM launcher appears, its
--- subtitle naming the live choice in words. No matcher declared in the manifest, the shared
--- default fuzzy strategy is more than enough over one row.
function M.rows()
  local mode = liveMode()
  local words = MODE_WORDS[mode] or MODE_WORDS.cursor
  return {
    row("Where the OLM launcher appears", words, ICON_PLACEMENT, { nav = true, to = "placement" }, true),
  }
end

--- M.select(item) -> presentation or nil
--- The top level's own onSelect. Choosing the one row is a genuine child, decision one,
--- host/stage pushing whatever comes back, so this level never completes the whole tool by
--- itself.
function M.select(item)
  if not item then return nil end
  if item.nav and item.to == "placement" then return buildPlacementChild() end
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
--- opts.stagePresent             optional, the shared stage door M.show asks through.
--- opts.stagePop                 optional, the door the placement child's own Back row asks
---                                through.
function M:configure(opts)
  opts = opts or {}
  cfg.readMode = opts.overlayPlacementMode
  cfg.setMode = opts.setOverlayPlacementMode
  cfg.stagePresent = opts.stagePresent
  cfg.stagePop = opts.stagePop
  if not cfg.readMode or not cfg.setMode then
    log.w("configured with no overlay placement reader or writer, the Where the OLM "
      .. "launcher appears page will show and change nothing")
  end
  return self
end

return M
