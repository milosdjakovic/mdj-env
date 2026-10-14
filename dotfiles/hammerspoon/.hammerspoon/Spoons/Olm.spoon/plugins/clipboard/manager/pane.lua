-- What the clipboard preview pane looks like, as UI kit nodes and nothing else. It holds no
-- canvas, no store, no async and no entry, only the shape of a header and of each kind of
-- block, so ui.lua can pick which blocks an entry has and compose them without knowing how
-- any of them is drawn. The kit arrives as the first argument of every function, since the
-- pane never loads it, which also lets the unit case drive this file with a bare kit and no
-- hs. Nothing here names a font, a size, a line height or a colour literal, every piece of
-- text is one of the kit's roles and every colour a role name.

local M = {}

-- The one gap between the header and the blocks, and between the blocks, for every kind.
-- A name of the kit's space scale, exposed so ui.lua can read its points for the swatch.
M.GAP = "m"

-- The facts separator, a plain gap rather than a dot, so the line reads as two calm anchors.
local FACTS_GAP = "   "

--- M.factsText(facts) -> string, the facts in their fixed order, kind then details then time
--- then marks, upper cased as a whole and joined by FACTS_GAP. A part that is nil or empty is
--- left out. facts is { source, kind, details, time, marks }, and source is the header's own.
function M.factsText(facts)
  local parts = {}
  local function add(value)
    if value ~= nil and value ~= "" then parts[#parts + 1] = tostring(value) end
  end
  add(facts.kind)
  for _, detail in ipairs(facts.details or {}) do add(detail) end
  add(facts.time)
  for _, mark in ipairs(facts.marks or {}) do add(mark) end
  return table.concat(parts, FACTS_GAP):upper()
end

--- M.header(ui, facts) -> node, one line for every kind. The source, the app icon and then
--- its name, sits at the left in the foreground colour and gives way first, its name cut
--- with an ellipsis. The facts sit flush right in the subtext colour and are never cut, which
--- is what the row's fillIndex is for, since the facts keep their natural width and the
--- source takes what is left. facts.source is { icon = hs.image or nil, name = string or nil },
--- and without one only the facts are drawn.
function M.header(ui, facts)
  local factsNode = ui.text(M.factsText(facts), "caption", { color = "subtext", align = "right" })
  local source = facts.source
  local left = {}
  if source and source.icon then
    -- No icon token is the height of a caption line, so the image is drawn into a raw node
    -- of exactly that height and width, a square the size of the text beside it.
    local side = ui.tokens().text.caption.lineHeight
    local icon = source.icon
    left[#left + 1] = ui.raw(side, function(rect)
      return { { type = "image", image = icon, imageScaling = "scaleProportionally",
        imageAlignment = "center", frame = { x = rect.x, y = rect.y, w = side, h = side } } }
    end, { width = side })
  end
  if source and source.name then
    left[#left + 1] = ui.text(source.name, "caption", { color = "foreground" })
  end
  if #left == 0 then
    return ui.row({ factsNode }, { align = "center" })
  end
  local sourceNode = #left == 1 and left[1] or ui.row(left, { gap = "s", align = "center" })
  return ui.row({ sourceNode, factsNode }, { gap = M.GAP, align = "center", fillIndex = 1 })
end

--- M.text(ui, str) -> node, copied text, a url, a file head, the three forms of a colour. The
--- code role since a person would copy it, wrapped at the pane width since copied prose is
--- one long line and the code block would cut it at the edge.
function M.text(ui, str)
  return ui.text(str, "code", { wrap = true })
end

--- M.paths(ui, list) -> node, one path per line in the path colour, list an array of strings.
function M.paths(ui, list)
  local lines = {}
  for i, path in ipairs(list) do
    lines[i] = ui.text(path, "code", { wrap = true, color = "path" })
  end
  return ui.stack(lines, { gap = "xs" })
end

--- M.note(ui, str) -> node, a short line saying why there is nothing more to show. Every note
--- looks the same, caption in subtext.
function M.note(ui, str)
  return ui.text(str, "caption", { color = "subtext" })
end

--- M.image(ui, img) -> node, the image scaled to the pane width, its height following its own
--- aspect, kept top left. The preview png is already small so nothing is resized here, and it
--- may scale up, since a clipboard image is shown as wide as the pane.
function M.image(ui, img)
  return ui.image(img)
end

-- The two greys of the checkerboard behind a translucent swatch. They are the one colour
-- literal the pane keeps, a neutral light and dark pair that has to read as a checker on
-- either half of the system, so no theme role fits and none is asked to. This is the checker
-- every image editor draws, not a tool's look.
local CHECKER_LIGHT = { white = 0.92, alpha = 1 }
local CHECKER_DARK = { white = 0.72, alpha = 1 }

-- A checkerboard behind a translucent swatch, so alpha reads against it instead of blending
-- invisibly into the panel. The cell scales with the swatch so the grid stays about eight
-- cells wide at any size, a fixed handful of rectangles.
local function checkerElements(x0, y0, w, h)
  local els = {}
  local cell = math.max(8, math.floor(math.min(w, h) / 8))
  els[1] = { type = "rectangle", action = "fill", fillColor = CHECKER_LIGHT,
    frame = { x = x0, y = y0, w = w, h = h } }
  local rowIdx, yy = 0, y0
  while yy < y0 + h do
    local ch = math.min(cell, y0 + h - yy)
    local colIdx, xx = 0, x0
    while xx < x0 + w do
      local cw = math.min(cell, x0 + w - xx)
      if (rowIdx + colIdx) % 2 == 1 then
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = CHECKER_DARK,
          frame = { x = xx, y = yy, w = cw, h = ch } }
      end
      xx, colIdx = xx + cell, colIdx + 1
    end
    yy, rowIdx = yy + cell, rowIdx + 1
  end
  return els
end

--- M.swatch(ui, colour, width, height) -> node, a flat block of the colour, over the checker
--- when the colour is not opaque. colour is an hs colour table with an alpha.
function M.swatch(ui, colour, width, height)
  return ui.raw(height, function(rect)
    local els = {}
    if (colour.alpha or 1) < 1 then els = checkerElements(rect.x, rect.y, width, height) end
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = colour,
      frame = { x = rect.x, y = rect.y, w = width, h = height } }
    return els
  end)
end

--- M.compose(ui, facts, blocks) -> node, the header first and then every block, one gap
--- between them whatever the kind. blocks is an array of nodes.
function M.compose(ui, facts, blocks)
  local children = { M.header(ui, facts) }
  for _, block in ipairs(blocks) do children[#children + 1] = block end
  return ui.stack(children, { gap = M.GAP })
end

return M
