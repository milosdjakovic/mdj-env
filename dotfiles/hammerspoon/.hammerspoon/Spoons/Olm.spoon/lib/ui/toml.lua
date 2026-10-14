-- A reader for the small subset of TOML the theme files use, and nothing else. Comments,
-- blank lines, [section] headers and key = "string" lines, and a line outside that is
-- refused with an error naming the file and the line number, never guessed at, so a typo in
-- a theme file is found where it was written rather than as a colour that quietly went
-- missing.
--
-- Pure Lua with no hs, so the unit loads in plain Lua. The file system is not touched here
-- either, parse takes the text and read takes a function that answers it, which is how
-- lib/ui/themes.lua hands in the real reader and a test hands in a table.

local M = {}

local function fail(label, lineNumber, why)
  error(label .. ", line " .. lineNumber .. ", " .. why, 0)
end

--- M.parse(text, label) -> table of sections, each a table of key to string.
--- A key before any header lands in the section named by the empty string. label names the
--- file in an error. The same key twice in one section is refused, since the second would
--- silently replace the first.
function M.parse(text, label)
  label = label or "toml"
  local out = { [""] = {} }
  local current = out[""]
  local lineNumber = 0
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    lineNumber = lineNumber + 1
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "" or trimmed:sub(1, 1) == "#" then
      -- A comment or a blank line, nothing to read.
    else
      local section = trimmed:match("^%[([%w_%-%.]+)%]%s*$")
        or trimmed:match("^%[([%w_%-%.]+)%]%s+#.*$")
      if section then
        if out[section] then fail(label, lineNumber, "the section [" .. section .. "] is declared twice") end
        current = {}
        out[section] = current
      else
        local key, value = trimmed:match('^([%w_%-]+)%s*=%s*"([^"]*)"%s*$')
        if not key then
          key, value = trimmed:match('^([%w_%-]+)%s*=%s*"([^"]*)"%s+#.*$')
        end
        if not key then
          fail(label, lineNumber, "this is not a comment, a [section] or a key = \"string\" line, "
            .. "the only three forms these files use")
        end
        if current[key] ~= nil then fail(label, lineNumber, "the key " .. key .. " is set twice in one section") end
        current[key] = value
      end
    end
  end
  return out
end

--- M.read(path, reader) -> table of sections.
--- reader is a function of a path answering the file's text, or nil when it is not there.
--- With none given the file is read from disk, which is the one place this file touches it.
function M.read(path, reader)
  local text
  if reader then
    text = reader(path)
  else
    local handle = io.open(path, "r")
    if handle then text = handle:read("a"); handle:close() end
  end
  if text == nil then error(path .. ", the file could not be read", 0) end
  return M.parse(text, path)
end

return M
