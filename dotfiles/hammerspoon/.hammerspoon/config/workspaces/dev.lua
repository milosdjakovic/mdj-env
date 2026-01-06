-- Dev workspace configuration
-- Data only - no logic

return {
  name = "dev",
  hotkey = { modifiers = { "shift", "alt" }, key = "D" },

  -- Apps in z-index order (first = bottom, last = top)
  apps = {
    "Safari",
    "GoogleChat",
    "Ghostty",
    "VisualStudioCode",
    "GoogleChrome",  -- Will be on top
  },

  -- Apps that should go to secondary display (if available)
  -- All other apps stay on primary
  secondaryDisplayApps = {
    -- For dev workspace, all apps go to secondary except GoogleChat
  },

  -- Apps that should always stay on primary (overrides secondaryDisplayApps)
  primaryDisplayApps = {
    "GoogleChat",
  },

  -- Sizing strategies per app
  -- Available actions: percentage, fullHeightReasonableWidth, resizeDefault, none
  strategies = {
    -- Used when only primary screen available
    primary = {
      VisualStudioCode = { action = "percentage", width = 97, height = 100 },
      GoogleChrome =     { action = "percentage", width = 97, height = 100 },
      Ghostty =          { action = "percentage", width = 90, height = 90 },
      GoogleChat =       { action = "percentage", width = 80, height = 90 },
      Safari =           { action = "percentage", width = 80, height = 90 },
    },
    -- Used when secondary screen available
    secondary = {
      VisualStudioCode = { action = "fullHeightReasonableWidth" },
      GoogleChrome =     { action = "percentage", width = 90, height = 90 },
      Ghostty =          { action = "resizeDefault" },
      GoogleChat =       { action = "percentage", width = 80, height = 90 },  -- stays on primary
      Safari =           { action = "fullHeightReasonableWidth" },
    },
  },
}
