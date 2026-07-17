-- Global settings
-- All configurable values in one place

return {
  -- Stage Manager margin (pixels to offset from left when active)
  stageManagerMargin = 66,

  -- Gap around and between managed windows, in pixels. One value drives both the
  -- outer inset (the margins in init.lua) and the gutter between tiled halves, so
  -- the spacing stays uniform. Set to 0 to disable gaps entirely (windows go
  -- flush to the screen edges and to each other). The Stage Manager margin above
  -- is respected independently of this.
  gap = 0,

  -- Window animation (0 = instant)
  windowAnimationDuration = 0,

  -- Terminal handler timing
  terminal = {
    initialDelay = 0.1,       -- Wait before checking if app is ready
    checkInterval = 0.25,     -- How often to poll for readiness
    maxAttempts = 20,         -- Maximum polls before giving up
    preferredTerminal = "Ghostty",  -- App name from config/apps.lua
    size = { width = 2400, height = 1350 },
    minPadding = { x = 40, y = 20 },
  },

  -- Workspace timing
  workspace = {
    checkInterval = 0.5,      -- How often to poll for app readiness
    timeout = 30,             -- Max seconds to wait per app
  },

  -- Cheat-sheet overlay appearance (the Hyper and SUPER modals). One place
  -- for how EVERY overlay looks; the shared CheatSheet renderer applies it to
  -- all of them. Per-overlay layout (column count, icons) stays in the spoons.
  -- Colours are 0-1 RGB; opacity is the panel's alpha. Omit any field to keep
  -- the built-in default.
  cheatSheet = {
    opacity = 0.95,                                    -- panel background alpha
    background = { red = 0.09, green = 0.09, blue = 0.11 }, -- panel colour
    cornerRadius = 16,                                 -- panel corner roundness
    badgeRadius = 6,                                   -- key-badge roundness
    fontSize = 16,
    padding = 28,                                      -- inner margin around content
  },

  -- Picker backend. The Chooser facade has two swappable backends, "native" (the
  -- built in hs.chooser) and "web" (the themed webview list on the Surface spoon).
  -- This one word picks the default for every chooser consumer, the clipboard, the
  -- VPN locations, and the command palette, so switching them all is one edit. The
  -- native backend stays available as a fallback. A single consumer can still
  -- override this with config.provider when a backend is migrated one at a time.
  chooserProvider = "native",

  -- Chooser theme. One source for how the searchable chooser and its docked
  -- preview look in light and dark. The clipboard reads it today; a future
  -- chooser based tool (and later the cheat sheets) can read the same source, so
  -- one edit restyles them all. The active side is picked per open from the live
  -- system appearance, so it tracks the automatic light and dark switch. Each
  -- side names the chooser background flag, the two row text colours (styledtext
  -- white values, since a styled row must restate its colour), and the preview
  -- webview colours (CSS hex). Omit the light block to fall back to dark.
  chooserTheme = {
    dark = {
      bgDark = true,
      titleColor = { white = 0.92 },
      subColor = { white = 0.55 },
      preview = { bg = "#1e1e22", fg = "#dcdcdc", meta = "#8a8a8a", path = "#7a7a7a", note = "#c8a86a" },
    },
    light = {
      bgDark = false,
      titleColor = { white = 0.15 },
      subColor = { white = 0.42 },
      preview = { bg = "#f2f2f5", fg = "#1c1c1e", meta = "#6b6b70", path = "#88888d", note = "#8a5a12" },
    },
  },

  -- Window sizing defaults
  windowSizing = {
    maxWidth = 2400,
    maxHeight = 1350,
    fullHeightMaxWidth = 2400,
    movePixels = 20,
    resizePixels = 50,
    screenRecording = { width = 2400, height = 1350 },
    smallSize = { width = 700, height = 800 },
  },
}
