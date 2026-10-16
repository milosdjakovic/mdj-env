-- The layer rule as a scan. Nothing outside plugins/ names a plugin, because the root and the
-- core may know only contracts, and a name written into core code is the coupling the core
-- split exists to end. The person's config (init.lua and config/ at the hammerspoon root),
-- tests and docs sit outside the scanned set, which drygate.sh decides, so this file only
-- reads the text it is handed.
--
-- This is the first of two layers. test/drygate-rename.lua is the second, it runs the
-- composition root over scrambled plugin names and reports any difference in what core
-- decided, which sees every route a name can take, including the ones no token pattern here
-- can. This scan stays because it names the file and the line, which a difference in behaviour
-- cannot, and because it reads code the root never runs at load, a host's code that runs only
-- once a list is shown.
--
-- THE IDENTITIES come from the manifests, never from a list written here. An identity is the
-- manifest's name when it declares one, else its directory, and the directory name is always
-- included as well, since a path or a require names the directory.
--
-- THE FORMS, all matched on code with comments removed. Plugin names are also ordinary words
-- (settings, audio, volume, convert, emoji, wifi), so each form is a place in the syntax where
-- a word can only be a name core chose, never a word a sentence happened to use.
--   1. A quoted string literal whose whole value is an identity, "vpn" or 'displayProfiles'.
--      That covers a table key written ["vpn"], a plugin handed to a function by name and a
--      member of a list of names.
--   2. A quoted string literal that is a path into a plugin, plugins/<dir> or plugins.<dir>,
--      followed by a boundary, which is how a require or a file path names one.
--   3. A bare identifier or a field access, name or .name, for an identity that carries an
--      upper case letter, displayProfiles and tmuxSessions. Lua code does not write a mixed
--      case word for anything but a name it owns.
--   4. A field or method access whose name is a lower case identity, opts.audio or
--      modules.clipboard, wherever the receiver is anything but the hs global. A table keyed by
--      plugin identity is reached exactly this way, and hs is the Hammerspoon api, whose
--      settings and wifi are Hammerspoon's own and never a plugin, since no plugin is ever
--      mounted on hs. Only the bare global is exempt, x.hs.settings is still reported.
--   5. A table constructor key that is a lower case identity, { apptoggler = 1 }, the same
--      table keyed by identity built rather than read.
--   6. A string built from literals. A chain of literals joined with .. is folded into one
--      string first, and so is string.format or ("..."):format with nothing but literal
--      arguments, and the result is matched as forms 1 and 2. "wi" .. "fi" is wifi.
--   7. A path into plugins finished at run time, a literal ending in plugins/ or plugins.
--      joined with .. to anything. Core reaching a plugin directory by a computed name is the
--      same leak as a literal one, and only the loader may walk that directory, which it does
--      through the plugin roots the root hands it rather than a path written here.
-- Not matched, a bare local variable that happens to share a plugin's name, local settings,
-- since a name a file chose for its own local reaches nothing. A name built any other way, a
-- reversed or upper cased literal, a table.concat of a list, is left to the rename proof.
--
-- Pure Lua with no hs, so test/drygate.lua and a unit case both load it.

local M = {}

--- M.tokens(text) -> list of { kind = "string"|"name"|"number"|"op", value, line, text }.
--- Skips both comment forms, line and block with any number of equals, and reads quoted and
--- long bracket strings as one string token. Operators are tokens too, so a scan can see
--- what stands before and after a word. Each token carries the full text of the line it
--- starts on, trimmed, which is how a finding names the line it was found on.
function M.tokens(text)
  local out = {}
  local i, n, line = 1, #text, 1
  local function longOpen(pos)
    return text:match("^%[(=*)%[", pos)
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
  local function push(kind, value)
    out[#out + 1] = { kind = kind, value = value, line = line }
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
      local startLine = line
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
      out[#out + 1] = { kind = "string", value = table.concat(buf), line = startLine }
      i = j + 1
    elseif ch == "[" and longOpen(i) then
      local body, nextI, newlines = readLong(i, longOpen(i))
      push("string", body)
      line = line + newlines
      i = nextI
    elseif ch:match("[%a_]") then
      local word = text:match("^[%w_]+", i)
      push("name", word)
      i = i + #word
    elseif ch:match("%d") then
      local num = text:match("^0[xX][%x%.]+", i) or text:match("^%d[%d%.]*[eE][%+%-]?%d+", i)
        or text:match("^%d[%d%.]*", i)
      push("number", num)
      i = i + #num
    elseif ch:match("%s") then
      i = i + 1
    else
      local op = text:match("^%.%.%.", i) or text:match("^%.%.", i) or text:match("^[=~<>]=", i)
        or text:match("^::", i) or text:match("^//", i) or text:match("^<<", i) or text:match("^>>", i) or ch
      push("op", op)
      i = i + #op
    end
  end
  local lines = {}
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l:match("^%s*(.-)%s*$") end
  for _, tok in ipairs(out) do tok.text = lines[tok.line] or "" end
  return out
end

local function isOp(tok, value) return tok ~= nil and tok.kind == "op" and tok.value == value end

-- A plain value a format argument can be, a string or a number literal.
local function literalValue(tok)
  if tok == nil then return nil end
  if tok.kind == "string" then return tok.value end
  if tok.kind == "number" then return tonumber(tok.value) end
  return nil
end

-- The arguments of a call whose open bracket is at index open, when every one of them is a
-- single literal, else nil.
local function literalArgs(toks, open)
  if not isOp(toks[open], "(") then return nil end
  local args, k = {}, open + 1
  if isOp(toks[k], ")") then return args end
  while true do
    local v = literalValue(toks[k])
    if v == nil then return nil end
    args[#args + 1] = v
    if isOp(toks[k + 1], ",") then
      k = k + 2
    elseif isOp(toks[k + 1], ")") then
      return args
    else
      return nil
    end
  end
end

--- M.folded(toks) -> list of { value, line, text, form }.
--- Every string core builds from literals alone, a chain of literals joined with .., and a
--- string.format or ("..."):format whose format and arguments are all literals, evaluated the
--- way Lua would. A single literal on its own is not listed here, form 1 already reads it.
function M.folded(toks)
  local out = {}
  local k = 1
  while k <= #toks do
    local tok = toks[k]
    if tok.kind == "string" and isOp(toks[k + 1], "..") and toks[k + 2] and toks[k + 2].kind == "string" then
      local parts, j = { tok.value }, k
      while isOp(toks[j + 1], "..") and toks[j + 2] and toks[j + 2].kind == "string" do
        parts[#parts + 1] = toks[j + 2].value
        j = j + 2
      end
      out[#out + 1] = { value = table.concat(parts), line = tok.line, text = tok.text, form = "string built by concatenation" }
      k = j + 1
    else
      if tok.kind == "name" and tok.value == "format" then
        local fmt, rest
        if isOp(toks[k - 1], ".") and toks[k - 2] and toks[k - 2].kind == "name" and toks[k - 2].value == "string" then
          local args = literalArgs(toks, k + 1)
          if args and type(args[1]) == "string" then fmt, rest = args[1], { table.unpack(args, 2) } end
        elseif isOp(toks[k - 1], ":") and isOp(toks[k - 2], ")") and toks[k - 3] and toks[k - 3].kind == "string"
          and isOp(toks[k - 4], "(") then
          local args = literalArgs(toks, k + 1)
          if args then fmt, rest = toks[k - 3].value, args end
        end
        if fmt then
          local ok, value = pcall(string.format, fmt, table.unpack(rest))
          if ok then
            out[#out + 1] = { value = value, line = tok.line, text = tok.text, form = "string built by format" }
          end
        end
      end
      k = k + 1
    end
  end
  return out
end

-- Forms 1 and 2 on one string value, the identity it names or nil, and the form.
local function namesIn(value, identities, dirs, wholeForm)
  if identities[value] or dirs[value] then return value, wholeForm end
  local d = value:match("plugins[/%.]([%w_]+)")
  if d and (dirs[d] or identities[d]) then return d, "path into plugins" end
  return nil
end

--- M.scan(text, identities, dirs) -> list of { line, text, identity, form }.
--- identities is a set of identity words, dirs is a set of directory names, both keyed by the
--- word. One hit per token or per folded string, the first form that matches.
function M.scan(text, identities, dirs)
  local hits = {}
  local toks = M.tokens(text)
  local function hit(tok, identity, form)
    hits[#hits + 1] = { line = tok.line, text = tok.text, identity = identity, form = form }
  end
  for k, tok in ipairs(toks) do
    local v = tok.value
    if tok.kind == "string" then
      local identity, form = namesIn(v, identities, dirs, "string literal")
      if identity then
        hit(tok, identity, form)
      elseif isOp(toks[k + 1], "..") and not (toks[k + 2] and toks[k + 2].kind == "string") then
        -- The last literal of a chain, joined to something computed. Fold the literals before
        -- it, so "plu" .. "gins/" .. name is seen the same as "plugins/" .. name.
        local whole, j = v, k
        while isOp(toks[j - 1], "..") and toks[j - 2] and toks[j - 2].kind == "string" do
          whole = toks[j - 2].value .. whole
          j = j - 2
        end
        if whole:match("plugins/$") or whole:match("plugins%.$") then
          hit(tok, "plugins", "path into plugins finished at run time")
        end
      end
    elseif tok.kind == "name" and (identities[v] or dirs[v]) then
      local prev, nextTok = toks[k - 1], toks[k + 1]
      if v:find("%u") then
        hit(tok, v, "identifier")
      elseif isOp(prev, ".") or isOp(prev, ":") then
        -- The receiver is the bare hs global only when nothing indexes into it first.
        local receiver = toks[k - 2]
        local bareHs = receiver and receiver.kind == "name" and receiver.value == "hs"
          and not (isOp(toks[k - 3], ".") or isOp(toks[k - 3], ":"))
        if not bareHs then hit(tok, v, "field") end
      elseif isOp(nextTok, "=") and (isOp(prev, "{") or isOp(prev, ",") or isOp(prev, ";")) then
        hit(tok, v, "table key")
      end
    end
  end
  for _, f in ipairs(M.folded(toks)) do
    local identity, form = namesIn(f.value, identities, dirs, f.form)
    if identity then
      if form == "path into plugins" then form = f.form .. " into plugins" end
      hits[#hits + 1] = { line = f.line, text = f.text, identity = identity, form = form }
    end
  end
  return hits
end

return M
