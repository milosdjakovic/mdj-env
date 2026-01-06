-- Vicert workspace configuration
-- Data only - no logic

return {
  name = "vicert",
  hotkey = { modifiers = { "shift", "alt" }, key = "V" },

  -- Apps in z-index order (first = bottom, last = top)
  apps = {
    "Safari",
    "GoogleChrome",
    "Bruno",
    "Docker",
    "Ghostty",
    "Slack",
    "Claude",  -- Will be on top
  },

  -- Apps that should go to secondary display (if available)
  secondaryDisplayApps = {
    "GoogleChrome",
    "Safari",
  },

  -- Apps that should always stay on primary
  primaryDisplayApps = {},

  -- Sizing strategies per app
  strategies = {
    -- Used when only primary screen available
    primary = {
      Claude =       { action = "percentage", width = 90, height = 90 },
      Slack =        { action = "percentage", width = 80, height = 90 },
      Ghostty =      { action = "none" },  -- Just launch, don't resize
      Docker =       { action = "percentage", width = 80, height = 80 },
      Bruno =        { action = "percentage", width = 80, height = 90 },
      GoogleChrome = { action = "percentage", width = 97, height = 100 },
      Safari =       { action = "percentage", width = 80, height = 90 },
    },
    -- Used when secondary screen available
    secondary = {
      Claude =       { action = "percentage", width = 90, height = 90 },
      Slack =        { action = "percentage", width = 80, height = 90 },
      Ghostty =      { action = "none" },  -- Just launch, don't resize
      Docker =       { action = "percentage", width = 80, height = 80 },
      Bruno =        { action = "percentage", width = 80, height = 90 },
      GoogleChrome = { action = "percentage", width = 90, height = 90 },
      Safari =       { action = "fullHeightReasonableWidth" },
    },
  },
}
