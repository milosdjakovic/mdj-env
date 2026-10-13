--- Measures the rendered pixel width of a string cheaply and safely, the mechanism every
--- picker provider that draws its own rows needs. Moved out of
--- lib/chooser/providers/native.lua by the contract freeze phase, docs/BRIEF-CONTRACT-FREEZE.md,
--- since nothing in the measuring itself is coupled to hs.chooser, so a second provider must
--- not reimplement it and must not reach into the native provider to borrow it.
---
--- SUMMED FROM A PER CHARACTER TABLE rather than measured whole, which is the trade the
--- whole feature rests on. Measuring a whole subtitle costs 0.11 ms, so a page of two
--- hundred rows would spend 22 ms per keystroke. Measuring each distinct character once
--- and adding costs 0.003 ms a string, thirty six times less, and a page disappears into
--- the noise. The characters in a row are drawn from a tiny alphabet that repeats across
--- every row, so the table fills in the first few rows and never grows again.
---
--- The price is kerning, which the sum cannot see. Measured against true whole string
--- widths it runs 0.7 percent high on real paths, under two pixels on a 254 pixel string.
--- HIGH is the direction that matters. Over counting shortens a string marginally early,
--- which looks like nothing, where under counting would let a string through that then
--- gets cut, which is the exact failure this exists to prevent. So there is no fudge
--- factor, the error already leans the safe way.
---
--- Stepped by UTF8 sequence and not by byte, because a path can hold anything and the
--- ellipsis this feeds is itself three bytes. Measuring those bytes one at a time returns
--- nothing for each and would undercount a shortened string to zero.

local M = {}
M.__index = M

--- M.new() -> an instance holding its own cache, keyed by font and then by size, since a
--- module now shared across providers rarely sees two of them agree on a font, where the
--- single instance native.lua used to hold needed only a size key.
function M.new()
  return setmetatable({ _cache = {} }, M)
end

--- instance:width(str, font, size) -> pixels. Character widths are cached for the life of
--- the instance rather than the call, since a character in a fixed font at a fixed size
--- renders the same forever.
function M:width(str, font, size)
  if not str or str == "" then return 0 end
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
  local style = { font = font, size = size }
  local total, i, n = 0, 1, #str
  while i <= n do
    -- A plain byte is its own character, so the common path skips utf8.offset entirely.
    -- Paths and titles are almost all ASCII and this runs on every row of every keystroke.
    local ch, nxt
    if str:byte(i) < 0x80 then
      ch, nxt = str:sub(i, i), i + 1
    else
      nxt = utf8.offset(str, 2, i) or (n + 1)
      ch = str:sub(i, nxt - 1)
    end
    local w = memo[ch]
    if not w then
      local sz = hs.drawing.getTextDrawingSize(ch, style)
      w = (sz and sz.w) or 0
      memo[ch] = w
    end
    total = total + w
    i = nxt
  end
  return total
end

return M
