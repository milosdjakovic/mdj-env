--- === Processes.chooser ===
---
--- The list surface over the engine. Pure policy, it talks to the engine only
--- through the injected api table and knows nothing about how a scan is performed
--- or what a source is.
---
--- Mostly a flat list, which is the point. Unlike the display profiles menu there
--- is nothing to drill into, you find a thing and you stop it, so Return running a
--- terminal action and letting the native chooser close is exactly right and no
--- Return interception is needed. The one exception is a stop the source refuses to
--- take silently, which re-shows as a two row confirmation, so the frame state here
--- is a single nullable pending stop rather than a menu stack.
---
--- The confirmation leads with the harmless row. A stray Return on a confirm screen
--- must never be the destructive answer, the same reason the display profiles delete
--- leads with Keep.

local M = { name = "Processes.chooser" }

local chooserPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(chooserPath .. "util.lua")()

local cfg = {}         -- injected, api from the spoon root, view deps from the main root
local chooser = nil    -- the one native Chooser instance
local rows = {}        -- rows from the most recent scan, read by the supplier
local pending = nil    -- a stop awaiting confirmation, { row = ..., message = ... }
local reopen = false   -- ask onClose to re-show rather than end, for the confirmation
local scanning = false -- guards against overlapping scans from a fast refresh

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji to a small image once and cache it, since the supplier runs on
-- every keystroke. The same helper the other choosers use.
local glyphCache = {}
local function emojiImage(str)
  local hit = glyphCache[str]
  if hit ~= nil then return hit or nil end
  local size = 28
  local cv = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  cv[1] = { type = "text", text = str, textSize = 21, textAlignment = "center",
            frame = { x = 0, y = 0, w = size, h = size } }
  local img = cv:imageFromCanvas()
  cv:delete()
  glyphCache[str] = img or false
  return img
end

-- Keyed by the runtime the source reported, falling back to a generic glyph, so an
-- unfamiliar runtime still gets a row rather than an empty icon slot.
local ICON = {
  docker = "🐳",
  node = "🟩", deno = "🦕", bun = "🥟",
  python = "🐍", python2 = "🐍", python3 = "🐍",
  ruby = "💎", puma = "💎", rails = "💎",
  java = "☕", kotlin = "☕", scala = "☕",
  php = "🐘", perl = "🐫", dotnet = "🟪",
  caddy = "🌐", nginx = "🌐",
}
local ICON_FALLBACK = "⚙️"
local ICON_EMPTY = "🚫"
local ICON_KEEP = "↩️"
local ICON_STOP = "🛑"

local function iconFor(runtime)
  return emojiImage(ICON[(runtime or ""):lower()] or ICON_FALLBACK)
end

--------------------------------------------------------------------------------
-- Row text
--------------------------------------------------------------------------------

-- Ports sit in the TITLE rather than the subtitle, next to the name, because the
-- port is half the identity of a development server and the thing you scan the list
-- for. The native chooser has no second column to right align them into, so they
-- trail the name instead of sitting at the edge.
local function titleFor(row)
  local ports = row.ports or {}
  if #ports == 0 then return row.title end
  local parts = {}
  for _, p in ipairs(ports) do parts[#parts + 1] = ":" .. p end
  return row.title .. "   " .. table.concat(parts, " ")
end

local function subtitleFor(row)
  local bits = {}
  bits[#bits + 1] = row.runtime
  if row.pid then bits[#bits + 1] = "pid " .. row.pid end
  if row.rss then bits[#bits + 1] = util.humanBytes(row.rss) end
  if row.status and row.status ~= "" then bits[#bits + 1] = row.status:lower() end
  if row.command and row.command ~= "" and row.command ~= row.title then
    bits[#bits + 1] = row.command
  end
  return util.elide(table.concat(bits, " · "), 150)
end

-- Everything a query may match, beyond what is visible. The port matters most, so a
-- half remembered ":3000" or a bare "3000" finds its listener, and the working
-- directory is folded in so a project name that never reaches the label still hits.
--
-- Lowercased here because the words matcher folds case on the query only and
-- compares the haystack verbatim, by contract, so the caller owns that fold. Without
-- it a runtime lsof reports as "Python" would not answer to "python", and no
-- container or project name with a capital in it would match a lowercase query.
-- Folding per keystroke is what the clipboard avoids, but these are a couple of
-- dozen short strings rather than long bodies, so the cost is nothing here.
--
-- Appended one at a time rather than built as a table literal. A local row has no
-- container name and a container row has no working directory, so exactly one field
-- is always nil and a literal would leave a hole that makes table.concat throw.
local function filterTextFor(row, title, subtitle)
  local bits = {}
  local function add(v) if v and v ~= "" then bits[#bits + 1] = v end end
  add(title)
  add(subtitle)
  add(row.cwd)
  add(row.containerName)
  add(row.runtime)
  for _, p in ipairs(row.ports or {}) do bits[#bits + 1] = tostring(p) end
  return table.concat(bits, " "):lower()
end

--------------------------------------------------------------------------------
-- Row suppliers
--------------------------------------------------------------------------------

local function listRows()
  if #rows == 0 then
    return { { title = "Nothing running", enabled = false,
               subTitle = "No development servers or containers found",
               image = emojiImage(ICON_EMPTY) } }
  end
  local out = {}
  for _, row in ipairs(rows) do
    local title, subtitle = titleFor(row), subtitleFor(row)
    out[#out + 1] = {
      title = title,
      subTitle = subtitle,
      image = iconFor(row.runtime),
      filterText = filterTextFor(row, title, subtitle),
      -- Serializable only. hs.chooser drops a function off a row, which is why
      -- every list tool here carries a descriptor and looks the real thing up on
      -- select rather than closing over it.
      item = { key = row.key },
    }
  end
  return out
end

-- The confirmation. Harmless answer first, so the fresh highlight and a stray Return
-- both leave the thing running.
local function confirmRows()
  return {
    { title = "Keep it running", subTitle = "", image = emojiImage(ICON_KEEP),
      item = { confirm = false } },
    { title = "Stop anyway", subTitle = pending.message or "",
      image = emojiImage(ICON_STOP), item = { confirm = true } },
  }
end

local function supplier()
  if pending then return confirmRows() end
  return listRows()
end

--------------------------------------------------------------------------------
-- Acting on a row
--------------------------------------------------------------------------------

local function rowByKey(key)
  for _, row in ipairs(rows) do
    if row.key == key then return row end
  end
  return nil
end

local function report(ok, message)
  if message and message ~= "" then hs.alert.show(message) end
end

-- Run a stop and deal with the three outcomes. Done, refused for a reason the user
-- should see, or refused only because the target is large, which becomes the
-- confirmation rather than an error.
local function runStop(row, opts)
  cfg.api.stop(row, opts, function(ok, message)
    if ok then
      report(true, message)
      return
    end
    if not opts.confirmed and message and message:find("confirm") then
      pending = { key = row.key, message = message }
      reopen = true
      -- The native chooser has already closed on the selection, so the confirm
      -- frame is shown on the next tick once it has finished hiding.
      hs.timer.doAfter(0, function()
        if chooser then chooser:show() end
      end)
      return
    end
    report(false, message or "could not stop")
  end)
end

local function onSelect(item)
  if not item then pending = nil return end

  if pending then
    local row = rowByKey(pending.key)
    local confirmed = item.confirm
    pending = nil
    if confirmed and row then runStop(row, { confirmed = true }) end
    return
  end

  local row = item.key and rowByKey(item.key)
  if row then runStop(row, {}) end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.show() - scan, then open on the result.
--- The scan is asynchronous, so the picker is shown only once the rows are in hand,
--- the same order TextCase reads a selection before opening. Showing first and
--- filling in later would flash an empty list on every open for no gain, a scan
--- costs well under a tenth of a second.
function M.show()
  if scanning then return end
  pending = nil
  scanning = true
  cfg.api.scan(function(result)
    scanning = false
    rows = result or {}
    if chooser then chooser:show() end
  end)
end

--- M.refresh() - rescan and redraw in place, without closing.
function M.refresh()
  if not (chooser and chooser:isShowing()) or scanning then return end
  scanning = true
  cfg.api.scan(function(result)
    scanning = false
    rows = result or {}
    if chooser and chooser:isShowing() then chooser:refresh() end
  end)
end

--- M.stopForced() - stop the highlighted row with no grace period and no size
--- confirmation. The deliberate escape hatch for something already wedged, which is
--- why it skips the guard that a plain stop respects.
function M.stopForced()
  if not (chooser and chooser:isShowing()) or pending then return end
  local item = chooser:selectedItem()
  local row = item and item.key and rowByKey(item.key)
  if not row then return end
  chooser:hide()
  runStop(row, { force = true, confirmed = true })
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
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

function M.insertSelected()
  if chooser then chooser:insertSelected() end
end

--- M.configure(opts) - merge injected deps across the two callers. The spoon root
--- injects `api`, the view over the engine. The main root injects `theme`, the
--- Chooser factory as `chooser`, the matcher, and the docked shortcut panel
--- callbacks, the same seams every other chooser receives.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- M.start() - build the one native chooser, once both configures have run.
function M.start()
  chooser = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = cfg.placeholder or "Search by project, port, or runtime",
    fieldMode = "filter",
    -- The word matcher rather than the shared fuzzy default, the same choice the
    -- clipboard makes and for the same reason. A query here is a real fragment you
    -- remember, a port number or a project name, not an abbreviation of a short
    -- known label, and subsequence matching over a haystack containing digits and
    -- paths ranks badly on exactly those. Words also keeps the engine's recency
    -- order instead of reranking it.
    matcher = cfg.matcher,
    rows = supplier,
    onSelect = onSelect,
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    -- Compose the root's panel teardown with the confirmation behavior. A pending
    -- confirm asked to re-show, anything else is a real dismissal and clears it, so
    -- an escape out of the confirmation leaves the process alone.
    onClose = function()
      if cfg.onClose then cfg.onClose() end
      if reopen then
        reopen = false
      else
        pending = nil
      end
    end,
  })
  return M
end

return M
