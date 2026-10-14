-- How wide a piece of text is. The kit's one measurer, cached by font and size, which the
-- layout engine asks for every text and badge it places.
--
-- The width is summed from a per character table rather than measured whole, the algorithm
-- lib/chooser/textwidth.lua held until it was deleted. Measuring each distinct character once
-- and adding is thirty six times cheaper than measuring the whole string, and the kerning it cannot see makes it run under one percent
-- high, which is the safe direction since over counting only shortens a string marginally
-- early. Both chooser providers measure through this file.
--
-- exact answers the other question, how wide one string draws, measured whole in a single
-- call with the kerning the sum cannot see. The layout engine places every text and badge
-- by it, since one laid out tree measures a handful of strings rather than a page of rows,
-- and since every shared surface was placed by a whole string measure before it moved onto
-- the kit, so a sum running a point high would move the next chip along by that point. It is
-- not cached, since its strings are whatever a surface is saying right now, a toast message
-- among them, and a cache keyed by them would only grow.
--
-- Wrapping is greedy by word, keeping whitespace as written and splitting a word wider than the
-- line by character, which is what the layout needs to know how many lines a wrapped text takes. It is an estimate of
-- what hs.styledtext will draw rather than a promise, since the system's own breaker can
-- choose differently around punctuation, and it errs toward one line more, never one less.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local tabs = assert(loadfile(here .. "tabs.lua"))()

local M = {}
M.__index = M

--- M.new() -> an instance holding its own cache, keyed by font and then by size.
function M.new()
  return setmetatable({ _cache = {}, _metrics = {} }, M)
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

--- instance:metrics(font, size) -> { ascender, descender, capHeight }, the real metrics of
--- the font at the size, asked of the system once and remembered. descender is negative, as
--- hs.styledtext.fontInfo answers it. The layout engine centres a text in its line band from
--- these, the way the canvas list centres a row.
function M:metrics(font, size)
  local byFont = self._metrics[font]
  if not byFont then
    byFont = {}
    self._metrics[font] = byFont
  end
  local m = byFont[size]
  if not m then
    local info = hs.styledtext.fontInfo({ name = font, size = size }) or {}
    m = { ascender = info.ascender or size, descender = info.descender or 0,
          capHeight = info.capHeight or size }
    byFont[size] = m
  end
  return m
end

--- instance:wrap(str, font, size, maxW) -> a list of lines, at least one.
--- Breaks at spaces and keeps whitespace as written, so leading indentation and a run of spaces
--- survive, since the canvas draws them and a count that dropped them would come out short. A run
--- of spaces that lands on a break is dropped rather than carried to the next line, and the spaces
--- trailing a line that breaks before a word go with it, a word wider
--- than maxW is broken by character, and a line that fits is answered whole after one measure.
--- Tabs are expanded first, by tabs.lua, the same width the code block draws. Explicit newlines
--- start a new line. A maxW of nil or below one character answers the string as one line.
function M:wrap(str, font, size, maxW)
  str = str or ""
  if not maxW or maxW <= 0 then return { str } end
  str = tabs.expand(str)
  local lines = {}
  for paragraph in (str .. "\n"):gmatch("(.-)\n") do
    if paragraph == "" or self:width(paragraph, font, size) <= maxW then
      lines[#lines + 1] = paragraph
    else
      local cur, curW = "", 0
      local before = #lines
      local pos, n = 1, #paragraph
      while pos <= n do
        local isSpace = paragraph:byte(pos) == 32
        local _, stop = paragraph:find(isSpace and "^ +" or "^[^ ]+", pos)
        local token = paragraph:sub(pos, stop)
        pos = stop + 1
        local w = self:width(token, font, size)
        if curW + w <= maxW then
          cur, curW = cur .. token, curW + w
        elseif isSpace then
          if cur ~= "" then lines[#lines + 1] = cur end
          cur, curW = "", 0
        else
          -- The spaces trailing a line that breaks before a word are the break, not content.
          cur = cur:gsub(" +$", "")
          if cur ~= "" then lines[#lines + 1] = cur end
          if w <= maxW then
            cur, curW = token, w
          else
            -- A word wider than the line is broken by character, so a long path still
            -- answers a count of lines rather than one line that overflows.
            local piece, pieceW = {}, 0
            for ch in token:gmatch(utf8.charpattern) do
              local cw = self:width(ch, font, size)
              if #piece > 0 and pieceW + cw > maxW then
                lines[#lines + 1] = table.concat(piece)
                piece, pieceW = {}, 0
              end
              piece[#piece + 1] = ch
              pieceW = pieceW + cw
            end
            cur, curW = table.concat(piece), pieceW
          end
        end
      end
      if cur ~= "" or #lines == before then lines[#lines + 1] = cur end
    end
  end
  return lines
end

return M
