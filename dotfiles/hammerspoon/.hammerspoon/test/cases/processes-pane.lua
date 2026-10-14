-- Unit case for the processes detail pane's shape, plugins/processes/pane-nodes.lua. The runner
-- reaches this file with a dofile call carrying an absolute path, so it locates itself through
-- debug.getinfo and derives every module path from there.
--
-- The nodes file is pure, it only builds UI kit nodes, so it is driven with the real kit, style
-- and layout loaded as plain Lua and a stub measurer at seven points a character, and no canvas
-- is ever made. What preview.lua decides, the docking, the cache, the sampler's figures and the
-- paint, needs a canvas and is outside this case.

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
local ui = setmetatable({
  tokens = function() return tokens end,
  measure = stubMeasure,
  layout = function(node, rect, opts) return engine.layout(node, rect, tokens, opts) end,
}, { __index = kit })

local nodes = fresh("plugins/processes/pane-nodes.lua")
local code = tokens.text.code

local function textOf(el) return el.text and el.text.getString and el.text:getString() end

-- Every node of one kind under a node, depth first.
local function find(node, kind, out)
  out = out or {}
  if node.kind == kind then out[#out + 1] = node end
  for _, child in ipairs(node.children or {}) do find(child, kind, out) end
  return out
end

local function headingLabels(list)
  local labels = {}
  for i, node in ipairs(list) do
    local head = node.children[1]
    labels[i] = head.kind == "row" and head.children[1].str or head.str
  end
  return table.concat(labels, ",")
end

--------------------------------------------------------------------------------
-- the sections
--------------------------------------------------------------------------------

local server = { pid = 10, key = "k", ports = { 3000, 3001 }, cwd = "/srv/app", command = "node",
  commandFull = "node server.js --flag" }
local listed = nodes.sections(ui, server)
check("a server row has ports, directory and command, in that order",
  headingLabels(listed) == "PORTS,DIRECTORY,COMMAND", headingLabels(listed))
check("ports are joined by the subtitle's dot and drawn as wrapped code in the foreground",
  listed[1].children[2].str == ":3000 · :3001" and listed[1].children[2].variant == "code"
    and listed[1].children[2].wrap == true and listed[1].children[2].color == "foreground")
check("the directory is code in the path colour",
  listed[2].children[2].color == "path" and listed[2].children[2].variant == "code")
check("the command prefers the untruncated form",
  listed[3].children[2].str == "node server.js --flag")

local container = { key = "c", containerId = "0123456789abcdef", command = "postgres:16", ports = { 5432 } }
local boxed = nodes.sections(ui, container)
check("a container row is labelled IMAGE, not COMMAND, and gets no directory",
  headingLabels(boxed) == "PORTS,IMAGE,CONTAINER", headingLabels(boxed))
check("the container id is the short form in the subtext colour",
  boxed[3].children[2].str == "0123456789ab" and boxed[3].children[2].color == "subtext")

local watcher = { pid = 4, key = "w", cwd = "/srv/x", command = "tsc" }
check("a section with no text is dropped whole, heading included",
  headingLabels(nodes.sections(ui, watcher)) == "DIRECTORY,COMMAND")
check("a row with nothing to say has no sections", #nodes.sections(ui, { key = "z" }) == 0)
check("an empty command string drops its section", #nodes.sections(ui, { command = "" }) == 0)

local home = os.getenv("HOME") or ""
if home ~= "" then
  local homed = nodes.sections(ui, { cwd = home .. "/proj" })
  check("the home directory is shortened to a tilde", homed[1].children[2].str == "~/proj")
end

--------------------------------------------------------------------------------
-- headings
--------------------------------------------------------------------------------

local headed = nodes.tree(ui, { tree = { { pid = 1, label = "a" } } }, 400, 400)
local treeHead = headed.children[1]
check("the tree heading carries its facts flush right in subtext",
  treeHead.kind == "row" and treeHead.children[1].str == "TREE"
    and treeHead.children[2].str == "stops 1 process" and treeHead.children[2].color == "subtext"
    and treeHead.children[2].align == "right")
local plural = nodes.tree(ui, { tree = { { pid = 1, label = "a" }, { pid = 2, label = "b", depth = 1 } } }, 400, 400)
check("the tree facts are plural for more than one member",
  plural.children[1].children[2].str == "stops 2 processes")
check("a section heading with no facts is the label alone",
  listed[1].children[1].kind == "text" and listed[1].children[1].variant == "section")

--------------------------------------------------------------------------------
-- the tree
--------------------------------------------------------------------------------

local sample = {
  { pid = 100, depth = 0, label = "sh" },
  { pid = 20000, depth = 1, label = "npm" },
  { pid = 300, depth = 2, label = "node" },
  { pid = 400, depth = 1, label = "tail" },
}
local drawn = nodes.treeLines(sample, 5)
check("the tree lines carry the corner, the bar and a padded pid",
  drawn[1] == "100   sh" and drawn[2] == "   ├─ 20000 npm" and drawn[3] == "   │  └─ 300   node"
    and drawn[4] == "   └─ 400   tail", table.concat(drawn, "|"))
check("a root carries no bar past it",
  nodes.treeLines({ { pid = 1, label = "a" }, { pid = 2, label = "b" } }, 1)[2] == "2 b")
check("a long label is not cut by the builder, the code block cuts it",
  nodes.treeLines({ { pid = 1, label = string.rep("x", 400) } }, 1)[1] == "1 " .. string.rep("x", 400))

local members = {}
for i = 1, 10 do members[i] = { pid = i, depth = 0, label = "m" .. i } end
local lh, head = code.lineHeight, tokens.text.section.lineHeight
local room = 5 * lh
local availH = head + tokens.space.xs + room
local cut = nodes.tree(ui, { tree = members }, 400, availH)
local block = find(cut, "code")[1]
check("the code block is handed the room under the heading", block.maxHeight == room,
  tostring(block.maxHeight))
check("the closing line is worded as a count of what was left out",
  block.more(6) == "… 6 more")
local els, treeH = ui.layout(cut, { x = 0, y = 0, w = 400, h = availH })
check("a cut tree keeps room lines less one and then the closing line, inside the height",
  treeH <= availH and textOf(els[#els]) == "… 6 more", tostring(treeH) .. " " .. tostring(textOf(els[#els])))
local whole = nodes.tree(ui, { tree = members }, 400, availH + 20 * lh)
local _, wholeH = ui.layout(whole, { x = 0, y = 0, w = 400, h = 2000 })
check("a tree that fits is drawn whole with no closing line",
  wholeH == head + tokens.space.xs + 10 * lh, tostring(wholeH))
check("a tree with no room for one member is dropped whole, heading included",
  nodes.tree(ui, { tree = members }, 400, head + tokens.space.xs + lh - 1) == nil)
check("a tree with room for exactly one member is drawn",
  nodes.tree(ui, { tree = { members[1] } }, 400, head + tokens.space.xs + lh) ~= nil)
check("a row with no tree has no tree section", nodes.tree(ui, { tree = {} }, 400, 400) == nil)

--------------------------------------------------------------------------------
-- the static half
--------------------------------------------------------------------------------

check("a row with nothing to say has no static half", nodes.static(ui, { key = "z" }, 400, 400) == nil)
local staticRow = { pid = 1, key = "s", cwd = "/srv/app", command = string.rep("word ", 60),
  tree = members }
local staticNode = nodes.static(ui, staticRow, 280, 400)
local _, staticH = ui.layout(staticNode, { x = 0, y = 0, w = 280, h = 400 })
check("the tree takes the height the wrapped sections leave and the half never overflows",
  staticH <= 400 and #find(staticNode, "code") >= 1, tostring(staticH))
local sectionsOnly = ui.stack(nodes.sections(ui, staticRow), { gap = nodes.GAP })
local _, sectionsH = ui.layout(sectionsOnly, { x = 0, y = 0, w = 280, h = 400 })
local treeBlock = find(staticNode, "code")
treeBlock = treeBlock[#treeBlock]
check("the tree's room is measured from the sections' laid out height",
  treeBlock.maxHeight == 400 - sectionsH - tokens.space[nodes.GAP] - head - tokens.space.xs,
  tostring(treeBlock.maxHeight))
-- The sections alone fill most of this height, so the tree has nothing left and goes.
local shortNode = nodes.static(ui, staticRow, 280, sectionsH + tokens.space[nodes.GAP] + 10)
check("a pane too short for the tree drops it and keeps the sections",
  #find(shortNode, "code") == 0 and #shortNode.children == #nodes.sections(ui, staticRow))

--------------------------------------------------------------------------------
-- the live block
--------------------------------------------------------------------------------

local strip = { facts = "12.0%", values = { 1, 2, 3 }, lo = 0, hi = 5 }
local spec = { cpu = strip, mem = { facts = "", values = {}, lo = 0, hi = 0 } }
check("a row with no pid has no live block and reserves nothing",
  nodes.live(ui, { key = "c" }, spec) == nil and nodes.liveSpan(ui, { key = "c" }) == 0)
local live = nodes.live(ui, { pid = 1 }, spec)
local _, liveH = ui.layout(live, { x = 0, y = 0, w = 300, h = 400 })
check("the live span is the laid out block and the gap before the static half, derived",
  nodes.liveSpan(ui, { pid = 1 }) == liveH + tokens.space[nodes.GAP], tostring(liveH))
local _, emptyH = ui.layout(nodes.live(ui, { pid = 1 }, { cpu = { facts = "", values = {}, lo = 0, hi = 0 },
  mem = { facts = "9 MB", values = { 1 }, lo = 1, hi = 1 } }), { x = 0, y = 0, w = 300, h = 400 })
check("the live height does not depend on the readings", emptyH == liveH, tostring(emptyH))

local sparkEls = nodes.spark(ui, { 1, 2, 3 }, 0, 5, "note").draw({ x = 10, y = 100, w = 300, h = 23 }, tokens)
check("a strip is the baseline in the dim colour then the line in the named colour",
  #sparkEls == 2 and sparkEls[1].strokeColor == tokens.colors.dim
    and sparkEls[2].strokeColor == tokens.colors.note)
check("the baseline runs the full width at the bottom of the strip",
  sparkEls[1].coordinates[1].x == 10 and sparkEls[1].coordinates[2].x == 310
    and sparkEls[1].coordinates[1].y == 100 + nodes.SPARK_GAP + nodes.SPARK_H)
check("the newest sample sits at the right edge",
  sparkEls[2].coordinates[3].x == 310)
local lone = nodes.spark(ui, { 1 }, 0, 1, "note").draw({ x = 0, y = 0, w = 300, h = 23 }, tokens)
check("a trail of one sample draws only the baseline", #lone == 1)
local flat = nodes.spark(ui, { 3, 3 }, 3, 3, "subtext").draw({ x = 0, y = 0, w = 300, h = 23 }, tokens)
check("a collapsed range draws down the middle of the strip",
  flat[2].coordinates[1].y == nodes.SPARK_GAP + nodes.SPARK_H - 0.5 * (nodes.SPARK_H - 1))
