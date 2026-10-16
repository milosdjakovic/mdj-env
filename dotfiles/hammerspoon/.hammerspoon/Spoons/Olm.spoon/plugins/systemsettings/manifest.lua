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
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "System Settings",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The icons the System Settings rows name, one per pane, in the emoji set and the SF Symbol
  -- set, and the identity icon the launcher row and the scoped list wear.
  icons = {
    systemsettings = { emoji = "⚙️", sf = "gearshape" },
    wifi = { emoji = "📶", sf = "wifi" },
    bluetooth = { emoji = "🔵", sf = "dot.radiowaves.left.and.right" },
    network = { emoji = "🌐", sf = "globe" },
    battery = { emoji = "🔋", sf = "battery.100" },
    general = { emoji = "⚙️", sf = "gearshape" },
    accessibility = { emoji = "♿", sf = "accessibility" },
    appearance = { emoji = "🌗", sf = "circle.lefthalf.filled" },
    siri = { emoji = "🧠", sf = "apple.intelligence" },
    desktopDock = { emoji = "🪟", sf = "dock.rectangle" },
    displays = { emoji = "🖥️", sf = "display" },
    menuBar = { emoji = "📊", sf = "menubar.rectangle" },
    spotlight = { emoji = "🔦", sf = "magnifyingglass" },
    wallpaper = { emoji = "🖼️", sf = "photo" },
    notifications = { emoji = "🔔", sf = "bell" },
    sound = { emoji = "🔊", sf = "speaker.wave.3" },
    focus = { emoji = "🎯", sf = "target" },
    screenTime = { emoji = "⏳", sf = "hourglass" },
    lockScreen = { emoji = "🔐", sf = "lock" },
    privacy = { emoji = "🛡️", sf = "hand.raised" },
    touchId = { emoji = "👆", sf = "touchid" },
    appleAccount = { emoji = "🍎", sf = "apple.logo" },
    family = { emoji = "👨‍👩‍👧", sf = "person.3" },
    keyboard = { emoji = "⌨️", sf = "keyboard" },
    mouse = { emoji = "🖱️", sf = "computermouse" },
    trackpad = { emoji = "🖲️", sf = "rectangle.and.hand.point.up.left" },
    printers = { emoji = "🖨️", sf = "printer" },
    users = { emoji = "👥", sf = "person.2" },
    internetAccounts = { emoji = "📧", sf = "at" },
    gameCenter = { emoji = "🎮", sf = "gamecontroller" },
    gameControllers = { emoji = "🕹️", sf = "arcade.stick.console" },
    dateTime = { emoji = "🕐", sf = "clock" },
    language = { emoji = "🌍", sf = "globe.europe.africa" },
    sharing = { emoji = "📡", sf = "square.and.arrow.up" },
    timeMachine = { emoji = "⏰", sf = "clock.arrow.circlepath" },
    startupDisk = { emoji = "💽", sf = "internaldrive" },
    loginItems = { emoji = "🚀", sf = "person.crop.circle.badge.checkmark" },
    softwareUpdate = { emoji = "🔄", sf = "arrow.triangle.2.circlepath" },
    storage = { emoji = "💾", sf = "externaldrive" },
    deviceManagement = { emoji = "📋", sf = "checklist" },
  },

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
    icon = "systemsettings",
    aliases = { "s", "system" },

    -- config/settingsPanes today, and every id below was read off this machine's installed
    -- settings extensions, but the ids are Apple's, not this person's, so the whole catalog
    -- is exactly the kind of value the fresh install rule says Olm should ship. A macOS
    -- update can still rename one, in which case a stale row opens nothing and the fix is
    -- one edit here, the same fix the original config/settingsPanes.lua file already
    -- documented for itself.
    panes = {
      { name = "Wi-Fi",                     id = "com.apple.wifi-settings-extension",             icon = "wifi", keywords = "wifi wireless internet network" },
      { name = "Bluetooth",                 id = "com.apple.BluetoothSettings",                   icon = "bluetooth", keywords = "bluetooth wireless devices" },
      { name = "Network",                   id = "com.apple.Network-Settings.extension",          icon = "network", keywords = "network ethernet vpn dns proxy" },
      { name = "Battery",                   id = "com.apple.Battery-Settings.extension",          icon = "battery", keywords = "battery power energy" },
      { name = "General",                   id = "com.apple.systempreferences.GeneralSettings",   icon = "general", keywords = "general about airdrop storage language date" },
      { name = "Accessibility",             id = "com.apple.Accessibility-Settings.extension",    icon = "accessibility", keywords = "accessibility a11y vision hearing zoom voiceover" },
      { name = "Appearance",                id = "com.apple.Appearance-Settings.extension",       icon = "appearance", keywords = "appearance theme dark light accent" },
      { name = "Apple Intelligence & Siri", id = "com.apple.Siri-Settings.extension",             icon = "siri", keywords = "siri apple intelligence ai assistant" },
      { name = "Desktop & Dock",            id = "com.apple.Desktop-Settings.extension",          icon = "desktopDock", keywords = "desktop dock mission control stage manager hot corners" },
      { name = "Displays",                  id = "com.apple.Displays-Settings.extension",         icon = "displays", keywords = "displays monitor resolution brightness night shift" },
      { name = "Menu Bar",                  id = "com.apple.ControlCenter-Settings.extension",    icon = "menuBar", keywords = "menu bar control center modules" },
      { name = "Spotlight",                 id = "com.apple.Spotlight-Settings.extension",        icon = "spotlight", keywords = "spotlight search indexing" },
      { name = "Wallpaper",                 id = "com.apple.Wallpaper-Settings.extension",        icon = "wallpaper", keywords = "wallpaper background desktop picture" },
      { name = "Notifications",             id = "com.apple.Notifications-Settings.extension",    icon = "notifications", keywords = "notifications alerts badges banners" },
      { name = "Sound",                     id = "com.apple.Sound-Settings.extension",            icon = "sound", keywords = "sound audio volume output input" },
      { name = "Focus",                     id = "com.apple.Focus-Settings.extension",            icon = "focus", keywords = "focus do not disturb dnd" },
      { name = "Screen Time",               id = "com.apple.Screen-Time-Settings.extension",      icon = "screenTime", keywords = "screen time limits downtime" },
      { name = "Lock Screen",               id = "com.apple.Lock-Screen-Settings.extension",      icon = "lockScreen", keywords = "lock screen screensaver" },
      { name = "Privacy & Security",        id = "com.apple.settings.PrivacySecurity.extension",  icon = "privacy", keywords = "privacy security permissions filevault firewall camera microphone" },
      { name = "Touch ID & Password",       id = "com.apple.Touch-ID-Settings.extension",         icon = "touchId", keywords = "touch id password fingerprint login" },
      { name = "Apple Account",             id = "com.apple.systempreferences.AppleIDSettings",   icon = "appleAccount", keywords = "apple account id icloud" },
      { name = "Family",                    id = "com.apple.Family-Settings.extension",           icon = "family", keywords = "family sharing screen time kids" },
      { name = "Keyboard",                  id = "com.apple.Keyboard-Settings.extension",         icon = "keyboard", keywords = "keyboard shortcuts input text" },
      { name = "Mouse",                     id = "com.apple.Mouse-Settings.extension",            icon = "mouse", keywords = "mouse pointer scroll" },
      { name = "Trackpad",                  id = "com.apple.Trackpad-Settings.extension",         icon = "trackpad", keywords = "trackpad gestures tap click" },
      { name = "Printers & Scanners",       id = "com.apple.Print-Scan-Settings.extension",       icon = "printers", keywords = "printers scanners print scan" },
      { name = "Users & Groups",            id = "com.apple.Users-Groups-Settings.extension",     icon = "users", keywords = "users groups accounts login" },
      { name = "Internet Accounts",         id = "com.apple.Internet-Accounts-Settings.extension", icon = "internetAccounts", keywords = "internet accounts mail calendar google" },
      { name = "Game Center",               id = "com.apple.Game-Center-Settings.extension",      icon = "gameCenter", keywords = "game center friends achievements" },
      { name = "Game Controllers",          id = "com.apple.Game-Controller-Settings.extension",  icon = "gameControllers", keywords = "game controllers gamepad" },
      { name = "Date & Time",               id = "com.apple.Date-Time-Settings.extension",        icon = "dateTime", keywords = "date time clock timezone" },
      { name = "Language & Region",         id = "com.apple.Localization-Settings.extension",     icon = "language", keywords = "language region locale format" },
      { name = "Sharing",                   id = "com.apple.Sharing-Settings.extension",          icon = "sharing", keywords = "sharing screen file remote" },
      { name = "Time Machine",              id = "com.apple.Time-Machine-Settings.extension",     icon = "timeMachine", keywords = "time machine backup" },
      { name = "Startup Disk",              id = "com.apple.Startup-Disk-Settings.extension",     icon = "startupDisk", keywords = "startup disk boot volume" },
      { name = "Login Items & Extensions",  id = "com.apple.LoginItems-Settings.extension",       icon = "loginItems", keywords = "login items startup extensions background" },
      { name = "Software Update",           id = "com.apple.Software-Update-Settings.extension",  icon = "softwareUpdate", keywords = "software update upgrade" },
      { name = "Storage",                   id = "com.apple.settings.Storage",                    icon = "storage", keywords = "storage disk space" },
      { name = "Device Management",         id = "com.apple.Profiles-Settings.extension",         icon = "deviceManagement", keywords = "device management profiles mdm" },
    },
  },
}
