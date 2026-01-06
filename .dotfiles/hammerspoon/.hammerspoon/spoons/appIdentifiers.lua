-- Get app identifier: osascript -e 'id of app "APP_NAME"'

local AppIdentifiers = {
    Finder = "com.apple.finder",
    Mail = "com.apple.mail",
    Books = "com.apple.iBooksX",
    Notes = "com.apple.Notes",
    Stickies = "com.apple.Stickies",
    Safari = "com.apple.Safari",
    Obsidian = "md.obsidian",
    GoogleChrome = "com.google.Chrome",
    GoogleChat = "com.google.Chrome.app.mdpkiolbdkhdjpekfbkbmhigcaggjagi",
    VisualStudioCode = "com.microsoft.VSCode",
    Zed = "dev.zed.Zed",
    Xcode = "com.apple.dt.Xcode",
    AndroidStudio = "com.google.android.studio",
    Hammerspoon = "org.hammerspoon.Hammerspoon",
    Docker = "com.electron.dockerdesktop",
    Bruno = "com.usebruno.app",
    TablePlus = "com.tinyapp.TablePlus",
    Yomu = "net.cecinestpasparis.yomu",
    Terminal = "com.apple.Terminal",
    Warp = "dev.warp.Warp-Stable",
    Alacritty = "org.alacritty",
    Kitty = "net.kovidgoyal.kitty",
    WezTerm = "com.github.wez.wezterm",
    Ghostty = "com.mitchellh.ghostty",
    iPhoneMirroring = "com.apple.ScreenContinuity",
    Slack = "com.tinyspeck.slackmacgap",
    PyCharm = "com.jetbrains.pycharm",
    Cursor = "com.todesktop.230313mzl4w4u92",
    ChatGPT = "com.openai.chat",
    Claude = "com.anthropic.claudefordesktop",
    ChatGPTAtlas = "com.openai.atlas.web"
}

return AppIdentifiers
