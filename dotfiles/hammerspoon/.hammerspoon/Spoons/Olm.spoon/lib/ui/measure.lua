-- How wide a piece of text is. The kit's one measurer, cached by font and size, which the
-- layout engine asks for every text and badge it places.
--
-- The algorithm is lib/chooser/textwidth.lua's, summed from a per character table rather
-- than measured whole, and that file's header holds the measurements behind the trade. In
-- short, measuring each distinct character once and adding is thirty six times cheaper than
-- measuring the whole string, and the kerning it cannot see makes it run under one percent
-- high, which is the safe direction since over counting only shortens a string marginally
-- early. textwidth.lua stays where it is in stage one, since its two providers move onto the
-- kit in stage two and this stage changes nothing a person can see. Until then the two hold
-- the same algorithm, and stage two deletes the older one.
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
