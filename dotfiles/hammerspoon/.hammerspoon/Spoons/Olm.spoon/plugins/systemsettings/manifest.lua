-- SystemSettings, what it declares about itself.
--
-- No external tool, it only turns an injected pane catalog into launcher rows and
-- opens a pane by url. And no surface, unlike every other plugin in this set, it owns no
-- chooser of its own and no hyperContext names it. Every pane is also an action,
-- systemsettings.General, which config/keymap.lua puts on a key.
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
    description = "Open any System Settings pane directly from the launcher.",
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
    battery = { emoji = "🔋", sf = "battery.0percent" },
    general = { emoji = "⚙️", sf = "gearshape" },
    accessibility = { emoji = "♿", sf = "accessibility" },
    appearance = { emoji = "🌗", sf = "sun.max" },
    siri = { emoji = "🧠", sf = "apple.intelligence" },
    desktopDock = { emoji = "🪟", sf = "dock.rectangle" },
    displays = { emoji = "🖥️", sf = "rectangle" },
    menuBar = { emoji = "📊", sf = "menubar.rectangle" },
    spotlight = { emoji = "🔦", sf = "magnifyingglass" },
    wallpaper = { emoji = "🖼️", sf = "mountain.2" },
    notifications = { emoji = "🔔", sf = "bell" },
    sound = { emoji = "🔊", sf = "speaker.wave.3" },
    focus = { emoji = "🎯", sf = "scope" },
    screenTime = { emoji = "⏳", sf = "clock" },
    lockScreen = { emoji = "🔐", sf = "lock" },
    privacy = { emoji = "🛡️", sf = "hand.raised" },
    touchId = { emoji = "👆", sf = "touchid" },
    appleAccount = { emoji = "🍎", sf = "person" },
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
    loginItems = { emoji = "🚀", sf = "power" },
    softwareUpdate = { emoji = "🔄", sf = "arrow.triangle.2.circlepath" },
    storage = { emoji = "💾", sf = "externaldrive" },
    deviceManagement = { emoji = "📋", sf = "checklist" },
    -- The search row's icon. It was the launcher's own while the launcher stated that row
    -- itself, and it moved here with the row in phase three of the core split, drawn
    -- identically in both sets, so the picture is unchanged.
    search = { emoji = "🔍", sf = "magnifyingglass" },
  },

  needs = {
    lib = {
      -- Opening a pane by url, which a pane's action runs unless the press hides System Settings,
      -- a decision this plugin makes itself in paneToggle. Required,
      -- since every pane action calls it, and a core lib is always present, so requiring it
      -- costs nothing on any install. The pane rows the launcher lists open through `open` below.
      appFocus = { from = "appfocus", policy = "required" },
    },

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
    -- open is the real member. Choosing a pane in the launcher runs through launcherRun
    -- below, which itself calls this same method, so naming it here is honest about where the
    -- row's own action ends up rather than inventing a member this plugin does not have.
    select = "open",
    -- The launcher's own catalog. launcherRows answers the search row and one row per pane,
    -- and launcherRun opens a chosen pane or focuses the search field, so the launcher asks
    -- the set for both and names no plugin. The pane rows are the same descriptors rows
    -- answers above, so the scoped list and the catalog can never disagree about a pane.
    launcherRows = "launcherRows",
    launcherRun = "launcherRun",
    -- One action per pane, named by the pane with every character that is not a letter or a
    -- digit taken out, systemsettings.General, built in configure from the pane catalog below.
    -- Each toggles System Settings onto its pane and names the app, so its chord shows on the
    -- launcher's System Settings row. The pane rows above stay rows rather than these actions,
    -- since a row opens its pane and never hides the app, which a toggle would.
    actions = "actions",
  },

  defaults = {
    description = "System Settings",
    icon = "systemsettings",
    -- No alias on purpose. A "system" alias searched the panes for "settings" when a person typed
    -- the app's own name, so the panes are found by name in the main launcher instead.

    -- The one row that is not a pane. It drops a person into Apple's own per setting search
    -- for everything the pane list does not reach, and it was the launcher's own row, listed
    -- among its special rows and run by a closure in the composition root, until phase three
    -- of the core split moved it here beside the method it calls. It names no key, so its
    -- subtitle says what it does rather than naming a chord.
    searchRow = {
      title = "Search Settings",
      subTitle = "System · opens the System Settings search field",
      icon = "search",
      -- Its place among the launcher's rows, after the screenshot actions and before the
      -- launcher's own rows, where it has always sat. See launcherOrder below.
      order = 20,
    },

    -- Where the pane rows sit in the launcher's own catalog, a number compared with every
    -- other contributor's and with the launcher's own. Fifty puts them after every command,
    -- capture at ten, the launcher's own rows at thirty, the window actions at forty, which is
    -- where the panes have always been. A person moves them in config/plugins.lua.
    launcherOrder = 50,

    -- config/settingsPanes today, and every id below was read off this machine's installed
    -- settings extensions, but the ids are Apple's, not this person's, so the whole catalog
    -- is exactly the kind of value the fresh install rule says Olm should ship. A macOS
    -- update can still rename one, in which case a stale row opens nothing and the fix is
    -- one edit here, the same fix the original config/settingsPanes.lua file already
    -- documented for itself.
    panes = {
      { name = "Wi-Fi",                     id = "com.apple.wifi-settings-extension",             icon = "wifi", keywords = "wifi, wireless, airport" },
      { name = "Bluetooth",                 id = "com.apple.BluetoothSettings",                   icon = "bluetooth", keywords = "headphones, pairing" },
      { name = "Network",                   id = "com.apple.Network-Settings.extension",          icon = "network", keywords = "ethernet, vpn, dns, proxy, ip address" },
      { name = "Battery",                   id = "com.apple.Battery-Settings.extension",          icon = "battery", keywords = "power, energy saver, low power mode" },
      { name = "General",                   id = "com.apple.systempreferences.GeneralSettings",   icon = "general", keywords = "about this mac, airdrop, handoff" },
      { name = "Accessibility",             id = "com.apple.Accessibility-Settings.extension",    icon = "accessibility", keywords = "a11y, vision, hearing, zoom, voiceover" },
      { name = "Appearance",                id = "com.apple.Appearance-Settings.extension",       icon = "appearance", keywords = "dark mode, light mode, accent colour, theme" },
      { name = "Apple Intelligence & Siri", id = "com.apple.Siri-Settings.extension",             icon = "siri", keywords = "ai, assistant, hey siri" },
      { name = "Desktop & Dock",            id = "com.apple.Desktop-Settings.extension",          icon = "desktopDock", keywords = "mission control, stage manager, hot corners" },
      { name = "Displays",                  id = "com.apple.Displays-Settings.extension",         icon = "displays", keywords = "monitor, resolution, brightness, night shift, true tone" },
      { name = "Menu Bar",                  id = "com.apple.ControlCenter-Settings.extension",    icon = "menuBar", keywords = "control center, status icons" },
      { name = "Spotlight",                 id = "com.apple.Spotlight-Settings.extension",        icon = "spotlight", keywords = "indexing" },
      { name = "Wallpaper",                 id = "com.apple.Wallpaper-Settings.extension",        icon = "wallpaper", keywords = "background, desktop picture, screensaver" },
      { name = "Notifications",             id = "com.apple.Notifications-Settings.extension",    icon = "notifications", keywords = "alerts, badges, banners" },
      { name = "Sound",                     id = "com.apple.Sound-Settings.extension",            icon = "sound", keywords = "audio, alert sound, output device, input device" },
      { name = "Focus",                     id = "com.apple.Focus-Settings.extension",            icon = "focus", keywords = "do not disturb, dnd, quiet hours" },
      { name = "Screen Time",               id = "com.apple.Screen-Time-Settings.extension",      icon = "screenTime", keywords = "downtime, app limits, parental controls" },
      { name = "Lock Screen",               id = "com.apple.Lock-Screen-Settings.extension",      icon = "lockScreen", keywords = "screensaver, require password" },
      { name = "Privacy & Security",        id = "com.apple.settings.PrivacySecurity.extension",  icon = "privacy", keywords = "permissions, filevault, firewall, camera access, microphone access, accessibility access" },
      { name = "Touch ID & Password",       id = "com.apple.Touch-ID-Settings.extension",         icon = "touchId", keywords = "fingerprint, login password" },
      { name = "Apple Account",             id = "com.apple.systempreferences.AppleIDSettings",   icon = "appleAccount", keywords = "apple id, icloud" },
      { name = "Family",                    id = "com.apple.Family-Settings.extension",           icon = "family", keywords = "family sharing, kids" },
      { name = "Keyboard",                  id = "com.apple.Keyboard-Settings.extension",         icon = "keyboard", keywords = "shortcuts, input sources, text replacement, dictation" },
      { name = "Mouse",                     id = "com.apple.Mouse-Settings.extension",            icon = "mouse", keywords = "pointer, scroll direction, tracking speed" },
      { name = "Trackpad",                  id = "com.apple.Trackpad-Settings.extension",         icon = "trackpad", keywords = "gestures, tap to click, natural scrolling" },
      { name = "Printers & Scanners",       id = "com.apple.Print-Scan-Settings.extension",       icon = "printers", keywords = "add printer" },
      { name = "Users & Groups",            id = "com.apple.Users-Groups-Settings.extension",     icon = "users", keywords = "accounts, guest user" },
      { name = "Internet Accounts",         id = "com.apple.Internet-Accounts-Settings.extension", icon = "internetAccounts", keywords = "mail accounts, google, exchange" },
      { name = "Game Center",               id = "com.apple.Game-Center-Settings.extension",      icon = "gameCenter", keywords = "friends, achievements" },
      { name = "Game Controllers",          id = "com.apple.Game-Controller-Settings.extension",  icon = "gameControllers", keywords = "gamepad, joystick" },
      { name = "Date & Time",               id = "com.apple.Date-Time-Settings.extension",        icon = "dateTime", keywords = "clock, timezone, time zone" },
      { name = "Language & Region",         id = "com.apple.Localization-Settings.extension",     icon = "language", keywords = "locale, date format, number format" },
      { name = "Sharing",                   id = "com.apple.Sharing-Settings.extension",          icon = "sharing", keywords = "screen sharing, file sharing, remote login, computer name" },
      { name = "Time Machine",              id = "com.apple.Time-Machine-Settings.extension",     icon = "timeMachine", keywords = "backup" },
      { name = "Startup Disk",              id = "com.apple.Startup-Disk-Settings.extension",     icon = "startupDisk", keywords = "boot" },
      { name = "Login Items & Extensions",  id = "com.apple.LoginItems-Settings.extension",       icon = "loginItems", keywords = "startup apps, open at login, background items" },
      { name = "Software Update",           id = "com.apple.Software-Update-Settings.extension",  icon = "softwareUpdate", keywords = "upgrade, macos update" },
      { name = "Storage",                   id = "com.apple.settings.Storage",                    icon = "storage", keywords = "disk space, free space" },
      { name = "Device Management",         id = "com.apple.Profiles-Settings.extension",         icon = "deviceManagement", keywords = "profiles, mdm" },
    },
  },
}
