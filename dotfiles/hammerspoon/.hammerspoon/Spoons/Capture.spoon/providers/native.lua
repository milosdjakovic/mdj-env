--- Capture provider, native macOS shortcuts.
---
--- Backed by the built-in macOS screenshot shortcuts, synthesized with
--- hs.eventtap.keyStroke. All key chord knowledge lives here, so the Capture
--- engine stays ignorant of chords. Always available, so this belongs last in
--- the chain as the universal fallback.
---
---   captureArea           Cmd+Shift+4        area to a file
---   captureAreaClipboard  Cmd+Ctrl+Shift+4   area to the clipboard (Ctrl added)
---   recordArea            Cmd+Shift+5        the capture toolbar, which includes
---                                            recording, since macOS has no
---                                            shortcut that starts an area
---                                            recording directly

return {
  name = "native",
  chords = {
    captureArea = { mods = { "cmd", "shift" }, key = "4" },
    captureAreaClipboard = { mods = { "cmd", "ctrl", "shift" }, key = "4" },
    recordArea = { mods = { "cmd", "shift" }, key = "5" },
  },
  -- The baseline: the OS shortcuts are always present, so this is always true.
  available = function()
    return true
  end,
  supports = function(self, action)
    return self.chords[action] ~= nil
  end,
  trigger = function(self, action)
    local chord = self.chords[action]
    if not chord then
      return false
    end
    hs.eventtap.keyStroke(chord.mods, chord.key, 0)
    return true
  end,
}
