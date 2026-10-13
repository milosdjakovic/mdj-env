-- Where everything goes. layout(node, rect, tokens, opts) walks a tree of kit nodes,
-- measures every text through the injected measurer, resolves every variant through the
-- tokens, and answers canvas elements plus the content height, so a pane that scrolls can
-- compute its own limit from the second value.
--
-- Two passes over the same tree. sizeOf answers how much room a node wants inside a given
-- width, and emit places it in a slot and appends its elements. A container asks sizeOf of
-- its children to decide their slots and then emits each one into its slot, so a stack and
-- a single text answer the same two questions and the walk never asks which it holds.
--
-- Nothing here owns a window. The caller draws what comes back on its own canvas, the same
-- division field/render.lua and lib/cheatsheet.lua already keep.
--
-- Text always leaves as hs.styledtext, since only styledtext carries a line break mode and a
-- pinned line height, and both are in use. A variant with pin set to false leaves the line
-- height unpinned, which draws exactly what a plain canvas text element draws, measured in
-- stage two against the plain elements every shared surface used before it moved here. Text
-- and badges are measured whole through the measurer's exact, falling back to its width
-- for a measurer that has no exact, such as a test's stub. A glyph icon is drawn to an hs.image the way
-- lib/glyphicon.lua draws one, and cached here by glyph and size, so iconImage can also feed
-- a native chooser row the very image a canvas pane would draw.

local M = {}

-- The surface node is chrome rather than content. It is drawn behind the whole rect the
-- layout was given, outside any scroll and outside the clip, and it takes no room and no
-- gap inside its container. The design says only that surface is the chrome with
-- CanvasPanel.surfaceElements behind it, so this placement is the smallest reading that
-- lets a pane write surface() as the first child of its root and get its frame painted.
local SURFACE = "surface"

local function round(n) return math.floor(n + 0.5) end

local function withAlpha(color, factor)
  if not color then return nil end
  if factor == 1 then return color end
  local out = {}
  for k, v in pairs(color) do out[k] = v end
  out.alpha = (color.alpha or 1) * factor
  return out
end

local function content(children)
  local out = {}
  for _, child in ipairs(children or {}) do
    if child.kind ~= SURFACE then out[#out + 1] = child end
  end
  return out
end

local function spaceOf(T, name)
  return (name and T.space[name]) or 0
end

-- The natural width of one string, measured whole when the measurer can, see the header.
local function widthOf(measure, str, font, size)
  if measure.exact then return measure:exact(str, font, size) end
  return measure:width(str, font, size)
end

--- M.new(deps) -> engine
--- deps.measure          a lib/ui/measure.lua instance, required.
--- deps.surfaceElements  optional, CanvasPanel.surfaceElements or anything shaped like it,
---                       (w, h) -> elements at origin. Injected by the composition root so
---                       the chrome is painted by the one routine that already paints it.
---                       With none injected a surface node draws nothing.
function M.new(deps)
  deps = deps or {}
  local measure = assert(deps.measure, "ui.layout, new needs a measure instance")
  local engine = {}
  local imageCache = {}

  --- engine.iconImage(source, points) -> hs.image or nil.
  --- A string is a glyph, drawn once per glyph and size with lib/glyphicon.lua's numbers, a
  --- 72 point canvas, 52 point text centred and dropped by 8 percent, then sized to points.
  --- Anything else is taken to be an image already and answered unchanged. A glyph that
  --- draws nothing is remembered as false and answered as nil.
  function engine.iconImage(source, points)
    if type(source) ~= "string" then return source end
    local key = source .. "\0" .. tostring(points)
    if imageCache[key] == nil then
      local side = 72
      local c = hs.canvas.new({ x = 0, y = 0, w = side, h = side })
      c[1] = { type = "text", text = source, textSize = 52, textAlignment = "center",
               frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
      local img = c:imageFromCanvas()
      c:delete()
      if img and points then img = img:setSize({ w = points, h = points }) end
      imageCache[key] = img or false
    end
    return imageCache[key] or nil
  end

  local sizeOf

  -- The slots of a row, each child's width and height, and the row's own size. Every child
  -- but the last takes its natural width, and the last takes what remains when fill is on.
  local function rowSlots(node, maxW, T)
    local kids = content(node.children)
    local gap = spaceOf(T, node.gap)
    local slots, used, rowH = {}, 0, 0
    for i, child in ipairs(kids) do
      if i > 1 then used = used + gap end
      local avail = math.max(0, maxW - used)
      local cw, ch = sizeOf(child, avail, T)
      if node.fill and i == #kids then cw = avail end
      slots[i] = { node = child, w = cw, h = ch }
      used = used + cw
      if ch > rowH then rowH = ch end
    end
    return slots, used, rowH
  end

  -- The lines of a flow, each a list of slots, wrapping before the child that would cross
  -- maxW. A child wider than the whole width still gets a line of its own.
  local function flowLines(node, maxW, T)
    local gapX, gapY = spaceOf(T, node.gapX), spaceOf(T, node.gapY)
    local lines, cur, curW, curH = {}, {}, 0, 0
    local widest = 0
    for _, child in ipairs(content(node.children)) do
      local cw, ch = sizeOf(child, maxW, T)
      if #cur > 0 and curW + gapX + cw > maxW then
        lines[#lines + 1] = { slots = cur, h = curH }
        cur, curW, curH = {}, 0, 0
      end
      local x = (#cur == 0) and 0 or (curW + gapX)
      cur[#cur + 1] = { node = child, x = x, w = cw, h = ch }
      curW = x + cw
      if ch > curH then curH = ch end
      if curW > widest then widest = curW end
    end
    if #cur > 0 then lines[#lines + 1] = { slots = cur, h = curH } end
    local total = 0
    for i, line in ipairs(lines) do total = total + line.h + (i > 1 and gapY or 0) end
    return lines, widest, total
  end

  local function gridRows(node, maxW, T)
    local gapX, gapY = spaceOf(T, node.gapX), spaceOf(T, node.gapY)
    local cols = node.columns
    local cellW = math.max(0, (maxW - gapX * (cols - 1)) / cols)
    local rows, total = {}, 0
    for i, child in ipairs(content(node.children)) do
      local r = math.floor((i - 1) / cols) + 1
      local col = (i - 1) % cols
      rows[r] = rows[r] or { slots = {}, h = 0 }
      local _, ch = sizeOf(child, cellW, T)
      table.insert(rows[r].slots, { node = child, x = col * (cellW + gapX), w = cellW, h = ch })
      if ch > rows[r].h then rows[r].h = ch end
    end
    for i, row in ipairs(rows) do total = total + row.h + (i > 1 and gapY or 0) end
    return rows, cellW, total
  end

  local function stackSize(children, gap, maxW, T)
    local w, h, n = 0, 0, 0
    for _, child in ipairs(content(children)) do
      local cw, ch = sizeOf(child, maxW, T)
      if n > 0 then h = h + gap end
      h = h + ch
      n = n + 1
      if cw > w then w = cw end
    end
    return w, h
  end

  -- How much room a node wants inside maxW, as width and height.
  sizeOf = function(node, maxW, T)
    local kind = node.kind
    if kind == "text" then
      local v = T.text[node.variant]
      if node.wrap then
        local lines = measure:wrap(node.str, v.font, v.size, maxW)
        return maxW, #lines * v.lineHeight
      end
      return math.min(math.ceil(widthOf(measure, node.str, v.font, v.size)), maxW), v.lineHeight
    elseif kind == "badge" then
      local b = T.badge[node.size]
      if node.fill then return maxW, b.height end
      local v = T.text[b.text]
      local w = math.ceil(widthOf(measure, node.key, v.font, v.size)) + 2 * b.padX
      return math.max(b.minWidth or b.height, w), b.height
    elseif kind == "icon" then
      local s = T.icon[node.size]
      return s, s
    elseif kind == "spacer" then
      local s = T.space[node.size]
      return s, s
    elseif kind == "divider" then
      return maxW, 1
    elseif kind == SURFACE then
      return 0, 0
    elseif kind == "row" then
      local _, used, rowH = rowSlots(node, maxW, T)
      return used, rowH
    elseif kind == "stack" then
      return stackSize(node.children, spaceOf(T, node.gap), maxW, T)
    elseif kind == "group" then
      return stackSize(node.children, 0, maxW, T)
    elseif kind == "flow" then
      local _, widest, total = flowLines(node, maxW, T)
      return widest, total
    elseif kind == "grid" then
      local _, _, total = gridRows(node, maxW, T)
      return maxW, total
    end
    error("ui.layout, unknown node kind '" .. tostring(kind) .. "'")
  end

  local function push(ctx, el)
    if ctx.id ~= nil then
      el.id = ctx.id
      el.trackMouseUp = true
    end
    ctx.els[#ctx.els + 1] = el
  end

  local function colorOf(ctx, role)
    return withAlpha(ctx.T.colors[role], ctx.alpha)
  end

  local emit

  local function emitStack(children, gap, x, y, w, ctx)
    local cy, n = y, 0
    for _, child in ipairs(content(children)) do
      local _, ch = sizeOf(child, w, ctx.T)
      if n > 0 then cy = cy + gap end
      emit(child, x, cy, w, ch, ctx)
      cy = cy + ch
      n = n + 1
    end
  end

  local function textElement(ctx, str, v, colorRole, align, lineBreak, frame)
    local paragraph = { alignment = align, lineBreak = lineBreak }
    if v.pin ~= false then
      paragraph.minimumLineHeight = v.lineHeight
      paragraph.maximumLineHeight = v.lineHeight
    end
    local styled = hs.styledtext.new(str, {
      font = { name = v.font, size = v.size },
      color = colorOf(ctx, colorRole),
      paragraphStyle = paragraph,
    })
    return { type = "text", text = styled, frame = frame }
  end

  -- Place a node in the slot x, y, w, h and append its elements. y is already scrolled.
  emit = function(node, x, y, w, h, ctx)
    local T = ctx.T
    local kind = node.kind
    if kind == "text" then
      local v = T.text[node.variant]
      local lineBreak = node.lineBreak or (node.wrap and "wordWrap" or "truncateTail")
      -- frameY and extraW place the frame against the box without taking room in it.
      push(ctx, textElement(ctx, node.str, v, node.color or v.color or "foreground",
        node.align or "left", lineBreak,
        { x = x, y = y + (v.frameY or 0), w = w + (v.extraW or 0), h = h }))
    elseif kind == "badge" then
      local b = T.badge[node.size]
      local v = T.text[b.text]
      local bw = sizeOf(node, w, T)
      local r = T.radius[b.radius or "badge"]
      push(ctx, { type = "rectangle", action = "fill", fillColor = colorOf(ctx, "badge"),
        roundedRectRadii = { xRadius = r, yRadius = r },
        frame = { x = x, y = y, w = bw, h = b.height } })
      -- Centred unrounded, then moved by textY, and wrapped by word, which is what a plain
      -- canvas text element does and what every badge drew with before stage two.
      push(ctx, textElement(ctx, node.key, v, "foreground", "center", "wordWrap",
        { x = x, y = y + (b.height - v.lineHeight) / 2 + (b.textY or 0), w = bw,
          h = v.lineHeight }))
    elseif kind == "icon" then
      local s = T.icon[node.size]
      local img = engine.iconImage(node.source, s)
      if img then
        push(ctx, { type = "image", image = img, imageAlpha = ctx.alpha,
          imageScaling = "scaleProportionally", frame = { x = x, y = y, w = s, h = s } })
      end
    elseif kind == "divider" then
      push(ctx, { type = "rectangle", action = "fill", fillColor = colorOf(ctx, "border"),
        frame = { x = x, y = y, w = w, h = 1 } })
    elseif kind == "spacer" or kind == SURFACE then
      -- A spacer is only room, and a surface was already painted behind everything.
      return
    elseif kind == "row" then
      local slots, _, rowH = rowSlots(node, w, T)
      local gap = spaceOf(T, node.gap)
      local cx = x
      for i, slot in ipairs(slots) do
        if i > 1 then cx = cx + gap end
        local cy = y
        if node.align == "center" then cy = y + round((rowH - slot.h) / 2)
        elseif node.align == "end" then cy = y + rowH - slot.h end
        emit(slot.node, cx, cy, slot.w, slot.h, ctx)
        cx = cx + slot.w
      end
    elseif kind == "stack" then
      emitStack(node.children, spaceOf(T, node.gap), x, y, w, ctx)
    elseif kind == "group" then
      local saved, savedId = ctx.alpha, ctx.id
      ctx.alpha = ctx.alpha * (node.alpha or 1)
      if node.id ~= nil then ctx.id = node.id end
      emitStack(node.children, 0, x, y, w, ctx)
      ctx.alpha, ctx.id = saved, savedId
    elseif kind == "flow" then
      local lines = flowLines(node, w, T)
      local gapY = spaceOf(T, node.gapY)
      local cy = y
      for i, line in ipairs(lines) do
        if i > 1 then cy = cy + gapY end
        for _, slot in ipairs(line.slots) do
          emit(slot.node, x + slot.x, cy, slot.w, slot.h, ctx)
        end
        cy = cy + line.h
      end
    elseif kind == "grid" then
      local rows = gridRows(node, w, T)
      local gapY = spaceOf(T, node.gapY)
      local cy = y
      for i, row in ipairs(rows) do
        if i > 1 then cy = cy + gapY end
        for _, slot in ipairs(row.slots) do
          emit(slot.node, x + slot.x, cy, slot.w, slot.h, ctx)
        end
        cy = cy + row.h
      end
    else
      error("ui.layout, unknown node kind '" .. tostring(kind) .. "'")
    end
  end

  -- Whether a tree holds a surface anywhere, so it can be painted once behind the rest.
  local function hasSurface(node)
    if node.kind == SURFACE then return true end
    for _, child in ipairs(node.children or {}) do
      if hasSurface(child) then return true end
    end
    return false
  end

  --- engine.layout(node, rect, tokens, opts) -> elements, contentHeight
  --- rect is { x, y, w, h } in the caller's canvas. tokens is a resolved table from
  --- lib/ui/style.lua. opts, every field optional.
  ---   scrollY  points the content is scrolled by. Every element moves up by it and the
  ---            content is clipped to rect, the clip opened once and closed once.
  ---   clip     true to clip to rect without scrolling.
  --- contentHeight is the height the tree wants at rect.w, before any scroll.
  function engine.layout(node, rect, tokens, opts)
    opts = opts or {}
    local els = {}

    if hasSurface(node) and deps.surfaceElements then
      for _, el in ipairs(deps.surfaceElements(rect.w, rect.h) or {}) do
        local copy = {}
        for k, v in pairs(el) do copy[k] = v end
        if el.frame then
          copy.frame = { x = (el.frame.x or 0) + rect.x, y = (el.frame.y or 0) + rect.y,
                         w = el.frame.w, h = el.frame.h }
        end
        els[#els + 1] = copy
      end
    end

    local clipped = opts.scrollY ~= nil or opts.clip == true
    if clipped then
      els[#els + 1] = { type = "rectangle", action = "clip",
        frame = { x = rect.x, y = rect.y, w = rect.w, h = rect.h } }
    end

    local _, contentH = sizeOf(node, rect.w, tokens)
    local ctx = { T = tokens, els = els, alpha = 1, id = nil }
    emit(node, rect.x, rect.y - (opts.scrollY or 0), rect.w, contentH, ctx)

    if clipped then els[#els + 1] = { type = "resetClip" } end
    return els, contentH
  end

  return engine
end

return M
