--- === Arithmetic ===
---
--- Evaluates a typed arithmetic expression and offers the result as a row. It is a
--- query row source, not a picker of its own, so it owns no chooser, no key, and no
--- window. It answers one question, given what the user typed, is there a result worth
--- showing, and returns rows as plain data. The launcher composes it with the other
--- sources and decides where the rows land, so this spoon never learns what surface it
--- appears in.
---
--- It needs nothing from outside Hammerspoon. Lua evaluates arithmetic natively and
--- already supports the four operators plus modulo, exponent, and parentheses, so there
--- is no tool to install, nothing to declare, and no process to spawn. That is why this
--- and unit conversion are two sources rather than one spoon. Conversion needs an
--- external tool and can be absent, this cannot, so keeping them apart means the half
--- that always works is never held back by the half that may not be there.
---
--- Safety comes from the alphabet, not from sandboxing alone. A query is evaluated only
--- after it passes a whitelist of digits, whitespace, the operators, the decimal point
--- and parentheses, so it cannot name a function, a variable, or a string. It is then
--- compiled in an empty environment and run under pcall, so a malformed expression is a
--- failed match rather than an error, and the result is kept only when it is a finite
--- number. Two Lua specifics are handled explicitly. A double minus opens a comment, so
--- `5--3` would otherwise evaluate to 5 and quietly lie, and two dots concatenate, which
--- yields a string the type check drops.

local obj = {}
obj.__index = obj

obj.name = "Arithmetic"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Injected via configure
obj._glyph = nil     -- the row glyph, rendered to an icon by whatever presents the row
obj._category = nil  -- the subtitle category word, so the presenter's wording stays config

-- The alphabet an expression may use. Anything else is not arithmetic and is refused
-- before Lua ever sees it, which is what makes evaluating it safe. The letter e is in the
-- set only so scientific notation like 1e5 parses. It cannot reach anything, since the
-- chunk runs in an empty environment where every name is nil, and a stray e on its own
-- fails to compile or faults under pcall, either way producing no row.
local ALLOWED = "^[%deE%s%+%-%*/%%%^%.%(%)]+$"

-- An expression must contain an operator, otherwise a plain number typed into the
-- launcher would produce a row restating itself, and it must contain a digit, so a lone
-- bracket or operator matches nothing.
local HAS_OP = "[%+%-%*/%%%^]"
local HAS_DIGIT = "%d"

-- Format a result for display and for copying. An integral value is shown without a
-- decimal tail, since Lua division always yields a float and 33.0 reads as noise, and
-- anything else keeps up to ten significant digits with the trailing zeros trimmed, so a
-- third of one reads as 0.3333333333 rather than in exponent form.
local function format(v)
  if v == math.floor(v) and math.abs(v) < 1e15 then
    return string.format("%d", v)
  end
  local s = string.format("%.10g", v)
  return s
end

--- Arithmetic:init()
--- Method
--- Initialize. Nothing to build, the evaluator is pure.
function obj:init()
  return self
end

--- Arithmetic:configure(opts)
--- Method
--- opts.glyph    the character shown as the row icon, rendered by the presenter.
--- opts.category the word leading the row subtitle, so the visible wording is config
---               rather than something this spoon decides for a surface it cannot see.
function obj:configure(opts)
  opts = opts or {}
  self._glyph = opts.glyph or "🧮"
  self._category = opts.category or "Arithmetic"
  return self
end

--- Arithmetic:evaluate(query) -> number or nil
--- Method
--- The whole grammar and the whole evaluation, exposed on its own so it can be checked
--- from the console without going through a row. Returns nil for anything that is not a
--- complete arithmetic expression with a finite numeric value.
function obj:evaluate(query)
  local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
  -- An explicit leading equals is accepted and stripped, so a value that would otherwise
  -- read as ordinary text can be forced through, and it costs nothing to allow.
  q = q:gsub("^=%s*", "")
  if q == "" then return nil end
  if not q:match(ALLOWED) then return nil end
  if not q:match(HAS_OP) then return nil end
  if not q:match(HAS_DIGIT) then return nil end
  -- A double minus opens a Lua comment, so the rest of the expression would be discarded
  -- and the answer would be confidently wrong. A double dot concatenates, which the type
  -- check below would catch, but refusing both here keeps the reason in one place.
  if q:find("--", 1, true) or q:find("..", 1, true) then return nil end

  -- Compiled in an empty environment, so even if the whitelist were ever loosened there
  -- is nothing reachable to call.
  local chunk = load("return " .. q, "arithmetic", "t", {})
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  if not ok then return nil end
  if type(value) ~= "number" then return nil end
  -- Infinity and not a number are arithmetic failures, a division by zero or an overflow,
  -- so they are not results worth offering.
  if value ~= value or value == math.huge or value == -math.huge then return nil end
  return value
end

--- Arithmetic:rows(query) -> list
--- Method
--- The query row source contract. Returns at most one row, or an empty list when the
--- query is not arithmetic, which is the overwhelmingly common case since every app
--- search contains letters and fails the whitelist on its first character.
---
--- The row is plain data like every other launcher row, carrying a glyph rather than a
--- rendered image so the presenter draws it with its own cache, and a serializable
--- descriptor rather than a function, since a function cannot survive being handed to a
--- native chooser. filterText is the raw query, so a presenter that filters its list
--- with a matcher keeps this row at the top instead of scoring the result against the
--- expression that produced it.
function obj:rows(query)
  local value = self:evaluate(query)
  if not value then return {} end
  local text = format(value)
  return {
    {
      title = text,
      subTitle = self._category .. " · " .. (query or ""):gsub("^%s+", ""):gsub("%s+$", "") .. " · copy the result",
      glyph = self._glyph,
      filterText = query,
      item = { kind = "calc", value = text },
    },
  }
end

return obj
