-- Capture, what it declares about itself.
--
-- A Chain of Responsibility over screenshot and recording backends, so what it needs from
-- outside Hammerspoon belongs to whichever provider file actually knows the tool rather
-- than to this root file. macocr's own declaration names the OCR backend and macshot's own
-- names the preferred screenshot backend, both optional since native, the tail of the
-- chain, always handles a screenshot or a recording, and OCR simply answers unavailable
-- with no backend installed.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Screen Capture",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The icons the capture actions name, in the emoji set and the SF Symbol set. A binding below
  -- names one and the launcher row for that action wears it.
  icons = {
    ocr = { emoji = "🔤", sf = "text.viewfinder" },
    screenshot = { emoji = "📸", sf = "camera" },
    record = { emoji = "🎥", sf = "video" },
  },

  needs = {
    -- Dispatch waits for the Hyper key to release before running, so a synthetic keystroke
    -- is not swallowed by the same tap that is holding the leader down. Optional, since without
    -- it a capture simply starts at once.
    lib = {
      hyperKey = { from = "hyperkey", policy = "optional" },
    },
    tools = {
      { name = "ocr", kind = "path", locator = "ocr", policy = "optional", unit = "macocr",
        reason = "the OCR backend, the sole handler of text capture",
        origin = { tap = "schappim/ocr/ocr" } },
      -- Installing the cask is not the whole story, the URL scheme still has to be enabled
      -- once in macshot's own settings, and the provider says exactly that at runtime when
      -- the scheme is off, so the instruction lives where the failure is seen.
      { name = "macshot", kind = "app", locator = "com.sw33tlie.macshot.macshot", policy = "optional", unit = "macshot",
        reason = "the preferred screenshot backend, native is the fallback",
        -- Manual rather than cask, because this is an opt in extra the Brewfile deliberately
        -- does not carry. A default install should not put a screenshot app on a machine that
        -- never asked for one, and native already answers here.
        origin = { manual = "the macshot cask, installed by hand when this backend is wanted" } },
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

  -- What this plugin can run is its actions, one descriptor per capture action, and Olm binds
  -- the keys the bindings below suggest to those descriptors, so this plugin binds nothing. It
  -- has no picker and no registration of its own, so it would appear in the launcher's list
  -- nowhere at all, yet its four actions are exactly the kind of thing a person looks for by
  -- typing screenshot. Declaring launcherRows is how it says that each of its own keyed actions
  -- deserves a row, which the launcher asks the set for rather than naming this plugin, and
  -- launcherRun is how a chosen row comes back here to run. The rows are built from the
  -- bindings below, so a key moved here moves in the list too and no copy of it exists anywhere
  -- else.
  provides = {
    actions = "actions",
    launcherRows = "launcherRows",
    launcherRun = "launcherRun",
  },

  defaults = {
    leader = "app",
    -- Where these four rows sit in the launcher's own catalog, a number compared with every
    -- other contributor's and with the launcher's own. Ten leads every other contributed row,
    -- where the screenshot actions have always been. A person moves them in
    -- config/plugins.lua like any default.
    launcherOrder = 10,
    bindings = {
      { action = "ocrArea", key = "3", description = "OCR", icon = "ocr" },
      { action = "captureAreaClipboard", key = "4", description = "Screenshot (copy)", icon = "screenshot" },
      { action = "captureArea", key = "4", mods = { "shift" }, description = "Screenshot", icon = "screenshot" },
      { action = "recordArea", key = "5", description = "Record screen", icon = "record" },
    },
  },
}
