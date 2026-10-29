-- The in process JavaScript rule as a scan. hs.osascript.javascript runs JXA inside
-- Hammerspoon, and every call leaves a JavaScriptCore context group there for good, with the
-- AppKit bridge metadata it loaded, several megabytes a call. Two callers grew the process past
-- a gigabyte this way, the SF Symbol source and the clipboard's file reader, so any call in
-- code is a finding, decisions/olm-icons.md has both. hs.osascript._osascript is caught too,
-- since it is the same door with the language passed in. JavaScript run in its own process,
-- osascript through hs.task, exits and frees everything, so it is not caught.
--
-- Pure Lua with no hs, so test/drygate.lua and a unit case both load it.

local M = {}

local codeOf = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "drygate-drawing.lua").codeOf

--- M.scan(text) -> list of { line, source }, one per line that calls in process JavaScript.
function M.scan(text)
  local hits, n = {}, 0
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = codeOf(l)
    if code and (code:find("osascript%.javascript") or code:find("osascript%._osascript")) then
      hits[#hits + 1] = { line = n, source = (l:gsub("^%s+", "")) }
    end
  end
  return hits
end

return M
