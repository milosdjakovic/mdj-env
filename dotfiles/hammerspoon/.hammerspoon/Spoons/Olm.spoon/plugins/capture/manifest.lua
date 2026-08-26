-- Capture, what it declares about itself.
--
-- A Chain of Responsibility over screenshot and recording backends, so what it needs from
-- outside Hammerspoon belongs to whichever provider file actually knows the tool rather
-- than to this root file. macocr's own declaration names the OCR backend and macshot's own
-- names the preferred screenshot backend, both optional since native, the tail of the
-- chain, always handles a screenshot or a recording, and OCR simply answers unavailable
-- with no backend installed.
return {
  needs = {
    -- Dispatch waits for the Hyper key to release before running, so a synthetic keystroke
    -- is not swallowed by the same tap that is holding the leader down, and bindHotkeys binds
    -- into HyperKey's modal rather than a literal combo. Optional, matching AppToggler,
    -- because bindHotkeys already falls back to the literal modifiers combo when this is
    -- absent.
    lib = {
      hyperKey = { from = "hyperkey", policy = "optional" },
    },
    tools = {
      { name = "ocr", kind = "path", locator = "ocr", policy = "optional", unit = "macocr",
        reason = "the OCR backend, the sole handler of text capture",
        origin = { tap = "schappim/ocr/ocr" } },
      { name = "macshot", kind = "app", locator = "com.sw33tlie.macshot.macshot", policy = "optional", unit = "macshot",
        reason = "the preferred screenshot backend, native is the fallback",
        origin = { manual = "install the macshot app, then enable its URL scheme in its settings" } },
      -- Delivering a macshot URL without bringing macshot to the front, the -g flag reaches
      -- through open rather than through hs.urlevent.openURL. Optional, and its absence
      -- costs only this one backend, native still handles a screenshot or a recording.
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional", unit = "macshot",
        reason = "delivering the macshot url in the background, without raising macshot",
        origin = { macos = "ships with the system" } },
    },
    -- The per consumer dependency adapter that turns a tool name into an absolute path is
    -- not named here on purpose. It is already ambient the moment needs.tools is non
    -- empty, which it is above, so a second line naming it would only restate that.
    data = {
      -- The order the provider chain is tried in, a plain priority list of NAMES the person
      -- edits in their own config as settings.capture.providers. Resolved against this plugin's
      -- own provider registry by this plugin, the only layer allowed to know which file answers
      -- to which word, so nothing outside it ever holds a backend.
      --
      -- The person's own rather than root computed, which is what this claimed to be. Owed by a
      -- file that is not allowed to name this plugin, it was paid by nobody, and the three words
      -- in settings were read by nothing at all, so reordering the chain changed nothing.
      -- Optional either way, since the engine falls back to its own shipped order.
      providers = { source = "user", policy = "optional",
        breaks = "the capture chain runs fine in its own shipped default order, " ..
                 "macshot then native then macocr, and only ignores the person's own choice " ..
                 "if they set one in settings.capture.providers" },
    },
  },

  -- What this plugin proposes for its own four actions, each on the app leader's Hyper
  -- modal. Short and specific to this plugin's own action names, unlike windowmanager's
  -- much larger table, so it is stated here rather than pointed at as user configuration.
  -- This plugin has no picker and no registration of its own, so it would appear in the
  -- launcher's list nowhere at all, yet its four actions are exactly the kind of thing a
  -- person looks for by typing screenshot. Declaring actionRows is how it says that each of
  -- its own keyed actions deserves a row, which the launcher asks the set for rather than
  -- naming this plugin. The rows are then built from the bindings below, so a key moved here
  -- moves in the list too and no copy of it exists anywhere else.
  provides = {
    actionRows = true,
  },

  defaults = {
    leader = "app",
    bindings = {
      { action = "ocrArea", key = "3", description = "OCR", glyph = "🔤" },
      { action = "captureAreaClipboard", key = "4", description = "Screenshot (copy)", glyph = "📸" },
      { action = "captureArea", key = "4", mods = { "shift" }, description = "Screenshot", glyph = "📸" },
      { action = "recordArea", key = "5", description = "Record screen", glyph = "🎥" },
    },
  },

  -- configure alone never binds a key. bindHotkeys is a separate call the composition
  -- root makes with the effective bindings table above, after any user override has been
  -- merged into it, so it is named here as a step beyond configure rather than left for
  -- someone to notice the four capture keys do nothing.
  wiring = {
    { method = "bindHotkeys", args = { "self.bindings" } },
  },
}
