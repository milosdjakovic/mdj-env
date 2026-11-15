-- The stage facade of step 3.3, docs/DESIGN-APP-HOSTED.md. While a bridged request runs a hosted
-- list's own code, its intercept, its onSelect or its back, the stage words that code calls are
-- recorded as the effects the app applies, rather than acting on the Lua stage, which is not the
-- list on screen. Outside a request a word acts as before. Pure, no hs, so test/bridgeserve.lua
-- checks it as it stands.
--
-- redrawPresented records rows {hold}, step 3.3. Step 3.3c adds the words the hosted tools' own
-- code calls, the bridge host's hostedWord answering stageSelectedItem, stageSelectedRow and
-- stageQuery from the request's own context and recording stageHide, stagePop, stagePush and
-- stageSetQuery, docs/PROTOCOL-BRIDGE.md The stage words.

local M = {}

--- facade.new() -> a facade
---   facade.during(fn, context) -> effects, ... runs fn with recording on, answering the effects
---                        recorded in order and whatever fn answered. An error in fn ends the
---                        recording and is raised again. context is the request's own row, its
---                        place and its query, { item, row, query }, which the stage words that
---                        read the list answer from, never the hidden Lua stage.
---   facade.context() -> the context of the request running now, nil outside one
---   facade.recording() -> whether a request is running a hosted list's code now
---   facade.record(effect) adds one effect to the request running now, answering whether it was
---                        recorded, false outside a request
function M.new()
  local f = {}
  local stack = {}

  function f.recording() return #stack > 0 end

  function f.context()
    local top = stack[#stack]
    return top and top.context or nil
  end

  function f.record(effect)
    local top = stack[#stack]
    if not top then return false end
    top[#top + 1] = effect
    return true
  end

  function f.during(fn, context)
    local effects = { context = type(context) == "table" and context or {} }
    stack[#stack + 1] = effects
    local result = table.pack(pcall(fn))
    stack[#stack] = nil
    if not result[1] then error(result[2], 0) end
    effects.context = nil
    return effects, table.unpack(result, 2, result.n)
  end

  return f
end

return M
