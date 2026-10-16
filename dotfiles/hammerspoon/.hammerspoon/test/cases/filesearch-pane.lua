-- Unit case for the file search side pane's shape, plugins/filesearch/viewers/sidepanel-nodes.lua.
-- The runner reaches this file with a dofile call carrying an absolute path, so it locates
-- itself through debug.getinfo and derives every module path from there.
--
-- The nodes file is pure, it only builds UI kit nodes, so it is driven with the real kit and
-- style loaded as plain Lua and a stub measurer at seven points a character, and no canvas is
-- ever made. What sidepanel.lua decides, the stat, the chain of describers and the thumbnails,
-- needs the file system and is outside this case, and the canvas is the shared docked pane's,
-- which test/cases/dockedpane.lua covers.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(path)
  local chunk, err = loadfile(olm .. path)
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

-- The real measurer with its width stubbed at seven points a character, so the kit's own wrap
-- runs and every break is arithmetic.
local stubMeasure = fresh("lib/ui/measure.lua").new()
function stubMeasure:width(str) return #(str or "") * 7 end

local styleLib = fresh("lib/ui/style.lua")
local style = styleLib.new({ appearance = function() return "Dark" end })
-- theme-exempt, fixture colours for a unit case, not a tool's look
style.configure({ colors = { dark = { foreground = { white = 0.92 }, subtext = { white = 0.55 },
  background = "#29292e", border = "#59575C" } } })
local tokens = style.tokens()
local kit = fresh("lib/ui/kit.lua").new(styleLib.names)
local engine = fresh("lib/ui/layout.lua").new({ measure = stubMeasure })
local ui = setmetatable({ tokens = function() return tokens end, measure = stubMeasure },
  { __index = kit })

local nodes = fresh("plugins/filesearch/viewers/sidepanel-nodes.lua")
local code = tokens.text.code

--------------------------------------------------------------------------------
-- wrapping a source line
--------------------------------------------------------------------------------

local function wrap(line, w) return stubMeasure:wrap(line, code.font, code.size, w) end

check("a line that fits is answered whole", #wrap("short line", 100) == 1 and wrap("short line", 100)[1] == "short line")
check("an empty line stays one empty line", #wrap("", 70) == 1 and wrap("", 70)[1] == "")
local broken = wrap("alpha beta gamma delta", 70)
local fits = #broken >= 2
for _, l in ipairs(broken) do if #l * 7 > 70 then fits = false end end
check("a line breaks at a space so no line is wider than the width", fits, table.concat(broken, "|"))
local indented = wrap("        local x = 1", 105)
check("leading indentation is kept on the first line", indented[1]:sub(1, 8) == "        ",
  indented[1])
local long = wrap(string.rep("x", 25), 70)
check("a word wider than the line breaks by character",
  #long == 3 and #long[1] == 10 and #long[3] == 5, tostring(#long))
local rejoined = table.concat(wrap("one  two   three four", 63), "")
check("no word is lost or split by a break between words",
  rejoined:gsub(" ", "") == "onetwothreefour", rejoined)

--------------------------------------------------------------------------------
-- the budget, counted in drawn lines
--------------------------------------------------------------------------------

local drawn = nodes.wrapBlock(ui, { "a\tb", string.rep("y", 30) }, 70)
check("a block is wrapped into drawn lines with tabs expanded first",
  drawn[1] == "a   b" and #drawn == 4, table.concat(drawn, "|"))

local function textLines(node)
  -- The code node nested under the heading, however deep the stacks put it.
  local found
  local function walk(n)
    if n.kind == "code" then found = n end
    for _, child in ipairs(n.children or {}) do walk(child) end
  end
  walk(node)
  return found and found.lines
end

local many = {}
for i = 1, 30 do many[i] = "line " .. i end
local trimmed = nodes.body(ui, { label = "HEAD", lines = many, wrap = true, budget = 10, slack = 5,
  total = 1000, hasLines = true }, 700)
local trimmedLines = textLines(trimmed)
check("past the budget and the slack the head is cut and ends in an ellipsis line",
  #trimmedLines == 11 and trimmedLines[10] == "line 10" and trimmedLines[11] == "...")
local heading = trimmed.children[1]
check("the heading says how many lines were kept",
  heading.kind == "row" and heading.children[2].str == "first 10 lines"
    and heading.children[2].color == "subtext")
local noteNode = trimmed.children[2].children[2]
check("the remainder note is caption in subtext under the block, worded as before",
  noteNode.variant == "caption" and noteNode.color == "subtext"
    and noteNode.str:match("^20 lines, %d+ characters more$") ~= nil, tostring(noteNode.str))
local within = nodes.body(ui, { label = "HEAD", lines = many, wrap = true, budget = 26, slack = 5 }, 700)
check("within the slack the file is shown whole and says nothing",
  #textLines(within) == 30 and within.children[1].kind == "text")
check("a note with no characters or lines to report is no note",
  nodes.remainderNote(0, 100, 100, true) == nil and nodes.remainderNote(0, 10, 100, false)
    == "90 characters more")

local empty = nodes.body(ui, { label = "HEAD", facts = "empty file", lines = {} }, 700)
check("an empty file keeps its heading facts and draws no block",
  empty.kind == "row" and empty.children[2].str == "empty file")
local folder = nodes.body(ui, { label = "FOLDER", facts = "3 items", lines = { "a/", "b" }, wrap = false }, 700)
check("a folder listing is a code block and is never wrapped",
  textLines(folder)[1] == "a/" and #textLines(folder) == 2)

--------------------------------------------------------------------------------
-- the image body and the header
--------------------------------------------------------------------------------

local img = { size = function() return { w = 40, h = 20 } end }
local picture = nodes.body(ui, { label = "PREVIEW", image = img }, 700)
check("an image body is a heading over an image that is never blown up",
  picture.children[2].kind == "image" and picture.children[2].upscale == false)
local _, imageH = engine.layout(picture, { x = 0, y = 0, w = 300, h = 400 }, tokens)
check("a small icon keeps its own height under the heading",
  imageH == tokens.text.section.lineHeight + tokens.space.xs + 20, tostring(imageH))

local header = nodes.header(ui, "main.lua", "~/src", {
  { label = "KIND", value = "LUA" }, { label = "USED", value = "2d ago", color = "primary" } })
local identity = header.children[1]
check("the name is title in the foreground and the folder is code in subtext, wrapping",
  identity.children[1].variant == "title" and identity.children[1].color == "foreground"
    and identity.children[2].variant == "code" and identity.children[2].color == "subtext"
    and identity.children[2].wrap == true)
local pair = header.children[2].children[2]
check("a fact is a row with the label left in subtext and the value flush right",
  pair.kind == "row" and pair.fillIndex == 2 and pair.children[1].str == "USED"
    and pair.children[1].color == "subtext" and pair.children[1].variant == "caption"
    and pair.children[2].align == "right" and pair.children[2].color == "primary")
check("a fact's value is the foreground unless it names another colour",
  header.children[2].children[1].children[2].color == "foreground")
local bare = nodes.header(ui, "x", "", { { label = "KIND", value = "File" } })
check("a row with no folder worth showing draws the name alone", #bare.children[1].children == 1)
