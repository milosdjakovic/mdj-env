--- === Canvas picker provider ===
---
--- The default provider, the chooser engine composed with the canvas view. Read
--- docs/CONTRACT-PICKER.md first, it is the specification the instance satisfies, and its
--- section on the engine and the view says why the provider is two halves.
---
--- lib/chooser/engine/init.lua owns every picker rule and all state, and implements the
--- twenty five contract methods and the extras the stage calls. canvas.lua beside this file is
--- the view, the surface, the field, the rows, the action bar, the pointer and the key tap, and
--- satisfies lib/chooser/view.lua. This file only names the two and wires them, the Bridge
--- pattern's composition, so the engine never names a concrete view and the view never holds a
--- rule. Until 2026-10-28 all of it was this one file, and the split changed no behaviour, see
--- decisions/olm-swift-chooser.md.
---
--- M.configure(opts) takes opts.panel, the CanvasPanel module, and opts.ui, the UI kit, both
--- injected here rather than loaded by path, since lib/panel.lua holds the shared surface style
--- and lib/ui the shared style the composition root configures exactly once, and a second copy
--- loaded fresh by path would answer an unconfigured module and draw something that does not
--- match every other surface in this configuration. It also takes opts.icon, opts.iconElements,
--- opts.yields, opts.listKeys and opts.focusHold, each forwarded to the half that reads it.
--- Whatever calls M.new is expected to have called M.configure first, and M.new refuses with a
--- plain reason when the panel or the kit is missing rather than drawing something that looks
--- subtly wrong.
---
--- It delivers no offline unit case of its own, this is a shell wiring real resources together,
--- so its coverage is the live probe at Spoons/Olm.spoon/test/probe-canvaspicker.lua and the unit
--- cases that drive a real instance with show replaced.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(relPath)
  local chunk, err = loadfile(herePath .. relPath)
  if not chunk then
    error("Canvas provider: failed to load " .. relPath .. ", " .. tostring(err))
  end
  return chunk()
end

local Engine = load("../../engine/init.lua")
local Canvas = load("canvas.lua")

-- Whether configure has been handed the panel and the kit, kept only so new can refuse with
-- the reason that names the missing one, in the order it always has.
local PANEL = nil
local UI = nil

local M = {}

--- M.configure(opts) takes opts.panel, the CanvasPanel module, and opts.ui, the UI kit, and
--- optionally opts.icon, the icon resolver function(icon, owner) -> hs.image or nil, opts.iconElements,
--- the same icon as canvas elements function(icon, owner, frame) -> elements or nil, which a row
--- draws through, and opts.yields, a function(event) answering true for a key down the field's tap
--- must let through instead of claiming, and opts.listKeys, a function(event) that runs a list key
--- the open list binds with no held leader and answers true when it took the key, and opts.focusHold,
--- a function answering a release function or nil, asked once per open after the surface shows and
--- released on teardown. Callable more than once, a nil field left unchanged, matching
--- CanvasPanel.configure's own idiom. Whatever calls M.new is expected to have called this first.
function M.configure(opts)
  opts = opts or {}
  if opts.panel ~= nil then PANEL = opts.panel end
  if opts.ui ~= nil then UI = opts.ui end
  Engine.configure({ ui = opts.ui, yields = opts.yields, listKeys = opts.listKeys,
    focusHold = opts.focusHold })
  Canvas.configure({ panel = opts.panel, ui = opts.ui, icon = opts.icon,
    iconElements = opts.iconElements })
  return M
end

--- M.uses(keyCode, mods) -> string or nil
--- What the field or this provider already does with a chord, in a few words, or nil when neither
--- reads it, the engine's answer with the canvas field's own keymap behind it. See the engine's
--- M.uses for the rules.
function M.uses(keyCode, mods)
  return Engine.uses(keyCode, mods, Canvas.fieldOp)
end

--- M.new(config) answers an instance satisfying lib/chooser/contract.lua exactly, validated by
--- the engine at construction and raised on a gap. Refuses outright when M.configure has not been
--- called with a panel, rather than drawing a surface with no shared chrome, which would look
--- subtly wrong instead of loudly missing.
function M.new(config)
  if not PANEL then
    error("Canvas provider: M.configure must be called with opts.panel, the CanvasPanel "
      .. "module, before M.new can build an instance, wiring this at the composition "
      .. "root is phase four and nothing has done it yet")
  end
  if not UI then
    error("Canvas provider: M.configure must be called with opts.ui, the UI kit, before "
      .. "M.new can build an instance, since every colour and the type come from its tokens")
  end
  return Engine.new(config, Canvas.new)
end

return M
