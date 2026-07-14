--- Capture provider, macOCR CLI.
---
--- Backed by schappim's macOCR (the `ocr` binary, brew install schappim/ocr/ocr).
--- Run with no arguments it lets you drag a screen region, OCRs it, and copies
--- the recognized text to the clipboard, so it is the text counterpart to the
--- screenshot providers. It draws its own region selection, so unlike native it
--- synthesizes no keystrokes. The engine already waits for the Hyper key to be
--- released before dispatch, which is all the selection overlay needs to own
--- Escape and Enter.
---
--- All macOCR knowledge lives here, its binary name and the one action it serves.
--- It supports only ocrArea, so the screenshot actions fall through to the other
--- providers and ocrArea falls through to it. available() resolves the binary on
--- the user's login PATH, so it works on both Apple Silicon (/opt/homebrew/bin)
--- and Intel (/usr/local/bin) with no path hardcoded, and steps aside cleanly on
--- a machine where it is not installed.

return {
  name = "macocr",
  binary = "ocr",
  actions = { ocrArea = true },

  -- Absolute path resolved by available() and consumed by trigger(). Dispatch
  -- always calls available() immediately before trigger(), so this field is the
  -- one seam between them, the liveness check and the launch share the exact
  -- path it found rather than resolving twice or hardcoding a location.
  _resolved = nil,

  available = function(self)
    -- Resolve on the user's login PATH so both Homebrew prefixes work without
    -- hardcoding either. Trim the trailing newline command -v prints.
    local path = hs.execute("command -v " .. self.binary, true) or ""
    path = path:gsub("%s+$", "")
    if path == "" then
      self._resolved = nil
      return false, "not installed (brew install schappim/ocr/ocr)"
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
