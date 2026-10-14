-- The typography rule as a scan, the way src/check-theme.sh reports a hex value written into
-- a tool's own config. Every font, size and line height in this spoon is a role of the UI
-- kit, lib/ui, so a font name, a text size or a line height written by hand anywhere else is
-- the drift that rule exists to end. This file is pure Lua with no hs and no filesystem
-- beyond the one reader at the bottom, so test/drygate.lua and a unit case both load it.
--
-- WHAT COUNTS. A value written by hand, which is a literal. A textSize read from a variable
-- the kit filled, or a font table built from the font and size a role handed over, is the
-- kit's value passing through and is not the drift, so the patterns look for the literal and
-- for an upper case constant, which is a literal one assignment removed. A line height field
-- is flagged whatever its value, since no caller outside the kit has a reason to set one.
--
-- WHAT NEVER COUNTS. A line that is a comment, and the comment at the end of a code line.
--
-- AN EXEMPTION, mirroring theme-exempt in form. An icon is drawn into a small canvas as a
-- glyph or an emoji, and a glyph is an image rather than text, so its size is its own. The
-- line, or the comment line directly above it, says type-exempt, a comma, and the reason. An
-- exemption with no reason is a finding, since an exemption with no reason is a size with no
-- owner.

local M = {}

-- Names a font is written as. A quoted string that begins with one of these and holds only
-- name characters is a font, so a sentence that happens to start with Georgia is not.
local FONT_PREFIXES = {
  ".AppleSystem", ".SF", "SF Pro", "SF Mono", "SF Compact", "Apple Color Emoji", "Apple Symbols",
  "Menlo", "Monaco", "Courier", "Helvetica", "Arial", "Georgia", "Times", "Lucida", "Avenir",
  "Futura", "Verdana", "Tahoma", "Palatino", "Optima", "Cochin", "Didot", "Baskerville",
  "JetBrains", "Fira", "Meslo",
}

local function isFontLiteral(c)
  for quote, body in c:gmatch("([\"'])([^\"']*)%1") do
    if #body <= 40 and body:match("^[%w%s%.%-]+$") then
      for _, prefix in ipairs(FONT_PREFIXES) do
        if body:sub(1, #prefix) == prefix then return true end
      end
    end
  end
  return false
end

-- Each rule is a name for the finding and a test on the code part of one line.
local RULES = {
  { "a literal textFont", function(c)
    return c:match("textFont%s*=%s*[\"']") or c:match("textFont%s*=%s*%u[%u%d_]*%f[^%w_]")
  end },
  { "a hand set text size", function(c)
    return c:match("[Tt]extSize%s*=%s*%.?%d") or c:match("[Tt]extSize%s*=%s*%u[%u%d_]*%f[^%w_]")
      or c:match("[Ff]ontSize%s*=%s*%.?%d") or c:match("[Tt]itleSize%s*=%s*%.?%d")
      or c:match("[Ss]ubSize%s*=%s*%.?%d")
  end },
  { "a hand built font table", function(c)
    return c:match("%f[%w]font%s*=%s*{[^}]*name%s*=%s*[\"']") or c:match("%f[%w]font%s*=%s*{[^}]*size%s*=%s*%.?%d")
      or c:match("%f[%w]font%s*=%s*{%s*$")
  end },
  { "a literal font name", isFontLiteral },
  { "a hand set line height", function(c)
    return c:match("minimumLineHeight") or c:match("maximumLineHeight") or c:match("lineHeightMultiple")
      or c:match("[Ll]ineHeight%s*=%s*%.?%d")
  end },
}

-- The code part of a line, with a whole line comment gone and the trailing comment cut off
-- where a double dash sits outside a quoted string. nil for a line that is only a comment
-- or blank.
local function codeOf(line)
  if line:match("^%s*%-%-") or line:match("^%s*$") then return nil end
  local quote
  local i, n = 1, #line
  while i <= n do
    local ch = line:sub(i, i)
    if quote then
      if ch == "\\" then i = i + 1 elseif ch == quote then quote = nil end
    elseif ch == "\"" or ch == "'" then
      quote = ch
    elseif ch == "-" and line:sub(i, i + 1) == "--" then
      return line:sub(1, i - 1)
    end
    i = i + 1
  end
  return line
end

local EXEMPT = "type%-exempt"

-- What the exemption on a line says, "" for none, or the reason it gave. The comment part of
-- the same line counts, and so does a whole comment line directly above.
local function exemptionOf(line, above)
  local function reasonIn(text)
    if not text or not text:find(EXEMPT) then return nil end
    local tail = text:match(EXEMPT .. "%s*,?%s*(.-)%s*$") or ""
    return tail
  end
  local own = reasonIn(line)
  if own ~= nil then return own end
  if above and above:match("^%s*%-%-") then return reasonIn(above) end
  return nil
end

--- M.scan(text) -> a list of { line = n, what = "...", exempt = reason or nil, source = trimmed }
--- one per offending line, a line named once for the first rule it breaks. An exempt line
--- carries its reason, and an exemption with no reason comes back as a finding of its own.
function M.scan(text)
  local out = {}
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  for n, line in ipairs(lines) do
    local code = codeOf(line)
    if code then
      for _, rule in ipairs(RULES) do
        if rule[2](code) then
          local reason = exemptionOf(line, lines[n - 1])
          local entry = { line = n, what = rule[1], source = line:match("^%s*(.-)%s*$") }
          if reason == nil then
            -- not exempt, a plain finding
          elseif reason == "" then
            entry.what = entry.what .. " with a type-exempt that gives no reason"
          else
            entry.exempt = reason
          end
          out[#out + 1] = entry
          break
        end
      end
    end
  end
  return out
end

--- M.scanFile(path) -> the same list for one file, nil when it cannot be read.
function M.scanFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return M.scan(text)
end

return M
