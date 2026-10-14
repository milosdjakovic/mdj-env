-- Live probe for the two canvas shells, phase three b of docs/PLAN-CANVAS-CHOOSER.md,
-- built from docs/BRIEF-CANVAS-SHELLS.md. Opened by a person against the Hammerspoon that
-- is already running, hs -c "dofile('/absolute/path/to/this/file')", never by this
-- session itself, and never a reload of the live config. Surface and Mouse are loaded
-- fresh straight out of this checkout, only lib.panel is reached from the live spoon.Olm
-- instance, since that is the one piece this probe cannot fake, the shared chrome a real
-- surface is judged against.
--
-- What this proves. A window drawn on hs.canvas that a hand can move and resize while it
-- stays on screen, proving setFrame is live rather than something that costs a hide and a
-- show, and a mouse tap that claims a click, a move or a scroll over that window and lets
-- the same kind of event through everywhere else on the screen, so whatever sits under the
-- window keeps answering to a hand exactly as if this probe were not open at all. The
-- window never takes key focus at any point in this, which a hand can confirm simply by
-- typing into whatever application is frontmost while the window sits there moving.
--
-- Only events over the window's own current frame are printed. A move or a scroll or a
-- click anywhere else on the whole screen still reaches whatever is under the pointer,
-- exactly as decision two of the brief asks for, but this file has no reason to narrate
-- every one of those, a hand judges that half by watching the machine stay usable rather
-- than by reading a flooded console. Printing every mouse move across the whole screen
-- would bury the lines that actually matter, so this probe only ever speaks about what its
-- own window saw and claimed.
--
-- The window moves and resizes itself on a timer through three frames in turn, proving
-- setFrame is live, and a hand does not have to do anything for that half of the proof
-- beyond watching it happen and beyond confirming that the claiming rule still holds true
-- at each new size and position, not only at the first one.
--
-- The one hazard a mouse tap carries that this probe guards against is its own to answer
-- for. Nothing here takes keyboard focus, so a tap left running after a mistake keeps
-- claiming clicks and scrolls over wherever its window last sat, with no window to close
-- to get it back. Escape tears everything down through a small key tap this file owns for
-- exactly that purpose and for nothing else, and a watchdog tears it down again regardless
-- of whatever else has or has not happened, so a hand that walks away or a mistake that
-- leaves escape unreachable both end the same way, on their own, within a bounded time.
-- Sixty seconds is the default and is what the brief asks for, since it is the shortest
-- wait that is not itself annoying, and a caller may set olmCanvasShellsProbeSeconds before
-- the dofile to widen it for one run, clamped between ten and six hundred seconds so no
-- caller can talk the limit out of firing at all.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local canvasDir = here .. "../lib/chooser/providers/default/"

local function loadFrom(dir, name)
  local chunk, err = loadfile(dir .. name)
  if not chunk then
    error("Olm canvas shells probe, failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local Surface = loadFrom(canvasDir, "surface.lua")
local Mouse = loadFrom(canvasDir, "mouse.lua")

-- The one piece reached from the live instance rather than loaded fresh, the shared
-- chrome a real surface has to be judged against. This probe is only ever opened against
-- a live checkout of this same config, so spoon.Olm is already up.
local panel = spoon.Olm and spoon.Olm.lib and spoon.Olm.lib.panel
if not panel then
  error("Olm canvas shells probe needs the running Olm instance's lib.panel, spoon.Olm does not appear to be loaded")
end

--------------------------------------------------------------------------------
-- Three frames to cycle through, centred on the screen holding the mouse, so a hand sees
-- the window move and resize without having to place it by hand first
--------------------------------------------------------------------------------

local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen() or hs.screen.primaryScreen()
local sf = screen:frame()

local function centered(w, h, offsetX, offsetY)
  return {
    x = sf.x + (sf.w - w) / 2 + (offsetX or 0),
    y = sf.y + (sf.h - h) / 2 + (offsetY or 0),
    w = w, h = h,
  }
end

local FRAMES = {
  centered(420, 260, 0, 0),
  centered(420, 260, 160, -90),
  centered(300, 340, -160, 90),
}

local dark = hs.host.interfaceStyle() == "Dark"

-- A couple of plain shapes plus a label, sized against whatever the current frame
-- happens to be, so the surface has something on it besides the shared chrome, and so
-- that a resize on the timer visibly redraws them at the new size rather than leaving
-- stale shapes sized for the frame before it.
local function shapes(w, h)
  local textColor = dark and { white = 0.92 } or { white = 0.15 }
  return {
    { type = "rectangle", action = "fill",
      fillColor = { red = 0.30, green = 0.52, blue = 0.90, alpha = 0.85 },
      frame = { x = w * 0.08, y = h * 0.15, w = w * 0.35, h = h * 0.30 } },
    { type = "oval", action = "fill",
      fillColor = { red = 0.88, green = 0.42, blue = 0.30, alpha = 0.85 },
      frame = { x = w * 0.55, y = h * 0.15, w = w * 0.37, h = h * 0.30 } },
    { type = "text", text = "Olm canvas shells probe", textSize = 15,
      textAlignment = "center", textColor = textColor,
      frame = { x = 0, y = h * 0.55, w = w, h = 26 } },
    { type = "text", text = "move, click and scroll over this window", textSize = 12,
      textAlignment = "center", textColor = textColor,
      frame = { x = 0, y = h * 0.55 + 24, w = w, h = 22 } },
  }
end

--------------------------------------------------------------------------------
-- The surface, the mouse tap, the escape tap, the frame cycling timer, and the teardown
-- every road here leads to
--------------------------------------------------------------------------------

local surface = Surface.new({ panel = panel })
local mouse
local escapeTap
local cycleTimer
local watchdog
local torn = false
local currentFrame = FRAMES[1]
local frameIndex = 1

local function redraw()
  surface:draw(shapes(currentFrame.w, currentFrame.h))
end

local function pointInFrame(p, fr)
  return p.x >= fr.x and p.x <= fr.x + fr.w and p.y >= fr.y and p.y <= fr.y + fr.h
end

local function fmtPoint(p)
  return string.format("%.0f, %.0f", p.x, p.y)
end

-- Only a point inside the window's own current frame is claimed and printed, everywhere
-- else the same kind of event is let through untouched, which is the one behaviour this
-- whole probe exists to let a hand judge.
mouse = Mouse.new({
  onDown = function(point, button)
    if not pointInFrame(point, currentFrame) then return false end
    print("Olm canvas shells probe, " .. button .. " down at " .. fmtPoint(point))
    return true
  end,
  onUp = function(point, button)
    if not pointInFrame(point, currentFrame) then return false end
    print("Olm canvas shells probe, " .. button .. " up at " .. fmtPoint(point))
    return true
  end,
  onMove = function(point)
    if not pointInFrame(point, currentFrame) then return false end
    print("Olm canvas shells probe, move at " .. fmtPoint(point))
    return true
  end,
  onScroll = function(point, dy, continuous)
    if not pointInFrame(point, currentFrame) then return false end
    print("Olm canvas shells probe, scroll dy " .. string.format("%.1f", dy)
      .. " continuous " .. tostring(continuous) .. " at " .. fmtPoint(point))
    return true
  end,
})

local ESCAPE_KEYCODE = 53

local function teardown(reason)
  if torn then return end
  torn = true
  if mouse then mouse:stop() end
  if escapeTap then
    escapeTap:stop()
    escapeTap = nil
  end
  if cycleTimer then
    cycleTimer:stop()
    cycleTimer = nil
  end
  if watchdog then
    watchdog:stop()
    watchdog = nil
  end
  if surface then
    surface:hide()
    surface:delete()
  end
  print("Olm canvas shells probe torn down, " .. tostring(reason))
end

-- A small key tap owned only by this probe and for nothing but escape, the same small
-- surface field/input.lua answers escape with before its own keymap is even asked.
escapeTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
  if ev:getKeyCode() == ESCAPE_KEYCODE then
    teardown("escape")
    return true
  end
  return false
end)

surface:setFrame(currentFrame)
redraw()
surface:show()
mouse:start()
escapeTap:start()

-- Cycles the window through the three frames above, proving setFrame moves and resizes a
-- window that is already on screen rather than costing a hide and a show, and redrawing
-- the shapes at each new size so nothing sized for the frame before it is left stale.
cycleTimer = hs.timer.doEvery(2.5, function()
  frameIndex = (frameIndex % #FRAMES) + 1
  currentFrame = FRAMES[frameIndex]
  surface:setFrame(currentFrame)
  redraw()
end)

-- The hard limit the brief asks for, tearing everything down whatever else has happened.
-- A minute is the default, and a caller may set olmCanvasShellsProbeSeconds before the
-- dofile to widen it for one run, clamped so no caller can talk it out of firing.
local requested = tonumber(rawget(_G, "olmCanvasShellsProbeSeconds") or 60) or 60
local limit = math.max(10, math.min(600, requested))
watchdog = hs.timer.doAfter(limit, function()
  teardown("the " .. tostring(math.floor(limit)) .. " second watchdog")
end)

print("Olm canvas shells probe is up, centred on the screen holding the mouse.")
print("The window moves and resizes itself every two and a half seconds, through three frames in turn.")
print("Click, move the mouse over it, or scroll over it, each is printed and claimed only while inside its current frame.")
print("The same kind of event anywhere else on screen still reaches whatever is under the pointer, try it against another window.")
print("Typing into whatever app is frontmost should work the whole time, this window never takes keyboard focus.")
print("Escape ends the probe now. With no escape it ends itself in " .. tostring(math.floor(limit)) .. " seconds.")
