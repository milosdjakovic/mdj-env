--- === Workspaces.engine ===
---
--- The mechanism, three questions and nothing else. Which displays are attached and what role
--- each plays. What is open right now, as a snapshot worth storing. And where each recorded
--- window goes when a layout is applied. It watches nothing, holds no state, and never launches,
--- closes, or hides anything. An app that is not running when a layout is applied is reported as
--- not open and left that way, which is the whole contract, a layout says where windows go and
--- never which windows should exist.
---
--- The earlier engine here was a watcher, recording every window move under a fingerprint of the
--- attached screens and putting windows back on its own after a dock or a wake. It was replaced
--- because remembering on its own meant remembering whatever macOS or an app last did, and the
--- correction surface for that was a chore nobody wanted. This one remembers only what a person
--- asked it to, when they asked.
---
--- DISPLAYS ARE NAMED BY ROLE, NEVER BY MONITOR. A display is the built in panel or an external
--- one, and externals are numbered left to right by position. So a layout knows a window was on
--- the external display, not that it was on one particular Dell, and the same layout applies in
--- front of any external monitor. The built in panel is recognised by the display UUID Apple
--- gives every Apple silicon built in panel, which is a constant rather than a per machine
--- value, with the display name as the fallback for an Intel machine, where the UUID differs and
--- the name is the only signal Hammerspoon exposes. hs.screen has no built in flag of its own.
---
--- FRAMES ARE FRACTIONS OF THE DISPLAY, NEVER POINTS. A window's frame is stored as a unit rect
--- of the visible frame of the display it sat on, so a layout taken in front of a 27 inch monitor
--- lands sensibly in front of a 24 inch one, and a different dock size or menu bar height moves
--- nothing off the display.

local E = {}

local OWN_BUNDLE = "org.hammerspoon.Hammerspoon"
local BUILTIN_UUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
local TOLERANCE = 5

--------------------------------------------------------------------------------
-- Displays and roles
--------------------------------------------------------------------------------

local function isBuiltin(screen)
  if screen:getUUID() == BUILTIN_UUID then return true end
  local name = screen:name() or ""
  return name:find("Built%-in") ~= nil or name == "Color LCD"
end

--- E.externalRole(i) -> string
--- The role name of the i-th external display counted left to right, "external" for the first
--- so the common single external case reads plainly in the file.
function E.externalRole(i)
  return i == 1 and "external" or ("external" .. i)
end

--- E.attached() -> { internal = bool, externals = n, byRole = { role = hs.screen } }
--- The displays attached right now, the built in panel under "internal" and every other one
--- under an external role in left to right order. Read fresh on every call, since a snapshot and
--- an apply are each one person's key press and a cached answer could only ever be stale.
function E.attached()
  local internal, externals = nil, {}
  for _, s in ipairs(hs.screen.allScreens()) do
    if not internal and isBuiltin(s) then internal = s else externals[#externals + 1] = s end
  end
  table.sort(externals, function(a, b)
    local fa, fb = a:fullFrame(), b:fullFrame()
    if fa.x ~= fb.x then return fa.x < fb.x end
    return fa.y < fb.y
  end)
  local byRole = {}
  if internal then byRole.internal = internal end
  for i, s in ipairs(externals) do byRole[E.externalRole(i)] = s end
  return { internal = internal ~= nil, externals = #externals, byRole = byRole }
end

--- E.topologyLabel(t) -> string
--- A topology in words, for a row's detail. t is { internal = bool, externals = n }.
function E.topologyLabel(t)
  t = t or {}
  local n = t.externals or 0
  local ext
  if n == 1 then ext = "one external display"
  elseif n == 2 then ext = "two external displays"
  elseif n > 2 then ext = n .. " external displays" end
  if t.internal and n == 0 then return "the built in display only" end
  if t.internal then return "the built in display and " .. ext end
  if n == 0 then return "no display" end
  return ext .. ", lid closed"
end

--- E.roleLabel(role) -> string
function E.roleLabel(role)
  if role == "internal" then return "the built in display" end
  if role == "external" then return "the external display" end
  local n = tonumber((role or ""):match("^external(%d+)$"))
  if n then
    local ordinal = ({ "second", "third", "fourth" })[n - 1] or (n .. "th")
    return "the " .. ordinal .. " external display"
  end
  return "an unknown display"
end

-- What a layout needs from the displays, the roles its included windows sit on.
local function rolesNeeded(layout)
  local needsInternal, externals = false, 0
  for _, app in ipairs(layout.apps or {}) do
    if not app.excluded then
      for _, w in ipairs(app.windows or {}) do
        if w.display == "internal" then needsInternal = true end
        local n = w.display == "external" and 1 or tonumber((w.display or ""):match("^external(%d+)$"))
        if n and n > externals then externals = n end
      end
    end
  end
  return needsInternal, externals
end

--- E.availability(layout, attached) -> available, reason
--- Whether every display a layout places a window on is attached right now. A layout taken on
--- the built in display alone applies just as well with an external plugged in, since the built
--- in display is still there, so availability is about what the layout needs rather than an
--- exact match of the topology it was taken under. The reason names what is missing.
function E.availability(layout, attached)
  attached = attached or E.attached()
  local needsInternal, externals = rolesNeeded(layout)
  if needsInternal and not attached.internal then
    return false, "needs the built in display"
  end
  if externals > attached.externals then
    if externals == 1 then return false, "needs an external display" end
    return false, "needs " .. externals .. " external displays"
  end
  return true
end

--------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------

-- A window worth recording or placing, standard and neither minimized nor fullscreen, and not
-- one of ours. The id is asked for first because a window object that outlived its window
-- answers nil to everything.
local function placeable(win)
  if win == nil or not win:id() then return false end
  if not win:isStandard() then return false end
  if win:isMinimized() or win:isFullScreen() then return false end
  local app = win:application()
  if app and app:bundleID() == OWN_BUNDLE then return false end
  return true
end

local function round4(v)
  return math.floor((tonumber(v) or 0) * 10000 + 0.5) / 10000
end

--- E.snapshot() -> { topology = { internal, externals }, apps = { { bundle, name, windows } } }
--- What is open right now on the current Space, grouped by app and sorted by app name, each
--- window as the role of the display it sits on and its frame as a unit rect of that display's
--- visible frame. Windows keep the order hs.window.allWindows answers them in, front to back,
--- which is the order apply falls back to when titles do not match.
function E.snapshot()
  local attached = E.attached()
  local roleOf = {}
  for role, s in pairs(attached.byRole) do roleOf[s:id()] = role end
  local byBundle, apps = {}, {}
  for _, win in ipairs(hs.window.allWindows()) do
    if placeable(win) then
      local app = win:application()
      local bundle = app and app:bundleID()
      local screen = win:screen()
      local role = bundle and screen and roleOf[screen:id()]
      if role then
        local entry = byBundle[bundle]
        if not entry then
          entry = { bundle = bundle, name = app:name() or bundle, windows = {} }
          byBundle[bundle] = entry
          apps[#apps + 1] = entry
        end
        local unit = screen:toUnitRect(win:frame())
        entry.windows[#entry.windows + 1] = {
          title = win:title() or "",
          display = role,
          unit = { x = round4(unit.x), y = round4(unit.y), w = round4(unit.w), h = round4(unit.h) },
        }
      end
    end
  end
  table.sort(apps, function(a, b) return a.name:lower() < b.name:lower() end)
  return { topology = { internal = attached.internal, externals = attached.externals }, apps = apps }
end

local function sameFrame(a, b)
  return math.abs(a.x - b.x) <= TOLERANCE and math.abs(a.y - b.y) <= TOLERANCE
    and math.abs(a.w - b.w) <= TOLERANCE and math.abs(a.h - b.h) <= TOLERANCE
end

local function screenAt(x, y)
  for _, s in ipairs(hs.screen.allScreens()) do
    local fr = s:fullFrame()
    if x >= fr.x and x < fr.x + fr.w and y >= fr.y and y < fr.y + fr.h then return s:id() end
  end
  return nil
end

-- Set a frame and read it back. An app with a grid of its own, a terminal snapping to cell
-- boundaries or a window with a minimum size, never answers the exact frame and never will, so
-- a readback off by more than the tolerance still counts as landed as long as it landed on the
-- display that was asked for. Only a window macOS pushed onto some other display is a refusal.
local function place(win, f)
  local cur = win:frame()
  if sameFrame(cur, f) then return true end
  win:setFrame(hs.geometry.rect(f.x, f.y, f.w, f.h), 0)
  local after = win:frame()
  if sameFrame(after, f) then return true end
  local wanted = screenAt(f.x + f.w / 2, f.y + f.h / 2)
  local got = screenAt(after.x + after.w / 2, after.y + after.h / 2)
  return wanted ~= nil and wanted == got
end

local function validUnit(u)
  if type(u) ~= "table" then return false end
  return type(u.x) == "number" and type(u.y) == "number" and type(u.w) == "number" and type(u.h) == "number"
end

-- The standard windows of every running instance of a bundle, front to back.
local function liveWindows(bundle)
  local out = {}
  for _, app in ipairs(hs.application.applicationsForBundleID(bundle) or {}) do
    for _, win in ipairs(app:allWindows() or {}) do
      if placeable(win) then out[#out + 1] = win end
    end
  end
  return out
end

-- Pair recorded windows with live ones. A title that matches exactly wins first, so two Chrome
-- windows go back to their own places rather than swapping, and whatever is left is paired in
-- order, front to back on both sides, since a title that changed with the tab is still most
-- likely the same window in the same place in the stack.
local function pairWindows(recorded, live)
  local pairs_, usedLive, usedRec = {}, {}, {}
  for ri, r in ipairs(recorded) do
    for li, w in ipairs(live) do
      if not usedLive[li] and (r.title or "") ~= "" and w:title() == r.title then
        pairs_[#pairs_ + 1] = { r, w }
        usedLive[li], usedRec[ri] = true, true
        break
      end
    end
  end
  local li = 1
  for ri, r in ipairs(recorded) do
    if not usedRec[ri] then
      while li <= #live and usedLive[li] do li = li + 1 end
      if li > #live then break end
      pairs_[#pairs_ + 1] = { r, live[li] }
      usedLive[li] = true
    end
  end
  return pairs_
end

--- E.apply(layout) -> report
--- Place every included app's windows where the layout recorded them and say what happened to
--- each app. The report is a list, in the layout's own order, of
---   { bundle, name, status, placed, recorded }
--- where status is one of
---   "placed"      every recorded window found a live one and landed,
---   "partial"     some did, placed says how many of recorded,
---   "notOpen"     the app is not running, and it is left that way,
---   "noWindow"    the app is running with no standard window to place,
---   "noDisplay"   its windows sit on a display that is not attached,
---   "refused"     macOS would not put the window where it was asked.
--- Excluded apps are not in the report at all, since the layout does not speak for them.
function E.apply(layout)
  local attached = E.attached()
  local report = {}
  for _, app in ipairs(layout.apps or {}) do
    if not app.excluded then
      local recorded = {}
      for _, w in ipairs(app.windows or {}) do
        if validUnit(w.unit) and type(w.display) == "string" then recorded[#recorded + 1] = w end
      end
      local row = { bundle = app.bundle, name = app.name or app.bundle, placed = 0, recorded = #recorded }
      local live = liveWindows(app.bundle)
      if #hs.application.applicationsForBundleID(app.bundle) == 0 then
        row.status = "notOpen"
      elseif #live == 0 then
        row.status = "noWindow"
      else
        local missing, refused = 0, 0
        for _, pair in ipairs(pairWindows(recorded, live)) do
          local r, win = pair[1], pair[2]
          local screen = attached.byRole[r.display]
          if not screen then
            missing = missing + 1
          elseif place(win, screen:fromUnitRect(hs.geometry.rect(r.unit.x, r.unit.y, r.unit.w, r.unit.h))) then
            row.placed = row.placed + 1
          else
            refused = refused + 1
          end
        end
        if row.placed == #recorded then row.status = "placed"
        elseif row.placed > 0 then row.status = "partial"
        elseif missing > 0 then row.status = "noDisplay"
        elseif refused > 0 then row.status = "refused"
        else row.status = "partial" end
      end
      report[#report + 1] = row
    end
  end
  return report
end

return E
