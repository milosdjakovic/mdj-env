-- The file search preview pane run end to end over the Lua code itself, for
-- test/fixtures/chooser/pane.json, step 1.4a of docs/PLAN-STANDALONE.md. Two callers share it, so the
-- fixture can never be recorded one way and checked another.
--
--   test/fixtures-pane-record.lua, run inside the live Hammerspoon, measures with the real fonts and
--   writes the fixture, what was measured with it.
--   test/fixtures.lua, the dry gate's runner, answers every measure from what the fixture recorded
--   and checks each case still lays out to what it expects.
--
-- A case is a row, its path and whether the index calls it a folder, or no row at all for the empty
-- state, and what the helper's peek found for it, shaped as sources/index.lua's parsePeek answers,
-- or null for a read that never answered. It goes through plugins/filesearch/viewers/sidepanel.lua's
-- show, the describers, buildModel and paintRow, then lib/previewpane.lua's native scroll path, the
-- path the swift chooser's pane takes, with lib/panel.lua's empty state and lib/ui's kit, measurer
-- and layout, every one of them the file itself loaded fresh in an environment of its own. Only four
-- things stand in. The measurer's two system calls, a backend that keeps what it is handed rather
-- than drawing it, hs.styledtext.new, which keeps the string and its attributes as a table, and the
-- thumbnail chain's render, which answers what the case's picture says, step 1.4b. No picture is no
-- generator answering, a picture's w and h one answering at once with an image of that size in
-- points, late as well the same answer after the pane first drew, so the repaint is what is
-- recorded, and rendering one that never answers. Time and the home folder are the case file's, so
-- an age and a short folder are the same on every run.
--
-- The tokens are the shape lib/chooser/providers/swift/pane.lua hands Olm.app, so the app is checked
-- against the very tokens it is handed.

local M = {}

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- A table with json.null turned into nil, so a decoded case reads like the Lua it stands for.
local function plain(v, null)
  if v == null then return nil end
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = plain(x, null) end
  return out
end
M.plain = plain

--- M.new(spoon, measured, opts) -> a runner. measured is { size = fn(str, style) -> { w, h },
--- info = fn(font) -> { ascender, descender, capHeight } }, the two calls measure.lua makes of hs.
--- opts.home and opts.now are what util.lua reads for the home folder and the time.
function M.new(spoon, measured, opts)
  opts = opts or {}
  local env = setmetatable({}, { __index = _G })
  local quiet = setmetatable({}, { __index = function() return function() end end })
  env.hs = {
    drawing = { getTextDrawingSize = measured.size },
    styledtext = {
      fontInfo = measured.info,
      new = function(str, attrs) return { styled = true, str = str, attrs = attrs } end,
    },
    logger = { new = function() return quiet end },
    screen = {},
    timer = { doAfter = function() return { stop = function() end } end },
  }
  env.os = setmetatable({
    time = function() return opts.now end,
    getenv = function(k) if k == "HOME" then return opts.home end return os.getenv(k) end,
  }, { __index = os })
  env.loadfile = function(path, mode) return loadfile(path, mode or "t", env) end
  env.dofile = function(path) return assert(env.loadfile(path))() end
  local function load(rel) return assert(env.loadfile(spoon .. rel))() end

  local styleLib = load("lib/ui/style.lua")
  local kitLib = load("lib/ui/kit.lua")
  local layoutLib = load("lib/ui/layout.lua")
  local measure = load("lib/ui/measure.lua").new()
  local engine = layoutLib.new({ measure = measure })
  local PreviewPane = load("lib/previewpane.lua")
  local Panel = load("lib/panel.lua")
  local thumbs = load("plugins/filesearch/thumbs.lua")
  local util = load("plugins/filesearch/util.lua")
  local sidepanelPath = spoon .. "plugins/filesearch/viewers/sidepanel.lua"

  local runner = {}

  --- runner.run(case, T, file) -> { elements, height, reset }, the elements as the backend was
  --- handed them, written as plain data, see M.element.
  function runner.run(case, T, file)
    local ui = kitLib.new(styleLib.names)
    ui.measure = measure
    ui.tokens = function() return T end
    ui.layout = function(node, rect, o)
      o = o or {}
      return engine.layout(node, rect, o.tokens or T, o)
    end
    ui.interior = function(w, h)
      local bw = T.interior.inset
      return { x = bw, y = bw, w = w - 2 * bw, h = h - 2 * bw, radius = T.interior.radius }
    end
    Panel.configure({ ui = ui })
    local rendered
    local function backend()
      return {
        place = function() end,
        scrollsNatively = function() return true end,
        render = function(_, content, scroll) rendered = { content = content, scroll = scroll } end,
        show = function() end, hide = function() end, destroy = function() end,
        isShowing = function() return true end, scrollBy = function() return false end,
      }
    end
    local deps = { ui = ui, surface = function() return {} end, emptyState = Panel.emptyStateElements,
      backend = backend }
    local viewer = assert(env.loadfile(sidepanelPath))()
    local picture, late = case.picture, nil
    local function render(_, cb)
      if not picture then return cb(nil) end
      if picture.rendering then return end
      local img = { size = function() return { w = picture.w, h = picture.h } end }
      if picture.late then
        late = function() cb(img) end
        return
      end
      cb(img)
    end
    viewer.configure({
      previewPane = function(spec) return PreviewPane.new(deps, spec) end,
      ui = ui,
      limits = file.limits,
      emptyText = file.emptyText,
      peek = function(_, _, cb)
        cb(case.seen)
        return { cancel = function() end }
      end,
      thumbs = { handles = thumbs.handles, image = render },
    })
    viewer.dock(copy(file.frame))
    if case.path then
      viewer.show(util.row(case.path, { isDir = case.isDir == true }))
    else
      viewer.clear()
    end
    if late then late() end
    viewer.destroy()
    assert(rendered, "the pane drew nothing")
    local out = {}
    for i, el in ipairs(rendered.content) do out[i] = M.element(el) end
    return { elements = out, height = rendered.scroll.height, reset = rendered.scroll.reset }
  end

  return runner
end

local function rect(f)
  return { x = f.x or 0, y = f.y or 0, w = f.w, h = f.h }
end

local function color(c)
  c = c or {}
  return { red = c.red or 0, green = c.green or 0, blue = c.blue or 0, alpha = c.alpha or 1 }
end

--- M.element(el) -> one hs.canvas element as plain data, the fields the app's PaneItem carries. A
--- clip and its radius, a resetClip, a picture with its frame, alpha, scaling and alignment, or a
--- text with its string, frame, font, size, colour, alignment, line break, pinned line height and
--- whether it tightens. Anything else raises, since the pane has never drawn one.
function M.element(el)
  if el.type == "resetClip" then return { type = "resetClip" } end
  if el.type == "image" then
    return { type = "image", frame = rect(el.frame), alpha = el.imageAlpha, scaling = el.imageScaling,
      alignment = el.imageAlignment }
  end
  if el.type == "rectangle" and el.action == "clip" then
    return { type = "clip", frame = rect(el.frame), radius = el.roundedRectRadii and el.roundedRectRadii.xRadius or 0 }
  end
  if el.type == "text" and type(el.text) == "table" and el.text.styled then
    local a = el.text.attrs
    local p = a.paragraphStyle or {}
    assert(p.minimumLineHeight == p.maximumLineHeight, "a text whose line height is not pinned both ways")
    return { type = "text", frame = rect(el.frame), text = el.text.str, font = a.font.name, size = a.font.size,
      color = color(a.color), align = p.alignment, lineBreak = p.lineBreak, lineHeight = p.minimumLineHeight,
      tight = p.tighteningFactorForTruncation == 0 }
  end
  error("the pane drew an element the fixture does not carry, " .. tostring(el.type) .. " " .. tostring(el.action))
end

--- M.compare(want, got) -> a list of problems, empty when they agree, numbers within 1e-9.
function M.compare(want, got, path, problems)
  problems = problems or {}
  path = path or ""
  if type(want) == "number" and type(got) == "number" then
    if math.abs(want - got) > 1e-9 then problems[#problems + 1] = path .. " wanted " .. want .. ", got " .. got end
  elseif type(want) == "table" and type(got) == "table" then
    local keys = {}
    for k in pairs(want) do keys[k] = true end
    for k in pairs(got) do keys[k] = true end
    for k in pairs(keys) do M.compare(want[k], got[k], path .. "." .. tostring(k), problems) end
  elseif want ~= got then
    problems[#problems + 1] = path .. " wanted " .. tostring(want) .. ", got " .. tostring(got)
  end
  return problems
end

return M
