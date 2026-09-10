-- Live probe for the canvas text field, phase two of docs/PLAN-CANVAS-CHOOSER.md, built
-- from docs/BRIEF-CANVAS-FIELD.md. Opened by a person against the Hammerspoon that is
-- already running, hs -c "dofile('/absolute/path/to/this/file')", never by this session
-- itself, and never a reload of the live config, the field this draws is loaded fresh
-- straight out of this checkout and touches nothing the running config already owns.
--
-- What this proves. A field with no window of its own, no accessibility tree, and no
-- keyboard focus, drawn on a canvas that only this probe owns, taking every key down
-- while it is up and answering to a hand the way an ordinary macOS text field would,
-- typing, arrow and word and line movement, selection, the emacs bindings, copy, cut,
-- paste, undo, redo, and escape to leave. Milos judges the feel from here, not the
-- assertion count, that judgment is what the acceptance section of the brief calls the
-- actual gate on phase three.
--
-- The one hazard a canvas field carries that a real field never does is this file's own
-- to guard against. Nothing here takes keyboard focus, so a tap left running after a
-- mistake keeps swallowing every key from whatever is frontmost with no window to close
-- to get it back. Escape tears the field down, and a sixty second watchdog tears it down
-- again regardless of whatever else has or has not happened, so a hand that walks away or
-- a bug that leaves escape unreachable both end the same way, on their own, within a
-- minute.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local fieldDir = here .. "../lib/chooser/providers/canvas/field/"

local function loadField(name)
  local chunk, err = loadfile(fieldDir .. name)
  if not chunk then
    error("Olm canvas field probe, failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local input = loadField("input.lua")
local render = loadField("render.lua")

--------------------------------------------------------------------------------
-- A plausible surface, centred on the screen holding the mouse
--------------------------------------------------------------------------------

local CANVAS_W, CANVAS_H = 480, 56
local FIELD_PAD = 16

local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen() or hs.screen.primaryScreen()
local sf = screen:frame()
local canvasFrame = {
  x = sf.x + (sf.w - CANVAS_W) / 2,
  y = sf.y + (sf.h - CANVAS_H) / 2,
  w = CANVAS_W, h = CANVAS_H,
}

local dark = hs.host.interfaceStyle() == "Dark"

-- A plausible style, hand set here rather than read from config/settings.lua, since
-- this probe answers whether the field feels right on its own, not whether it inherits
-- the production theme correctly, which is a wiring question for a later phase once
-- something depends on this field at all.
local style = {
  fontSize = 16,
  textColor = dark and { white = 0.92 } or { white = 0.15 },
  selectionColor = dark and { white = 1, alpha = 0.20 } or { white = 0, alpha = 0.14 },
  caretColor = dark and { white = 0.92 } or { white = 0.15 },
}

local canvas = hs.canvas.new(canvasFrame)
canvas:level(hs.canvas.windowLevels.popUpMenu)

local fieldRect = { x = FIELD_PAD, y = 0, w = CANVAS_W - 2 * FIELD_PAD, h = CANVAS_H }

-- The real shared chrome when Olm is the spoon actually running, which it is, this file
-- is only ever opened against a live checkout of this same config. A plain rectangle
-- stands in if that instance cannot be reached for whatever reason, so this probe still
-- draws something rather than failing before a hand ever reaches the keyboard.
local function surfaceChrome()
  if spoon.Olm and spoon.Olm.lib and spoon.Olm.lib.panel then
    local ok, els = pcall(spoon.Olm.lib.panel.surfaceElements, CANVAS_W, CANVAS_H)
    if ok and els then return els end
  end
  return {
    { type = "rectangle", action = "fill",
      fillColor = dark and { white = 0.15, alpha = 1 } or { white = 0.85, alpha = 1 },
      frame = { x = 0, y = 0, w = CANVAS_W, h = CANVAS_H } },
  }
end

--------------------------------------------------------------------------------
-- The field itself, the blink timer, and the teardown every road here leads to
--------------------------------------------------------------------------------

local field
local blinkTimer
local watchdog
local caretVisible = true
local torn = false

local function redraw()
  local els = surfaceChrome()
  local state = field:getState()
  for _, el in ipairs(render.elements(state, fieldRect, style, caretVisible)) do
    els[#els + 1] = el
  end
  canvas:replaceElements(els)
end

-- Half a second on, half a second off, restarted from visible on every keystroke, which
-- is what makes typing read as continuous rather than as the caret happening to be in
-- its off half a moment ago. Decision four keeps this clock out of model.lua and
-- render.lua alike, so it lives here, the one file that owns the field for as long as
-- this probe is up.
local function resetBlink()
  caretVisible = true
  if blinkTimer then blinkTimer:stop() end
  blinkTimer = hs.timer.doEvery(0.5, function()
    caretVisible = not caretVisible
    redraw()
  end)
end

-- Every road out of this probe, escape, the watchdog, or a person killing Hammerspoon
-- itself, runs through here, guarded so the watchdog firing after escape already closed
-- things does nothing a second time.
local function teardown(reason)
  if torn then return end
  torn = true
  if field then field:stop() end
  if blinkTimer then
    blinkTimer:stop()
    blinkTimer = nil
  end
  if watchdog then
    watchdog:stop()
    watchdog = nil
  end
  if canvas then canvas:hide() end
  print("Olm canvas field probe torn down, " .. tostring(reason))
end

field = input.Field.new({
  text = "",
  onChange = function()
    resetBlink()
    redraw()
  end,
  onKey = function(ev)
    print("Olm canvas field probe, an unclaimed key reached onKey, keycode "
      .. tostring(ev:getKeyCode()))
  end,
  onDismiss = function()
    teardown("escape")
  end,
})

field:start()
resetBlink()
redraw()
canvas:show()

-- The hard limit decision seven and the brief both ask for, tearing the field down
-- whatever else has happened, a hand that walked away or a mistake that left escape
-- unreachable both end the same way rather than leaving a tap armed against whatever is
-- frontmost indefinitely.
--
-- A minute is the default and is what the brief asks for, since it is the shortest wait
-- that is not itself annoying. Working through a checklist by hand takes longer than that,
-- so a caller may set olmCanvasFieldProbeSeconds before the dofile to widen it for one
-- run. It is clamped, because the whole value of this limit is that no caller can talk it
-- out of firing.
local requested = tonumber(rawget(_G, "olmCanvasFieldProbeSeconds") or 60) or 60
local limit = math.max(10, math.min(600, requested))
watchdog = hs.timer.doAfter(limit, function()
  teardown("the " .. tostring(math.floor(limit)) .. " second watchdog")
end)

print("Olm canvas field probe is up, centred on the screen holding the mouse.")
print("Type to insert. Left and right move by character, option by word, cmd to either end.")
print("Add shift to any of those three to extend a selection instead of moving past it.")
print("Delete and forward delete remove a character, option a word, cmd the line to the start.")
print("Cmd a selects all. Cmd c copies, cmd x cuts, cmd v pastes.")
print("Cmd z undoes, cmd shift z redoes.")
print("Ctrl a, ctrl e, ctrl b, ctrl f, ctrl d, ctrl h and ctrl k are honoured as well.")
print("Escape ends the field now. With no escape it ends itself in " .. tostring(math.floor(limit)) .. " seconds.")
