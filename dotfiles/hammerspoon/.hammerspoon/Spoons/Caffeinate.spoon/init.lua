--- === Caffeinate ===
---
--- A keep awake tool. Hyper+K opens a small panel with a short list of actions,
--- Indefinite, For a duration, Until a time, and Off. Up and down move through them,
--- and landing on a timed row focuses its hours and minutes field so you can type at
--- once. Return applies the highlighted row. A running session is overridden by
--- applying another, no off first. The live status shows at the bottom.
---
--- This file is the composition root and the command policy. It loads the engine,
--- the keep awake mechanism, and receives the Panel atom injected by the main root,
--- the shared webview panel mechanism, then names them and wires them together. The
--- panel draws the rows, the inline fields, and the status, and hands back the applied
--- row with its hours and minutes. This file turns that into an engine call, and
--- returns an error string for the panel to show when a value is missing. It is module
--- style with plain functions, so it exposes the same small control surface the
--- clipboard manager does, isShowing and hide, which the shared control in the main
--- root calls on whichever tool is open.
---
--- Why the Panel atom and not the shared Chooser atom. The chooser is a list picker
--- whose rows are always numbered and its field cannot constrain input, right for the
--- clipboard but wrong here. Keep awake wants a short list with inline numeric fields
--- that clamp to hours and minutes, which the webview Panel gives natively. It can
--- also take focus, because keep awake pastes nothing back, unlike the clipboard.

local M = { name = "Caffeinate", version = "2.0", author = "mdj-env" }

-- Load the engine sibling by absolute path, the Capture idiom (a spoon dir is not
-- on package.path). The view is the shared Panel atom, injected by the root rather
-- than loaded here, since it lives in its own spoon and the clipboard and VPN use it
-- too.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local engine = dofile(spoonPath .. "engine.lua")

local cfg = nil   -- injected: the shared theme and the Panel factory
local view = nil

--------------------------------------------------------------------------------
-- Status and parsing (command policy)
--------------------------------------------------------------------------------

local function statusText(s)
  if not s.active then return "Off" end
  if not s.expiry then return "On, indefinite" end
  local rem = s.expiry - os.time()
  if rem <= 0 then return "Ending" end
  local hh = os.date("%H:%M", s.expiry)
  local mins = math.floor(rem / 60)
  if mins < 60 then
    return string.format("On until %s, %d min left", hh, math.max(1, mins))
  end
  return "On until " .. hh
end

-- The next occurrence of a 24 hour clock time, rolling to tomorrow when it already
-- passed today.
local function nextOccurrence(h, m)
  local t = os.date("*t")
  t.hour, t.min, t.sec = h, m, 0
  local ts = os.time(t)
  if ts <= os.time() then ts = ts + 86400 end
  return ts
end

-- The option rows the view shows. Order is the display order. An entry kind of
-- "duration" reads hours and minutes as a span, "clock" reads a 24 hour time, and a
-- row with no entry applies at once. The view builds the fields and clamps them, so
-- this stays pure data.
local OPTIONS = {
  { id = "indefinite", label = "Indefinite" },
  { id = "for",        label = "For a duration", entry = "duration" },
  { id = "until",      label = "Until a time",   entry = "clock" },
  { id = "off",        label = "Off" },
}

-- A row was applied. indefinite and off act at once. for reads hours and minutes as
-- a span and needs a positive total. until reads a 24 hour time and holds awake to
-- its next occurrence. Applying replaces any running session, so an override never
-- needs an off first. Returns nil on success so the view closes, or an error string
-- so it stays open and shows it.
local function onApply(sel)
  local id = sel.id
  if id == "indefinite" then engine.keepIndefinitely(); return nil end
  if id == "off" then engine.disable(); return nil end
  local h, m = tonumber(sel.h) or 0, tonumber(sel.m) or 0
  if id == "for" then
    local secs = h * 3600 + m * 60
    if secs <= 0 then return "Enter a duration" end
    engine.keepFor(secs)
    return nil
  end
  if id == "until" then
    engine.keepUntil(nextOccurrence(h, m))
    return nil
  end
  return nil
end

-- The engine changed while the panel may be open (a timed session expired). Redraw
-- so the status line tracks it.
local function onChange()
  if view then view:refresh() end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard manager)
--------------------------------------------------------------------------------

--- M.show() - open the keep awake panel.
function M.show()
  if view then view:show() end
end

function M.isShowing()
  return view ~= nil and view:isShowing()
end

function M.hide()
  if view then view:close() end
end

-- Vim style navigation, routed here from Hyper+j and Hyper+k by the main root, the
-- same shared control the clipboard uses.
function M.selectNext()
  if view then view:selectNext() end
end

function M.selectPrev()
  if view then view:selectPrev() end
end

--- M.configure(opts) - inject the shared theme and the Panel factory.
function M.configure(opts)
  cfg = opts or {}
  return M
end

--- M.start() - wire the engine and build the view. Called once by the root.
function M.start()
  engine.configure({ onChange = onChange })
  engine.start()
  view = cfg.panel.new({
    name = "caffeinate",
    theme = cfg.theme,
    options = OPTIONS,
    status = function() return statusText(engine.status()) end,
    onApply = onApply,
  })
  return M
end

return M
