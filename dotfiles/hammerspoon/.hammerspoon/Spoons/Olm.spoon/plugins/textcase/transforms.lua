--- TextCase transforms.
---
--- The pure policy set behind the picker, a Strategy family of interchangeable
--- string to string case conversions plus the shared word tokenizer the reshaping
--- ones build on. This file names no picker and no clipboard, it is only the
--- algorithms, so the engine depends on this small contract (each entry is an id, a
--- name, and a fn) and never on a concrete transform. Adding a case is a new row in
--- the ordered list below, nothing else.
---
--- Three families. The literal ones (upper, lower, toggle) just recase the characters in
--- place, so they preserve every separator and punctuation mark. The prose ones (title,
--- sentence, capitalize) humanize first, turning identifier delimiters (_ and -) and
--- camelCase humps into spaces while leaving real sentence punctuation intact, so a snake,
--- kebab, or camel identifier reads as spaced words but ordinary prose keeps its commas and
--- periods. The identifier ones (camel, pascal, snake, constant, kebab, dot) tokenize fully
--- into words and rejoin them with the target convention.
---
--- Tokenizing is ASCII, a Lua pattern limitation: %w and the case methods act on
--- ASCII letters only, so an accented letter is treated as a separator and the literal
--- upper/lower leave it untouched. Acceptable for the common case; a byte level
--- Unicode recase would be a larger change and is not the point of this tool.

-- Split arbitrary text into lowercase words. Camel humps and acronym runs are turned
-- into boundaries first (fooBar -> foo Bar, XMLParser -> XML Parser), then every run
-- of alphanumerics is a word and everything else (spaces, _ - . /, punctuation) is a
-- separator. Digits stay attached to their neighbours (utf8 stays one word).
local function words(s)
  s = s:gsub("(%l)(%u)", "%1 %2")     -- lower/UPPER hump: fooBar -> foo Bar
  s = s:gsub("(%u+)(%u%l)", "%1 %2")  -- acronym then word: XMLParser -> XML Parser
  local out = {}
  for w in s:gmatch("%w+") do
    out[#out + 1] = w:lower()
  end
  return out
end

-- Capitalize one already-lowercased word: first letter up, rest unchanged.
local function cap(w)
  return w:sub(1, 1):upper() .. w:sub(2)
end

-- Humanize for the prose cases: turn identifier delimiters and camel humps into spaces,
-- but leave sentence punctuation (. , ! ? and the rest) and existing spacing alone. So a
-- snake_case, kebab-case, or camelCase identifier becomes spaced words, while real prose
-- keeps its punctuation. Only _ and - are treated as delimiters; a dot or slash is left as
-- is, since a period is far more often sentence punctuation than a separator.
local function humanize(s)
  s = s:gsub("(%l)(%u)", "%1 %2")     -- camel hump: fooBar -> foo Bar
  s = s:gsub("(%u+)(%u%l)", "%1 %2")  -- acronym then word: XMLParser -> XML Parser
  s = s:gsub("[_%-]+", " ")           -- identifier delimiters -> space
  s = s:gsub("%s+", " ")              -- collapse whitespace runs
  return (s:gsub("^ ", ""):gsub(" $", ""))
end

local function pascalize(ws)
  local t = {}
  for _, w in ipairs(ws) do t[#t + 1] = cap(w) end
  return table.concat(t)
end

local function camelize(ws)
  if #ws == 0 then return "" end
  local t = { ws[1] }
  for i = 2, #ws do t[#t + 1] = cap(ws[i]) end
  return table.concat(t)
end

local function join(ws, sep)
  return table.concat(ws, sep)
end

-- The ordered catalog. `name` is written in its own case so the row title itself
-- demonstrates the result, and `fn` is the pure transform the engine runs over the
-- selection for both the preview subtitle and the pasted result.
return {
  { id = "upper",     name = "UPPER CASE",     fn = function(s) return s:upper() end },
  { id = "lower",     name = "lower case",     fn = function(s) return s:lower() end },
  { id = "title",     name = "Title Case",
    fn = function(s) return (humanize(s):gsub("%a+", function(w) return cap(w:lower()) end)) end },
  { id = "sentence",  name = "Sentence case",
    fn = function(s) return (humanize(s):lower():gsub("%a", string.upper, 1)) end },
  { id = "capitalize", name = "Capitalize",
    fn = function(s) return (humanize(s):gsub("%a", string.upper, 1)) end },
  { id = "toggle",    name = "tOGGLE cASE",
    fn = function(s)
      return (s:gsub("%a", function(c) return c:match("%l") and c:upper() or c:lower() end))
    end },
  { id = "camel",     name = "camelCase",      fn = function(s) return camelize(words(s)) end },
  { id = "pascal",    name = "PascalCase",     fn = function(s) return pascalize(words(s)) end },
  { id = "snake",     name = "snake_case",     fn = function(s) return join(words(s), "_") end },
  { id = "constant",  name = "CONSTANT_CASE",  fn = function(s) return join(words(s), "_"):upper() end },
  { id = "kebab",     name = "kebab-case",     fn = function(s) return join(words(s), "-") end },
  { id = "dot",       name = "dot.case",       fn = function(s) return join(words(s), ".") end },
}
