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
