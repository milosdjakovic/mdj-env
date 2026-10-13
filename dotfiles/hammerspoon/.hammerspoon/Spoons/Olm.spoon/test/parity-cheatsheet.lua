-- Parity probe for lib/cheatsheet.lua, stage two of docs/DESIGN-UI-KIT.md. Run through
-- test/parity.sh, which exports the old tree and names it in PARITY_ARGS. Builds the grid
-- for three fixed models, shaped like the Hyper sheet with its dormant fade, like the window
-- sheet with content sized badges and separators, and with every layout default, through the
-- old file and the new one, which draws every leaf through the kit, and reports every
-- difference, the content size included.

local source = debug.getinfo(1, "S").source
local here = (source:match("^@(.*)$") or source):match("^(.*/)")
local lib = dofile(here .. "parity-lib.lua")

local ok, err = pcall(function()
  local policy = lib.policy()
  local ui = lib.newUI(policy)
  local cs = policy.cheatSheet or {}
  local icon = hs.image.imageFromName("NSCaution")

  local function sheet(path, opts)
    local obj = dofile(path)
    obj:init()
    obj:configure(opts)
    return obj
  end
  local old = sheet(lib.old .. "lib/cheatsheet.lua", { theme = policy.chooserTheme,
    fontSize = cs.fontSize, lineHeight = cs.lineHeight, badgeRadius = cs.badgeRadius,
    padding = cs.padding, canvasPanel = lib.fakePanel() })
  local new = sheet(lib.new .. "lib/cheatsheet.lua", { ui = ui, padding = cs.padding,
    canvasPanel = lib.fakePanel() })

  local function apps(names, withIcon)
    local rows = {}
    for i, n in ipairs(names) do
      rows[i] = { badge = n:sub(1, 1):upper(), label = n, icon = withIcon and icon or nil }
    end
    return rows
  end
  local models = {
    { name = "the Hyper shape", model = {
      columns = 4, colWidth = 215, rowHeight = 48, badgeWidth = 28, badgeHeight = 28,
      iconSize = 32, gap = 10, groupGap = 20, sections = {
        { title = "OPEN", rows = apps({ "Chrome", "Terminal", "Finder", "Mail", "Activity Monitor" }, true) },
        { title = "DORMANT", alpha = 0.55, titleAlpha = 1.0, rows = apps({ "Xcode", "Notes", "Zed" }, true) },
        { title = "SERVICES", columns = 4, colWidth = 215, iconSize = 0,
          rows = apps({ "OCR", "Screenshot", "Record screen", "Lock" }, false) },
      } } },
    { name = "the window shape", model = {
      columns = 2, colWidth = 250, rowHeight = 44, badgeWidth = 44, badgeHeight = 28, gap = 12,
      sections = {
        { title = "MOVE", rows = {
          { badge = "⇧←", label = "Left half" },
          { badges = { "H", "←" }, label = "Left" },
          { badges = { "⌘K", "⌥⇧J" }, sep = "then", label = "A chord with a very long label indeed" },
          { badge = "↩", label = "Maximise" },
        } },
        { rows = { { badge = "esc", label = "Close" }, { badges = { "i" }, label = "Narrow" } } },
      } } },
    { name = "every default", model = { sections = {
      { title = "KEYS", rows = { { badge = "A", label = "Alpha" }, { badge = "B", label = "Beta" },
                                 { badge = "C", label = "Gamma" } } } } } },
  }

  for _, half in ipairs(lib.halves) do
    for _, m in ipairs(models) do
      local ob = lib.withHalf(half, function() old._model = m.model; return old:_build() end)
      local nb = lib.withHalf(half, function() new._model = m.model; return new:_build() end)
      lib.check("cheat sheet, " .. m.name .. ", " .. half, ob.els, nb.els, ob.w + 40, ob.h + 40,
        { lib.sizeDiff("content size", ob, nb) })
    end
  end
  lib.summary()
end)
if not ok then lib.out("ERROR " .. tostring(err)) end
lib.done()
