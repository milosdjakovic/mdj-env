-- The composite trigger, one leader listening on more than one trigger at once.
--
-- Hyper ships on Caps Lock and on the four real modifiers, and META on Right Option and on shift,
-- ctrl and alt, so a machine without kanata, which sends F18 for a Caps Lock hold, and a machine
-- with it, which sends the four modifiers, both reach the same leader and Olm is told neither. This
-- file holds the triggers it is handed, a held one and a modifier one as the root builds it, and
-- answers the same four function contract every trigger answers, start, bound, isActive and owns.
-- It names no concrete trigger. The root builds each half and hands them over, so the root stays
-- the one place a trigger is chosen.
--
-- Each method is answered for the contract it serves rather than by one blanket rule.
--
-- start starts every half. A half that fails says one console line and the others keep working, so
-- a machine whose function key could not be placed still has its modifiers, and the composite fails
-- only when every half did. A half that raises counts as failing rather than stopping the rest.
--
-- bound hands every binding to every half. The modifier half is built by the root to leave a
-- binding asking for a modifier it is already made of, which it could not tell from the plain
-- binding on that key, and to count it rather than warn, since that binding is still reached
-- through the held key. After start this file says the count once, a routine line.
--
-- isActive and owns are true when any half answers true. A press arrives through exactly one half,
-- F18 or the modifiers, never both, which phase 0 of docs/PLAN-MACHINES.md measured, so asking
-- every half is the same as asking the half that was pressed. An F18 hold owns every key while it
-- is down, the held trigger's answer, and four held modifiers own only an event carrying them, the
-- modifier trigger's.
--
-- Sealing over an open list follows the half that fired as well, and that one cannot be answered
-- here, since lib/leader.lua decides it per key press. Each half hands itself to the adapter when it
-- asks about a key, and the adapter reads sealsOverLists off the half it was handed, so an F18 press
-- seals as a held leader does and a modifier press seals only when its leader hosts a list key. The
-- composite therefore states no sealsOverLists of its own.
--
-- It is pure Lua apart from a logger, so a plain test drives it over the real halves with stubs.

local obj = {}

local log = hs.logger.new("Leader", "info")

local ORDINALS = { "first", "second", "third", "fourth" }

--- obj.new(spec) -> trigger
---   spec.triggers  the halves, each a trigger answering the four function contract, in the order
---                  they start and are bound. The root hands the held one first.
function obj.new(spec)
  spec = spec or {}
  local halves = spec.triggers or {}
  local trigger = {}

  local function nameOf(host)
    return tostring(host and host._name or "plain")
  end

  local function ordinal(i)
    return ORDINALS[i] or ("number " .. tostring(i))
  end

  function trigger.isActive()
    for _, half in ipairs(halves) do
      if half.isActive() == true then return true end
    end
    return false
  end

  function trigger.owns(ev)
    for _, half in ipairs(halves) do
      if half.owns(ev) then return true end
    end
    return false
  end

  function trigger.bound(host, binding)
    for _, half in ipairs(halves) do half.bound(host, binding) end
  end

  function trigger.start(host)
    local started, reasons = 0, {}
    for i, half in ipairs(halves) do
      local ok, answer, why = pcall(half.start, host)
      if ok and answer ~= false then
        started = started + 1
      else
        local reason = ok and tostring(why) or ("it raised, " .. tostring(answer))
        reasons[#reasons + 1] = reason
        log.w("the " .. nameOf(host) .. " leader's " .. ordinal(i) .. " trigger did not start, " .. reason
          .. ", so the leader listens on its other trigger alone")
      end
    end
    if started == 0 then
      return false, "none of its triggers started, " .. table.concat(reasons, ", and ")
    end
    -- What the modifier half left to the held key, counted over every binding it was handed by now,
    -- which is every row of a load, since the root binds before it starts.
    local skipped = 0
    for _, half in ipairs(halves) do
      if type(half.skipped) == "function" then skipped = skipped + half.skipped() end
    end
    if skipped > 0 then
      log.i(string.format("the %s leader leaves %d chord(s) asking for a modifier its modifiers already hold "
        .. "to its held key, since the two would be one physical combination", nameOf(host), skipped))
    end
    return true
  end

  return trigger
end

return obj
