--- Capture provider, macOCR CLI.
---
--- Backed by an OCR command line tool that, run with no arguments, lets you drag a
--- screen region, OCRs it, and copies the recognized text to the clipboard, so it is
--- the text counterpart to the screenshot providers. It draws its own region
--- selection, so unlike native it synthesizes no keystrokes. The engine already
--- waits for the Hyper key to be released before dispatch, which is all the
--- selection overlay needs to own Escape and Enter.
---
--- All knowledge of that tool lives here, the name it is declared under and the one
--- action it serves. It supports only ocrArea, so the screenshot actions fall
--- through to the other providers and ocrArea falls through to it.
---
--- It resolves nothing itself. The engine hands it the dependency adapter and it
--- asks for the tool by the name this spoon declared, so the probing happens once
--- for the whole config, no path or Homebrew prefix is hardcoded, and this file
--- names no way to install anything. It steps aside cleanly when the tool is absent.

return {
  name = "macocr",
  -- The name this tool is declared under in the spoon's dependencies file. Both the
  -- declaration and this lookup use it, so a rename is caught by the adapter rather
  -- than failing silently.
  tool = "ocr",
  actions = { ocrArea = true },

  -- Absolute path handed over by available() and consumed by trigger(). Dispatch
  -- always calls available() immediately before trigger(), so this field is the
  -- one seam between them, the liveness check and the launch share the exact
  -- path it found rather than resolving twice or hardcoding a location.
  _resolved = nil,

  available = function(self, deps)
    if not deps then
      self._resolved = nil
      return false, "no dependency adapter injected"
    end
    local path = deps.path(self.tool)
    if not path then
      self._resolved = nil
      return false, "not installed"
    end
    self._resolved = path
    return true
  end,

  supports = function(self, action)
    return self.actions[action] == true
  end,

  trigger = function(self)
    if not self._resolved then
      return false
    end
    -- Detached: the tool blocks while you drag the selection, so a synchronous
    -- run would freeze Hammerspoon for the whole capture. hs.task runs it off
    -- the main loop. No arguments means interactive select, OCR, copy to
    -- clipboard.
    hs.task.new(self._resolved, nil):start()
    return true
  end,
}
