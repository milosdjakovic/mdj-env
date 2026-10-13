-- What the stage two parity probes share. Each probe builds one surface's canvas elements for
-- a fixed model twice, once through the old code and once through the new, and hands both
-- lists here to be compared. Stage two of docs/DESIGN-UI-KIT.md moved the shared surfaces onto
-- the UI kit under the rule that nothing a person sees changes, and these probes are how that
-- rule is checked rather than assumed.
--
-- The comparison is two passes. The first walks the two lists element by element and reports
-- every font, size, colour, alignment, line break, pinned line height, rectangle, radius,
-- image and frame that differs, with a plain canvas text element and an hs.styledtext one
-- reduced to the same fields, so a text that moved from one form to the other compares on
-- what it draws rather than on how it was spelled. A click id is reported apart, since it is
-- not something a person sees. The second pass draws both lists offscreen and compares the
-- pixels, which is the verdict, since it catches anything the field list cannot name.
--
-- The old code is not loaded live. test/parity.sh exports the old tree from git into a
-- scratch directory and sets PARITY_ARGS before a probe runs, naming that directory and the
-- file results are written to, since a reply through the hs command line tool can go missing
-- and a file cannot. Both halves are drawn by standing in for hs.host.interfaceStyle for the
-- length of one synchronous build, restored before anything else can run.

local M = {}

local source = debug.getinfo(1, "S").source
local here = (source:match("^@(.*)$") or source):match("^(.*/)")

M.args = PARITY_ARGS or error("parity probes run through test/parity.sh, PARITY_ARGS is not set")
M.new = here .. "../"
M.old = M.args.old
M.hsDir = M.new .. "../../"

local outFile = assert(io.open(M.args.out, "w"))

function M.out(line)
  outFile:write(line .. "\n")
  outFile:flush()
end

function M.done()
  outFile:write("DONE\n")
  outFile:close()
  PARITY_ARGS = nil
end

function M.policy()
  return dofile(M.hsDir .. "config/settings.lua")
end

-- A fresh kit from this checkout, configured with the very spec the composition root builds.
function M.newUI(policy)
  local ui = dofile(M.new .. "lib/ui/init.lua")
  ui.configure({ spec = dofile(M.new .. "root/uispec.lua").spec(policy) })
  return ui
end

M.halves = { "dark", "light" }

-- Runs fn with the appearance answering the given half, and puts the real call back
-- whatever fn does.
function M.withHalf(half, fn)
  local real = hs.host.interfaceStyle
  hs.host.interfaceStyle = function() return half == "dark" and "Dark" or nil end
  local results = table.pack(pcall(fn))
  hs.host.interfaceStyle = real
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

-- A panel factory standing in for CanvasPanel, which keeps the content strategy it is handed.
function M.fakePanel()
  local fake = { placements = { below = "below", above = "above", left = "left", right = "right",
                                center = "center" } }
  function fake.new(cfg)
    fake.content = cfg.content
    return { arm = function() end, poke = function() end, hide = function() end,
             show = function() end, isShowing = function() return false end }
  end
  return fake
end

--------------------------------------------------------------------------------
-- Reducing an element to what it draws
--------------------------------------------------------------------------------

local fontNames = {}
local function canonicalFont(name, size)
  local key = tostring(name) .. "\0" .. tostring(size)
  if fontNames[key] == nil then
    local t = hs.styledtext.new("x", { font = { name = name, size = size } }):asTable()
    fontNames[key] = t[2].attributes.font.name
  end
  return fontNames[key]
end

local function putColor(out, prefix, c)
  if c == nil then out[prefix] = "none"; return end
  local r, g, b
  if c.white ~= nil and c.red == nil then
    r, g, b = c.white, c.white, c.white
  else
    r, g, b = c.red or 0, c.green or 0, c.blue or 0
  end
  out[prefix .. ".r"], out[prefix .. ".g"], out[prefix .. ".b"] = r, g, b
  out[prefix .. ".a"] = c.alpha or 1
end

local imageIds, nextImage = setmetatable({}, { __mode = "k" }), 0
local function imageId(img)
  if img == nil then return "none" end
  if not imageIds[img] then
    nextImage = nextImage + 1
    imageIds[img] = "image" .. nextImage
  end
  return imageIds[img]
end

-- One element as a flat table of named fields. Keys starting with a tilde are not visible.
function M.reduce(el)
  local out = { type = el.type }
  if el.frame then
    out["frame.x"], out["frame.y"] = el.frame.x, el.frame.y
    out["frame.w"], out["frame.h"] = el.frame.w, el.frame.h
  end
  if el.type == "text" then
    if type(el.text) == "userdata" then
      local t = el.text:asTable()
      out.str = t[1]
      local a = (t[2] and t[2].attributes) or {}
      local font = a.font or {}
      out.font = canonicalFont(font.name, font.size)
      out.size = font.size
      putColor(out, "color", a.color)
      local p = a.paragraphStyle or {}
      out.align = p.alignment or "natural"
      out.lineBreak = p.lineBreak or "wordWrap"
      out.minLineHeight = p.minimumLineHeight or 0
      out.maxLineHeight = p.maximumLineHeight or 0
    else
      out.str = tostring(el.text)
      local size = el.textSize or 27
      out.font = canonicalFont(el.textFont or ".AppleSystemUIFont", size)
      out.size = size
      putColor(out, "color", el.textColor or { white = 1 })
      out.align = el.textAlignment or "natural"
      out.lineBreak = el.textLineBreak or "wordWrap"
      out.minLineHeight, out.maxLineHeight = 0, 0
    end
  elseif el.type == "rectangle" then
    out.action = el.action or "strokeAndFill"
    if out.action ~= "clip" then
      putColor(out, "fill", el.fillColor)
      putColor(out, "stroke", el.strokeColor)
      out.strokeWidth = el.strokeWidth or "none"
      local r = el.roundedRectRadii
      out["radius.x"] = r and r.xRadius or 0
      out["radius.y"] = r and r.yRadius or 0
    end
  elseif el.type == "image" then
    out.image = imageId(el.image)
    out.imageAlpha = el.imageAlpha or 1
    out.imageScaling = el.imageScaling or "scaleProportionally"
  end
  -- An empty string draws nothing, and a styled one carries no attributes to read back, so
  -- only its string and frame are compared.
  if el.type == "text" and out.str == "" then
    for _, k in ipairs({ "font", "size", "color", "color.r", "color.g", "color.b", "color.a",
                         "align", "lineBreak", "minLineHeight", "maxLineHeight" }) do
      out[k] = nil
    end
  end
  if el.id ~= nil then out["~id"] = tostring(el.id) end
  if el.trackMouseUp ~= nil then out["~trackMouseUp"] = tostring(el.trackMouseUp) end
  return out
end

local function same(a, b)
  if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
  return a == b
end

-- Every field that differs between two element lists, as lines, visible ones first.
function M.diff(oldEls, newEls)
  local visible, hidden = {}, {}
  local n = math.max(#oldEls, #newEls)
  for i = 1, n do
    local o, w = oldEls[i], newEls[i]
    if not o or not w then
      visible[#visible + 1] = "element " .. i .. " present only in the "
        .. (o and "old" or "new") .. " list"
    else
      local ro, rw = M.reduce(o), M.reduce(w)
      local keys = {}
      for k in pairs(ro) do keys[k] = true end
      for k in pairs(rw) do keys[k] = true end
      local sorted = {}
      for k in pairs(keys) do sorted[#sorted + 1] = k end
      table.sort(sorted)
      for _, k in ipairs(sorted) do
        if not same(ro[k], rw[k]) then
          local line = "element " .. i .. " " .. k .. " old " .. tostring(ro[k])
            .. " new " .. tostring(rw[k])
          if k:sub(1, 1) == "~" then hidden[#hidden + 1] = line
          else visible[#visible + 1] = line end
        end
      end
    end
  end
  return visible, hidden
end

-- Both lists drawn offscreen on the same opaque ground, compared as encoded images.
local function render(els, w, h)
  local c = hs.canvas.new({ x = 0, y = 0, w = w, h = h })
  c[1] = { type = "rectangle", action = "fill", fillColor = { white = 0.5 },
           frame = { x = 0, y = 0, w = w, h = h } }
  for i, el in ipairs(els) do c[i + 1] = el end
  local img = c:imageFromCanvas()
  c:delete()
  return img and img:encodeAsURLString() or ""
end

function M.samePixels(oldEls, newEls, w, h)
  return render(oldEls, w, h) == render(newEls, w, h)
end

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

local totals = { cases = 0, clean = 0 }

-- Compares one case and writes its verdict. extras is an optional list of lines naming
-- differences found outside the element lists, a preferred size among them.
function M.check(name, oldEls, newEls, w, h, extras)
  totals.cases = totals.cases + 1
  local visible, hidden = M.diff(oldEls, newEls)
  for _, line in ipairs(extras or {}) do visible[#visible + 1] = line end
  local pixels = M.samePixels(oldEls, newEls, w, h)
  local clean = #visible == 0 and pixels
  if clean then totals.clean = totals.clean + 1 end
  M.out((clean and "SAME " or "DIFF ") .. name .. ", " .. #oldEls .. " elements, "
    .. #visible .. " visible field differences, pixels " .. (pixels and "identical" or "DIFFERENT")
    .. (#hidden > 0 and (", " .. #hidden .. " non visual") or ""))
  for _, line in ipairs(visible) do M.out("  " .. line) end
  for _, line in ipairs(hidden) do M.out("  non visual, " .. line) end
end

function M.sizeDiff(label, a, b)
  if same(a.w, b.w) and same(a.h, b.h) then return nil end
  return label .. " old " .. tostring(a.w) .. "x" .. tostring(a.h) .. " new "
    .. tostring(b.w) .. "x" .. tostring(b.h)
end

function M.summary()
  M.out("TOTAL " .. totals.clean .. " of " .. totals.cases .. " cases identical")
end

return M
