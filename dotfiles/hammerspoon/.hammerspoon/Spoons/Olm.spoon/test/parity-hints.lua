-- Parity probe for lib/hints.lua, stage two of docs/DESIGN-UI-KIT.md. Run through
-- test/parity.sh, which exports the old tree and names it in PARITY_ARGS. Builds the docked
-- shortcut bar for a fixed context at two widths, and the message, colour and report toasts
-- for fixed states, through the old file and the new one, which draws through the kit, and
-- reports every difference, the preferred sizes included since a toast's size places it.

local source = debug.getinfo(1, "S").source
local here = (source:match("^@(.*)$") or source):match("^(.*/)")
local lib = dofile(here .. "parity-lib.lua")

local ok, err = pcall(function()
  local policy = lib.policy()
  local ui = lib.newUI(policy)
  local oldHints = dofile(lib.old .. "lib/hints.lua")
  local newHints = dofile(lib.new .. "lib/hints.lua")
  local glyphFor = dofile(lib.old .. "lib/cheatsheet.lua").glyphFor

  local plan = { contexts = { list = { bindings = {
    { action = "enter", key = "o", description = "Open" },
    { action = "closeChooser", key = "w", description = "Close" },
    { action = "selectNext", key = "j", description = "Next" },
    { action = "selectPrev", key = "k", description = "Previous" },
    { action = "copyPath", key = "c", mods = { "shift" }, description = "Copy path" },
    { action = "reveal", key = "r", description = "Reveal in Finder", chord = false },
    { action = "preview", key = "space", description = "Toggle preview" },
    { action = "remove", key = ",", description = "Remove", chord = false },
    { action = "pin", key = "i", description = "" },
  } } } }

  local function contentFor(hintsLib, extra)
    local fake = lib.fakePanel()
    local deps = { predicates = {}, glyphFor = glyphFor, leaderName = "Hyper",
      chordLabel = function(leader, key, mods) return leader .. " " .. glyphFor(key, mods) end,
      canvasPanel = fake, settings = {} }
    for k, v in pairs(extra) do deps[k] = v end
    hintsLib.shortcutPanelFor("list", plan, deps)
    return fake.content
  end

  for _, half in ipairs(lib.halves) do
    for _, w in ipairs({ 592, 300 }) do
      local oldSize, old = lib.withHalf(half, function()
        local c = contentFor(oldHints, { theme = policy.chooserTheme })
        return c.preferredSize(w), c.draw(w)
      end)
      local newSize, new = lib.withHalf(half, function()
        local c = contentFor(newHints, { ui = ui })
        return c.preferredSize(w), c.draw(w)
      end)
      lib.check("hint bar at " .. w .. ", " .. half, old, new, w + 40, oldSize.h + 40,
        { lib.sizeDiff("preferred size", oldSize, newSize) })
    end

    local oldToast = oldHints.toast({ theme = policy.chooserTheme })
    local newToast = newHints.toast({ ui = ui })
    local icon = hs.image.imageFromName("NSCaution")
    local function both(name, build)
      local oldSize, old = lib.withHalf(half, function()
        local c = build(oldToast)
        local s = c.preferredSize()
        return s, c.draw(s.w, s.h)
      end)
      local newSize, new = lib.withHalf(half, function()
        local c = build(newToast)
        local s = c.preferredSize()
        return s, c.draw(s.w, s.h)
      end)
      lib.check(name .. ", " .. half, old, new, oldSize.w + 40, oldSize.h + 40,
        { lib.sizeDiff("preferred size", oldSize, newSize) })
    end
    both("message toast", function(t) return t.message({ text = "Appended to the clipboard entry" }) end)
    both("colour toast", function(t)
      return t.color({ hex = "#3a7bd5", color = { red = 0x3a / 255, green = 0x7b / 255, blue = 0xd5 / 255, alpha = 1 } })
    end)
    both("report toast", function(t)
      return t.list({ title = "Not open", secondsLeft = 4, rows = {
        { icon = icon, label = "Google Chrome", detail = "not running" },
        { icon = icon, label = "A very long application name that will truncate", detail = "missing", dim = true },
        { label = "Terminal", detail = "skipped" },
      } }, function() end)
    end)
    both("report toast with no rows", function(t)
      return t.list({ title = "Nothing to do", secondsLeft = 0, rows = {} }, function() end)
    end)
  end
  lib.summary()
end)
if not ok then lib.out("ERROR " .. tostring(err)) end
lib.done()
