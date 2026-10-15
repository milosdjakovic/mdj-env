-- What can be drawn. Every primitive answers a node, a plain table holding a kind and its
-- fields, and nothing else. A node never holds a colour, a font or a size, only the name of
-- a variant the style resolves at layout time, such as title, dim or hint. Containers hold
-- child nodes, so a stack and a single text answer the same layout call, which is the
-- Composite pattern the design names.
--
-- Loads in plain Lua with no hs. Every name a primitive is given is checked here, at the
-- moment the node is built, against the vocabulary the style owns, and an unknown one is an
-- error naming it. A misspelled variant caught where it was written is a line number, the
-- same mistake caught at draw time is a blank where a label should be.

local M = {}

-- The closed sets a node's options take, published so a caller writes kit.aligns.center
-- rather than a bare word, the same shape CanvasPanel.placements already has. A member's
-- value is its own name.
M.kinds = {
  text = "text", badge = "badge", icon = "icon", row = "row", stack = "stack",
  flow = "flow", grid = "grid", divider = "divider", spacer = "spacer",
  surface = "surface", group = "group", code = "code", raw = "raw", image = "image",
}
M.aligns = { left = "left", center = "center", right = "right" }
M.rowAligns = { start = "start", center = "center", ["end"] = "end" }
M.lineBreaks = {
  wordWrap = "wordWrap", charWrap = "charWrap", clip = "clip",
  truncateHead = "truncateHead", truncateTail = "truncateTail",
  truncateMiddle = "truncateMiddle",
}

local function sortedNames(set)
  local names = {}
  for name in pairs(set) do names[#names + 1] = name end
  table.sort(names)
  return table.concat(names, ", ")
end

-- The one refusal. Level 3 points the error at the line that called the primitive rather
-- than at this helper or the primitive itself.
local function member(set, value, what, primitive)
  if set[value] then return value end
  error("ui.kit " .. primitive .. ", unknown " .. what .. " '" .. tostring(value)
    .. "', expected one of " .. sortedNames(set), 3)
end

local function optional(set, value, what, primitive)
  if value == nil then return nil end
  return member(set, value, what, primitive)
end

local function valueSet(t)
  local out = {}
  for _, v in pairs(t) do out[v] = true end
  return out
end

local ALIGNS = valueSet(M.aligns)
local ROW_ALIGNS = valueSet(M.rowAligns)
local LINE_BREAKS = valueSet(M.lineBreaks)

local function childList(children, primitive)
  if type(children) ~= "table" then
    error("ui.kit " .. primitive .. ", children must be a list of nodes", 3)
  end
  for i, child in ipairs(children) do
    if type(child) ~= "table" or not M.kinds[child.kind] then
      error("ui.kit " .. primitive .. ", child " .. i .. " is not a node", 3)
    end
  end
  return children
end

-- Tab expansion is tabs.lua's, shared with the measurer so the code block and the wrap agree on
-- the width. A sibling loaded by path rather than named by the composition root, since it is
-- plain Lua with no collaborators.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local tabs = assert(loadfile(here .. "tabs.lua"))()
M.tabWidth = tabs.width
local expandTabs = tabs.expand

--- M.new(names) -> the primitives, bound to one vocabulary.
--- names is lib/ui/style.lua's M.names, the sets of colour, text, space, icon and badge
--- names, and the list of type roles. Injected rather than loaded so this file names no sibling.
function M.new(names)
  assert(type(names) == "table", "ui.kit, new needs the style's names")
  local kit = { kinds = M.kinds, aligns = M.aligns, rowAligns = M.rowAligns,
                lineBreaks = M.lineBreaks,
                -- The five type roles, title body caption section code, which a text node
                -- names as its variant. Their font, size, line height and colour all come
                -- from the style, none is given here.
                roles = names.roles }

  --- kit.text(str, variant, opts) -> node
  --- The kit applies no text transform of any kind, no upper casing and no other change of
  --- case, so a caller that wants a section label in capitals writes it in capitals.
  --- opts.color a colour role, opts.align one of aligns, opts.lineBreak one of lineBreaks,
  --- opts.wrap true to wrap at the width the text is laid out in. opts.width, a number of
  --- points, makes the text a slot of exactly that width, never wider than the room it is
  --- given, with opts.align placing the text inside it. It exists for a figure that changes
  --- under the eye. The system font draws digits of different widths, so a number drawn at its
  --- own width would push whatever sits beside it sideways as it changes, and a slot sized to
  --- the widest value, with the number aligned right inside it, keeps the neighbour still.
  --- A wrapping text wraps at the slot's width.
  function kit.text(str, variant, opts)
    opts = opts or {}
    if opts.width ~= nil and (type(opts.width) ~= "number" or opts.width < 0) then
      error("ui.kit text, width must be a number of points, not " .. tostring(opts.width), 2)
    end
    return {
      kind = M.kinds.text,
      str = tostring(str or ""),
      variant = member(names.text, variant, "variant", "text"),
      color = optional(names.colors, opts.color, "color", "text"),
      align = optional(ALIGNS, opts.align, "align", "text"),
      lineBreak = optional(LINE_BREAKS, opts.lineBreak, "lineBreak", "text"),
      wrap = opts.wrap and true or false,
      width = opts.width,
    }
  end

  --- kit.badge(key, size, opts) -> node, size names cheat, hint or button. opts.fill true
  --- makes the chip as wide as the slot it is laid out in rather than as wide as its glyph,
  --- which is how the cheat sheet draws a fixed width badge column.
  function kit.badge(key, size, opts)
    opts = opts or {}
    return { kind = M.kinds.badge, key = tostring(key or ""),
             size = member(names.badge, size, "size", "badge"),
             fill = opts.fill == true }
  end

  --- kit.icon(imageOrGlyph, size) -> node, size names row, list or sheet. A string is a
  --- glyph and a table is an icon spec keyed by source name, both drawn by the root's icon engine,
  --- and anything else is taken as an image already.
  function kit.icon(imageOrGlyph, size)
    return { kind = M.kinds.icon, source = imageOrGlyph,
             size = member(names.icon, size, "size", "icon") }
  end

  --- kit.row(children, opts) -> node, left to right. opts.gap a space name, opts.align one
  --- of rowAligns for the cross axis. One child takes the remaining width, the last unless
  --- opts.fillIndex names another, an integer from 1 to the child count, and every other
  --- child keeps its natural width, so a row can truncate its first child and keep the one
  --- beside it whole. opts.fill false turns the filling off, and then fillIndex is ignored.
  function kit.row(children, opts)
    opts = opts or {}
    childList(children, "row")
    local fillIndex = opts.fillIndex
    if fillIndex ~= nil then
      if type(fillIndex) ~= "number" or fillIndex ~= math.floor(fillIndex)
        or fillIndex < 1 or fillIndex > #children then
        error("ui.kit row, fillIndex must be an integer from 1 to " .. #children
          .. ", not " .. tostring(fillIndex), 2)
      end
    end
    return { kind = M.kinds.row, children = children,
             gap = optional(names.space, opts.gap, "gap", "row"),
             align = optional(ROW_ALIGNS, opts.align, "align", "row"),
             fill = opts.fill ~= false, fillIndex = fillIndex }
  end

  --- kit.heading(label, facts) -> node, a section label at the left and optional facts flush
  --- against the right edge, both in the section role, the facts in subtext. Without facts it
  --- is the label alone. The label is the child that takes the remaining width, so the facts
  --- keep their whole width and it is the label that gives way in a pane too narrow for both.
  --- It lives in the kit because the file search, processes and speedtest panes all head a
  --- section the same way, and three private copies would drift.
  function kit.heading(label, facts)
    if facts == nil or facts == "" then return kit.text(label, "section") end
    return kit.row({
      kit.text(label, "section"),
      kit.text(facts, "section", { color = "subtext", align = M.aligns.right }),
    }, { fillIndex = 1 })
  end

  --- kit.stack(children, opts) -> node, top to bottom. opts.gap a space name.
  function kit.stack(children, opts)
    opts = opts or {}
    return { kind = M.kinds.stack, children = childList(children, "stack"),
             gap = optional(names.space, opts.gap, "gap", "stack") }
  end

  --- kit.flow(children, opts) -> node, left to right wrapping at the width. opts.gapX and
  --- opts.gapY are space names.
  function kit.flow(children, opts)
    opts = opts or {}
    return { kind = M.kinds.flow, children = childList(children, "flow"),
             gapX = optional(names.space, opts.gapX, "gapX", "flow"),
             gapY = optional(names.space, opts.gapY, "gapY", "flow") }
  end

  --- kit.grid(children, opts) -> node. opts.columns a count, default 1, opts.gapX and
  --- opts.gapY space names.
  function kit.grid(children, opts)
    opts = opts or {}
    local columns = opts.columns or 1
    if type(columns) ~= "number" or columns < 1 then
      error("ui.kit grid, columns must be a count of at least one, not " .. tostring(columns), 2)
    end
    return { kind = M.kinds.grid, children = childList(children, "grid"),
             columns = math.floor(columns),
             gapX = optional(names.space, opts.gapX, "gapX", "grid"),
             gapY = optional(names.space, opts.gapY, "gapY", "grid") }
  end

  --- kit.divider() -> node, one point rule in the border colour across the width.
  function kit.divider()
    return { kind = M.kinds.divider }
  end

  --- kit.spacer(size) -> node, a space name, taken as height in a stack and width in a row.
  function kit.spacer(size)
    return { kind = M.kinds.spacer, size = member(names.space, size, "size", "spacer") }
  end

  --- kit.surface() -> node, the chrome behind the whole rect the layout is given.
  function kit.surface()
    return { kind = M.kinds.surface }
  end

  --- kit.group(children, opts) -> node, children top to bottom with no gap. opts.alpha
  --- multiplies every child colour and image alpha, opts.id is the click id every element
  --- inside it carries.
  function kit.group(children, opts)
    opts = opts or {}
    if opts.alpha ~= nil and type(opts.alpha) ~= "number" then
      error("ui.kit group, alpha must be a number, not " .. tostring(opts.alpha), 2)
    end
    return { kind = M.kinds.group, children = childList(children, "group"),
             alpha = opts.alpha, id = opts.id }
  end

  --- kit.code(lines, opts) -> node, a preformatted block in the code role. lines is an
  --- array of strings, drawn as one text element for the visible lines with the whitespace kept exactly,
  --- never collapsed and never wrapped, each line cut at the rect width with truncateTail.
  --- Tabs are expanded here to the next multiple of TAB_WIDTH columns. opts.maxHeight, when
  --- the lines do not fit in it, draws as many lines as fit minus one and a closing line in
  --- the caption role. opts.more is a function of the count of lines left out answering that
  --- closing line, defaulting to "N more lines". Content height is the drawn height.
  function kit.code(lines, opts)
    opts = opts or {}
    if type(lines) ~= "table" then
      error("ui.kit code, lines must be an array of strings", 2)
    end
    if opts.maxHeight ~= nil and type(opts.maxHeight) ~= "number" then
      error("ui.kit code, maxHeight must be a number, not " .. tostring(opts.maxHeight), 2)
    end
    if opts.more ~= nil and type(opts.more) ~= "function" then
      error("ui.kit code, more must be a function of the count", 2)
    end
    local out = {}
    for i, line in ipairs(lines) do out[i] = expandTabs(tostring(line)) end
    return { kind = M.kinds.code, lines = out, maxHeight = opts.maxHeight, more = opts.more }
  end

  --- kit.raw(height, draw, opts) -> node, room the caller draws into itself. Layout reserves
  --- height points, a number, at the node's position and calls draw(rect, tokens) with the
  --- absolute rect it was given after the scroll offset, then inserts the element list draw
  --- returns at that point, in order. The room is as wide as the slot it is laid out in,
  --- unless opts.width, a number of points, says otherwise, which is how a raw node sits
  --- beside other children in a row, an icon the caller draws itself in front of a name.
  function kit.raw(height, draw, opts)
    opts = opts or {}
    if type(height) ~= "number" or height < 0 then
      error("ui.kit raw, height must be a number of points, not " .. tostring(height), 2)
    end
    if type(draw) ~= "function" then
      error("ui.kit raw, draw must be a function", 2)
    end
    if opts.width ~= nil and (type(opts.width) ~= "number" or opts.width < 0) then
      error("ui.kit raw, width must be a number of points, not " .. tostring(opts.width), 2)
    end
    return { kind = M.kinds.raw, height = height, draw = draw, width = opts.width }
  end

  --- kit.image(img, opts) -> node, a picture scaled to the width of its slot, keeping its own
  --- aspect and kept at the top left. Its height is derived from the width it is laid out at,
  --- so a stack sizes it correctly whatever the pane width turns out to be. img is an hs.image
  --- or anything answering size() with a table holding w and h. opts.upscale, true by default,
  --- says whether the picture may draw wider than its own size. false never draws it wider than
  --- it is, so a small icon is shown at the size it really is rather than blown up into a blur.
  --- Group alpha and the click id reach it the way they reach an icon. It exists so the
  --- clipboard and the file search pane share one image instead of two raw nodes that agree.
  function kit.image(img, opts)
    opts = opts or {}
    local hasSize = img ~= nil and (type(img) == "table" or type(img) == "userdata")
      and type(img.size) == "function"
    if not hasSize then
      error("ui.kit image, img must be an image that answers size(), not " .. tostring(img), 2)
    end
    if opts.upscale ~= nil and type(opts.upscale) ~= "boolean" then
      error("ui.kit image, upscale must be true or false, not " .. tostring(opts.upscale), 2)
    end
    return { kind = M.kinds.image, image = img, upscale = opts.upscale ~= false }
  end

  return kit
end

return M
