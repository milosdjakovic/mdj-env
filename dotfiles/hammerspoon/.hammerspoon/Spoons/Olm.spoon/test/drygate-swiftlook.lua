-- The look rule over the Swift side, over every Swift file Olm.app and the swift chooser draw
-- with, app/Sources, app/Plugins and lib/chooser/providers/swift/native. Every icon and every font
-- follows one global set, the look the Lua side resolves and hands over, chooser.json's style and
-- pane, so a Swift line that builds a font, writes a colour or picks a symbol weight by hand is a
-- surface keeping a look of its own, the hole the white info icon in Olm.app's bar came through on
-- 2026-11-18. Such a line is a finding naming it. The files that read the look are not read, the
-- field readers in Fields.swift and Lua.swift, the defaults in Model.swift the look overwrites, and
-- the element readers in PaneElements.swift. A line that must anyway, a mask drawn in black whose
-- colour is never seen or the emoji canvas sized as lib/icons draws it, declares look-exempt and a
-- reason, the comma required, on it or on the comment line above, which is counted as accepted.
-- decisions/olm-standalone.md has why.
--
-- The Lua side has its own, test/drygate-typography.lua for fonts and the colour roles of the kit.
-- Pure Lua with no hs, so test/drygate.lua loads it.

local M = {}

local PATTERNS = {
  { "NSFont%.[%a]*[Ff]ont%s*%(", "a font built by hand" },
  { "NSFont%s*%(%s*name:", "a font built by hand" },
  { "[^%w_]%.[%a]*[sS]ystemFont%s*%(", "a font built by hand" },
  { "NSColor%s*%(%s*[%a]+:%s*%-?[%d.]", "a colour literal" },
  -- clear is no colour, the absence of one a view starts from, so only a named colour is one.
  { "NSColor%.(%a+)", "a colour literal", allow = { clear = true } },
  { "CGColor%s*%(%s*[%a]+:%s*%-?[%d.]", "a colour literal" },
  { "weight:%s*%.%a", "a symbol or font weight by hand" },
}

local READERS = {
  ["lib/chooser/providers/swift/native/Fields.swift"] = true,
  ["lib/chooser/providers/swift/native/Lua.swift"] = true,
  ["lib/chooser/providers/swift/native/Model.swift"] = true,
  ["app/Sources/OlmCore/PaneElements.swift"] = true,
}

--- M.applies(rel) -> whether the rule reads this file.
function M.applies(rel)
  if READERS[rel] then return false end
  return rel:match("^app/Sources/.+%.swift$") ~= nil or rel:match("^app/Plugins/.+%.swift$") ~= nil
    or rel:match("^lib/chooser/providers/swift/native/.+%.swift$") ~= nil
end

local function exemptOf(line)
  return line:match("look%-exempt,%s*(%S.*)$")
end

-- The code part of a line, nil for a line that is only a comment. A string's own // is rare
-- enough in these files that cutting at the first one is safe.
local function codeOf(line)
  if line:match("^%s*//") then return nil end
  return (line:gsub("//.*$", ""))
end

local function hitOf(code)
  for _, p in ipairs(PATTERNS) do
    local s, _, cap = code:find(p[1])
    if s and not (p.allow and cap and p.allow[cap]) then return p[2] end
    -- A line may hold an allowed match first and a refused one after it.
    if s and p.allow then
      for name in code:gmatch(p[1]) do
        if not p.allow[name] then return p[2] end
      end
    end
  end
  return nil
end

--- M.scan(text) -> list of { line, what, source, exempt }.
function M.scan(text)
  local hits, n, prev = {}, 0, nil
  for l in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = codeOf(l)
    local what = code and hitOf(code)
    if what then
      local above = prev and prev:match("^%s*//") and exemptOf(prev)
      hits[#hits + 1] = { line = n, what = what, source = (l:gsub("^%s+", "")), exempt = exemptOf(l) or above }
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
