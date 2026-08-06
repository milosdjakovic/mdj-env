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
-- codepoints, and OUT the final data.lua. It needs no spoon loaded, only hs.canvas.
--
-- This stage also writes the committed artifact, since it is the one place holding the
-- final list and it runs inside Hammerspoon where Lua can quote its own strings. And
-- because it holds both the new list and the committed one at the same moment, it is also
-- where the refresh reports what arrived, what left, and which arrivals no keyword reaches.

local ICON_SIZE = 72
local ICON_TEXT_SIZE = 52

-- The box learning and the candidate test render through one canvas at one size, which is
-- all the filter needs, so this size is deliberately independent of the picker's icon size
-- and does not track it. A glyph the font stack can draw is drawable at any size, so a box
-- at this size is a box at every size, and rendering larger here only makes each signature
-- more distinctive.
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

print("tofu filter: kept " .. #kept .. ", dropped " .. dropped ..
  " box glyphs, learned from " .. boxCount .. " box images")

-- Report what changed against the set already committed, before overwriting it. A refresh
-- is worth running when new glyphs land, and the only reason to run it is to find out what
-- landed, which a diff of two generated files cannot tell you because it is thousands of
-- lines of noise the moment upstream reorders anything. So the generator answers it while
-- it still holds both sides.
--
-- Every arrival is listed with the words that reach it beyond the ones in its own name,
-- because that is the part a person has to judge. An arrival with none of them is reachable
-- only through its official Unicode name, which is fine when that name holds a word anyone
-- would type, and useless when it does not, the command key being the standing example at
-- place of interest sign. The report cannot tell those two apart, so it states the fact and
-- leaves the call, which is also why adding a synonym stays a hand written table rather
-- than something inferred here. Departures are listed too, since a glyph the font stack
-- stopped drawing is the other thing worth knowing and it would otherwise vanish silently.
-- The lists are capped, and the cap says how many it did not print, so a large refresh
-- never reads as a small one.
local REPORT_CAP = 60

local function loadCommitted(path)
  local chunk = loadfile(path)
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

-- The words that reach an entry beyond the ones already in its display name. This is what
-- decides whether a new glyph is findable, since the name is what you would have to know
-- exactly in order to search for it.
local function extraWords(e)
  local inName = {}
  for w in (e.n or ""):lower():gmatch("%S+") do inName[w] = true end
  local seen, out = {}, {}
  for w in (e.k or ""):lower():gmatch("%S+") do
    if not inName[w] and not seen[w] then
      seen[w] = true
      out[#out + 1] = w
    end
  end
  return out
end

local function reportList(label, rows)
  if #rows == 0 then return end
  print(label .. " " .. #rows)
  for i = 1, math.min(REPORT_CAP, #rows) do print("  " .. rows[i]) end
  if #rows > REPORT_CAP then
    print("  and " .. (#rows - REPORT_CAP) .. " more not listed")
  end
end

local committed = loadCommitted(OUT)
if not committed then
  print("refresh diff: no committed dataset to compare against, everything is new")
else
  local was, is = {}, {}
  for _, e in ipairs(committed) do was[e.e] = e end
  for _, e in ipairs(kept) do is[e.e] = e end

  local added, gone = {}, {}
  for _, e in ipairs(kept) do
    if not was[e.e] then
      local extras = extraWords(e)
      local reach = #extras == 0 and "nothing but its name" or table.concat(extras, " ")
      added[#added + 1] = e.e .. "  " .. (e.n or "") .. "  [" .. reach .. "]"
    end
  end
  for _, e in ipairs(committed) do
    if not is[e.e] then
      gone[#gone + 1] = e.e .. "  " .. (e.n or "")
    end
  end

  if #added == 0 and #gone == 0 then
    print("refresh diff: no change, the same " .. #kept .. " glyphs")
  else
    print("refresh diff: " .. #added .. " added, " .. #gone .. " gone, " ..
      (#kept - #added) .. " unchanged")
    reportList("added, each with the words that reach it beyond its name", added)
    reportList("gone, no longer in the set", gone)
  end
end

-- Write the kept rows as a Lua table rather than as json. hs.json.decode is quadratic in
-- the number of objects in an array, measured at 3.0 seconds for this set against 6
-- milliseconds for the same rows as a Lua literal, and the picker pays that load on every
-- config reload rather than once. So the shape of the artifact is what fixes it, and the
-- reason json was chosen originally, that the generator would otherwise escape names into
-- Lua strings by hand, is answered by doing it here where Lua escapes its own strings.
--
-- %q escapes exactly what Lua needs to read the value back and leaves utf8 bytes alone, so
-- every glyph travels as itself. It escapes a newline as a backslash and a real line break
-- though, which would split a row across lines, so control characters are flattened to a
-- space first. No upstream name carries one, this only makes the one row per line promise
-- unconditional, and that promise is what keeps the committed file diffable.
local function q(s)
  return string.format("%q", (tostring(s or ""):gsub("%c", " ")))
end

local out = assert(io.open(OUT, "w"))
out:write("-- Generated by regenerate.sh, do not edit by hand. Rerun the generator instead.\n")
out:write("return {\n")
for _, e in ipairs(kept) do
  out:write(string.format("{e=%s,n=%s,a=%s,k=%s,t=%s},\n",
    q(e.e), q(e.n), q(e.a), q(e.k), q(e.t)))
end
out:write("}\n")
out:close()
