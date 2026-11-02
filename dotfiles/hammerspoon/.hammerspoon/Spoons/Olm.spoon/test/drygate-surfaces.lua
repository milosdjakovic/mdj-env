-- The surface rule as a scan, over every Lua and Swift file under plugins. A plugin says what is
-- shown and the core shows it, rows through the stage, verbs through the actions pane, a preview
-- through the preview pane and a message through the notify word, so every surface comes and goes
-- the one way native/Motion.swift moves it and looks like the rest of Olm. A plugin file that puts
-- something on screen itself, an alert, a dialog, a webview, a drawing, a chooser, a canvas it
-- shows rather than snapshots into an icon, or in a Swift helper a window, a panel or an alert of
-- its own, is a finding naming its line. A line that must anyway, a system surface the core has no
-- answer for, declares surface-exempt and a reason, on it or on the comment line above, which is
-- counted as accepted. decisions/olm-swift-chooser.md has why.
--
-- Pure Lua with no hs, so test/drygate.lua loads it.

local M = {}

local LUA = {
  { "hs%.alert", "an alert" },
  { "hs%.dialog", "a dialog" },
  { "hs%.webview", "a webview" },
  { "hs%.drawing", "a drawing" },
  { "hs%.chooser%.new", "a chooser" },
}

local SWIFT = {
  { "NSWindow%s*%(", "a window" },
  { "NSPanel%s*%(", "a panel" },
  { "NSAlert%s*%(", "an alert" },
  { "NSPopover%s*%(", "a popover" }, -- names-exempt, the AppKit class this rule refuses
  { "NSColorSampler%s*%(", "the system colour sampler" },
  { "orderFront", "a window ordered front" },
}

--- M.applies(rel) -> whether the rule reads this file, every Lua and Swift file under plugins.
function M.applies(rel)
  return rel:match("^plugins/.+%.lua$") ~= nil or rel:match("^plugins/.+%.swift$") ~= nil
end

local function exemptOf(line)
  return line:match("surface%-exempt,%s*(%S.*)$")
end

-- The code part of a line, with its comment cut off, nil for a line that is only a comment.
local function codeOf(line, swift)
  local mark = swift and "//" or "%-%-"
  if line:match("^%s*" .. mark) then return nil end
  return (line:gsub(mark .. ".*$", ""))
end

--- M.scan(text, swift) -> list of { line, what, source, exempt }.
function M.scan(text, swift)
  local hits, n, prev = {}, 0, nil
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  -- A canvas snapshotted into an image is an icon, which the drawing rule judges, so a Lua file
  -- that calls imageFromCanvas is not read for a canvas shown.
  local snapshots = not swift and text:find("imageFromCanvas") ~= nil
  local patterns = swift and SWIFT or LUA
  for _, l in ipairs(lines) do
    n = n + 1
    local code = codeOf(l, swift)
    if code then
      local what
      for _, p in ipairs(patterns) do
        if code:find(p[1]) then what = p[2] break end
      end
      if not what and not swift and not snapshots and code:find("canvas%.new") then
        what = "a canvas shown"
      end
      if what then
        local above = prev and prev:match("^%s*" .. (swift and "//" or "%-%-")) and exemptOf(prev)
        hits[#hits + 1] = { line = n, what = what, source = (l:gsub("^%s+", "")), exempt = exemptOf(l) or above }
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
  return M.scan(text, path:match("%.swift$") ~= nil)
end

return M
