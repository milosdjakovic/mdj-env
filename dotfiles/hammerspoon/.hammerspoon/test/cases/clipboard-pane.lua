-- Unit case for the clipboard preview pane's shape, plugins/clipboard/manager/pane.lua. The
-- runner reaches this file with a dofile call carrying an absolute path, so it locates itself
-- through debug.getinfo and derives every module path from there.
--
-- The pane is pure, it only builds UI kit nodes, so it is driven with the real kit and style
-- loaded as plain Lua and a stub measurer at seven points a character, and no canvas is ever
-- made. What each kind of entry answers for its facts is checked as the tables the table in
-- ui.lua's KINDS builds, since ui.lua itself reaches for the canvas and the store.

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

local stubMeasure = {}
function stubMeasure:width(str) return #(str or "") * 7 end
function stubMeasure:wrap(str, _, _, maxW)
  local per = math.max(1, math.floor(maxW / 7))
  local lines = {}
  for i = 1, math.max(1, #str), per do lines[#lines + 1] = str:sub(i, i + per - 1) end
  return lines
end

local styleLib = fresh("lib/ui/style.lua")
local style = styleLib.new({ appearance = function() return "Dark" end })
-- theme-exempt, fixture colours for a unit case, not a tool's look
style.configure({ colors = { dark = { foreground = { white = 0.92 }, subtext = { white = 0.55 },
  background = "#29292e", border = "#59575C" } } })
local tokens = style.tokens()
local kit = fresh("lib/ui/kit.lua").new(styleLib.names)
local engine = fresh("lib/ui/layout.lua").new({ measure = stubMeasure })

-- The kit as a plugin receives it, the primitives plus the tokens.
local ui = setmetatable({ tokens = function() return tokens end }, { __index = kit })

local pane = fresh("plugins/clipboard/manager/pane.lua")
local GAP = "   "

--------------------------------------------------------------------------------
-- the facts, one case per kind in the table
--------------------------------------------------------------------------------

check("text, kind then chars then time then the batch mark, upper cased as a whole",
  pane.factsText({ kind = "Text", details = { "1234 chars" }, time = "2m ago",
    marks = { "#2 Appended" } })
    == table.concat({ "TEXT", "1234 CHARS", "2M AGO", "#2 APPENDED" }, GAP))
check("url has no details", pane.factsText({ kind = "URL", details = {}, time = "now", marks = {} })
  == "URL" .. GAP .. "NOW")
check("a colour is kind and time", pane.factsText({ kind = "Color", time = "1h ago" })
  == "COLOR" .. GAP .. "1H AGO")
check("an image is kind, dimensions, size, time",
  pane.factsText({ kind = "Image", details = { "640x480", "12 KB" }, time = "3d ago" })
    == table.concat({ "IMAGE", "640X480", "12 KB", "3D AGO" }, GAP))
check("one file is kind, size, time, then the badge before the batch mark",
  pane.factsText({ kind = "File", details = { "4 KB" }, time = "5m ago",
    marks = { "Linked", "#1 Appended" } })
    == table.concat({ "FILE", "4 KB", "5M AGO", "LINKED", "#1 APPENDED" }, GAP))
check("several files add the item count before the size",
  pane.factsText({ kind = "File", details = { "3 items", "9 KB" }, time = "5m ago", marks = {} })
    == table.concat({ "FILE", "3 ITEMS", "9 KB", "5M AGO" }, GAP))
check("a manage history row is its meta line alone, no time and no marks",
  pane.factsText({ kind = "Older than 4d", details = { "12 of 80" }, marks = {} })
    == "OLDER THAN 4D" .. GAP .. "12 OF 80")
check("an absent part is left out, never an empty gap",
  pane.factsText({ kind = "Text", details = {}, time = nil, marks = {} }) == "TEXT")

--------------------------------------------------------------------------------
-- the header
--------------------------------------------------------------------------------

local icon = {}
local withSource = pane.header(ui, { source = { icon = icon, name = "Safari" }, kind = "Text",
  details = { "5 chars" }, time = "now", marks = {} })
local factsNode = withSource.children[2]
local sourceNode = withSource.children[1]
check("the header is one row, the source first and the facts second, the source filling",
  withSource.kind == "row" and #withSource.children == 2 and withSource.fillIndex == 1
    and factsNode.kind == "text")
check("the facts are caption in subtext, flush right and upper cased",
  factsNode.variant == "caption" and factsNode.color == "subtext" and factsNode.align == "right"
    and factsNode.str == "TEXT" .. GAP .. "5 CHARS" .. GAP .. "NOW", factsNode.str)
check("the source is an icon then the name in caption and the foreground colour",
  sourceNode.kind == "row" and sourceNode.children[1].kind == "raw"
    and sourceNode.children[2].variant == "caption" and sourceNode.children[2].color == "foreground"
    and sourceNode.children[2].str == "Safari")
check("the icon is a square the height of a caption line",
  sourceNode.children[1].height == tokens.text.caption.lineHeight
    and sourceNode.children[1].width == tokens.text.caption.lineHeight)
local drawn = sourceNode.children[1].draw({ x = 4, y = 6, w = 19, h = 19 }, tokens)
check("the icon draws as one image element in its rect",
  #drawn == 1 and drawn[1].type == "image" and rawequal(drawn[1].image, icon)
    and drawn[1].frame.x == 4 and drawn[1].frame.y == 6)

do
  local longName = string.rep("n", 60)
  local header = pane.header(ui, { source = { name = longName }, kind = "Text", details = {},
    time = "now", marks = {} })
  local els = engine.layout(header, { x = 10, y = 0, w = 300, h = 50 }, tokens)
  local factsW = #"TEXT   NOW" * 7
  check("a long name is cut to what the facts leave and the facts keep their whole width",
    els[1].frame.w == 300 - 10 - factsW and els[2].frame.w == factsW,
    els[1].frame.w .. ", " .. els[2].frame.w .. ", wanted facts " .. factsW)
  check("the facts end at the right edge of the row", els[2].frame.x + els[2].frame.w == 310,
    tostring(els[2].frame.x + els[2].frame.w))
end

do
  local bare = pane.header(ui, { kind = "Everything", details = { "3 items" }, marks = {} })
  local els = engine.layout(bare, { x = 0, y = 0, w = 300, h = 50 }, tokens)
  check("with no source only the facts are drawn, in a slot the whole width",
    #bare.children == 1 and #els == 1 and els[1].frame.w == 300 and els[1].frame.x == 0)
end

--------------------------------------------------------------------------------
-- the blocks
--------------------------------------------------------------------------------

local text = pane.text(ui, "copied")
check("a text block is the code role and wraps", text.kind == "text" and text.variant == "code"
  and text.wrap == true and text.color == nil)
local paths = pane.paths(ui, { "/a/b", "/c/d" })
check("paths are one code text each in the path colour, wrapping",
  paths.kind == "stack" and #paths.children == 2 and paths.children[1].variant == "code"
    and paths.children[1].color == "path" and paths.children[1].wrap == true
    and paths.children[2].str == "/c/d")
local note = pane.note(ui, "Loading…")
check("a note is caption in subtext", note.variant == "caption" and note.color == "subtext"
  and note.str == "Loading…")
local img = { size = function() return { w = 100, h = 50 } end }
local imageNode = pane.image(ui, img)
check("an image block is the kit's image node, which may scale up",
  imageNode.kind == "image" and imageNode.upscale == true)
local imageEls, imageH = engine.layout(imageNode, { x = 3, y = 9, w = 200, h = 100 }, tokens)
check("the image is as tall as its aspect at that width, kept top left, scaled proportionally",
  imageH == 100 and imageEls[1].imageAlignment == "topLeft"
    and imageEls[1].imageScaling == "scaleProportionally"
    and imageEls[1].frame.x == 3 and imageEls[1].frame.y == 9 and imageEls[1].frame.w == 200)
local opaque = pane.swatch(ui, { red = 1, green = 0, blue = 0, alpha = 1 }, 100, 60).draw(
  { x = 0, y = 0, w = 100, h = 60 }, tokens)
local clear = pane.swatch(ui, { red = 1, green = 0, blue = 0, alpha = 0.5 }, 100, 60).draw(
  { x = 0, y = 0, w = 100, h = 60 }, tokens)
check("an opaque swatch is one fill and a translucent one has the checker under it",
  #opaque == 1 and #clear > 1 and clear[#clear].fillColor.alpha == 0.5)

--------------------------------------------------------------------------------
-- compose
--------------------------------------------------------------------------------

do
  local composed = pane.compose(ui, { kind = "Text", marks = {} }, { text, note })
  check("compose is a stack with the header first and then every block",
    composed.kind == "stack" and #composed.children == 3 and composed.children[1].kind == "row"
      and composed.children[2] == text and composed.children[3] == note)
  check("compose has one gap, a name of the kit's space scale",
    composed.gap == pane.GAP and tokens.space[pane.GAP] ~= nil)
  local _, height = engine.layout(composed, { x = 0, y = 0, w = 300, h = 400 }, tokens)
  local want = tokens.text.caption.lineHeight + tokens.text.code.lineHeight
    + tokens.text.caption.lineHeight + 2 * tokens.space[pane.GAP]
  check("the laid out height is the three blocks and two gaps", height == want,
    tostring(height) .. ", wanted " .. want)
end

--------------------------------------------------------------------------------
-- the manage history page answers the pane's facts, not a joined line
--------------------------------------------------------------------------------

do
  local prune = fresh("plugins/clipboard/manager/prune.lua")
  local now = os.time()
  local entries = {
    { title = "fresh", ts = now - 60 },
    { title = "old one", ts = now - 7200 },
    { title = "older", ts = now - 90000 },
  }
  prune.configure({ store = { all = function() return entries end } })

  local last, body = prune.preview({ side = "last", span = "1 hour", secs = 3600 })
  check("a span slice answers a kind and a details list, and a body string",
    last.kind == "Last 1 hour" and #last.details == 1 and last.details[1] == "1 of 3"
      and type(body) == "string" and last.time == nil and last.source == nil)
  local all = prune.preview({ side = "all" })
  check("everything names the item count as its one detail",
    all.kind == "Everything" and all.details[1] == "3 items")
  local newest = prune.preview({ side = "newest", count = 2 })
  check("a count slice keeps the count in the kind and the share in the details",
    newest.kind == "The newest 2" and newest.details[1] == "2 of 3")
  check("a hint row has nothing to say", prune.preview({ side = "hint" }) == nil)
  check("the facts feed the header as they are, upper cased as a whole",
    pane.factsText({ kind = last.kind, details = last.details, marks = {} })
      == "LAST 1 HOUR" .. GAP .. "1 OF 3")
end
