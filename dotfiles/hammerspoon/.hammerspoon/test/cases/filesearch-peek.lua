-- Unit case for the file search preview pane's reads, sources/index.lua's parsePeek and the row
-- handling in viewers/sidepanel.lua. A read belongs to the helper so a slow file can never hold up
-- a key, so this drives the viewer over a fake helper and a fake pane, answers by hand, and pins
-- that nothing paints before an answer, that a row left behind is cancelled, and that an answer
-- arriving late paints nothing. The helper's own bytes are pinned through parsePeek, which reads
-- what fileindex peek writes.

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

--------------------------------------------------------------------------------
-- what the helper writes
--------------------------------------------------------------------------------

local parse = fresh("plugins/filesearch/sources/index.lua").parsePeek

local file = parse("file\t5\t100\t90\na\255\254b\n")
check("a file answers its facts", file.attrs.mode == "file" and file.attrs.size == 5
  and file.attrs.modification == 100 and file.attrs.creation == 90)
check("a head keeps bytes that are not text", file.blob == "a\255\254b\n")

local gone = parse("missing\n")
check("a path that is gone answers no facts", gone ~= nil and gone.attrs == nil)

local folder = parse("dir\t160\t100\t90\n3\t1\n50\td\tsub\n40\t-\tone\n")
check("a folder answers its count and whether it was cut",
  folder.folder.scanned == 3 and folder.folder.truncated == true)
check("a folder's entries keep the helper's order, a folder marked",
  folder.folder.entries[1].name == "sub/" and folder.folder.entries[2].name == "one")

local closed = parse("dir\t64\t100\t90\n")
check("a folder that could not be opened answers no listing",
  closed.attrs ~= nil and closed.folder == nil)
check("an answer of no recognisable shape is nil", parse("nonsense") == nil and parse(nil) == nil)

--------------------------------------------------------------------------------
-- the viewer over a fake helper
--------------------------------------------------------------------------------

local stubMeasure = fresh("lib/ui/measure.lua").new()
function stubMeasure:width(str) return #(str or "") * 7 end
local styleLib = fresh("lib/ui/style.lua")
local style = styleLib.new({ appearance = function() return "Dark" end })
-- theme-exempt, fixture colours for a unit case, not a tool's look
style.configure({ colors = { dark = { foreground = { white = 0.92 }, subtext = { white = 0.55 },
  background = "#29292e", border = "#59575C" } } })
local tokens = style.tokens()
local kit = fresh("lib/ui/kit.lua").new(styleLib.names)

local bodies = 0
local ui = setmetatable({
  tokens = function() return tokens end,
  measure = stubMeasure,
  -- The header is laid out with the clip option and only a body with a scroll offset.
  layout = function(_, _, opts)
    if opts and opts.scrollY then bodies = bodies + 1 end
    return {}, 10
  end,
}, { __index = kit })

local BOX = { x = 0, y = 0, w = 300, h = 400 }
local draws, keeps = 0, {}
local fakePane = {
  isEnabled = function() return true end,
  inner = function() return BOX end,
  draw = function(paint, opts)
    draws = draws + 1
    keeps[#keeps + 1] = opts.keepScroll
    paint({ inner = BOX, viewport = BOX, scrollY = 0 })
  end,
  clear = function() end, hide = function() end, destroy = function() end,
  dock = function() end, repaint = function() end, scrollBy = function() end,
}

local asks, cancels = {}, 0
local function fakePeek(path, bounds, cb)
  local ask = { path = path, bounds = bounds, answer = cb }
  asks[#asks + 1] = ask
  return { cancel = function() cancels = cancels + 1 end }
end

local viewer = fresh("plugins/filesearch/viewers/sidepanel.lua")
viewer.configure({ previewPane = function() return fakePane end, ui = ui, peek = fakePeek,
  limits = { readCap = 1000, folderEntries = 7 } })

local function row(name, isDir)
  return { path = "/x/" .. name, name = name, dir = "/x", ext = isDir and "" or "txt",
    isDir = isDir == true }
end
local TEXT = { attrs = { mode = "file", size = 6 }, blob = "hello\n" }

viewer.show(row("a"))
check("a row asks the helper, and nothing paints before it answers", #asks == 1 and draws == 0)
check("the helper is told the configured bounds", asks[1].bounds.readCap == 1000
  and asks[1].bounds.entries == 7 and asks[1].bounds.scanCap > 0)

viewer.show(row("a"))
check("a second show of the row being read asks nothing more", #asks == 1 and cancels == 0)

viewer.show(row("b"))
check("a newer row cancels the read in flight", #asks == 2 and cancels == 1)
asks[1].answer(TEXT)
check("an answer for a row left behind paints nothing", draws == 0)

asks[2].answer(TEXT)
check("the newest answer paints, from the top of the body", draws == 1 and keeps[1] == false
  and bodies == 1)

viewer.show(row("b"))
check("a row already described asks nothing and keeps its scroll", #asks == 2 and draws == 2
  and keeps[2] == true)

viewer.show(row("c"))
asks[3].answer({ attrs = { mode = "file", size = 8 }, blob = "a\0b\n" })
check("a binary head is described by its header alone", draws == 3 and bodies == 2,
  tostring(bodies))

viewer.show(row("d", true))
asks[4].answer({ attrs = { mode = "directory" }, folder = { scanned = 1, truncated = false,
  entries = { { name = "one", at = 1 } } } })
check("a folder's listing is the body", draws == 4 and bodies == 3, tostring(bodies))

viewer.show(row("e"))
asks[5].answer(nil)
check("no answer at all still describes the row by its header", draws == 5 and bodies == 3)

local before = cancels
viewer.show(row("f"))
viewer.clear()
check("clearing the pane cancels the read", cancels == before + 1)
asks[6].answer(TEXT)
check("an answer after a clear paints nothing", draws == 5)

before = cancels
viewer.show(row("g"))
viewer.hide()
check("hiding the pane cancels the read", cancels == before + 1)

before = cancels
viewer.show(row("h"))
viewer.destroy()
check("closing the pane cancels the read", cancels == before + 1)
