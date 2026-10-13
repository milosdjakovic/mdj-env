-- Live probe for the canvas picker provider, section two of
-- docs/BRIEF-CANVAS-PROVIDER.md, phase three c of the canvas chooser track. Opened by a
-- person against the Hammerspoon that is already running, hs -c "dofile('/absolute/path/
-- to/this/file')", never by this session itself, and never a reload of the live config.
-- The provider is loaded fresh straight out of this checkout, only lib.panel is reached
-- from the live spoon.Olm instance, since that is the one piece this probe cannot fake,
-- the shared chrome a real surface is judged against, matching probe-canvasshells.lua's
-- own reasoning for the identical reach.
--
-- What this proves. A complete picker built on this provider, wired the way a real
-- consumer would wire lib/chooser/init.lua, with a supplier carrying real running
-- applications, a mix of rows with a subtitle and without one, one disabled row on
-- purpose, and real icons, filtered live by the same fuzzy matcher every other chooser
-- in this configuration ranks with, moved with the arrow keys wrapping at either end,
-- chosen with Return, with a mouse click, or with cmd plus a digit naming a visible
-- slot, right clicked, scrolled, and every one of intercept, back, onHighlight, onSelect,
-- onScroll, onRightClick, onPositioned and onClose printing a line so a hand can see each
-- one actually fire rather than take it on faith.
--
-- contract.lua's own validate is asked directly against the built instance and its
-- answer is printed before the picker ever shows, proof rather than assertion that this
-- provider satisfies the full twenty five name contract, the acceptance section of the
-- brief asking for exactly that line.
--
-- A small placeholder pane is drawn beside the picker purely so a hand has somewhere to
-- scroll that is not the list itself, config.onScroll firing only for a scroll over a
-- companion rect and this probe otherwise having no consumer of its own wanting one.
-- That pane draws nothing but a label, it is not part of the provider under test, and it
-- comes down the moment the picker does.
--
-- The one hazard this probe carries that a real consumer's own wiring would not is its
-- to guard against. The field tap and the mouse tap both claim events while this picker
-- is up, so a mistake that left either one armed would keep swallowing keys or clicks
-- from whatever sits underneath with no window to close to get them back. This provider
-- already answers that itself, one idempotent hide tearing both taps down before
-- anything else, and escape reaches that same path. A watchdog tears it down again
-- regardless of whatever else has or has not happened, so a hand that walks away or a
-- mistake that leaves escape unreachable both end the same way, on their own, within a
-- bounded time.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local canvasDir = here .. "../lib/chooser/providers/canvas/"
local chooserDir = here .. "../lib/chooser/"

local function loadFrom(dir, name)
  local chunk, err = loadfile(dir .. name)
  if not chunk then
    error("Olm canvas picker probe, failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local canvasProvider = loadFrom(canvasDir, "init.lua")
local contract = loadFrom(chooserDir, "contract.lua")
local match = loadFrom(chooserDir, "match.lua")

-- The one piece reached from the live instance rather than loaded fresh, the shared
-- chrome a real surface has to be judged against. This probe is only ever opened against
-- a live checkout of this same config, so spoon.Olm is already up.
local panel = spoon.Olm and spoon.Olm.lib and spoon.Olm.lib.panel
if not panel then
  error("Olm canvas picker probe needs the running Olm instance's lib.panel, spoon.Olm does not appear to be loaded")
end

-- The kit the provider reads its colours and type from, the running instance's own for the
-- same reason as the panel above.
local ui = spoon.Olm.lib.ui
if not ui then
  error("Olm canvas picker probe needs the running Olm instance's lib.ui")
end

canvasProvider.configure({ panel = panel, ui = ui })

--------------------------------------------------------------------------------
-- Rows, real running applications carrying real icons, padded out with synthetic ones,
-- one disabled on purpose, and a few carrying no subtitle at all
--------------------------------------------------------------------------------

-- One row per running application, name as the title and bundle path as the subtitle,
-- with the real icon in the image slot, wrapped in pcall per application since a
-- background helper or an app mid launch can answer nothing for its own name, its own
-- path, or its own bundle identifier, and one such application must not stop every other
-- row this probe was going to show. Matches probe-canvasfield.lua's own buildAppRows.
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
        item = name,
        enabled = true,
      }
    end
  end
  return rows
end

-- Enough rows to run past one screen of the default nine, so the viewport actually has
-- to scroll rather than only ever showing everything a machine happens to have open.
local MIN_ROWS = 30

local function buildRows()
  local rows = buildAppRows()

  -- One row inserted on purpose, near the top so a hand does not have to scroll to find
  -- it, enabled set to false so a dimmed row that refuses Return is something visible
  -- rather than something only the offline cases prove.
  table.insert(rows, math.min(2, #rows + 1), {
    title = "Disabled example row",
    subTitle = "enabled is false here on purpose, this row dims and Return refuses it",
    item = "disabled example",
    enabled = false,
  })

  -- A handful of rows carrying no subtitle at all, the mix the brief asks this probe
  -- to show, list render.lua centring a title on its own rather than leaving it sitting
  -- high with a gap under it where a subtitle would have gone.
  for i = 1, 4 do
    rows[#rows + 1] = {
      title = "No subtitle row " .. i,
      item = "no subtitle " .. i,
      enabled = true,
    }
  end

  if #rows < MIN_ROWS then
    for i = 1, MIN_ROWS - #rows do
      rows[#rows + 1] = {
        title = "Synthetic row " .. i,
        subTitle = "padding past thirty rows since this machine is not running enough applications to do it alone",
        item = "synthetic " .. i,
        enabled = true,
      }
    end
  end

  return rows
end

local allRows = buildRows()

--------------------------------------------------------------------------------
-- A small placeholder pane, purely so a hand has somewhere to scroll that is not the
-- list itself, config.onScroll only ever firing over a companion rect
--------------------------------------------------------------------------------

local companionCanvas = nil

local function hideCompanion()
  if companionCanvas then
    companionCanvas:delete()
    companionCanvas = nil
  end
end

local function showCompanion(frame)
  hideCompanion()
  if not frame then return end
  companionCanvas = hs.canvas.new(frame)
  companionCanvas:level(hs.canvas.windowLevels.popUpMenu)
  companionCanvas:clickActivating(false)
  local dark = hs.host.interfaceStyle() == "Dark"
  companionCanvas:replaceElements({
    { type = "rectangle", action = "fill",
      fillColor = dark and { white = 0.2, alpha = 0.9 } or { white = 0.9, alpha = 0.9 },
      frame = { x = 0, y = 0, w = frame.w, h = frame.h } },
    { type = "text", text = "scroll here for onScroll",
      textSize = 13, textAlignment = "center",
      textColor = dark and { white = 0.85 } or { white = 0.2 },
      frame = { x = 4, y = frame.h / 2 - 10, w = frame.w - 8, h = 20 } },
  })
  companionCanvas:show()
end

--------------------------------------------------------------------------------
-- The instance itself, every callback wired to a printed line
--------------------------------------------------------------------------------

local watchdog

local function fmtFrame(fr)
  if not fr then return "none" end
  return string.format("x %.0f y %.0f w %.0f h %.0f", fr.x, fr.y, fr.w, fr.h)
end

local config = {
  screen = function() return hs.mouse.getCurrentScreen() or hs.screen.mainScreen() end,
  rows = function() return allRows end,
  matcher = match.fuzzy,
  placeholder = "Type to filter",

  onSelect = function(item)
    print("Olm canvas picker probe, onSelect fired for " .. tostring(item))
  end,

  intercept = function(item, enabled)
    print("Olm canvas picker probe, intercept asked for " .. tostring(item)
      .. ", enabled " .. tostring(enabled) .. ", answering false so the row completes as always")
    return false
  end,

  back = function()
    print("Olm canvas picker probe, back asked on an empty field, answering false so the key does nothing")
    return false
  end,

  onHighlight = function(item)
    print("Olm canvas picker probe, onHighlight fired for " .. tostring(item))
  end,

  onRightClick = function(item, row)
    print("Olm canvas picker probe, onRightClick fired for row " .. tostring(row)
      .. ", item " .. tostring(item))
  end,

  onScroll = function(points)
    print("Olm canvas picker probe, onScroll fired with " .. string.format("%.1f", points) .. " points")
  end,

  onPositioned = function(chooserFrame, companionFrame)
    print("Olm canvas picker probe, onPositioned fired, chooser " .. fmtFrame(chooserFrame)
      .. ", companion " .. fmtFrame(companionFrame))
    showCompanion(companionFrame)
  end,

  onClose = function()
    print("Olm canvas picker probe, onClose fired, the picker is down")
    hideCompanion()
    if watchdog then
      watchdog:stop()
      watchdog = nil
    end
  end,
}

local instance = canvasProvider.new(config)

-- The acceptance section of the brief asks for this proved by a line in the probe
-- rather than asserted. M.new above already validates internally and would have raised
-- before this line ever ran had the instance failed, so a person reading the console
-- sees the same answer confirmed a second time, honestly, against the real instance.
local contractOK, contractReason = contract.validate(instance)
print("Olm canvas picker probe, contract.validate answered " .. tostring(contractOK)
  .. (contractReason and (", " .. tostring(contractReason)) or ""))

instance:setPaneWidth(220)
instance:show()

-- The hard limit the brief asks for, tearing the picker down whatever else has
-- happened. A minute is the default, and a caller may set olmCanvasPickerProbeSeconds
-- before the dofile to widen it for one run, clamped so no caller can talk it out of
-- firing, matching probe-canvasfield.lua's own convention for the identical limit.
local requested = tonumber(rawget(_G, "olmCanvasPickerProbeSeconds") or 60) or 60
local limit = math.max(10, math.min(600, requested))
-- Fix round item nine. instance:hide() alone is the same active guarded path this
-- watchdog exists to back up, so it cannot recover a state where active is already
-- false while a tap is still armed, the exact state a mistake in teardown ordering
-- would leave behind. Field:isRunning and Mouse:isRunning both say in their own
-- comments that they exist for a watchdog to check, so this reads both after the hide
-- and stops either tap directly if it is still armed, reporting what it found.
watchdog = hs.timer.doAfter(limit, function()
  print("Olm canvas picker probe, the " .. tostring(math.floor(limit)) .. " second watchdog fired")
  instance:hide()
  local fieldArmed = instance.field and instance.field:isRunning()
  local mouseArmed = instance.mouse and instance.mouse:isRunning()
  if fieldArmed then instance.field:stop() end
  if mouseArmed then instance.mouse:stop() end
  print("Olm canvas picker probe, watchdog hard stop, field tap was armed "
    .. tostring(fieldArmed) .. ", mouse tap was armed " .. tostring(mouseArmed))
end)

print("Olm canvas picker probe is up, on the screen currently holding the mouse.")
print(#allRows .. " rows are loaded, one disabled on purpose, a few carrying no subtitle, the rest apps with icons.")
print("Type to filter, the same fuzzy matcher every other chooser in this configuration ranks with.")
print("Up and down move the highlight and wrap at either end, cmd plus one through nine chooses that visible slot.")
print("Return chooses the highlighted row, a click chooses whichever row it lands on and releases on.")
print("Right click a row to see onRightClick fire, scroll over the list to move its viewport.")
print("Scroll over the small pane beside the picker to see onScroll fire, that pane is this probe's own, not the provider's.")
print("Backspace on an empty field asks config.back, this probe answers false so it does nothing visible.")
print("Escape ends the picker now. With no escape it ends itself in " .. tostring(math.floor(limit)) .. " seconds.")
