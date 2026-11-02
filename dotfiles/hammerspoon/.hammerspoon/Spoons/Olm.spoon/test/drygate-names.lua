-- The names rule as a scan. The parts a person sees have one name each, settled by Milos on
-- 2026-11-02, see the Names section of AGENTS.md and decisions/olm-names.md, and a word that was
-- retired then is a second name for a part that already has one, which is the drift the rule
-- exists to end. Pure Lua with no hs and no filesystem beyond the one reader at the bottom, so
-- test/drygate.lua and a unit case both load it.
--
-- WHAT COUNTS. A retired word anywhere on a line, code and comment alike, in a Lua, Swift or
-- Markdown file of the spoon, since a comment and a doc are where a name is learned.
--
-- WHAT NEVER COUNTS. This file, which has to spell the words. The dated plans, briefs, reviews and
-- probes under docs/, which are history and keep the words of their day. A hyphenated file name,
-- docs/PLAN-ACTION-BAR.md or decisions/olm-action-panel.md, which names a record rather than a
-- part.
--
-- AN EXEMPTION, in the form kbd-exempt takes. The line, or the line directly above it, says
-- names-exempt, a comma, and the reason. An exemption with no reason is a finding.

local M = {}

-- Each retired word, as a lowercase Lua pattern, and the name that replaced it.
M.RETIRED = {
  { "companion", "preview pane, previewPane" },
  { "docked ?panes?%f[%W]", "preview pane, previewPane" },
  { "footer", "bottom bar, bottomBar" },
  { "action ?bars?%f[%W]", "bottom bar, bottomBar" },
  { "popover", "floating pane, floatingPane" },
  { "actions? ?panel", "actions pane, actionsPane" },
  { "keys? ?panel", "info pane, infoPane" },
  { "keys group", "left side" },
  { "actions group", "right side" },
  { "showkeys", "showInfo" },
  { "togglekeys", "toggleInfo" },
}

--- M.applies(rel) -> whether the rule reads the file at that path inside the spoon.
function M.applies(rel)
  if rel == "test/drygate-names.lua" then return false end
  if rel:match("^docs/[A-Z]+%-") and not rel:match("^docs/PLUGIN%-") and not rel:match("^docs/CONTRACT%-")
    and not rel:match("^docs/DESIGN%-") then
    return false
  end
  return true
end

local EXEMPT = "names%-exempt"

local function exemptionOf(line, above)
  local function reasonIn(text)
    if not text or not text:find(EXEMPT) then return nil end
    return text:match(EXEMPT .. "%s*,%s*(.-)%s*$") or ""
  end
  local own = reasonIn(line)
  if own ~= nil then return own end
  return reasonIn(above)
end

local function retiredIn(line)
  -- A hyphenated record name is not a part's name, so its words are taken out first.
  local low = line:lower():gsub("[%w_]+%-[%w%-_]+%.md", "")
  for _, r in ipairs(M.RETIRED) do
    local s, e = low:find(r[1])
    if s then return line:sub(s, e), r[2] end
  end
  return nil
end

--- M.scan(text) -> a list of { line, what, exempt, source }, one per line holding a retired word.
function M.scan(text)
  local out = {}
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  for n, line in ipairs(lines) do
    local word, now = retiredIn(line)
    if word then
      local reason = exemptionOf(line, lines[n - 1])
      local entry = { line = n, what = "the retired word '" .. word .. "', now " .. now,
        source = line:match("^%s*(.-)%s*$") }
      if reason == "" then
        entry.what = entry.what .. ", with a names-exempt that gives no reason"
      elseif reason ~= nil then
        entry.exempt = reason
      end
      out[#out + 1] = entry
    end
  end
  return out
end

--- M.scanFile(path) -> M.scan of the file, or nil when it cannot be read.
function M.scanFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return M.scan(text)
end

return M
