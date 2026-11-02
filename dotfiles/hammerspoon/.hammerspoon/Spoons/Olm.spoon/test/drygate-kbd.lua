-- The key vocabulary rule as a scan. Every key a person reads is a constant of lib/kbd.lua, so a
-- key glyph written anywhere else, a command sign in a subtitle or a return arrow in a badge, is a
-- second spelling of a key that the vocabulary cannot space, order or one day draw as a picture,
-- which is the drift the rule exists to end. Settled by Milos on 2026-11-02, see
-- decisions/olm-chooser-keys.md. Pure Lua with no hs and no filesystem beyond the one reader at
-- the bottom, so test/drygate.lua and a unit case both load it.
--
-- WHAT COUNTS. A key glyph on a code line, written as the character itself or as a \u{} escape,
-- in a Lua or a Swift file of the spoon.
--
-- WHAT NEVER COUNTS. lib/kbd.lua, where every glyph is written. The emoji catalogue, whose rows
-- are emoji a person picks rather than keys. A comment line and the comment at the end of a code
-- line. An emoji icon spec, emoji = "...", which is an icon and not a key.
--
-- AN EXEMPTION, in the form type-exempt takes. The line, or the comment line directly above it,
-- says kbd-exempt, a comma, and the reason. An exemption with no reason is a finding.
--
-- WHAT IT CANNOT SEE. A chord built as a string from a key name, "cmd" .. "+" .. key, carries no
-- glyph. That shape is refused at run time instead, since every renderer reads a chord through
-- kbd.alternatives or kbd.glyphs, and both raise on anything that is not a kbd chord.

local M = {}

-- The files the rule never reads, by their path inside the spoon.
M.SKIP = {
  ["lib/kbd.lua"] = true,
  ["plugins/emoji/data.lua"] = true,
}

-- Every glyph lib/kbd.lua writes, as the character and as the escape Lua and Swift both spell.
local GLYPHS = {
  { "\u{2318}", "2318" }, { "\u{21E7}", "21E7" }, { "\u{2325}", "2325" }, { "\u{2303}", "2303" },
  { "\u{21A9}", "21A9" }, { "\u{2324}", "2324" }, { "\u{2423}", "2423" }, { "\u{21E5}", "21E5" },
  { "\u{232B}", "232B" }, { "\u{2326}", "2326" }, { "\u{2726}", "2726" }, { "\u{25C6}", "25C6" },
  { "\u{25CF}", "25CF" },
}

-- The code part of a line, nil for a comment line. A comment opener inside a string is rare
-- enough in this spoon that a plain search for it is the right trade.
local function codeOf(line)
  if line:match("^%s*%-%-") or line:match("^%s*//") then return nil end
  local code = line:gsub("%s%-%-%s.*$", ""):gsub("%s//%s.*$", "")
  code = code:gsub("emoji%s*=%s*\"[^\"]*\"", "")
  return code
end

local function glyphIn(code)
  for _, g in ipairs(GLYPHS) do
    if code:find(g[1], 1, true) then return g[1] end
    if code:find("\\u{" .. g[2] .. "}", 1, true) or code:find("\\u{" .. g[2]:lower() .. "}", 1, true) then
      return "\\u{" .. g[2] .. "}"
    end
  end
  return nil
end

local EXEMPT = "kbd%-exempt"

local function exemptionOf(line, above)
  local function reasonIn(text)
    if not text or not text:find(EXEMPT) then return nil end
    return text:match(EXEMPT .. "%s*,%s*(.-)%s*$") or ""
  end
  local own = reasonIn(line)
  if own ~= nil then return own end
  if above and (above:match("^%s*%-%-") or above:match("^%s*//")) then return reasonIn(above) end
  return nil
end

--- M.applies(rel) -> whether the rule reads the file at that path inside the spoon.
function M.applies(rel)
  return not M.SKIP[rel] and not rel:match("^test/") and not rel:match("/test/")
end

--- M.scan(text) -> a list of { line, what, exempt, source }, one per line holding a key glyph.
function M.scan(text)
  local out = {}
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  for n, line in ipairs(lines) do
    local code = codeOf(line)
    local glyph = code and glyphIn(code)
    if glyph then
      local reason = exemptionOf(line, lines[n - 1])
      local entry = { line = n, what = "the key glyph " .. glyph, source = line:match("^%s*(.-)%s*$") }
      if reason == "" then
        entry.what = entry.what .. " with a kbd-exempt that gives no reason"
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
