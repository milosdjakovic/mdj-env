-- Global settings
-- All configurable values in one place

return {
  -- Stage Manager margin (pixels to offset from left when active)
  stageManagerMargin = 66,

  -- Window animation (0 = instant)
  windowAnimationDuration = 0,

  -- Terminal handler timing
  terminal = {
    initialDelay = 0.1,       -- Wait before checking if app is ready
    checkInterval = 0.25,     -- How often to poll for readiness
    maxAttempts = 20,         -- Maximum polls before giving up
    preferredTerminal = "Ghostty",  -- App name from config/apps.lua
  },

  -- Workspace timing
  workspace = {
    checkInterval = 0.5,      -- How often to poll for app readiness
    timeout = 30,             -- Max seconds to wait per app
  },

  -- Window sizing defaults
  windowSizing = {
    maxWidth = 1800,
    maxHeight = 1200,
    fullHeightMaxWidth = 2400,
    movePixels = 20,
    resizePixels = 50,
    screenRecording = { width = 2400, height = 1350 },
    smallSize = { width = 700, height = 800 },
  },
}
