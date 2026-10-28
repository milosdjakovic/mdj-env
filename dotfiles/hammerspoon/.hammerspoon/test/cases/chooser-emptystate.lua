-- Unit case for the empty state of the default chooser's row list, drawn by
-- Spoons/Olm.spoon/lib/chooser/providers/default/list/render.lua when a typed query leaves no
-- rows. The provider hands render the shared CanvasPanel.emptyStateElements as style.emptyState
-- and the query it ranked with, and render alone decides whether the band shows it, so this case
-- drives render with a stand in for that routine and reads what comes back. Loaded the way
-- cases/canvaslist.lua loads it, through debug.getinfo, with no absolute path written down.
--
-- render.lua asks hs.styledtext for font metrics. Run through the units runner that is the real
-- one, and run under plain lua a stand in answers it, so the case reads the same either way.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone.

if not hs then
  hs = { styledtext = { fontInfo = function(f) return { ascender = f.size, descender = 0, capHeight = f.size * 0.7 } end } }
end

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local listDir = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/default/list/"

local modelChunk, modelErr = loadfile(listDir .. "model.lua")
if not modelChunk then
  print("FAIL load Olm.spoon canvas list model.lua, " .. tostring(modelErr))
  return
end
local model = modelChunk()

local renderChunk, renderErr = loadfile(listDir .. "render.lua")
if not renderChunk then
  print("FAIL load Olm.spoon canvas list render.lua, " .. tostring(renderErr))
  return
end
local render = renderChunk()

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local FONT = ".AppleSystemUIFont"
local ROW_H = 47
local LAYOUT = {
  font = FONT, textSize = 16, textLine = 22,
  subFont = FONT, subSize = 14, subLine = 19,
  numFont = FONT, numSize = 16,
  rowH = ROW_H, rowCount = 9, padBottom = 14,
}
local RECT = { x = 14, y = 57, w = 452, h = 9 * ROW_H + 14 }

-- The stand in for CanvasPanel.emptyStateElements, one text at the origin like the real one,
-- remembering the box it was asked to fill.
local asked
local style = {
  emptyState = function(w, h)
    asked = { w = w, h = h }
    return { { type = "text", text = "No results", frame = { x = 0, y = h / 2 - 19, w = w, h = 19 } } }
  end,
}

local function emptyText(els)
  for _, el in ipairs(els) do
    if el.type == "text" and el.text == "No results" then return el end
  end
end

local none = model.newState({}, LAYOUT, "")
local some = model.newState({ { title = "Safari" }, { title = "Mail" } }, LAYOUT, "")

-- The predicate, on its own.
check("a typed query with no rows shows the empty state", render.showsEmptyState(none, "zzz"))
check("an empty query with no rows does not", not render.showsEmptyState(none, ""))
check("no query at all does not", not render.showsEmptyState(none, nil))
check("a typed query with rows does not", not render.showsEmptyState(some, "sa"))

-- What is drawn.
do
  asked = nil
  local els = render.elements(none, RECT, LAYOUT, style, nil, "zzz")
  local el = emptyText(els)
  check("the empty state is drawn for a typed query with no rows", el ~= nil)
  check("it fills the band the rows would have filled", asked and asked.w == RECT.w
    and asked.h == render.bandHeight(LAYOUT),
    asked and (asked.w .. " x " .. asked.h) or "never asked")
  check("it is placed inside the band", el and el.frame.x == RECT.x
    and el.frame.y > RECT.y and el.frame.y < RECT.y + RECT.h)
  check("the band keeps room for at least one row", render.bandHeight(LAYOUT) >= ROW_H)
  check("no highlight is drawn under it", (function()
    for _, e in ipairs(els) do
      if e.type == "rectangle" and e.action == "fill" then return false end
    end
    return true
  end)())
  check("the clip is still closed after it", els[#els].type == "resetClip")
end

do
  asked = nil
  local els = render.elements(none, RECT, LAYOUT, style, nil, "")
  check("nothing is drawn for an empty query with no rows", emptyText(els) == nil and asked == nil)
end

do
  asked = nil
  local els = render.elements(some, RECT, LAYOUT, style, nil, "sa")
  check("nothing is drawn while rows are showing", emptyText(els) == nil and asked == nil)
end

do
  local els = render.elements(none, RECT, LAYOUT, {}, nil, "zzz")
  check("a caller with no empty state routine draws nothing there", emptyText(els) == nil)
end

-- A one row list, the smallest a presentation may declare, still has room for the message.
do
  local one = { font = FONT, textSize = 16, textLine = 22, subFont = FONT, subSize = 14,
    subLine = 19, numFont = FONT, numSize = 16, rowH = ROW_H, rowCount = 1, padBottom = 14 }
  asked = nil
  render.elements(model.newState({}, one, ""), RECT, one, style, nil, "zzz")
  check("a one row list hands the empty state a whole row of room",
    asked and asked.h >= ROW_H, asked and tostring(asked.h) or "never asked")
end

-- Zero rows still answer no highlighted row and no visible slot, so Return, a digit and a click
-- reach nothing, exactly as before the empty state.
check("no row is highlighted under the empty state", model.highlightedRow(none) == nil)
check("no visible slot answers under the empty state", model.rowAtVisibleSlot(none, 1) == nil)
check("no point in the band answers a row", model.rowAtPoint(none, ROW_H / 2) == nil)

-- The provider's own bookkeeping of which query the rows were ranked for, which is what render
-- reads to decide the empty state. It needs the real UI kit, so it runs only inside Hammerspoon,
-- the way cases/stage-holdkey.lua builds the same provider, with show replaced so nothing is ever
-- drawn and the rects left unset so the provider's own redraw stays a no op.
if hs.canvas then
  local olmDir = caseDir .. "/../../Spoons/Olm.spoon/"
  local Chooser = loadfile(olmDir .. "lib/chooser/init.lua")()
  local Default = Chooser.providers.default
  Default.configure({ panel = {}, ui = loadfile(olmDir .. "lib/ui/init.lua")() })

  local source = {}
  local inst = Default.new({ matcher = false, rows = function() return source end })
  function inst:show()
    self.active = true
    self._rects = { rowCount = 10 }
    self:_updateDrawLayout()
    self._rects = nil
    self:_rebuildList("", true)
    self._suppressRebuild = true
    self.view:setText("")
    self._suppressRebuild = false
  end

  local function empty() return render.showsEmptyState(inst.listState, inst._rankedQuery) end

  inst:show()
  check("show ranks for the empty query", inst._rankedQuery == "")
  check("show with no rows draws no empty state", not empty())

  inst:setQuery("zzz")
  check("setQuery records the query it ranked for", inst._rankedQuery == "zzz",
    tostring(inst._rankedQuery))
  check("a typed query with no rows draws the empty state after setQuery", empty())

  -- Rows arrive after the query was typed, as a slow source's do, and a refresh ranks them for
  -- the field's current text.
  source = { { title = "Zzz row", item = { id = "z" } } }
  inst:refresh(true)
  check("refresh ranks for the field's current query", inst._rankedQuery == "zzz",
    tostring(inst._rankedQuery))
  check("rows that arrive clear the empty state on refresh", not empty())

  -- The field runs ahead of the rows for the length of a setQuery, its text already new and its
  -- rows not yet rebuilt. The empty state must still answer for the rows on screen, which were
  -- ranked for the old text and exist, so reading the field instead would flash No results.
  inst._suppressRebuild = true
  inst.view:setText("zzzq")
  inst._suppressRebuild = false
  check("a field ahead of the rows leaves the ranked query where it was",
    inst._rankedQuery == "zzz", tostring(inst._rankedQuery))
  check("so no empty state shows for rows that are about to be replaced", not empty())
  check("while the field's own text would have said there is nothing",
    render.showsEmptyState(model.newState({}, LAYOUT, ""), inst:query()))

  -- The rebuild that catches the rows up records the new query and tells the truth.
  source = {}
  inst:refresh(true)
  check("the catch up rebuild ranks for the new text", inst._rankedQuery == "zzzq",
    tostring(inst._rankedQuery))
  check("and with no rows left it draws the empty state", empty())

  inst:setQuery("")
  check("clearing the field with rows gone draws nothing", not empty() and inst._rankedQuery == "")
  inst.active = false
end
