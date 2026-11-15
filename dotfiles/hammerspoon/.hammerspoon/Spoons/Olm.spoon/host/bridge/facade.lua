-- The stage facade of step 3.3, docs/DESIGN-APP-HOSTED.md. While a bridged request runs a hosted
-- list's own code, its intercept, its onSelect or its back, the stage words that code calls are
-- recorded as the effects the app applies, rather than acting on the Lua stage, which is not the
-- list on screen. Outside a request a word acts as before. Pure, no hs, so test/bridgeserve.lua
-- checks it as it stands.
--
-- One word records today, redrawPresented, Caffeinate's when a timed session ends, which the
-- bridge host turns into rows {hold}. A word joins in the step whose tool calls it.

local M = {}

--- facade.new() -> a facade
---   facade.during(fn) -> effects, ... runs fn with recording on, answering the effects recorded
---                        in order and whatever fn answered. An error in fn ends the recording
---                        and is raised again.
---   facade.recording() -> whether a request is running a hosted list's code now
---   facade.record(effect) adds one effect to the request running now, answering whether it was
---                        recorded, false outside a request
function M.new()
  local f = {}
  local stack = {}

  function f.recording() return #stack > 0 end

  function f.record(effect)
    local top = stack[#stack]
    if not top then return false end
    top[#top + 1] = effect
    return true
  end

  function f.during(fn)
    local effects = {}
    stack[#stack + 1] = effects
    local result = table.pack(pcall(fn))
    stack[#stack] = nil
    if not result[1] then error(result[2], 0) end
    return effects, table.unpack(result, 2, result.n)
  end

  return f
end

return M
