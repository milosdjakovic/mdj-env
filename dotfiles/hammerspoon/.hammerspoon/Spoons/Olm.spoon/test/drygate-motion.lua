-- The one motion rule as a scan, over the swift library's sources. Every surface it draws comes
-- and goes through native/Motion.swift, a view through Motion.appear and Motion.disappear and a
-- window through a WindowMotion, so one edit to its knobs moves every surface and none can surprise
-- by moving its own way. A source of it anywhere else that orders a window in or out, fades one, or
-- builds an animation is a finding naming its line. A window ordered front inside the closure
-- handed to a WindowMotion's show is the presenter's own and is not caught, and AppKit's own window
-- animation switched off is not either. A line that must do one of these anyway declares
-- motion-exempt and a reason, on it or on the comment line above, which is counted as accepted.
-- decisions/olm-swift-chooser.md has why.
--
-- Pure Lua with no hs, so test/drygate.lua loads it.

local M = {}

local PATTERNS = {
  { "orderFront", "a window ordered front" },
  { "orderOut", "a window ordered out" },
  { "alphaValue", "an alpha set by hand" },
  { "animator%(%)", "an AppKit animator" },
  { "NSAnimationContext", "an AppKit animation group" },
  { "CABasicAnimation", "a Core Animation animation" },
  { "CAKeyframeAnimation", "a Core Animation animation" },
  { "CASpringAnimation", "a Core Animation animation" },
  { "animationBehavior%s*=", "AppKit's window animation" },
}

--- M.applies(rel) -> whether the rule reads this file, every source of the swift library but
--- Motion.swift. A helper a plugin compiles into a program of its own is not the library's.
function M.applies(rel)
  return rel:match("lib/chooser/providers/swift/native/[^/]+%.swift$") ~= nil
    and not rel:match("native/Motion%.swift$")
end

local function exemptOf(line)
  return line:match("motion%-exempt,%s*(%S.*)$")
end

--- M.scan(text) -> list of { line, what, source, exempt }.
function M.scan(text)
  local hits, n, prev = {}, 0, nil
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = l:gsub("//.*$", "")
    local allowed = code:find("motion%.show%s*{") or code:find("animationBehavior%s*=%s*%.none")
    if not allowed then
      for _, p in ipairs(PATTERNS) do
        if code:find(p[1]) then
          local own = exemptOf(l)
          local above = prev and prev:match("^%s*//") and exemptOf(prev)
          hits[#hits + 1] = { line = n, what = p[2], source = (l:gsub("^%s+", "")), exempt = own or above }
          break
        end
      end
    end
    prev = l
  end
  return hits
end

function M.scanFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return M.scan(text)
end

return M
