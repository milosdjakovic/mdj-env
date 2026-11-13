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
    ["hyper+O"] = "apptoggler.Obsidian",
    ["hyper+D"] = "apptoggler.Docker",

    -- This machine's own
    ["hyper+`"] = "apptoggler.Herdr",
    ["hyper+C"] = "apptoggler.GoogleChrome",
    ["hyper+G"] = "apptoggler.GoogleChat",
    ["hyper+V"] = "apptoggler.VisualStudioCode",
    ["hyper+Z"] = "apptoggler.Zed",
    ["hyper+L"] = "apptoggler.Slack",
    ["hyper+A"] = "apptoggler.Claude",

    -- The trial key of Olm's step 3.2, Olm.app's own launcher while Hyper and Space opens the Lua
    -- one, chosen by Milos on 2026-11-13. It goes when the flip of step 3.5 gives the app Hyper
    -- and Space.
    ["hyper+0"] = "bridge.launcher",
  },

  apps = {
    -- The Google Chat web app as Chrome installed it here.
    GoogleChat = "com.google.Chrome.app.pommaclcbfghclhalboakcipcmmndhcj",
  },
}
