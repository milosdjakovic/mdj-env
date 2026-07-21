-- System Settings pane catalog. Pure data, the same kind of editable list as
-- apps.lua and keys.lua, consumed by SystemSettings.spoon which is the mechanism.
-- Each row names one pane in the System Settings sidebar.
--
--   name      the label shown in the launcher row, matching the sidebar wording.
--   id        the pane's bundle identifier. The spoon prefixes the
--             x-apple.systempreferences: scheme, so opening the URL navigates
--             System Settings straight to this pane.
--   glyph     an emoji drawn as the row icon, the same treatment the launcher
--             already gives its action rows. The real pane icons live in asset
--             catalogs Hammerspoon cannot read, so a glyph stands in.
--   keywords  extra words folded into the launcher's match text but never shown,
--             so a pane is findable by a synonym its name lacks. Wi-Fi is reached
--             by typing wifi, Desktop and Dock by typing mission control.
--
-- The ids were read from this machine's installed settings extensions in
-- /System/Library/ExtensionKit/Extensions, so they track what is actually here.
-- A macOS update can rename an id, in which case a stale row opens nothing and
-- the fix is one edit here. Adding or reordering a pane is also one edit here,
-- with no code change.

return {
  { name = "Wi-Fi",                     id = "com.apple.wifi-settings-extension",           glyph = "📶", keywords = "wifi wireless internet network" },
  { name = "Bluetooth",                 id = "com.apple.BluetoothSettings",                 glyph = "🔵", keywords = "bluetooth wireless devices" },
  { name = "Network",                   id = "com.apple.Network-Settings.extension",        glyph = "🌐", keywords = "network ethernet vpn dns proxy" },
  { name = "Battery",                   id = "com.apple.Battery-Settings.extension",        glyph = "🔋", keywords = "battery power energy" },
  { name = "General",                   id = "com.apple.systempreferences.GeneralSettings", glyph = "⚙️", keywords = "general about airdrop storage language date" },
  { name = "Accessibility",             id = "com.apple.Accessibility-Settings.extension",  glyph = "♿", keywords = "accessibility a11y vision hearing zoom voiceover" },
  { name = "Appearance",                id = "com.apple.Appearance-Settings.extension",     glyph = "🌗", keywords = "appearance theme dark light accent" },
  { name = "Apple Intelligence & Siri", id = "com.apple.Siri-Settings.extension",           glyph = "🧠", keywords = "siri apple intelligence ai assistant" },
  { name = "Desktop & Dock",            id = "com.apple.Desktop-Settings.extension",        glyph = "🪟", keywords = "desktop dock mission control stage manager hot corners" },
  { name = "Displays",                  id = "com.apple.Displays-Settings.extension",       glyph = "🖥️", keywords = "displays monitor resolution brightness night shift" },
  { name = "Menu Bar",                  id = "com.apple.ControlCenter-Settings.extension",  glyph = "📊", keywords = "menu bar control center modules" },
  { name = "Spotlight",                 id = "com.apple.Spotlight-Settings.extension",      glyph = "🔦", keywords = "spotlight search indexing" },
  { name = "Wallpaper",                 id = "com.apple.Wallpaper-Settings.extension",      glyph = "🖼️", keywords = "wallpaper background desktop picture" },
  { name = "Notifications",             id = "com.apple.Notifications-Settings.extension",  glyph = "🔔", keywords = "notifications alerts badges banners" },
  { name = "Sound",                     id = "com.apple.Sound-Settings.extension",          glyph = "🔊", keywords = "sound audio volume output input" },
  { name = "Focus",                     id = "com.apple.Focus-Settings.extension",          glyph = "🎯", keywords = "focus do not disturb dnd" },
  { name = "Screen Time",               id = "com.apple.Screen-Time-Settings.extension",    glyph = "⏳", keywords = "screen time limits downtime" },
  { name = "Lock Screen",               id = "com.apple.Lock-Screen-Settings.extension",    glyph = "🔐", keywords = "lock screen screensaver" },
  { name = "Privacy & Security",        id = "com.apple.settings.PrivacySecurity.extension", glyph = "🛡️", keywords = "privacy security permissions filevault firewall camera microphone" },
  { name = "Touch ID & Password",       id = "com.apple.Touch-ID-Settings.extension",       glyph = "👆", keywords = "touch id password fingerprint login" },
  { name = "Apple Account",             id = "com.apple.systempreferences.AppleIDSettings",  glyph = "🍎", keywords = "apple account id icloud" },
  { name = "Family",                    id = "com.apple.Family-Settings.extension",         glyph = "👨‍👩‍👧", keywords = "family sharing screen time kids" },
  { name = "Keyboard",                  id = "com.apple.Keyboard-Settings.extension",       glyph = "⌨️", keywords = "keyboard shortcuts input text" },
  { name = "Mouse",                     id = "com.apple.Mouse-Settings.extension",          glyph = "🖱️", keywords = "mouse pointer scroll" },
  { name = "Trackpad",                  id = "com.apple.Trackpad-Settings.extension",       glyph = "🖲️", keywords = "trackpad gestures tap click" },
  { name = "Printers & Scanners",       id = "com.apple.Print-Scan-Settings.extension",     glyph = "🖨️", keywords = "printers scanners print scan" },
  { name = "Users & Groups",            id = "com.apple.Users-Groups-Settings.extension",   glyph = "👥", keywords = "users groups accounts login" },
  { name = "Internet Accounts",         id = "com.apple.Internet-Accounts-Settings.extension", glyph = "📧", keywords = "internet accounts mail calendar google" },
  { name = "Game Center",               id = "com.apple.Game-Center-Settings.extension",    glyph = "🎮", keywords = "game center friends achievements" },
  { name = "Game Controllers",          id = "com.apple.Game-Controller-Settings.extension", glyph = "🕹️", keywords = "game controllers gamepad" },
  { name = "Date & Time",               id = "com.apple.Date-Time-Settings.extension",      glyph = "🕐", keywords = "date time clock timezone" },
  { name = "Language & Region",         id = "com.apple.Localization-Settings.extension",   glyph = "🌍", keywords = "language region locale format" },
  { name = "Sharing",                   id = "com.apple.Sharing-Settings.extension",        glyph = "📡", keywords = "sharing screen file remote" },
  { name = "Time Machine",              id = "com.apple.Time-Machine-Settings.extension",   glyph = "⏰", keywords = "time machine backup" },
  { name = "Startup Disk",              id = "com.apple.Startup-Disk-Settings.extension",   glyph = "💽", keywords = "startup disk boot volume" },
  { name = "Login Items & Extensions",  id = "com.apple.LoginItems-Settings.extension",     glyph = "🚀", keywords = "login items startup extensions background" },
  { name = "Software Update",           id = "com.apple.Software-Update-Settings.extension", glyph = "🔄", keywords = "software update upgrade" },
  { name = "Storage",                   id = "com.apple.settings.Storage",                  glyph = "💾", keywords = "storage disk space" },
  { name = "Device Management",         id = "com.apple.Profiles-Settings.extension",       glyph = "📋", keywords = "device management profiles mdm" },
}
