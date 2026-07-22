-- Drop every candidate glyph that renders as a missing glyph box on this Mac.
--
-- The picker's premise is glyphs the system can actually draw, and the only authority
-- on that is the render itself, not any table of blocks. So this stage, the filter in
-- the generator's pipe, renders each candidate through the very canvas the picker uses
-- and rejects any whose image is a placeholder box. It learns the boxes rather than
-- guessing them, an unassigned codepoint can only render as a box, so rendering a spread
-- of unassigned codepoints collects the set of box images this font stack produces, and
-- any candidate whose render matches one is itself a box. The boxes are region shaped, a
-- few distinct images, so a sample across the range captures them all.
--
-- It is run by regenerate.sh through the hs command line, which sets three globals with
-- the file paths, CANDIDATES the merged emoji and symbol list, REFS the unassigned
-- codepoints, and OUT the final data.json. It needs no spoon loaded, only hs.canvas.

local ICON_SIZE = 72
local ICON_TEXT_SIZE = 52

-- The same canvas geometry the spoon renders icons through, so a box here is exactly a
-- box there.
local canvas = hs.canvas.new({ x = 0, y = 0, w = ICON_SIZE, h = ICON_SIZE })
canvas[1] = { type = "text", text = "", textSize = ICON_TEXT_SIZE,
  textAlignment = "center", frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }

local function render(glyph)
  canvas[1].text = glyph
  local img = canvas:imageFromCanvas()
  return img and img:encodeAsURLString() or nil
end

-- Collect the box images. The refs file holds every unassigned BMP codepoint; a fixed
-- sample spread evenly across them is plenty, since the boxes vary by region and a wide
-- sample hits every region. Rendering all of them would be slower for no gain.
local refs = {}
for line in io.lines(REFS) do
  local cp = tonumber(line)
  if cp then refs[#refs + 1] = cp end
end
local SAMPLES = 600
local step = math.max(1, math.floor(#refs / SAMPLES))
local boxes = {}
local boxCount = 0
for i = 1, #refs, step do
  local sig = render(utf8.char(refs[i]))
  if sig and not boxes[sig] then boxes[sig] = true; boxCount = boxCount + 1 end
end

-- Filter the candidates. A glyph rendering to a known box image, or to nothing, is
-- dropped. Emoji are colour glyphs and never match a monochrome box, so they pass
-- untouched; the drops are all missing symbols.
local data = hs.json.read(CANDIDATES) or {}
local kept = {}
local dropped = 0
for _, e in ipairs(data) do
  local sig = render(e.e)
  if sig and not boxes[sig] then
    kept[#kept + 1] = e
  else
    dropped = dropped + 1
  end
end

hs.json.write(kept, OUT, true, true)
print("tofu filter: kept " .. #kept .. ", dropped " .. dropped ..
  " box glyphs, learned from " .. boxCount .. " box images")
