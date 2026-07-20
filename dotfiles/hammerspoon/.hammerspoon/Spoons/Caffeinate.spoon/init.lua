--- === Caffeinate ===
---
--- A keep awake tool. Hyper+K opens one native chooser whose search field doubles as the
--- value entry, showing a single row that morphs with what you type. An empty field is the
--- state toggle, Activate while keep awake is off and Deactivate while it is on, its
--- subtitle carrying the live status. A clock like 15:30 morphs the row into a hold until
--- that time, and a duration like 1h30m morphs it into a hold for that span, the subtitle
--- naming the concrete end. Anything half typed or malformed leaves the row disabled with
--- the two format examples, so Return can never apply an empty or invalid value.
---
--- One row, not a list, so the chooser stays a single compact line and there is never a
--- second row to submit by mistake. The two formats never overlap, since a clock needs the
--- colon and a duration needs an h or m suffix, so the query resolves to at most one. The
--- format examples live in the subtitle rather than the placeholder, which kept the
--- placeholder short enough not to clip. Typing a value while a session is already running
--- sets a new bound rather than turning off first, which the engine already supports by
--- replacing the running session.
---
--- This file is the composition root and the command policy. It loads the engine, the keep
--- awake mechanism, and receives the Chooser factory injected by the main root, the shared
--- native picker the menu search and the VPN list also use. It parses the query into rows,
--- turns a chosen row into an engine call, and forwards the deferred shortcut hint panel
--- callbacks straight through without learning what they drive. It is module style with
--- plain functions, so it exposes the same small control surface the clipboard does,
--- isShowing and hide, which the shared control in the main root calls on whichever tool
--- is open.
---
--- Why the native Chooser now and not the webview Panel. The old panel existed only to
--- host inline hours and minutes fields that clamp. Folding the value into the search field
--- removes that need, so keep awake joins the VPN list and the menu search on the one snappy
--- native backend, and the Panel atom retires with no consumer left.

local M = { name = "Caffeinate", version = "3.0", author = "mdj-env" }

-- Load the engine sibling by absolute path, the Capture idiom (a spoon dir is not on
-- package.path). The view is the shared Chooser atom, injected by the root rather than
-- loaded here, since it lives in its own spoon and the clipboard, VPN, and menu search
-- use it too.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local engine = dofile(spoonPath .. "engine.lua")

local cfg = nil       -- injected: the shared theme, the Chooser factory, and the panel callbacks
local chooser = nil   -- the one native Chooser instance

--------------------------------------------------------------------------------
-- Status wording, time parsing, and spans (command policy)
--------------------------------------------------------------------------------

-- The live status as a short line for the primary row subtitle. Off when nothing is held,
-- On with no bound when indefinite, and On until the clock with the minutes left while a
-- timed session runs, collapsing to just the clock once more than an hour remains.
local function statusText(s)
  if not s.active then return "Currently off. Stays awake for good." end
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

-- The next occurrence of a 24 hour clock time, rolling to tomorrow when it already passed
-- today, so 09:00 typed in the afternoon means tomorrow morning.
local function nextOccurrence(h, m)
  local t = os.date("*t")
  t.hour, t.min, t.sec = h, m, 0
  local ts = os.time(t)
  if ts <= os.time() then ts = ts + 86400 end
  return ts
end

-- Parse a clock value, HH:MM or H:MM, into hours and minutes, or nil when it is not a
-- valid time. The colon is required, which is what keeps a clock from colliding with a
-- duration.
local function parseClock(q)
  local h, m = q:match("^(%d%d?):(%d%d)$")
  if not h then return nil end
  h, m = tonumber(h), tonumber(m)
  if h > 23 or m > 59 then return nil end
  return h, m
end

-- Parse a duration value, any mix of an hours part and a minutes part like 1h30m, 90m, or
-- 2h, into a positive second span, or nil when it is not a duration. An h or m suffix is
-- required and the whole string must be consumed, so stray characters fail rather than
-- parsing a partial value.
local function parseDuration(q)
  local hh = q:match("(%d+)h")
  local mm = q:match("(%d+)m")
  if not hh and not mm then return nil end
  local rest = q:gsub("%d+h", ""):gsub("%d+m", "")
  if rest ~= "" then return nil end
  local secs = (tonumber(hh) or 0) * 3600 + (tonumber(mm) or 0) * 60
  if secs <= 0 then return nil end
  return secs
end

-- A second span as a compact human label, 1h 30m, 2h, or 45m, dropping a zero part.
local function humanSpan(secs)
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  if h > 0 and m > 0 then return string.format("%dh %dm", h, m) end
  if h > 0 then return string.format("%dh", h) end
  return string.format("%dm", m)
end

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- Render an emoji string to a small image so a row can carry it as its icon, an offscreen
-- canvas drawn once and cached by the string, since the supplier runs on every keystroke.
-- A false marks a string that cannot render, so it is attempted only once.
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

-- A green circle reads as go, a red one as stop, a clock as an absolute time, an hourglass
-- as a span, a keyboard as the prompt to keep typing.
local ICON = {
  on = "🟢",
  off = "🔴",
  clock = "🕒",
  duration = "⏳",
  hint = "⌨️",
}

-- The two format examples, shown in a subtitle so the placeholder can stay short. The clock
-- example is 24 hour so the format is unambiguous.
local EXAMPLES = "Time 18:45 or duration 2h30m"

--------------------------------------------------------------------------------
-- Row supplier (one morphing row, state and query driven)
--------------------------------------------------------------------------------

-- The single row, whose shape follows the field. An empty field is the state toggle,
-- Deactivate while a session runs with the live status beneath, and Activate for an
-- indefinite hold while off with the format examples beneath. A valid clock morphs it into
-- a hold until that time and a valid duration into a hold for that span, each naming the
-- concrete end. Any other non empty text is not yet a value, so the row is disabled and
-- names the two formats, which keeps Return from applying an empty or half typed value. The
-- status is read live on each call, so the toggle subtitle tracks a session winding down.
local function rows(query)
  local q = (query or ""):gsub("%s+", "")
  local s = engine.status()

  if q == "" then
    if s.active then
      return { { title = "Deactivate", subTitle = statusText(s), image = emojiImage(ICON.off), item = { id = "off" } } }
    end
    return { { title = "Activate", subTitle = "Indefinite. " .. EXAMPLES, image = emojiImage(ICON.on), item = { id = "indefinite" } } }
  end

  local h, m = parseClock(q)
  if h then
    local ts = nextOccurrence(h, m)
    return { { title = string.format("Stay awake until %02d:%02d", h, m), subTitle = "in " .. humanSpan(ts - os.time()), image = emojiImage(ICON.clock), item = { id = "until", ts = ts } } }
  end

  local secs = parseDuration(q)
  if secs then
    return { { title = "Stay awake for " .. humanSpan(secs), subTitle = "ends " .. os.date("%H:%M", os.time() + secs), image = emojiImage(ICON.duration), item = { id = "for", secs = secs } } }
  end

  return { { title = "Keep awake", subTitle = EXAMPLES, image = emojiImage(ICON.hint), enabled = false, item = { id = "hint" } } }
end

--------------------------------------------------------------------------------
-- Selection dispatch (command policy)
--------------------------------------------------------------------------------

-- A row was chosen. Each id maps to one engine call. Applying a timed or indefinite hold
-- replaces any running session, so an override never needs an off first. The hint rows are
-- disabled, so onSelect never fires for them.
local function onSelect(sel)
  if not sel then return end
  if sel.id == "indefinite" then
    engine.keepIndefinitely()
  elseif sel.id == "off" then
    engine.disable()
  elseif sel.id == "until" then
    engine.keepUntil(sel.ts)
  elseif sel.id == "for" then
    engine.keepFor(sel.secs)
  end
end

-- The engine changed while the chooser may be open, a timed session expired. Redraw so the
-- primary row's title and status follow the live state.
local function onChange()
  if chooser and chooser:isShowing() then chooser:refresh() end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard and the VPN list)
--------------------------------------------------------------------------------

--- M.show() - open the keep awake chooser. The list reads the live state itself, so there
--- is nothing to fetch first.
function M.show()
  if chooser then chooser:show() end
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

function M.hide()
  if chooser then chooser:hide() end
end

-- Vim style navigation, routed here from the caffeinate Hyper context by the main root, the
-- same shared control the clipboard and the VPN list use.
function M.selectNext()
  if chooser then chooser:selectNext() end
end

function M.selectPrev()
  if chooser then chooser:selectPrev() end
end

--- M.insertSelected() - apply the highlighted row, exactly as Return does, routed here from
--- Hyper+i.
function M.insertSelected()
  if chooser then chooser:insertSelected() end
end

--- M.configure(opts) - inject the shared theme, the Chooser factory, and the optional
--- docked panel callbacks (onPositioned, onActivity, onClose) the root wires to its
--- deferred shortcut hint panel. The spoon forwards those straight to its chooser without
--- learning what they drive, so the panel stays the root's concern.
function M.configure(opts)
  cfg = opts or {}
  return M
end

--- M.start() - wire the engine and build the one native chooser. Called once by the root.
function M.start()
  engine.configure({ onChange = onChange })
  engine.start()
  chooser = cfg.chooser.new({
    -- Pinned to the native hs.chooser backend, the snappy one the menu search and the VPN
    -- list use. The field is a live filter, so the supplier re-parses the query on every
    -- keystroke and the single row morphs as you type. Two rows tall, since the list only
    -- ever holds the one morphing row but the larger row font clips it at one, so the extra
    -- row of height gives the single row room to render fully.
    provider = "native",
    theme = cfg.theme,
    placeholder = "Time or duration",
    fieldMode = "filter",
    layout = { rowCount = 2 },
    rows = rows,
    onSelect = onSelect,
    -- The root's deferred shortcut hint panel, wired through the chooser's own seams so the
    -- spoon stays ignorant of the panel. All optional, nil when no panel is injected.
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    onClose = cfg.onClose,
  })
  return M
end

return M
