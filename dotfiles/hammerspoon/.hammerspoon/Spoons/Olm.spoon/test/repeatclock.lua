-- lib/chordkey.lua's driven repeat on a virtual clock, shared with test/fixtures.lua, which runs the
-- fixture's kind keys.repeat. A case is { delay, interval, hold, handler } and its answer every run,
-- { at, depth }, the press at 0 with depth 0 included. The fake hs it needs is set only while a case
-- runs, so a runner with its own hs keeps it.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local M = {}

function M.run(c)
  local now, queue = 0, {}
  local fake = {
    timer = { doAfter = function(wait, fn)
      local t = { due = now + wait, fn = fn, live = true }
      function t:stop() self.live = false end
      queue[#queue + 1] = t
      return t
    end },
    eventtap = { keyRepeatDelay = function() return c.delay end, keyRepeatInterval = function() return c.interval end },
  }
  local saved = _G.hs
  _G.hs = fake
  local ChordKey = assert(loadfile(here .. "../lib/chordkey.lua"))()
  local runs = {}
  local k = { active = true, repeatTiming = { delay = c.delay, interval = c.interval } }
  local function fn(depth)
    runs[#runs + 1] = { at = now, depth = depth }
    now = now + c.handler
  end
  -- The press, as the engine runs it, the handler at 0 with depth 0 and the repeat armed then.
  fn(0)
  now = 0
  ChordKey._startRepeat(ChordKey, k, 1, fn)
  while true do
    table.sort(queue, function(x, y) return x.due < y.due end)
    local nextTimer
    for i, t in ipairs(queue) do
      if t.live then nextTimer = table.remove(queue, i) break end
    end
    if not nextTimer or nextTimer.due >= c.hold then break end
    now = math.max(now, nextTimer.due)
    nextTimer.fn()
  end
  _G.hs = saved
  return runs
end

return M
