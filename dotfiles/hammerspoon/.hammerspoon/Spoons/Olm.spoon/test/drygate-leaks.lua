-- The layer rule as a scan. Nothing outside plugins/ names a plugin, because the root and the
-- core may know only contracts, and a name written into core code is the coupling the core
-- split exists to end. The person's config (init.lua and config/ at the hammerspoon root),
-- tests and docs sit outside the scanned set, which drygate.sh decides, so this file only
-- reads the text it is handed.
--
-- THE IDENTITIES come from the manifests, never from a list written here. An identity is the
-- manifest's name when it declares one, else its directory, and the directory name is always
-- included as well, since a path or a require names the directory.
--
-- THE RULE. Plugin names are also ordinary words (settings, audio, volume, convert, emoji,
-- wifi), and hs.settings or hs.wifi is the Hammerspoon api and not a plugin, so a plain word
-- match drowns in false hits. Three precise forms are matched instead, all on code with
-- comments removed.
--   1. A quoted string literal whose whole value is an identity, "vpn" or 'displayProfiles'.
--      That covers a table key written ["vpn"], a plugin handed to a function by name and a
--      member of a list of names.
--   2. A quoted string literal that is a path into a plugin, plugins/<dir> or plugins.<dir>,
--      followed by a boundary, which is how a require or a file path names one.
--   3. A bare identifier or a field access, name or .name, only for an identity that carries
--      an upper case letter, displayProfiles and tmuxSessions. Lua code does not write a
--      mixed case word for anything but a name it owns, so that form is a plugin and never a
--      common word. A lower case identity is never matched as a bare word, only as form 1 or 2,
--      because there a bare word is indistinguishable from ordinary code.
-- Not matched on purpose, a lower case identity written as a bare field such as opts.audio.
-- That is the one blind spot, named so it is not mistaken for coverage.
--
-- Pure Lua with no hs, so test/drygate.lua and a unit case both load it.

local M = {}

--- M.tokens(text) -> list of { kind = "string"|"name", value = string, line = number }.
--- Skips both comment forms, line and block with any number of equals, and reads quoted and
--- long bracket strings as one string token. A long bracket string is kept as a string, since
--- it is code, and only a comment is dropped.
function M.tokens(text)
  local out = {}
  local i, n, line = 1, #text, 1
  local function longOpen(pos)
    local eq = text:match("^%[(=*)%[", pos)
    return eq
  end
  local function readLong(pos, eq)
    local close = "]" .. eq .. "]"
    local from = pos + #eq + 2
    local s, e = text:find(close, from, true)
    local stop = e or n
    local body = text:sub(from, (s or n + 1) - 1)
    local _, newlines = text:sub(pos, stop):gsub("\n", "")
    return body, stop + 1, newlines
  end
  while i <= n do
    local ch = text:sub(i, i)
    if ch == "\n" then
      line = line + 1
      i = i + 1
    elseif text:sub(i, i + 1) == "--" then
      local eq = longOpen(i + 2)
      if eq then
        local _, nextI, newlines = readLong(i + 2, eq)
        line = line + newlines
        i = nextI
      else
        local stop = text:find("\n", i, true)
        i = stop or n + 1
      end
    elseif ch == "\"" or ch == "'" then
      local j, buf = i + 1, {}
      while j <= n do
        local c = text:sub(j, j)
        if c == "\\" then
          buf[#buf + 1] = text:sub(j, j + 1)
          if text:sub(j + 1, j + 1) == "\n" then line = line + 1 end
          j = j + 2
        elseif c == ch or c == "\n" then
          break
        else
          buf[#buf + 1] = c
          j = j + 1
        end
      end
      out[#out + 1] = { kind = "string", value = table.concat(buf), line = line }
      i = j + 1
    elseif ch == "[" and longOpen(i) then
      local body, nextI, newlines = readLong(i, longOpen(i))
      out[#out + 1] = { kind = "string", value = body, line = line }
      line = line + newlines
      i = nextI
    elseif ch:match("[%a_]") then
      local word = text:match("^[%w_]+", i)
      out[#out + 1] = { kind = "name", value = word, line = line }
      i = i + #word
    else
      i = i + 1
    end
  end
  return out
end

--- M.scan(text, identities, dirs) -> list of { line, identity, form }.
--- identities is a set of identity words, dirs is a set of directory names, both keyed by the
--- word. One hit per token, the first form that matches.
function M.scan(text, identities, dirs)
  local hits = {}
  for _, tok in ipairs(M.tokens(text)) do
    local v = tok.value
    if tok.kind == "string" then
      if identities[v] or dirs[v] then
        hits[#hits + 1] = { line = tok.line, identity = v, form = "string literal" }
      else
        local d = v:match("plugins[/%.]([%w_]+)")
        if d and (dirs[d] or identities[d]) then
          hits[#hits + 1] = { line = tok.line, identity = d, form = "path into plugins" }
        end
      end
    elseif v:find("%u") and (identities[v] or dirs[v]) then
      hits[#hits + 1] = { line = tok.line, identity = v, form = "identifier" }
    end
  end
  return hits
end

return M
