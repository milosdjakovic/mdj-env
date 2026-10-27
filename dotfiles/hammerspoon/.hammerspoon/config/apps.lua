-- App bundle ID registry
-- The app toggler reads it as its own data, through the apptoggler entry in config/plugins.lua.
-- The browserTabs entry there reads Chrome's id from it too.
-- Get app identifier: osascript -e 'id of app "APP_NAME"'

return {
  -- System
  Finder = "com.apple.finder",
  Mail = "com.apple.mail",
  Books = "com.apple.iBooksX",
  Notes = "com.apple.Notes",
  Stickies = "com.apple.Stickies",
  Safari = "com.apple.Safari",
  Preview= "com.apple.Preview",
  ActivityMonitor = "com.apple.ActivityMonitor",
  SystemSettings = "com.apple.systempreferences",

  -- Terminals
  Terminal = "com.apple.Terminal",
  Warp = "dev.warp.Warp-Stable",
  Alacritty = "org.alacritty",
  Kitty = "net.kovidgoyal.kitty",
  WezTerm = "com.github.wez.wezterm",
  Ghostty = "com.mitchellh.ghostty",

  -- Editors
  VisualStudioCode = "com.microsoft.VSCode",
  Zed = "dev.zed.Zed",
  Cursor = "com.todesktop.230313mzl4w4u92",
  PyCharm = "com.jetbrains.pycharm",
  Xcode = "com.apple.dt.Xcode",
  AndroidStudio = "com.google.android.studio",

  -- Browsers
  GoogleChrome = "com.google.Chrome",
  GoogleChat = "com.google.Chrome.app.mdpkiolbdkhdjpekfbkbmhigcaggjagi",
  Arc = "company.thebrowser.Browser",

  -- Dev tools
  -- The outer Docker.app, which macOS can launch and the sheet can show. The window belongs to
  -- the Docker Desktop.app nested inside it, com.electron.dockerdesktop, which Launch Services
  -- does not register, so naming that one launched nothing and left Docker off the Hyper sheet.
  -- Asked again while running, Docker.app has no window of its own and is reopened, which brings
  -- the dashboard forward.
  Docker = "com.docker.docker",
  Bruno = "com.usebruno.app",
  TablePlus = "com.tinyapp.TablePlus",
  Hammerspoon = "org.hammerspoon.Hammerspoon",

  -- AI
  Claude = "com.anthropic.claudefordesktop",
  ChatGPT = "com.openai.chat",
  ChatGPTAtlas = "com.openai.atlas.web",

  -- Productivity
  Obsidian = "md.obsidian",
  Slack = "com.tinyspeck.slackmacgap",
  Yomu = "net.cecinestpasparis.yomu",
  iPhoneMirroring = "com.apple.ScreenContinuity",
}
