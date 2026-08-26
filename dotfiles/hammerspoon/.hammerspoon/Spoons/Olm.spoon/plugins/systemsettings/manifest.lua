-- SystemSettings, what it declares about itself.
--
-- No external tool, it only turns an injected pane catalog into launcher rows and
-- opens a pane by url. And no surface, unlike every other plugin in this set, it owns no
-- chooser of its own and no hyperContext names it.
--
-- The pane catalog is macOS knowledge, not this person's own, every pane id below ships
-- with the operating system rather than with anything only this machine's owner could name,
-- so it lives in defaults rather than behind a required data need that would leave a fresh
-- install with no System Settings rows at all.
--
-- provides states the one true fact this plugin holds regardless of which of its two
-- current doorways actually reads it, that rows and a way to act on one genuinely exist. The
-- launcher's own needs.set.scopes query asks for exactly that pair, and without this
-- declaration nothing tells the loader that SystemSettings must be configured before the
-- launcher captures its rows, which is the exact silent loss the launcher already suffered.
return {
  needs = {
    tools = {
      -- open is what turns a pane's x-apple.systempreferences url into a real navigation,
      -- the whole of what this plugin does past building the url itself. Optional, and an
      -- unresolved open degrades to a row that logs rather than one that silently opens
      -- nothing.
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional", unit = "panes",
        reason = "opening a System Settings pane by its url scheme",
        origin = { macos = "ships with the system" } },
    },
  },

  provides = {
    rows = "rows",
    -- open is the real member. Choosing a pane in the live root actually runs through the
    -- launcher's own item.kind dispatch, actions.settingsPane, which itself calls this same
    -- method, so naming it here is honest about where the row's own action ends up rather
    -- than inventing a member this plugin does not have.
    select = "open",
  },

  defaults = {
    description = "System Settings",
    glyph = "⚙️",
    aliases = { "s", "system" },

    -- config/settingsPanes today, and every id below was read off this machine's installed
    -- settings extensions, but the ids are Apple's, not this person's, so the whole catalog
    -- is exactly the kind of value the fresh install rule says Olm should ship. A macOS
    -- update can still rename one, in which case a stale row opens nothing and the fix is
    -- one edit here, the same fix the original config/settingsPanes.lua file already
    -- documented for itself.
    panes = {
      { name = "Wi-Fi",                     id = "com.apple.wifi-settings-extension",             glyph = "📶", keywords = "wifi wireless internet network" },
      { name = "Bluetooth",                 id = "com.apple.BluetoothSettings",                   glyph = "🔵", keywords = "bluetooth wireless devices" },
      { name = "Network",                   id = "com.apple.Network-Settings.extension",          glyph = "🌐", keywords = "network ethernet vpn dns proxy" },
      { name = "Battery",                   id = "com.apple.Battery-Settings.extension",          glyph = "🔋", keywords = "battery power energy" },
      { name = "General",                   id = "com.apple.systempreferences.GeneralSettings",   glyph = "⚙️", keywords = "general about airdrop storage language date" },
      { name = "Accessibility",             id = "com.apple.Accessibility-Settings.extension",    glyph = "♿", keywords = "accessibility a11y vision hearing zoom voiceover" },
      { name = "Appearance",                id = "com.apple.Appearance-Settings.extension",       glyph = "🌗", keywords = "appearance theme dark light accent" },
      { name = "Apple Intelligence & Siri", id = "com.apple.Siri-Settings.extension",             glyph = "🧠", keywords = "siri apple intelligence ai assistant" },
      { name = "Desktop & Dock",            id = "com.apple.Desktop-Settings.extension",          glyph = "🪟", keywords = "desktop dock mission control stage manager hot corners" },
      { name = "Displays",                  id = "com.apple.Displays-Settings.extension",         glyph = "🖥️", keywords = "displays monitor resolution brightness night shift" },
      { name = "Menu Bar",                  id = "com.apple.ControlCenter-Settings.extension",    glyph = "📊", keywords = "menu bar control center modules" },
      { name = "Spotlight",                 id = "com.apple.Spotlight-Settings.extension",        glyph = "🔦", keywords = "spotlight search indexing" },
      { name = "Wallpaper",                 id = "com.apple.Wallpaper-Settings.extension",        glyph = "🖼️", keywords = "wallpaper background desktop picture" },
      { name = "Notifications",             id = "com.apple.Notifications-Settings.extension",    glyph = "🔔", keywords = "notifications alerts badges banners" },
      { name = "Sound",                     id = "com.apple.Sound-Settings.extension",            glyph = "🔊", keywords = "sound audio volume output input" },
      { name = "Focus",                     id = "com.apple.Focus-Settings.extension",            glyph = "🎯", keywords = "focus do not disturb dnd" },
      { name = "Screen Time",               id = "com.apple.Screen-Time-Settings.extension",      glyph = "⏳", keywords = "screen time limits downtime" },
      { name = "Lock Screen",               id = "com.apple.Lock-Screen-Settings.extension",      glyph = "🔐", keywords = "lock screen screensaver" },
      { name = "Privacy & Security",        id = "com.apple.settings.PrivacySecurity.extension",  glyph = "🛡️", keywords = "privacy security permissions filevault firewall camera microphone" },
      { name = "Touch ID & Password",       id = "com.apple.Touch-ID-Settings.extension",         glyph = "👆", keywords = "touch id password fingerprint login" },
      { name = "Apple Account",             id = "com.apple.systempreferences.AppleIDSettings",   glyph = "🍎", keywords = "apple account id icloud" },
      { name = "Family",                    id = "com.apple.Family-Settings.extension",           glyph = "👨‍👩‍👧", keywords = "family sharing screen time kids" },
      { name = "Keyboard",                  id = "com.apple.Keyboard-Settings.extension",         glyph = "⌨️", keywords = "keyboard shortcuts input text" },
      { name = "Mouse",                     id = "com.apple.Mouse-Settings.extension",            glyph = "🖱️", keywords = "mouse pointer scroll" },
      { name = "Trackpad",                  id = "com.apple.Trackpad-Settings.extension",         glyph = "🖲️", keywords = "trackpad gestures tap click" },
      { name = "Printers & Scanners",       id = "com.apple.Print-Scan-Settings.extension",       glyph = "🖨️", keywords = "printers scanners print scan" },
      { name = "Users & Groups",            id = "com.apple.Users-Groups-Settings.extension",     glyph = "👥", keywords = "users groups accounts login" },
      { name = "Internet Accounts",         id = "com.apple.Internet-Accounts-Settings.extension", glyph = "📧", keywords = "internet accounts mail calendar google" },
      { name = "Game Center",               id = "com.apple.Game-Center-Settings.extension",      glyph = "🎮", keywords = "game center friends achievements" },
      { name = "Game Controllers",          id = "com.apple.Game-Controller-Settings.extension",  glyph = "🕹️", keywords = "game controllers gamepad" },
      { name = "Date & Time",               id = "com.apple.Date-Time-Settings.extension",        glyph = "🕐", keywords = "date time clock timezone" },
      { name = "Language & Region",         id = "com.apple.Localization-Settings.extension",     glyph = "🌍", keywords = "language region locale format" },
      { name = "Sharing",                   id = "com.apple.Sharing-Settings.extension",          glyph = "📡", keywords = "sharing screen file remote" },
      { name = "Time Machine",              id = "com.apple.Time-Machine-Settings.extension",     glyph = "⏰", keywords = "time machine backup" },
      { name = "Startup Disk",              id = "com.apple.Startup-Disk-Settings.extension",     glyph = "💽", keywords = "startup disk boot volume" },
      { name = "Login Items & Extensions",  id = "com.apple.LoginItems-Settings.extension",       glyph = "🚀", keywords = "login items startup extensions background" },
      { name = "Software Update",           id = "com.apple.Software-Update-Settings.extension",  glyph = "🔄", keywords = "software update upgrade" },
      { name = "Storage",                   id = "com.apple.settings.Storage",                    glyph = "💾", keywords = "storage disk space" },
      { name = "Device Management",         id = "com.apple.Profiles-Settings.extension",         glyph = "📋", keywords = "device management profiles mdm" },
    },
  },
}
