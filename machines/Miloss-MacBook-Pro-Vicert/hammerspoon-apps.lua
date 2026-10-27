-- This machine's Hyper app keys. It replaces machines/default/hammerspoon-apps.lua whole, so the
-- default's keys are repeated here and this machine's own follow. That file's header has the shape.

return {
  keys = {
    -- Shipped with macOS
    ["hyper+B"] = "apptoggler.Books",
    ["hyper+F"] = "apptoggler.Finder",
    ["hyper+M"] = "apptoggler.Mail",
    ["hyper+S"] = "apptoggler.Safari",
    ["hyper+N"] = "apptoggler.Notes",
    ["hyper+I"] = "apptoggler.iPhoneMirroring",
    ["hyper+R"] = "apptoggler.Preview",
    ["hyper+T"] = "apptoggler.Stickies",
    ["hyper+\\"] = "apptoggler.ActivityMonitor",
    ["hyper+,"] = "systemsettings.General",

    -- Installed by the Brewfile
    ["hyper+`"] = "apptoggler.Ghostty",
    ["hyper+O"] = "apptoggler.Obsidian",
    ["hyper+D"] = "apptoggler.Docker",

    -- This machine's own
    ["hyper+C"] = "apptoggler.GoogleChrome",
    ["hyper+V"] = "apptoggler.VisualStudioCode",
    ["hyper+Z"] = "apptoggler.Zed",
    ["hyper+L"] = "apptoggler.Slack",
    ["hyper+A"] = "apptoggler.Claude",
  },

  apps = {},
}
