-- App bundle ID registry
-- Get app identifier: osascript -e 'id of app "APP_NAME"'

return {
  -- System
  Finder = "com.apple.finder",
  Mail = "com.apple.mail",
  Books = "com.apple.iBooksX",
  Notes = "com.apple.Notes",
  Stickies = "com.apple.Stickies",
  Safari = "com.apple.Safari",

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

  -- Dev tools
  Docker = "com.electron.dockerdesktop",
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
