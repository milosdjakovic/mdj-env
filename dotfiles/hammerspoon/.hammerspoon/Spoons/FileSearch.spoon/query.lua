--- File search query parsing.
---
--- One pure function turning what was typed into a structured search. It touches no
--- filesystem, no Hammerspoon api, and no clock, which is deliberate and is the reason
--- this file exists separately at all. The grammar is the trickiest part of the spoon
--- and the only part with real branching, so keeping it pure means it can be exercised
--- with a standalone lua and no running Hammerspoon.
---
--- THE GRAMMAR IN TWO RULES.
---   A dot ATTACHED to a token is a type, so `.js hello` is JavaScript matching hello.
---   A dot ALONE is a token of its own meaning include hidden, so `. js` is everything
---   matching js with hidden files included.
--- Everything else is plain text. A bare word is never a type, which is what makes
--- `js hello there` find a file actually called that, and `hi everyone` an ordinary
--- search rather than a hunt for the extension hi.
---
--- Why registry membership decides and not spacing. `.js` and `.jshintrc` both have a
--- dot attached, and both are things people type. Rather than a rule about whether the
--- token looks finished, the remainder is simply looked up. `js` is a known type so it
--- filters, `jshintrc` is not so it is a hidden filename fragment. Both readings are
--- what you would want, and neither needs explaining. The cost is that an extension
--- absent from the registry does not filter strictly, and that is survivable because an
--- extension is part of a filename, so it still matches as text.
---
--- Scope is the first remaining token containing a slash, split at its LAST slash, so
--- `downloads/hs` scopes to Downloads and searches for hs while `downloads/` scopes with
--- nothing to search, which is a browse. Resolving that token to a real directory is
--- NOT done here, because it needs the filesystem and possibly a frecency tool. This
--- file hands the raw token onward and the engine resolves it, which is what keeps the
--- parse pure.

local M = {}

-- Split on whitespace, keeping it simple since a query is short.
local function words(s)
  local out = {}
  for w in (s or ""):gmatch("%S+") do out[#out + 1] = w end
  return out
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Peel the leading token off, returning it and whatever follows.
local function peel(s)
  local tok, tail = s:match("^(%S+)(.*)$")
  return tok, tail or ""
end

--- query.parse(raw, types) -> parsed
---
--- types is the token to extension map from config, the only outside knowledge this
--- needs, passed in rather than required so the function stays pure.
---
--- The result carries:
---   raw        what was typed, untouched
---   hidden     include paths Spotlight cannot see, from the lone dot or a dotted text
---   ignored    include what gitignore and the prune list drop, from a lone bang
---   typeTokens list of type tokens consumed, for display
---   exts       union of the extensions those tokens cover, or nil for no type filter
---   scope      the raw directory token including its trailing slash, or nil
---   text       the free text, whitespace collapsed
---   words      that text split, since every matcher wants it split anyway
---   kind       "recent" with nothing to search, "browse" with a scope and no text,
---              "search" otherwise. The engine branches on this rather than
---              re deriving it, so the one place that decides what a query means is here
function M.parse(raw, types)
  raw = raw or ""
  types = types or {}

  local q = {
    raw = raw,
    hidden = false,
    ignored = false,
    typeTokens = {},
    exts = nil,
    scope = nil,
    text = "",
    words = {},
  }

  local rest = trim(raw)

  -- The leading slot. Sigils and type tokens are consumed in a loop so their order is
  -- free and several may combine, which is what lets `. .js src/` read as hidden
  -- JavaScript under src. A token that is neither stops the loop, and everything from
  -- there on is scope and text.
  local seen = {}
  while rest ~= "" do
    local tok, tail = peel(rest)
    if not tok then break end
    local consumed = false

    if tok == "." then
      q.hidden = true
      consumed = true
    elseif tok == "!" then
      q.ignored = true
      consumed = true
    else
      local name = tok:match("^%.(.+)$")
      name = name and name:lower() or nil
      if name and types[name] then
        if not seen[name] then
          seen[name] = true
          q.typeTokens[#q.typeTokens + 1] = name
          q.exts = q.exts or {}
          for _, ext in ipairs(types[name]) do
            q.exts[#q.exts + 1] = ext
          end
        end
        consumed = true
      end
    end

    if not consumed then break end
    rest = trim(tail)
  end

  -- The scope slot. Only the first remaining token is considered, and only when it
  -- holds a slash, so a slash appearing later in free text is left alone.
  if rest ~= "" then
    local first, tail = peel(rest)
    if first and first:find("/", 1, true) then
      local scope, remainder = first:match("^(.*/)([^/]*)$")
      if scope then
        q.scope = scope
        rest = trim((remainder or "") .. " " .. tail)
      end
    end
  end

  q.text = trim(rest):gsub("%s+", " ")
  q.words = words(q.text)

  -- A text starting with a dot means a hidden filename, which is how `.zshrc` works
  -- with no sigil. Only when no type was consumed, since `.js` already had its dot
  -- read as a type and its text is whatever came after.
  if #q.typeTokens == 0 and q.text:sub(1, 1) == "." then
    q.hidden = true
  end

  if q.text == "" then
    q.kind = q.scope and "browse" or "recent"
  else
    q.kind = "search"
  end

  return q
end

--- query.sameShape(a, b) -> boolean
--- Whether two parses ask about the same candidate population, ignoring their text.
--- This is what decides whether a result set can be reused, so it compares everything
--- that changes which files could match and nothing that only changes which of them do.
function M.sameShape(a, b)
  if not a or not b then return false end
  if a.hidden ~= b.hidden or a.ignored ~= b.ignored then return false end
  if a.scope ~= b.scope then return false end
  local ae, be = a.exts, b.exts
  if (ae == nil) ~= (be == nil) then return false end
  if ae and be then
    if #ae ~= #be then return false end
    for i = 1, #ae do
      if ae[i] ~= be[i] then return false end
    end
  end
  return true
end

--- query.narrows(prev, next) -> boolean
--- Whether `next` can be answered by filtering the results already held for `prev`,
--- with no new search. True only when the population is identical and the text merely
--- grew, since a longer text over the same population can only ever match a subset.
---
--- Deleting a character, editing the middle, or changing a sigil, a type, or the scope
--- all fail this, and correctly so. The caller has one more condition this cannot see,
--- that the held set was not truncated by its cap, because a subset of a truncated set
--- is not a subset of the truth.
function M.narrows(prev, next)
  if not M.sameShape(prev, next) then return false end
  if not prev.text or not next.text then return false end
  if #next.text <= #prev.text then return false end
  return next.text:sub(1, #prev.text) == prev.text
end

return M
