-- How wide a piece of text is. The kit's one measurer, cached by font and size, which the
-- layout engine asks for every text and badge it places.
--
-- The algorithm is lib/chooser/textwidth.lua's, summed from a per character table rather
-- than measured whole, and that file's header holds the measurements behind the trade. In
-- short, measuring each distinct character once and adding is thirty six times cheaper than
-- measuring the whole string, and the kerning it cannot see makes it run under one percent
-- high, which is the safe direction since over counting only shortens a string marginally
-- early. The canvas provider measures through this file since stage two. textwidth.lua stays
-- for the native provider alone, which keeps its own measuring because the system draws its
-- rows, so the two hold the same algorithm until that provider goes.
--
-- exact answers the other question, how wide one string draws, measured whole in a single
-- call with the kerning the sum cannot see. The layout engine places every text and badge
-- by it, since one laid out tree measures a handful of strings rather than a page of rows,
-- and since every shared surface was placed by a whole string measure before it moved onto
-- the kit, so a sum running a point high would move the next chip along by that point. It is
-- not cached, since its strings are whatever a surface is saying right now, a toast message
-- among them, and a cache keyed by them would only grow.
--
-- Wrapping is greedy by word, splitting a word wider than the line by character, which is
-- what the layout needs to know how many lines a wrapped text takes. It is an estimate of
-- what hs.styledtext will draw rather than a promise, since the system's own breaker can
-- choose differently around punctuation, and it errs toward one line more, never one less.

local M = {}
M.__index = M

--- M.new() -> an instance holding its own cache, keyed by font and then by size.
function M.new()
  return setmetatable({ _cache = {} }, M)
end

local function memoFor(self, font, size)
  local byFont = self._cache[font]
  if not byFont then
    byFont = {}
    self._cache[font] = byFont
  end
  local memo = byFont[size]
  if not memo then
    memo = {}
    byFont[size] = memo
  end
  return memo
end

-- One character's width, measured once per font and size and remembered after.
local function charWidth(memo, ch, font, size)
  local w = memo[ch]
  if not w then
    local sz = hs.drawing.getTextDrawingSize(ch, { font = font, size = size })
    w = (sz and sz.w) or 0
    memo[ch] = w
  end
  return w
end

-- Every character of a string, stepped by UTF8 sequence and not by byte, since a three byte
-- ellipsis measured a byte at a time answers nothing for each.
local function eachChar(str)
  local i, n = 1, #str
  return function()
    if i > n then return nil end
    local ch, nxt
    if str:byte(i) < 0x80 then
      ch, nxt = str:sub(i, i), i + 1
    else
      nxt = utf8.offset(str, 2, i) or (n + 1)
      ch = str:sub(i, nxt - 1)
    end
    i = nxt
    return ch
  end
end

--- instance:width(str, font, size) -> points.
function M:width(str, font, size)
  if not str or str == "" then return 0 end
  local memo = memoFor(self, font, size)
  local total = 0
  for ch in eachChar(str) do total = total + charWidth(memo, ch, font, size) end
  return total
end

--- instance:exact(str, font, size) -> points, one string measured whole.
function M:exact(str, font, size)
  if not str or str == "" then return 0 end
  local sz = hs.drawing.getTextDrawingSize(str, { font = font, size = size })
  return (sz and sz.w) or 0
end

--- instance:wrap(str, font, size, maxW) -> a list of lines, at least one.
--- Greedy by word, a word wider than maxW broken by character. Explicit newlines start a
--- new line. A maxW of nil or below one character answers the string as one line.
function M:wrap(str, font, size, maxW)
  str = str or ""
  if not maxW or maxW <= 0 then return { str } end
  local lines = {}
  local spaceW = self:width(" ", font, size)
  for paragraph in (str .. "\n"):gmatch("(.-)\n") do
    local cur, curW = nil, 0
    for word in paragraph:gmatch("%S+") do
      local ww = self:width(word, font, size)
      if cur and curW + spaceW + ww <= maxW then
        cur, curW = cur .. " " .. word, curW + spaceW + ww
      else
        if cur then lines[#lines + 1] = cur end
        if ww <= maxW then
          cur, curW = word, ww
        else
          -- A word wider than the line is broken by character, so a long path still
          -- answers a count of lines rather than one line that overflows.
          local memo = memoFor(self, font, size)
          local piece, pieceW = "", 0
          for ch in eachChar(word) do
            local cw = charWidth(memo, ch, font, size)
            if piece ~= "" and pieceW + cw > maxW then
              lines[#lines + 1] = piece
              piece, pieceW = "", 0
            end
            piece, pieceW = piece .. ch, pieceW + cw
          end
          cur, curW = piece, pieceW
        end
      end
    end
    lines[#lines + 1] = cur or ""
  end
  return lines
end

return M
