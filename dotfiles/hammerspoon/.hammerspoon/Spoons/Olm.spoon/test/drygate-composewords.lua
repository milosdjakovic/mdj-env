-- Reads the set of root sourced words root/compose.lua actually publishes, for check three,
-- a manifest's own needs.data entry naming source root against what the root really hands
-- out. docs/PLUGIN-CONTRACT.md's own "The root fan out" section names this set in prose,
-- and review finding H2 is the exact failure this check exists to catch structurally rather
-- than by a person rereading that prose by hand, stageSetPlaceholder declared, validated,
-- reported satisfied, and delivered nowhere for a whole migration.
--
-- WHY THIS IS A SCAN AND NOT A REAL READ. root/compose.lua is the composition root, not a
-- manifest, and is not pure data. It is a long function full of real hs calls, closures over
-- module locals, and atoms this gate never constructs, so loadfile plus pcall cannot answer
-- what it publishes the way it can for a manifest. Running it for real needs the whole live
-- config this gate exists specifically so a builder agent never has to start. So this reads
-- the SOURCE TEXT instead, which is what the task that opened this file calls a structured
-- read when a real one is not achievable, a bracket depth aware scan rather than a blind
-- regex, its own limits named below rather than pretended away.
--
-- THE MECHANISM. Comments and string and long bracket contents are blanked first, so a brace
-- or an equals sign inside prose or a literal never perturbs the count. Then, for each named
-- local table literal this file is told to read, rootValues plus the small set of per host
-- option tables root/compose.lua builds by hand for the five plugins that bypass the generic
-- fan out, a brace depth counter walks the cleaned text and records an identifier
-- immediately followed by a single equals sign while depth is exactly one, the level right
-- inside that literal's own opening brace. A nested table's own keys never leak into the
-- answer, because entering one raises the depth past one for as long as it is open.
--
-- WHAT THIS DOES NOT SEE, named rather than hidden. `function ... end`, `if ... end`, `for
-- ... end` and the rest never open a brace, so a plain assignment inside a function VALUE
-- sitting in the literal, `local fn = dispatchTable[action]` inside actionPanelOpts's own
-- run, reads as depth one too, indistinguishable from a real key by brace counting alone.
-- The one cheap guard this file adds, skipping any match immediately preceded by the `local`
-- keyword, closes the exact case found while this file was being built and documented in the
-- comment beside it below, but a non local reassignment inside a nested function body would
-- still slip through undetected. A computed key, `[expr] = value`, is never seen either,
-- since the pattern only matches a bare identifier. And a word delivered by a later
-- assignment statement rather than written inside the literal itself, `opts.sections = ...`
-- for host/hypercheatsheet's own sections, found while this file was being built and left
-- unfixed on purpose rather than patched with one more hand named exception, since a hand
-- kept exception list is the exact roster this whole configuration's own design principles
-- exist to remove, is not seen either. A finding this check raises is therefore a strong
-- signal worth checking by hand against root/compose.lua before treating it as settled,
-- worded that way at the one call site that raises it, never a silent, unappealable refusal.
local M = {}

-- The named local table literals in root/compose.lua this scan reads. rootValues is the
-- generic fan out every ordinary plugin's own root sourced need is answered from. The other
-- five are root/compose.lua's own hand built option tables for the host modules that bypass
-- that fan out entirely, hypercheatsheet, queryscope, actionpanel, and stage, plus
-- queryScopeLate and launcherOpts, both built later and folded into lateData rather than
-- wireData, for queryscope's own second pass and the launcher.
M.TABLE_NAMES = {
  "rootValues", "hyperCheatSheetOpts", "queryScopeOpts", "queryScopeLate",
  "actionPanelOpts", "stageOpts", "launcherOpts",
}

local function stripCommentsAndStrings(src)
  local out = {}
  local i, n = 1, #src
  while i <= n do
    local two = src:sub(i, i + 1)
    if two == "--" then
      local eqs = src:match("^%-%-%[(=*)%[", i)
      if eqs then
        local _, closeEnd = src:find("%]" .. eqs .. "%]", i)
        local stop = closeEnd or n
        for j = i, stop do out[j] = (src:sub(j, j) == "\n") and "\n" or " " end
        i = stop + 1
      else
        local nl = src:find("\n", i) or (n + 1)
        for j = i, nl - 1 do out[j] = " " end
        i = nl
      end
    else
      local c = src:sub(i, i)
      if c == '"' or c == "'" then
        local quote = c
        local j = i + 1
        while j <= n do
          local cj = src:sub(j, j)
          if cj == "\\" then j = j + 2
          elseif cj == quote then break
          else j = j + 1 end
        end
        j = math.min(j, n)
        for k = i, j do out[k] = (src:sub(k, k) == "\n") and "\n" or " " end
        i = j + 1
      elseif c == "[" and src:match("^%[(=*)%[", i) then
        local eqs = src:match("^%[(=*)%[", i)
        local _, closeEnd = src:find("%]" .. eqs .. "%]", i)
        local stop = closeEnd or n
        for j = i, stop do out[j] = (src:sub(j, j) == "\n") and "\n" or " " end
        i = stop + 1
      else
        out[i] = c
        i = i + 1
      end
    end
  end
  return table.concat(out)
end

-- Top level keys of one named local table literal, found by balanced brace depth counting
-- on the cleaned text. Answers nil plus a reason when the literal itself cannot be found at
-- all, which the caller treats as its own finding, since a table name this file was told to
-- read having vanished from compose.lua is worth knowing about rather than silently reading
-- as an empty, always failing word set.
local function topLevelKeys(cleanSrc, varName)
  local declStart = cleanSrc:find("local%s+" .. varName .. "%s*=%s*{")
  if not declStart then return nil, "no 'local " .. varName .. " = {' found" end
  local openBrace = cleanSrc:find("{", declStart)
  local i, n = openBrace + 1, #cleanSrc
  local depth = 0
  local keys, seen = {}, {}
  while i <= n do
    local c = cleanSrc:sub(i, i)
    if c == "{" then
      depth = depth + 1
      i = i + 1
    elseif c == "}" then
      if depth == 0 then break end
      depth = depth - 1
      i = i + 1
    elseif depth == 0 then
      local s, _, ident = cleanSrc:find("^([%a_][%w_]*)%s*=[^=]", i)
      if s then
        -- A table key is never preceded by `local`, the one cheap guard against a plain
        -- assignment inside a function value at this same brace depth, see this file's own
        -- header.
        local precedingLocal = cleanSrc:sub(math.max(1, i - 7), i - 1):match("local%s+$")
        if not precedingLocal and not seen[ident] then
          seen[ident] = true
          keys[#keys + 1] = ident
        end
        -- Skip the whole identifier just examined, matched or not, so a rejected word is
        -- never re-scanned from its own second letter onward, which would otherwise report
        -- a truncated suffix as if it were a real key.
        i = i + #ident
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return keys
end

--- M.published(composePath)
--- The set of root sourced words root/compose.lua publishes, as a lookup table, word to
--- true, plus a list of any named table this scan could not find at all, which the caller
--- reports as its own finding rather than silently treating as zero published words.
function M.published(composePath)
  local f, openErr = io.open(composePath, "r")
  if not f then return nil, { "could not open " .. composePath .. ", " .. tostring(openErr) } end
  local text = f:read("a")
  f:close()

  local clean = stripCommentsAndStrings(text)
  local words, problems = {}, {}
  for _, varName in ipairs(M.TABLE_NAMES) do
    local keys, err = topLevelKeys(clean, varName)
    if not keys then
      problems[#problems + 1] = "root/compose.lua, " .. varName .. ", " .. err
    else
      for _, k in ipairs(keys) do words[k] = true end
    end
  end
  return words, problems
end

return M
