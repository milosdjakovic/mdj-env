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
  surface = "surface", group = "group",
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

--- M.new(names) -> the primitives, bound to one vocabulary.
--- names is lib/ui/style.lua's M.names, the sets of colour, text, space, icon and badge
--- names. Injected rather than loaded so this file names no sibling.
function M.new(names)
  assert(type(names) == "table", "ui.kit, new needs the style's names")
  local kit = { kinds = M.kinds, aligns = M.aligns, rowAligns = M.rowAligns,
                lineBreaks = M.lineBreaks }

  --- kit.text(str, variant, opts) -> node
  --- opts.color a colour role, opts.align one of aligns, opts.lineBreak one of lineBreaks,
  --- opts.wrap true to wrap at the width the text is laid out in.
  function kit.text(str, variant, opts)
    opts = opts or {}
    return {
      kind = M.kinds.text,
      str = tostring(str or ""),
      variant = member(names.text, variant, "variant", "text"),
      color = optional(names.colors, opts.color, "color", "text"),
      align = optional(ALIGNS, opts.align, "align", "text"),
      lineBreak = optional(LINE_BREAKS, opts.lineBreak, "lineBreak", "text"),
      wrap = opts.wrap and true or false,
    }
  end

  --- kit.badge(key, size) -> node, size names cheat, hint or button.
  function kit.badge(key, size)
    return { kind = M.kinds.badge, key = tostring(key or ""),
             size = member(names.badge, size, "size", "badge") }
  end

  --- kit.icon(imageOrGlyph, size) -> node, size names row, list or sheet. A string is a
  --- glyph the layout draws to an image, anything else is taken as an image already.
  function kit.icon(imageOrGlyph, size)
    return { kind = M.kinds.icon, source = imageOrGlyph,
             size = member(names.icon, size, "size", "icon") }
  end

  --- kit.row(children, opts) -> node, left to right. opts.gap a space name, opts.align one
  --- of rowAligns for the cross axis. The last child takes the remaining width, unless
  --- opts.fill is false.
  function kit.row(children, opts)
    opts = opts or {}
    return { kind = M.kinds.row, children = childList(children, "row"),
             gap = optional(names.space, opts.gap, "gap", "row"),
             align = optional(ROW_ALIGNS, opts.align, "align", "row"),
             fill = opts.fill ~= false }
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

  return kit
end

return M
