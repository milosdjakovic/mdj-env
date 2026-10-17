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
--
-- Phase three a adds the row list underneath, drawn on the very same canvas, filtered by
-- whatever the field's own text says and moved by up and down, two keys the field's own
-- keymap never names, which is exactly why both still reach onKey unclaimed rather than
-- being typed into the buffer as a stray character. Return reads back whichever row the
-- list currently highlights and prints it rather than acting on it, choosing a row for
-- real is the picker's own job and still to come, this phase only asks whether the list
-- looks and moves right, close enough to the real chooser that a hand can compare the two
-- side by side and judge honestly. Rows come from every running application, name as the
-- title and bundle path as the subtitle, real icons included, padded with synthetic rows
-- when this machine is not running enough of them to fill more than one screen of list,
-- and one row among them is marked disabled on purpose so decision seven of the list
-- brief, dimmed and refusing Return, is something a hand can actually see rather than take
-- on faith.
--
-- Round two of this track's build plan withdrew decision three, matching the native
-- chooser's own proportions, since a field built for one short line has no business
-- standing as tall as the real chooser's own nib happened to make it, and asked for a
-- surface designed on its own terms instead. Round two also found the last visible row,
-- once scrolled all the way to the bottom, drawing a few points short of every row above
-- it, traced to this probe sizing its own canvas with nothing left over between the last
-- row and the canvas's own edge, so the shared surface border had nowhere to sit but on
-- top of that row. GEOMETRY.edgeMargin is the fix, a margin the row band never has to
-- share a boundary with, held apart from the row band's own height rather than carved out
-- of it, and list render.lua's own M.bandHeight is what this probe asks for that height
-- instead of multiplying rowH by rowCount a second time in a place that could quietly
-- stop agreeing with the first.
--
-- Round three settled the highlight's own wrap at both ends by hand rather than by a
-- false comparison to the native chooser, which clamps, and there is no switch left
-- anywhere in this file for that, list model.lua wraps and has never learned a second
-- mode.
--
-- Round four found the proportions from round two closer but still wrong in kind. One
-- text size now answers for both the field's own text and a row's own title, textSize in
-- GEOMETRY below, since a field text size and a title size that merely happen to agree are
-- two numbers that will eventually stop agreeing, and naming the one value for what it is,
-- the whole surface's own text size, is what keeps that from happening rather than luck.
-- baseH and rowH are the same small number now too, a search box and a row being read as
-- one continuous compact surface rather than a tall field sitting over short rows. A row
-- with no subtitle centres its title instead of leaving it sitting high with a gap under
-- it, list render.lua's own concern entirely, nothing here changed for that beyond
-- shrinking rowH. And cmd plus a digit one through nine now chooses one of the first nine
-- rows the viewport currently shows, exactly what Return does to whichever row is
-- highlighted, refusing a disabled row and printing whichever one it lands on, reaching
-- this file through onKey unclaimed the same way up, down and return already did, with
-- list render.lua drawing that same digit quietly on each of those rows so the shortcut is
-- one a hand can actually find.
--
-- Round five replaced decision four of the original list brief outright. scrollTop in
-- list model.lua is now a point offset rather than a row index, so this file's own list
-- rect can hold a row that is only partly shown at its top or its bottom, cut by
-- hs.canvas's own clip action inside list render.lua rather than by anything computed
-- here. That is also what makes the wheel worth having at all, a trackpad's own
-- continuous point deltas are handed straight to list model.lua's scrollBy and macOS's own
-- momentum tail comes along for free, while a mouse wheel's coarse notches are converted
-- to points and eased toward over a short run of ticks rather than arriving all at once,
-- both driven by a second hs.eventtap this file now owns and tears down exactly the way it
-- already tears down the field's own tap, the blink timer and the watchdog. The wheel
-- moves the viewport only, never the highlight, and the next arrow key press is what pulls
-- the viewport back to wherever the highlight actually sits, snapping there instantly with
-- no animation, which is list model.lua's own job and unchanged by anything in this file.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local fieldDir = here .. "../lib/chooser/providers/default/field/"
local listDir = here .. "../lib/chooser/providers/default/list/"

local function loadFrom(dir, name)
  local chunk, err = loadfile(dir .. name)
  if not chunk then
    error("Olm canvas field probe, failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local input = loadFrom(fieldDir, "input.lua")
local fieldRender = loadFrom(fieldDir, "render.lua")
local listModel = loadFrom(listDir, "model.lua")
local listRender = loadFrom(listDir, "render.lua")
-- The list model ranks only with a matcher handed in, so the probe hands it the shared one.
local fuzzy = loadFrom(here .. "../lib/chooser/", "match.lua").fuzzy

--------------------------------------------------------------------------------
-- A plausible surface, centred on the screen holding the mouse
--------------------------------------------------------------------------------

-- GEOMETRY IS THE ONE TABLE TO EDIT. Every number this probe draws with, and every
-- tunable the scroll easing below needs, lives here and nowhere else, so a hand asking
-- for the field taller, the rows tighter, the icon bigger, or the wheel to catch up
-- faster changes one line in one file rather than hunting through render.lua and this
-- probe both. width, rowH, rowCount, baseH, font, textSize and subSize keep the field
-- names lib/chooser/providers/legacy.lua gave DEFAULT_LAYOUT, save for textSize which
-- round four renamed away from that module's own titleSize on purpose, explained just
-- below, so a real provider handed this same table later needs no translation to read
-- most of it. padX, iconSize, iconGap, textTopPad and showRowNumbers name what that
-- native layout has no word for at all, a real hs.chooser row being drawn by the
-- operating system's own nib rather than by anything this configuration states in
-- points. edgeMargin is the clearance this probe leaves between the field and list
-- content and the canvas's own outer edge on every side, round two's own fix for the
-- short last row, explained in full where this file's own header tells the story.
-- wheelNotchPoints, scrollEaseFactor, scrollEaseInterval and scrollEaseEpsilon are round
-- five's own additions, read only by the scroll tap and its easing timer further down
-- this file, and are described there rather than here since they answer a question about
-- how scrolling feels rather than about how the surface is laid out.
--
-- textSize is round four's own decision, one number for both the field's own text and a
-- row's own title, named for the surface as a whole rather than for either place it
-- lands, since a field text size and a title size that only happen to agree are two
-- numbers that will eventually drift apart the moment one of them is retuned alone. It
-- feeds style.fontSize for the field below and layout.textSize for the list, the same
-- single value read twice rather than two values kept in step by hand. subSize keeps a
-- size of its own, since it is deliberately smaller and is genuinely the one place a
-- second size earns itself, the row's own subtitle and, small and dim, the row numbers
-- round four's own decision four asks this list to draw.
--
-- baseH and rowH are round four's other decision, the same small number, since a search
-- box holding one short line and a row holding one line of the very same size need the
-- same amount of room to breathe and no more, and a list whose rows changed height
-- depending on whether a row carried a subtitle would read as jumping rather than
-- filtering, which is exactly why list render.lua centres a subtitle free row instead of
-- growing it. Thirty eight is round four's own opening position, expected to move the
-- moment a hand sees it on screen and asks for it taller or tighter, the same posture
-- round two's own numbers were opened with.
local GEOMETRY = {
  width = 620,
  baseH = 38,
  rowH = 38,
  rowCount = 9,
  font = ".AppleSystemUIFont",
  textSize = 16,
  subSize = 12,
  padX = 16,
  iconSize = 28,
  iconGap = 10,
  textTopPad = 5,
  edgeMargin = 12,
  showRowNumbers = true,
  wheelNotchPoints = 120,
  scrollEaseFactor = 0.28,
  scrollEaseInterval = 1 / 60,
  scrollEaseEpsilon = 0.5,
}

local CANVAS_W = GEOMETRY.width
local CANVAS_H = GEOMETRY.edgeMargin * 2 + GEOMETRY.baseH + listRender.bandHeight(GEOMETRY)

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
-- something depends on this field at all. fontSize reads GEOMETRY.textSize rather than a
-- field only number of its own, round four's own point stated in full above.
local geometryLib = loadFrom(here .. "../lib/chooser/providers/default/", "geometry.lua")
local kitTokens = spoon.Olm and spoon.Olm.lib and spoon.Olm.lib.ui and spoon.Olm.lib.ui.tokens()
local function faded(color, factor)
  local c = {}
  for k, v in pairs(color) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end
local textColor = kitTokens and kitTokens.colors.foreground
  or (dark and { white = 0.92 } or { white = 0.15 })
local style = {
  font = kitTokens and kitTokens.text.title.font or GEOMETRY.font,
  fontSize = GEOMETRY.textSize,
  textColor = textColor,
  selectionColor = kitTokens and kitTokens.colors.highlight
    or (dark and { white = 1, alpha = 0.20 } or { white = 0, alpha = 0.14 }),
  caretColor = textColor,
  placeholderColor = faded(textColor, kitTokens and kitTokens.alpha.dim or 0.4),
  caretWidth = geometryLib.DEFAULT_LAYOUT.caretWidth,
}

-- The list's own colours, hand set here for the same reason style above is, chooserTheme
-- names a title colour and a subtitle colour but no highlight colour or row number colour
-- of its own, a real hs.chooser's own highlight being painted by the system rather than by
-- this configuration, so this probe picks colours rather than reading ones that do not
-- exist. numberColor is left unset on purpose, list render.lua's own fallback, a dimmed
-- subColor, already reads as quiet without this probe stating a fifth colour for it.
local listStyle = {
  titleColor = dark and { white = 0.92 } or { white = 0.15 },
  subColor = dark and { white = 0.6 } or { white = 0.38 },
  highlightColor = dark and { white = 1, alpha = 0.12 } or { white = 0, alpha = 0.08 },
}

local canvas = hs.canvas.new(canvasFrame)
canvas:level(hs.canvas.windowLevels.popUpMenu)

-- Both rects sit inset from the canvas by edgeMargin on every side, top, bottom, left
-- and right alike, rather than the left and right inset the field alone used to carry.
-- That is the actual fix for the short last row, the row band below never again asked
-- to share its own bottom edge with the canvas's own outer edge, where the shared
-- surface border is drawn. listRect.h comes from listRender.bandHeight rather than a
-- second rowH times rowCount written out here, so this probe and the file that draws
-- the rows can never quietly disagree about how tall that band is.
local fieldRect = {
  x = GEOMETRY.edgeMargin, y = GEOMETRY.edgeMargin,
  w = CANVAS_W - 2 * GEOMETRY.edgeMargin, h = GEOMETRY.baseH,
}
local listRect = {
  x = GEOMETRY.edgeMargin, y = GEOMETRY.edgeMargin + GEOMETRY.baseH,
  w = CANVAS_W - 2 * GEOMETRY.edgeMargin, h = listRender.bandHeight(GEOMETRY),
}

-- listRect restated in screen coordinates rather than the canvas's own local ones, the
-- one rect the scroll tap below actually needs, since hs.eventtap hands every callback a
-- screen coordinate through its own location method and this canvas's own frame is fixed for as
-- long as this probe is up, never moved or resized after canvas.new above, so this only
-- has to be computed once rather than on every scroll event.
local listScreenRect = {
  x = canvasFrame.x + listRect.x, y = canvasFrame.y + listRect.y,
  w = listRect.w, h = listRect.h,
}

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
-- Rows for the list, real running applications padded out with synthetic ones
--------------------------------------------------------------------------------

-- One row per running application, name as the title and bundle path as the subtitle,
-- with the real icon in the image slot, exactly the row shape lib/chooser/providers
-- legacy.lua documents at its own head. Wrapped in pcall per application since a
-- background helper or an app mid launch can answer nothing for its own name, its own
-- path, or its own bundle identifier, and one such application must not stop every other
-- row this probe was going to show.
local function buildAppRows()
  local rows = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    local okName, name = pcall(function() return app:name() end)
    if okName and name and name ~= "" then
      local okPath, path = pcall(function() return app:path() end)
      local okBundle, bundleID = pcall(function() return app:bundleID() end)
      local image = nil
      if okBundle and bundleID then
        local okImage, img = pcall(hs.image.imageFromAppBundle, bundleID)
        if okImage then image = img end
      end
      rows[#rows + 1] = {
        title = name,
        subTitle = (okPath and path) or "",
        image = image,
        item = app,
        enabled = true,
      }
    end
  end
  return rows
end

-- Enough rows to run well past one screen of nine, so the viewport actually has to
-- scroll rather than only ever showing everything a machine happens to have open.
local MIN_ROWS = 30

local function buildRows()
  local rows = buildAppRows()

  -- One row inserted on purpose, near the top so a hand does not have to scroll to find
  -- it, enabled set to false so decision seven of the list brief, dimmed and refusing
  -- Return, is something visible rather than something only the unit case proves.
  table.insert(rows, math.min(2, #rows + 1), {
    title = "Disabled example row",
    subTitle = "enabled is false here on purpose, this row dims and Return refuses it",
    item = "disabled example",
    enabled = false,
  })

  if #rows < MIN_ROWS then
    for i = 1, MIN_ROWS - #rows do
      rows[#rows + 1] = {
        title = "Synthetic row " .. i,
        subTitle = "padding past one screen since this machine is not running enough applications to do it alone",
        item = "synthetic " .. i,
        enabled = true,
      }
    end
  end

  return rows
end

--------------------------------------------------------------------------------
-- The field itself, the list beside it, the blink timer, the scroll tap and easing
-- timer, and the teardown every road here leads to
--------------------------------------------------------------------------------

local field
local blinkTimer
local scrollTap
local scrollEaseTimer
local scrollEaseTarget
local watchdog
local caretVisible = true
local torn = false

-- listState is seeded once from every row this machine can offer right now, decision
-- three of the list brief asking for a list close enough to the real chooser to compare
-- honestly rather than one rebuilt live from a changing application set, which is a
-- question for whatever eventually supplies this list for real. lastQuery is compared
-- against the field's own text on every change, so a caret move or a selection extend,
-- which also fires onChange, does not rerank and does not reset the list's own highlight
-- and scroll position for no reason, only an actual change to the typed text does that.
local listState = listModel.newState(buildRows(), GEOMETRY, "")
local lastQuery = ""

local function redraw()
  local els = surfaceChrome()
  local fieldState = field:getState()
  for _, el in ipairs(fieldRender.elements(fieldState, fieldRect, style, caretVisible)) do
    els[#els + 1] = el
  end
  for _, el in ipairs(listRender.elements(listState, listRect, GEOMETRY, listStyle)) do
    els[#els + 1] = el
  end
  canvas:replaceElements(els)
end

-- Half a second on, half a second off, restarted from visible on every keystroke, which
-- is what makes typing read as continuous rather than as the caret happening to be in
-- its off half a moment ago. Decision four of the field brief keeps this clock out of
-- model.lua and render.lua alike, so it lives here, the one file that owns the field for
-- as long as this probe is up.
local function resetBlink()
  caretVisible = true
  if blinkTimer then blinkTimer:stop() end
  blinkTimer = hs.timer.doEvery(0.5, function()
    caretVisible = not caretVisible
    redraw()
  end)
end

--------------------------------------------------------------------------------
-- Scrolling, round five. A trackpad's own continuous point deltas move the viewport
-- directly, a wheel's coarse notches are converted to points and eased toward over a
-- short run of ticks, and either one stops any ease already in flight from the other so
-- the two never fight over where the viewport actually is.
--------------------------------------------------------------------------------

-- Stops whatever easing is in flight and forgets its target, called before every direct
-- scroll, keyboard move, or query change so a wheel step queued a moment ago can never
-- keep nudging the viewport after something else has already decided where it belongs.
local function stopScrollEase()
  if scrollEaseTimer then
    scrollEaseTimer:stop()
    scrollEaseTimer = nil
  end
  scrollEaseTarget = nil
end

-- One tick of the ease, moving the current scrollTop a fixed fraction of the remaining
-- distance toward scrollEaseTarget rather than the whole distance at once, which is what
-- reads as catching up smoothly instead of arriving in one jump. Stops itself once the
-- remaining distance is under scrollEaseEpsilon points, snapping the last short distance
-- exactly onto the target rather than leaving an ease that technically never finishes.
local function easeScrollStep()
  if not scrollEaseTarget then return end
  local current = listState.scrollTop
  local remaining = scrollEaseTarget - current
  if math.abs(remaining) <= GEOMETRY.scrollEaseEpsilon then
    listState = listModel.scrollTo(listState, scrollEaseTarget)
    stopScrollEase()
    redraw()
    return
  end
  listState = listModel.scrollTo(listState, current + remaining * GEOMETRY.scrollEaseFactor)
  redraw()
end

-- A wheel notch converted to points and folded into whatever target is already being
-- eased toward, rather than replacing it, so a run of notches in quick succession reads
-- as one accelerating scroll rather than a new ease restarting on every tick. The target
-- itself is bounded through list model.lua's own maxScrollTop the moment it changes,
-- never left to grow past what the list could ever actually show, since an unbounded
-- target would otherwise sit far past the list's own end after a few notches and the
-- ease would have to spend a visible moment unwinding an overshoot the list was never
-- going to allow in the first place.
local function scrollByWheelNotch(deltaPoints)
  local base = scrollEaseTarget or listState.scrollTop
  local target = base + deltaPoints
  local maxScroll = listModel.maxScrollTop(listState)
  if target < 0 then target = 0 end
  if target > maxScroll then target = maxScroll end
  scrollEaseTarget = target
  if not scrollEaseTimer then
    scrollEaseTimer = hs.timer.doEvery(GEOMETRY.scrollEaseInterval, easeScrollStep)
  end
end

-- The same point in space test legacy.lua's own scroll watcher already uses for its
-- companion pane, restated here rather than reached for since that file is the one this
-- whole track leaves untouched, a plain bounds check against a rect in screen
-- coordinates.
local function pointInFrame(p, fr)
  return p.x >= fr.x and p.x <= fr.x + fr.w and p.y >= fr.y and p.y <= fr.y + fr.h
end

-- Armed only while this probe is up and only over the list's own rect, a canvas answers
-- no scroll of its own, so without this tap a trackpad or a wheel over the list does
-- nothing at all. Outside listScreenRect this returns false untouched, so a scroll
-- anywhere else on screen still reaches whatever is actually under the pointer there.
-- Which kind of event it is comes from the event itself rather than being assumed, a
-- trackpad's own continuous flag being how legacy.lua already tells the two apart for
-- its own companion pane. A continuous event's point delta moves the viewport directly
-- and stops any wheel ease already in flight, since a hand touching the trackpad has
-- taken over from whatever the wheel queued a moment before. A discrete wheel notch
-- never touches scrollTop directly at all, it only ever updates the ease target through
-- scrollByWheelNotch. The sign on both is flipped once, matching legacy.lua's own
-- reasoning stated in full in that file, the event measures the fingers and the list
-- measures its own content, so the two run opposite ways.
local function startScrollTap()
  local props = hs.eventtap.event.properties
  scrollTap = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function(e)
    if not pointInFrame(e:location(), listScreenRect) then return false end
    if e:getProperty(props.scrollWheelEventIsContinuous) ~= 0 then
      local points = e:getProperty(props.scrollWheelEventPointDeltaAxis1)
      if points and points ~= 0 then
        stopScrollEase()
        listState = listModel.scrollBy(listState, -points)
        redraw()
      end
    else
      local notches = e:getProperty(props.scrollWheelEventDeltaAxis1)
      if notches and notches ~= 0 then
        scrollByWheelNotch(-notches * GEOMETRY.wheelNotchPoints)
      end
    end
    return true
  end)
  scrollTap:start()
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
  stopScrollEase()
  if scrollTap then
    scrollTap:stop()
    scrollTap = nil
  end
  if watchdog then
    watchdog:stop()
    watchdog = nil
  end
  if canvas then canvas:hide() end
  print("Olm canvas field probe torn down, " .. tostring(reason))
end

-- Reranks the list only when the field's own text actually changed, comparing against
-- lastQuery rather than reranking on every onChange, which also fires for a plain caret
-- move or a selection extend that leaves the text untouched, and reranking on those would
-- reset the list back to its own top for no reason every time a hand merely moved the
-- caret inside what it had already typed. A fresh query resets scrollTop to the top of
-- the list on its own account, list model.lua's own setQuery, so any wheel ease still in
-- flight is stopped here too rather than left to fight that reset on its very next tick.
local function syncListQuery()
  local text = field:getState().text
  if text ~= lastQuery then
    lastQuery = text
    stopScrollEase()
    listState = listModel.setQuery(listState, text, fuzzy)
  end
end

-- Choosing a row, the one answer Return and cmd plus a digit share rather than two that
-- could drift, round four's own decision four stated plainly, choosing means exactly
-- what Return means including refusing a disabled row. source names where the choice
-- came from purely for the print line, nothing here reads it back.
local function chooseRow(row, source)
  if not row then
    print("Olm canvas list probe, " .. source .. " has no row to choose there right now")
  elseif row.enabled == false then
    print("Olm canvas list probe, the row " .. source .. " would choose is disabled and cannot be chosen, "
      .. tostring(row.title))
  else
    print("Olm canvas list probe, selected " .. tostring(row.title) .. " via " .. source)
  end
end

-- The virtual keycodes for up, down, and the two keys macOS answers for return, the plain
-- key above the shift key and the one on the numeric keypad. None of the four are named
-- anywhere in field keymap.lua, so every one of them already reaches onKey exactly the way
-- the list brief says the list should hang off this field, unclaimed and undelegated to
-- the buffer, rather than through any change to input.lua, keymap.lua or model.lua.
local KEYCODE_UP, KEYCODE_DOWN = 126, 125
local KEYCODE_RETURN, KEYCODE_KEYPAD_ENTER = 36, 76

-- The raw virtual keycodes for the digit keys one through nine, read from the running
-- config's own hs.keycodes.map the same way field keymap.lua's own header says its own
-- numbers were derived, restated here rather than reached for since keymap.lua is off
-- limits for this list feature and cmd plus a digit is named nowhere in it, reaching
-- onKey unclaimed the same way the four keycodes above already do.
local KEYCODE_DIGIT = {
  [18] = 1, [19] = 2, [20] = 3, [21] = 4, [23] = 5,
  [22] = 6, [26] = 7, [28] = 8, [25] = 9,
}

field = input.Field.new({
  text = "",
  onChange = function()
    syncListQuery()
    resetBlink()
    redraw()
  end,
  onKey = function(ev)
    local code = ev:getKeyCode()
    local digit = KEYCODE_DIGIT[code]
    if digit and ev:getFlags().cmd then
      local row = listModel.rowAtVisibleSlot(listState, digit)
      chooseRow(row, "cmd " .. digit)
    elseif code == KEYCODE_DOWN then
      stopScrollEase()
      listState = listModel.moveDown(listState)
      redraw()
    elseif code == KEYCODE_UP then
      stopScrollEase()
      listState = listModel.moveUp(listState)
      redraw()
    elseif code == KEYCODE_RETURN or code == KEYCODE_KEYPAD_ENTER then
      chooseRow(listModel.highlightedRow(listState), "return")
    else
      print("Olm canvas field probe, an unclaimed key reached onKey, keycode " .. tostring(code))
    end
  end,
  onDismiss = function()
    teardown("escape")
  end,
})

field:start()
startScrollTap()
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
print("Typing also filters the list under the field, up and down move its highlight, and both wrap.")
print("Return chooses whichever row is highlighted, the second row is disabled on purpose and refuses it.")
print("Cmd plus one through nine chooses that visible row directly, numbered quietly on its own trailing edge.")
print("Scroll with a trackpad or a wheel over the list to move the viewport without moving the highlight.")
print("Escape ends the field now. With no escape it ends itself in " .. tostring(math.floor(limit)) .. " seconds.")
