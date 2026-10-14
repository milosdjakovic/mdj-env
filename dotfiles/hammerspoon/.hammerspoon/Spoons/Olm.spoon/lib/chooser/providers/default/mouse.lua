--- === Canvas mouse ===
---
--- The only file in this provider that touches hs.eventtap for mouse events, the same
--- way field/input.lua is the only one that touches it for keys. This is a shell around a
--- resource, not a Strategy, it holds no policy of its own, it does not know what a row
--- is or where any surface actually sits on screen.
---
--- Mouse.new(opts) takes callbacks and nothing else.
---
---   onDown(point, button)     button is left or right
---   onUp(point, button)
---   onMove(point)
---   onScroll(point, dy, continuous)
---
--- Every point arrives in absolute screen coordinates, the same space geometry.resolve
--- answers frames in and the same space hs.window frames already use.
---
--- Every callback ANSWERS TRUE TO CLAIM the event and anything else lets it through, and
--- this is the load bearing decision in this file. A canvas never takes focus, so an
--- unclaimed click reaches whatever application sits underneath, and a picker that let
--- its own clicks fall through would select a row and click the covered app in the same
--- gesture. Equally, a picker that claimed every click on the whole screen would make the
--- rest of the machine unusable while it is open. So this file never decides where a
--- surface sits and never runs a bounds test of its own, it only reports what happened
--- and where, and the consumer that actually knows the shape of its own surface is the
--- one place that decision can honestly live.
---
--- start(), stop(), isRunning(). Armed on show and stopped on hide, never left running a
--- moment longer than the surface is meant to be up. Commit 1ccab6f is this
--- configuration's own record of what a tap left believed active costs on this machine, a
--- leader believed held rather than checked swallowing keys nobody meant to lose, and a
--- tap left armed here is the same hazard turned toward the mouse instead. Nothing in a
--- tap callback may raise, so every consumer callback runs inside a pcall, and a failure
--- reports itself and lets the event through rather than abandoning the callback halfway
--- with the claim decision left unmade.
---
--- Scrolling. Spoons/Olm.spoon/test/probe-canvasfield.lua already carries a working
--- scroll tap, built and hand judged across round five of the list brief, and the
--- mechanics below are lifted from there rather than written a second time. It tells a
--- trackpad from a wheel through hs.eventtap.event.properties.scrollWheelEventIsContinuous,
--- the same property the native provider's own companion pane watcher reads, and hands
--- back the raw continuous point delta for the one and the raw notch delta for the
--- other, on the axis that probe already reads. Neither is converted or eased here, since
--- the easing policy, follow a trackpad directly and ease a wheel toward its target over
--- a few ticks, belongs to whichever consumer is driving a list with it and not to this
--- file. A scroll event that carries no delta at all, which a trackpad reports at a phase
--- boundary, is not handed onward and claims nothing.
---
--- onMove exists so a picker can highlight whatever the pointer sits over, which the
--- native widget does for free and whose absence here would read as this backend being
--- broken. The moved event type is only ever added to the tap when onMove is supplied,
--- the same shape the native provider takes with onHighlight, so a consumer that does not
--- want it pays nothing, not even the cost of the event reaching this file's own
--- dispatch. Down, up and scroll are always watched, a picker with no use for any of them
--- would not be a picker.

local Mouse = {}
Mouse.__index = Mouse

--- Mouse.new(opts) answers a new instance holding the four callbacks, none of them
--- required. No tap exists until start is called.
function Mouse.new(opts)
  opts = opts or {}
  return setmetatable({
    onDown = opts.onDown,
    onUp = opts.onUp,
    onMove = opts.onMove,
    onScroll = opts.onScroll,
    tap = nil,
    _retiredTap = nil,
  }, Mouse)
end

-- Runs fn inside a pcall and answers true only when fn itself answered exactly true,
-- anything else, false, nil, or a raised error, lets the event through. A raised error
-- is reported rather than swallowed, since a consumer callback that never gets to
-- finish is a finding worth the print line it leaves behind, the same posture
-- field/input.lua already takes toward its own onKey.
local function invokeClaim(fn, ...)
  if not fn then return false end
  local ok, claimed = pcall(fn, ...)
  if not ok then
    print("Olm canvas mouse, a callback failed and the event was let through, " .. tostring(claimed))
    return false
  end
  return claimed == true
end

-- The scroll wheel branch, the mechanics lifted from probe-canvasfield.lua's own tap as
-- the header above says. isContinuous answers whether a trackpad or a smooth wheel
-- produced this event rather than a mouse's discrete notches, and the two axes it reads
-- from are the same ones that probe already settled on. A delta of nil or zero is not
-- handed onward, there is nothing there for a consumer to act on.
local function scrollDelta(ev)
  local props = hs.eventtap.event.properties
  local continuous = ev:getProperty(props.scrollWheelEventIsContinuous) ~= 0
  local dy
  if continuous then
    dy = ev:getProperty(props.scrollWheelEventPointDeltaAxis1)
  else
    dy = ev:getProperty(props.scrollWheelEventDeltaAxis1)
  end
  return dy, continuous
end

-- The tap callback itself, dispatching by event type to the matching consumer callback
-- and answering exactly what invokeClaim answers, true to claim and false to let the
-- event through to whatever sits underneath.
function Mouse:_handle(ev)
  local types = hs.eventtap.event.types
  local t = ev:getType()
  local point = ev:location()

  if t == types.leftMouseDown then
    return invokeClaim(self.onDown, point, "left")
  elseif t == types.rightMouseDown then
    return invokeClaim(self.onDown, point, "right")
  elseif t == types.leftMouseUp then
    return invokeClaim(self.onUp, point, "left")
  elseif t == types.rightMouseUp then
    return invokeClaim(self.onUp, point, "right")
  elseif t == types.mouseMoved then
    return invokeClaim(self.onMove, point)
  elseif t == types.scrollWheel then
    local dy, continuous = scrollDelta(ev)
    if not dy or dy == 0 then return false end
    return invokeClaim(self.onScroll, point, dy, continuous)
  end
  return false
end

--- start() arms the tap. Idempotent, calling it again while already armed does nothing.
--- The moved event type is only added when onMove was supplied at construction, so a
--- consumer with no use for it never has those events reach this file at all.
function Mouse:start()
  if self.tap then return end
  self._retiredTap = nil
  local types = hs.eventtap.event.types
  local watched = {
    types.leftMouseDown, types.leftMouseUp,
    types.rightMouseDown, types.rightMouseUp,
    types.scrollWheel,
  }
  if self.onMove then
    watched[#watched + 1] = types.mouseMoved
  end
  self.tap = hs.eventtap.new(watched, function(ev) return self:_handle(ev) end)
  self.tap:start()
end

--- stop() tears the tap down completely, the tap object itself dropped rather than
--- merely stopped, so nothing armed is left behind for start to find and skip past.
---
--- Fix round item eight, insurance rather than a known failure. An outside press
--- reaches this from inside the tap's own callback, on the same Lua stack that
--- callback is still running on, and the line below used to drop the last reference to
--- that userdata, self.tap, in that same moment. Lua will not collect it synchronously
--- mid callback, so nothing here is known to break, but if it ever did the finalizer
--- would disable and release a tap while its own callback was still on the stack, and
--- Commit 1ccab6f already carries what a tap left believed torn down costs on this
--- machine. Holding the retired userdata in self._retiredTap keeps a reference alive
--- past the callback that dropped it, cleared on the next start so nothing
--- accumulates across opens, and isRunning still answers exactly what it answered
--- before, self.tap alone, since that is the field a fresh start replaces.
function Mouse:stop()
  if self.tap then
    self.tap:stop()
    self._retiredTap = self.tap
    self.tap = nil
  end
end

--- isRunning() answers whether the tap is currently armed, for a watchdog to check
--- before deciding it has anything left to tear down.
function Mouse:isRunning()
  return self.tap ~= nil
end

return Mouse
