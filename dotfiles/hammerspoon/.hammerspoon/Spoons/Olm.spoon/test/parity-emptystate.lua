-- Parity probe for CanvasPanel.emptyStateElements, stage two of docs/DESIGN-UI-KIT.md. Run
-- through test/parity.sh, which exports the old tree and names it in PARITY_ARGS. Builds the
-- empty state for a fixed set of boxes and options through the old lib/panel.lua and the new
-- one, which draws through the kit, and reports every difference. The four plugins that call
-- it all pass their own colour, so most cases do too.

local source = debug.getinfo(1, "S").source
local here = (source:match("^@(.*)$") or source):match("^(.*/)")
local lib = dofile(here .. "parity-lib.lua")

local ok, err = pcall(function()
  local policy = lib.policy()
  local ui = lib.newUI(policy)
  local oldPanel = dofile(lib.old .. "lib/panel.lua")
  local newPanel = dofile(lib.new .. "lib/panel.lua")
  newPanel.configure({ ui = ui })

  local meta = { red = 0x8a / 255, green = 0x8a / 255, blue = 0x8a / 255, alpha = 1 }
  local cases = {
    { name = "default options", w = 300, h = 200 },
    { name = "a caller colour", w = 300, h = 200, opts = { color = meta } },
    { name = "a caller text and colour", w = 420, h = 260,
      opts = { text = "No files match this query", color = meta } },
    { name = "a caller size", w = 300, h = 200, opts = { size = 15, color = meta } },
    { name = "a narrow box that wraps", w = 90, h = 120,
      opts = { text = "Nothing to preview here at all", color = meta } },
  }
  for _, half in ipairs(lib.halves) do
    for _, c in ipairs(cases) do
      local old = lib.withHalf(half, function() return oldPanel.emptyStateElements(c.w, c.h, c.opts) end)
      local new = lib.withHalf(half, function() return newPanel.emptyStateElements(c.w, c.h, c.opts) end)
      lib.check("empty state, " .. c.name .. ", " .. half, old, new, c.w + 40, c.h + 40)
    end
  end
  lib.summary()
end)
if not ok then lib.out("ERROR " .. tostring(err)) end
lib.done()
