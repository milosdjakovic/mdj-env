-- Keybinding definitions
-- Pure data, no logic

-- Modifier key combinations
local HYPER = { "shift", "ctrl", "alt", "cmd" }
local CTRL_ALT = { "ctrl", "alt" }
local SHIFT_ALT = { "shift", "alt" }

return {
  -- Expose modifiers for Spoons that need them
  modifiers = {
    HYPER = HYPER,
    CTRL_ALT = CTRL_ALT,
    SHIFT_ALT = SHIFT_ALT,
  },

  -- Leader key catalog. Each entry maps a physical key we remap FROM to an
  -- unused function key we remap TO, applied at the HID level by KeyRemap (wired
  -- in init.lua). The catalog is pure fact, it names no consumer, so apps and
  -- windows depend on it and never the other way around. A key is remapped only
  -- when a consumer below references it by name; anything unreferenced stays a
  -- normal key. To free a physical key, stop referencing its entry. To move a
  -- domain to another key, change that domain's reference. Keycodes are resolved
  -- from `fkey` in init.lua via hs.keycodes.map, so this stays free of raw
  -- numbers.
  leaderKeys = {
    HYPER = { source = "capsLock",     fkey = "f18" }, -- Caps Lock
    META  = { source = "rightOption",  fkey = "f16" }, -- Right Option
    SUPER = { source = "rightCommand", fkey = "f17" }, -- Right Command
  },

  -- Which catalog key each domain uses. This single reference is the domain
  -- naming its leader, the only place the app or window to physical key link
  -- lives. Change a name to move that domain onto another key; leave a catalog
  -- key unreferenced and it stays a normal key. HYPER drives app toggles,
  -- clipboard, and capture; the window leader drives resize, move, center, and
  -- display switching.
  appLeader    = "HYPER",
  windowLeader = "META",

  -- App toggle bindings (for AppToggler.spoon)
  -- Uses app names from config/apps.lua.
  -- These fire by holding the Hyper key (Caps Lock, remapped to F18 and driven
  -- by HyperKey.spoon) plus the letter. A quick Caps Lock tap toggles real Caps
  -- Lock instead. The `modifiers = HYPER` field is the FALLBACK: if HyperKey is
  -- not wired up in init.lua, AppToggler binds these to the literal ⇧⌃⌥⌘ combo
  -- instead. So it is not dead data -- remove HyperKey and the combo comes back.
  appToggles = {
    -- First character
    { app = "Books",            modifiers = HYPER, key = "B" },
    { app = "GoogleChrome",     modifiers = HYPER, key = "C" },
    { app = "Docker",           modifiers = HYPER, key = "D" },
    { app = "Finder",           modifiers = HYPER, key = "F" },
    { app = "Mail",             modifiers = HYPER, key = "M" },
    { app = "Obsidian",         modifiers = HYPER, key = "O" },
    { app = "Safari",           modifiers = HYPER, key = "S" },
    { app = "VisualStudioCode", modifiers = HYPER, key = "V" },
    { app = "Notes",            modifiers = HYPER, key = "N" },
    { app = "iPhoneMirroring",  modifiers = HYPER, key = "I" },
    { app = "Zed",              modifiers = HYPER, key = "Z" },
    { app = "Preview",          modifiers = HYPER, key = "R" },
    -- Second character
    { app = "Stickies",         modifiers = HYPER, key = "T" },
    { app = "Slack",            modifiers = HYPER, key = "L" },
    -- Third character
    { app = "Claude",           modifiers = HYPER, key = "A" },
    -- Default terminal: plain focus/cycle. (alt+` summons it placed via TerminalHandler)
    { app = "Ghostty",          modifiers = HYPER, key = "`" },
    -- Activity Monitor. On backslash rather than slash, because slash now opens file search,
    -- and the two read as a pair on adjacent keys, one for what the machine is doing and one
    -- for what is on it.
    { app = "ActivityMonitor",  modifiers = HYPER, key = "\\" },
    -- System Settings, opened straight to the General pane. The url field makes
    -- AppToggler open (and navigate) to that pane instead of a plain focus.
    { app = "SystemSettings",   modifiers = HYPER, key = ",", url = "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings" },
    -- Disabled (uncomment to enable)
    -- { app = "ChatGPTAtlas",   modifiers = HYPER, key = "A" },
    -- { app = "AndroidStudio",  modifiers = HYPER, key = "A" },
    -- { app = "Hammerspoon",    modifiers = HYPER, key = "H" },
    -- { app = "TablePlus",      modifiers = HYPER, key = "P" },
    -- { app = "Xcode",          modifiers = HYPER, key = "X" },
  },

  -- Clipboard history (for ClipboardHistory.spoon). Hyper+X opens it; the backend
  -- is the provider chain wired in init.lua, the clipboardShortcut combo by default
  -- (whatever manager you bind it to) and the native manager if you gate the shortcut
  -- on an app that is not running. Same modifiers/key shape as appToggles so the
  -- HYPER field is the fallback combo when HyperKey is not wired up. The
  -- `description` labels its Hyper cheat sheet and launcher rows.
  clipboardHistory = { modifiers = HYPER, key = "X", description = "Clipboard history" },

  -- Append copy and sequential paste, the two clipboard actions that need no list. Append
  -- copy glues the selection onto the newest entry instead of pushing a new one, so several
  -- selections gather into one item. Paste next walks the history, the first press pasting
  -- the newest entry exactly as a plain paste would and each press after it stepping one
  -- older, without reordering history or leaving the clipboard changed.
  --
  -- Both are global combos rather than Hyper bindings, the only clipboard keys that are.
  -- They extend the ordinary copy and paste keys and are pressed mid edit, so they should sit
  -- under the same hand shape rather than behind a leader, the same reasoning that puts the
  -- terminal toggle on a plain combo. Ctrl and Option is the free corner of the keyboard,
  -- because Apple keeps Cmd in every menu shortcut, so a Ctrl and Option letter is almost
  -- never an app command. Cmd and Option was the obvious first choice and is not usable,
  -- Finder puts copy as pathname and move item here there and design tools put copy and
  -- paste properties there. The one real collision left is VoiceOver, whose whole command
  -- set uses Ctrl and Option as its modifier.
  --
  -- Being global, neither appears in a leader's cheat sheet, so both carry a `description`
  -- for their launcher rows, which is where they are discoverable.
  appendCopy = { modifiers = CTRL_ALT, key = "C", description = "Append copy" },
  pasteNext = { modifiers = CTRL_ALT, key = "V", description = "Paste next" },

  -- External clipboard shortcut, for ClipboardHistory's generic `shortcut`
  -- provider. Hammerspoon fires this combo and whatever clipboard manager you bind
  -- the SAME combo to (Raycast, Alfred, or any other) reveals its history. It is
  -- purely shortcut based and names no app, so it always fires and the manager on
  -- the other end decides what happens. This is the one place the combo lives, keep
  -- it in step with the shortcut set inside that app. Add an optional `app` naming
  -- an entry in the apps registry to instead gate on it, firing only while it runs
  -- and letting the native Hammerspoon clipboard take over otherwise.
  clipboardShortcut = { mods = { "cmd", "alt", "ctrl", "shift" }, key = "c" },

  -- Keep awake (for Caffeinate.spoon). Same shape as appToggles. Hyper+K
  -- opens the keep awake panel, a typed field, not a list. It is a base binding,
  -- suppressed while a modal context owns Hyper.
  -- `aliases` are the words that scope the launcher to this tool, so typing one of them and
  -- a space turns the launcher list into this picker and deleting the space returns. They
  -- live here, beside the key, because the row that advertises them and the resolver that
  -- answers them both read this one entry, the same reason the key itself is data rather
  -- than something each surface knows. An entry with no aliases is simply not scopable.
  caffeinate = { modifiers = HYPER, key = "K", description = "Keep awake", aliases = { "k", "awake" } },

  -- VPN controls (for Vpn.spoon). Same shape again. Hyper+P opens the VPN control
  -- panel, a short list of actions with the live connection state at the top. It is
  -- a base binding, suppressed while a modal context owns Hyper.
  vpn = { modifiers = HYPER, key = "P", description = "VPN", aliases = { "v", "vpn" } },

  -- Colour picker (for Eyedropper.spoon). Hyper+2 turns the pointer into a screen
  -- eyedropper with a magnifier loupe, a click copies the pixel hex. It is not a
  -- chooser, so it has no Hyper context, it is a lone action like lock and sleep,
  -- bound as a base HyperKey binding and surfaced as a launcher row. The HYPER
  -- field is the fallback combo when HyperKey is not wired up.
  colorPicker = { modifiers = HYPER, key = "2", description = "Color picker" },

  -- Hyper context layers. Each context is a group of Hyper bindings that are live
  -- only while its `when` predicate holds. priority settles a key when several
  -- contexts are active at once, higher wins, and any key no context binds falls
  -- through to the app toggles. This is pure data. The composition root maps each
  -- action name to a function and resolves the predicate name against the shared
  -- registry, so this list stays free of both. Adding a switcher later is a new
  -- block here plus its predicate in init.lua, with no engine change. A context
  -- is also modal, while it is live the base app toggles are suppressed so Hyper
  -- belongs to the context, and any key it does not bind does nothing.
  --
  -- These contexts share the navigation actions, since only one tool is ever open
  -- and the composition root routes each action to the active one.
  --
  -- The clipboard chooser. j and k navigate vim style, i inserts the highlighted
  -- item the same as Return, a appends the highlighted item to a batch so several
  -- items can be gathered and pasted together on close, d deletes the highlighted
  -- item (or the whole batch once one is marked, when its label reads "Delete
  -- marked"), and x closes the chooser, the same as Escape. x needs its own binding
  -- because the context is modal, so the base Hyper+X toggle is suppressed while the
  -- native chooser is open.
  --
  -- The keep awake field is a single morphing row, not a list, so the context binds
  -- only the commit (i) and close (x) actions, no j and k highlight movement. Typing the
  -- hours and minutes happens with Hyper released, since a held Hyper owns the keys. This
  -- context stays modal, so while it is open the base Hyper toggles are suppressed and
  -- Hyper belongs to it, and it is the active context so holding Hyper reveals nothing.
  --
  -- The VPN chooser is one flat list, the controls on top and the locations below. It
  -- carries the same j, k, i, and x: j and k move the highlight, i confirms the
  -- highlighted row the same as Return (toggle the tunnel or connect to the city), and x
  -- closes it. It runs on the native backend, so plain typing filters the list while Hyper
  -- is released. Like menu search, it docks the deferred shortcut hint panel, which stays
  -- hidden until the user pauses (settings.shortcutsPanel.delayMs) and then spells these out.
  hyperContexts = {
    {
      name = "clipboard",
      when = "clipboardOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Paste" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        -- Cmd is the sub-modifier within Hyper, so Hyper+Cmd+j/k scroll the preview
        -- while bare Hyper+j/k still move the highlight. The resolver matches these
        -- exact-mods bindings ahead of the mod-less move catch-alls on the same keys.
        { key = "j", mods = { "cmd" }, action = "scrollPreviewDown", description = "Scroll preview down" },
        { key = "k", mods = { "cmd" }, action = "scrollPreviewUp",   description = "Scroll preview up" },
        { key = "a", action = "appendSelected", description = "Append to batch" },
        -- Delete the highlighted entry, or the whole marked batch. The composition
        -- root relabels this to "Delete marked" while a batch is gathered.
        { key = "d", action = "deleteSelected",  description = "Delete" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    {
      name = "caffeinate",
      when = "caffeinateOpen",
      priority = 100,
      -- One morphing row, never a list, so there is nothing to move between. Only
      -- confirm and close, no selectNext/selectPrev.
      bindings = {
        { key = "i", action = "insertSelected", description = "Confirm" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    {
      name = "vpn",
      when = "vpnOpen",
      priority = 100,
      bindings = {
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "i", action = "insertSelected", description = "Confirm" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The launcher chooser. i runs the highlighted command the same as
    -- Return, j and k navigate vim style, and Space closes it, the same as Escape.
    -- Space is the open key, so it doubles as the close, the way the clipboard's X
    -- does. Plain typing filters the list while Hyper is released.
    {
      name = "launcher",
      when = "launcherOpen",
      priority = 100,
      bindings = {
        { key = "i",     action = "insertSelected", description = "Run" },
        { key = "j",     action = "selectNext",     description = "Move down" },
        { key = "k",     action = "selectPrev",     description = "Move up" },
        { key = "space", action = "closeChooser",   description = "Close" },
      },
    },
    -- The menu search chooser. Lists the frontmost app's menu items on Hyper+E.
    -- i runs the highlighted item the same as Return, j and k navigate vim style,
    -- and x closes it, the same as the clipboard and VPN choosers. Menu search opens
    -- on Hyper+E, so unlike the launcher, whose open key doubles as its close, there is
    -- no open key to reuse here; x is the close (and Escape closes natively). Plain
    -- typing filters while Hyper is released.
    {
      name = "menuSearch",
      when = "menuSearchOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Run" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The display profiles chooser. A nested menu you navigate. i drills into the
    -- highlighted row the same as Return (enter a profile, list its displays, confirm an
    -- action, or select the Back row to step out), j and k move the highlight, and x closes
    -- the whole thing the same as Escape. There is no separate back key, a Back row sits at
    -- each level. Plain typing filters the profile list and enters names while Hyper is
    -- released. It docks the deferred shortcut hint panel like the other native choosers.
    {
      name = "displayProfiles",
      when = "displayProfilesOpen",
      priority = 100,
      -- enter is this tool's own confirm, an in-place drill or action rather than the shared
      -- insertSelected, since selecting through the native chooser would close it and force a
      -- re-show. Return is intercepted to the same in-place enter, so both keys step the menu
      -- without a flash.
      bindings = {
        { key = "i", action = "enter",        description = "Select" },
        { key = "j", action = "selectNext",   description = "Move down" },
        { key = "k", action = "selectPrev",   description = "Move up" },
        { key = "x", action = "closeChooser", description = "Close" },
      },
    },
    -- The emoji picker chooser. i inserts the highlighted glyph the same as Return,
    -- j and k navigate vim style, and x closes it. The open key j is itself the move
    -- down key here, so like menu search the open key cannot double as the close, x
    -- is the close (and Escape closes natively). Plain typing filters while Hyper is
    -- released.
    {
      name = "emoji",
      when = "emojiOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Insert" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The overlay display picker (launcher-only). A drill-in menu, so i selects the
    -- highlighted row (drilling into Configure or a profile, or committing a mode or
    -- a display), j and k navigate vim style, and x closes it. Same shared nav as the
    -- other choosers; it just has no Hyper open key of its own.
    {
      name = "overlayDisplay",
      when = "overlayDisplayOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Select" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The text case picker (launcher-only). A flat list of cases, so i applies the
    -- highlighted case to the selection the same as Return, j and k navigate vim style,
    -- and x closes it. Same shared nav as the other choosers, it just has no Hyper open
    -- key of its own. Plain typing filters the cases while Hyper is released.
    {
      name = "textCase",
      when = "textCaseOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Apply" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The browser tabs chooser. Every open tab across the switched on browsers, with a
    -- settings level behind the last row, so it is a menu and not a flat list. i confirms the
    -- highlighted row in place, opening a tab or stepping into settings and back out, j and k
    -- move the highlight, and x closes it. Like display profiles it binds `enter` rather than
    -- the shared insertSelected, so stepping into settings never closes and re-shows. Plain
    -- typing filters the tabs while Hyper is released.
    {
      name = "browserTabs",
      when = "browserTabsOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "enter",        description = "Select" },
        { key = "j", action = "selectNext",   description = "Move down" },
        { key = "k", action = "selectPrev",   description = "Move up" },
        { key = "x", action = "closeChooser", description = "Close" },
      },
    },
    -- The processes picker (launcher-only). A flat list, so i stops the highlighted
    -- server or container the same as Return, j and k navigate vim style, and x closes it.
    -- Three extra actions are its own. f stops with no grace period and no size check,
    -- for something already wedged, r rescans in place so the list can be refreshed
    -- without closing and reopening, and s reorders by live load so whatever is burning
    -- a core comes to the top. All three are answered only by this surface, so they are
    -- no ops anywhere else. Plain typing filters by project, port, or runtime while
    -- Hyper is released.
    {
      name = "processes",
      when = "processesOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Stop" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "s", action = "sortByLoad",     description = "Sort by load" },
        { key = "f", action = "stopForced",     description = "Force stop" },
        { key = "r", action = "refreshList",    description = "Rescan" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The file search chooser. i opens the highlighted file with its default application, j
    -- and k navigate vim style, and x closes it. Five actions are its own. Walking a directory
    -- tree is l to go in and h to come back, both of which work by rewriting the query as a
    -- folder scope, so one picker searches and then browses through what it found and there is
    -- no second idea of where it is. h j k l are the whole movement set on one hand, which is
    -- why reveal is f for Finder rather than sitting on one of them. Coming back was on r first
    -- and moved here, because h is where the hand already expects it and two keys for one action
    -- would put the same row on the helper panel twice. o opens the folder holding the row and y
    -- copies its path. All five are answered only by this surface, so they are no ops anywhere
    -- else. Plain typing filters while Hyper is released, and typing a question mark shows the
    -- query grammar.
    --
    -- Going up does nothing when the query carries no folder, since there is nowhere above a
    -- search of everywhere, so h is inert until you are actually inside a directory.
    {
      name = "fileSearch",
      when = "fileSearchOpen",
      priority = 100,
      bindings = {
        { key = "i", action = "insertSelected", description = "Open" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "k", action = "selectPrev",     description = "Move up" },
        -- Cmd is the sub-modifier within Hyper, the same pair the clipboard uses for the
        -- same job, so scrolling the pane is one gesture across both tools. A trackpad or
        -- a wheel over the pane does it too, which the Chooser atom reports.
        --
        -- These two and the peek below each declare what they NEED from the preview provider the
        -- root chose, since one provider draws a pane this config scrolls for you and the other
        -- opens a window that scrolls itself and has to be asked for. The root answers the
        -- requirement once and drops the bindings that do not apply, so a key is never listed in
        -- the shortcut panel while doing nothing.
        { key = "j", mods = { "cmd" }, action = "scrollPreviewDown",
          needs = "scrollablePreview", description = "Scroll preview down" },
        { key = "k", mods = { "cmd" }, action = "scrollPreviewUp",
          needs = "scrollablePreview", description = "Scroll preview up" },
        { key = "space", action = "peekPreview",
          needs = "askedPreview", description = "Quick Look" },
        { key = "l", action = "browseInto",     description = "Into folder" },
        { key = "h", action = "browseUp",       description = "Up a level" },
        { key = "f", action = "revealInFinder", description = "Reveal in Finder" },
        { key = "o", action = "openFolder",     description = "Open folder" },
        { key = "y", action = "copyPath",       description = "Copy path" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
  },

  -- System actions bound onto the Hyper key in init.lua. Hyper+Esc sleeps the
  -- Mac, Hyper+§ locks the screen. Each is a plain key with no sub-modifier. The
  -- HYPER field is the fallback combo when HyperKey is not wired up, and
  -- `description` labels each row on the Hyper cheat sheet (a SYSTEM section).
  sleep = { modifiers = HYPER, key = "escape", description = "Sleep" },
  lock  = { modifiers = HYPER, key = "§",      description = "Lock" },

  -- Screen capture (for Capture.spoon). Provider-agnostic action names; the
  -- active provider maps them to its own commands, so swapping capture apps never
  -- touches this list. Screenshots and recording go through macshot (or native as
  -- fallback); ocrArea goes through the macocr provider (schappim's `ocr` CLI),
  -- which drags a region, OCRs it, and copies the text to the clipboard. Keys
  -- mirror the macOS Cmd-Shift-3 / Cmd-Shift-4 / Cmd-Shift-5 muscle memory. The
  -- HYPER field is the fallback combo used when HyperKey is not wired up, matching
  -- appToggles. Optional `mods` are sub-modifiers within the Hyper modal, so
  -- Hyper+4 and Hyper+Shift+4 are distinct, clipboard vs file. The bare Hyper+4
  -- copies the region to the clipboard, the common case, and Hyper+Shift+4 saves it
  -- to a file. `description` labels the row on the Hyper cheat sheet, where init.lua
  -- surfaces these as a CAPTURE section.
  capture = {
    { action = "ocrArea",              modifiers = HYPER, key = "3",                     description = "OCR" },
    { action = "captureAreaClipboard", modifiers = HYPER, key = "4",                     description = "Screenshot (copy)" },
    { action = "captureArea",          modifiers = HYPER, key = "4", mods = { "shift" }, description = "Screenshot" },
    { action = "recordArea",           modifiers = HYPER, key = "5",                     description = "Record screen" },
  },

  -- Window management bindings (for WindowManager.spoon via WindowLeader.spoon).
  -- This is an ORDERED list: the sequence here is exactly the cheat-sheet order
  -- (WindowCheatSheet fills row-major, two columns), so reorder these lines to
  -- reorder the overlay. `action` names the WindowManager handler and `key` is a
  -- single press. An optional `mods` list adds required sub-modifiers, so a bare
  -- arrow and a Shift+arrow are two actions on one key. Each label is the action
  -- name humanized (nextDisplay -> "Next Display"); add `description = "..."` to
  -- any entry to override its label. An optional `when = "<predicate>"` gates the
  -- binding on live state. When the named predicate returns false the key does
  -- nothing and its cheat-sheet row is hidden. Predicates live in the registry
  -- wired up in init.lua, so this stays pure data. Unknown names are treated as
  -- always active so a typo fails visibly rather than silently hiding a binding.
  --
  -- There is deliberately NO leader field here. Every binding attaches to
  -- whichever catalog key `windowLeader` above names, resolved and stamped on in
  -- init.lua. So a bare arrow resizes, a Shift+arrow moves, and letters and
  -- symbols cover maximize, presets, grow/shrink, center, and display switch, all
  -- on that one leader. Changing `windowLeader` moves the whole set to another
  -- key without touching a single line below. Hold the leader ~0.6s with no other
  -- key to reveal the cheat sheet.
  windowManagement = {
    -- Switch display (first row; hidden on a single display by the predicate)
    { action = "previousDisplay",      key = ",", when = "multipleDisplays" },
    { action = "nextDisplay",          key = ".", when = "multipleDisplays" },
    -- Resize (bare key)
    { action = "leftHalf",             key = "left" },
    { action = "rightHalf",            key = "right" },
    { action = "fullHeight",           key = "up" },
    { action = "reasonableSize",       key = "down" },
    { action = "maximize",             key = "return" },
    { action = "smallSize",            key = "Z" },
    { action = "increaseSize",         key = "=" },
    { action = "decreaseSize",         key = "-" },
    -- Move (WASD) and center
    { action = "moveLeft",             key = "a" },
    { action = "moveRight",            key = "d" },
    { action = "moveUp",               key = "w" },
    { action = "moveDown",             key = "s" },
    { action = "center",               key = "C" },
    -- Hide all except the focused window (kept last so it sits in the last row)
    { action = "hideAllExceptFocused", key = "H" },
  },

  -- Launcher (for the Chooser atom, wired in init.lua). Hyper+Space opens a filterable
  -- list of every installed app (open first, then not running) plus the Hyper and
  -- window-leader actions; apps with a Hyper toggle show their shortcut, and Return runs
  -- the highlighted row. Same shape as clipboardHistory/vpn: a base HyperKey binding,
  -- suppressed while a modal context owns Hyper, with the HYPER field as the fallback
  -- combo. It also has its own hyperContext below, so while open it takes the shared
  -- j/k/i navigation and Space closes it (the open key doubles as the close, like the
  -- clipboard's X).
  launcher = { modifiers = HYPER, key = "space", description = "Launcher" },

  -- Menu search (for the Chooser atom, wired in init.lua). Hyper+E lists every
  -- enabled menu bar item of the frontmost app, read through the macOS
  -- Accessibility API, and runs the highlighted one. Same shape as the command
  -- palette: a base HyperKey binding, suppressed while a modal context owns Hyper.
  -- It also has its own hyperContext above, so while open it takes the shared
  -- j/k/i navigation and Space closes it. There is no HYPER fallback combo, since
  -- it has no meaning without HyperKey wired up (the menu tree is fetched live).
  -- Menu search is a discovery opener, so it is the one scopable tool with no launcher row
  -- of its own, which leaves its aliases advertised nowhere until the alias editor exists.
  menuSearch = { modifiers = HYPER, key = "e", description = "Menu search", aliases = { "m", "menu" } },

  -- Emoji picker (for Emoji.spoon, wired in init.lua). Hyper+J opens a filterable
  -- list of every emoji, matched by name, shortcode, tag, or category, so a keyword
  -- finds a glyph without its exact Unicode name. Same shape as the other pickers, a
  -- base HyperKey binding suppressed while a modal context owns Hyper, with the HYPER
  -- field as the fallback combo. It has its own hyperContext above, so while open it
  -- takes the shared j and k navigation and i inserts, and x closes it the way menu
  -- search does, since the open key j is itself the move down key inside.
  emoji = { modifiers = HYPER, key = "j", description = "Emoji picker", aliases = { "e", "emoji" } },

  -- External menu search combo. When Hyper+E is set to hand off (see init.lua) it
  -- fires this combo, and whatever tool you bind the SAME combo to anywhere opens.
  -- It is a plain shortcut with no app conditions, so it works everywhere. This is
  -- the one place the combo lives, keep it in step with the tool you bind it to.
  menuSearchShortcut = { mods = { "cmd", "alt", "ctrl", "shift" }, key = "j" },

  -- Display profiles (for DisplayProfiles.spoon, wired in init.lua). An inspect and manage
  -- tool for the saved display arrangements, opened from the launcher only, so it has no
  -- dedicated key and no modifiers. It lists the profiles, marks the active one, and lets you
  -- capture, rename, and delete the captured ones. It has its own hyperContext above, so
  -- while open it takes the shared j/k/i navigation and x closes it. `description` labels its
  -- launcher row.
  displayProfiles = { description = "Display Profiles" },

  -- Text case (for TextCase.spoon, wired in init.lua). Recases the current selection in
  -- place. Opened from the launcher only, so it has no dedicated key and no modifiers. It
  -- reads the selection, lists every case with the selection previewed in each, and pastes
  -- the chosen one over the selection. It has its own hyperContext above, so while open it
  -- takes the shared j/k/i navigation and x closes it. `description` labels its launcher row.
  --
  -- Deliberately not scopable. A scope cannot read the selection, since that needs the keyboard
  -- in the app the launcher is covering, so a scoped version could list the cases but never
  -- preview your own text in them. The preview is most of what makes the picker worth opening,
  -- so the alias was tried and removed rather than kept as a lesser copy of the tool.
  textCase = { description = "Text Case" },

  -- Browser tabs (for BrowserTabs.spoon, wired in init.lua). Hyper+W lists every open tab
  -- across the browsers that are switched on, most recently looked at first, each row showing
  -- its browser's icon, and the last row opens settings where each browser is switched on or
  -- off. Same shape as the other pickers, a base HyperKey binding suppressed while a modal
  -- context owns Hyper, with the HYPER field as the fallback combo. It has its own
  -- hyperContext above, so while open it takes the shared j, k, i, and x navigation. W reads
  -- as web, since B is already the Books toggle and T the Stickies one.
  --
  -- Scoped, it lists the tabs alone. The settings row is a step into a second level, which a
  -- scope has no way to show, so reaching the browser switches means opening the tool itself.
  browserTabs = { modifiers = HYPER, key = "W", description = "Browser tabs", aliases = { "t", "tabs" } },

  -- File search (for FileSearch.spoon, wired in init.lua). Hyper+/ searches the filesystem by
  -- name, optionally filtered by type, scoped to a folder, and optionally reaching the files
  -- macOS does not index at all. Same shape as the other pickers, a base HyperKey binding
  -- suppressed while a modal context owns Hyper, with the HYPER field as the fallback combo. It
  -- has its own hyperContext above, so while open it takes the shared j/k/i navigation plus its
  -- own browse, reveal, open folder and copy path actions, and x closes it.
  --
  -- Slash reads as search, the way it does in vim and in every browser find, and Activity
  -- Monitor moved one key over to backslash to free it.
  -- The alias is the same character as the key, which is the point. One thing to remember, and
  -- a slash reads as a path everywhere else too. Only one word, since `file` would claim every
  -- launcher query beginning with that word and a space.
  fileSearch = { modifiers = HYPER, key = "/", description = "File search", aliases = { "/" } },

  -- Processes (for Processes.spoon, wired in init.lua). Finds the development servers you
  -- left running, identified by the port they hold and the project they run in, and stops
  -- them by taking the whole process group or the whole container rather than one leaf
  -- process. Opened from the launcher only, so it has no dedicated key and no modifiers. It
  -- has its own hyperContext above, so while open it takes the shared j/k/i navigation plus
  -- its own force stop, rescan and sort by load, and x closes it. `description` labels its
  -- launcher row.
  --
  -- Named for what it lists rather than for the spoon behind it. It shows local port
  -- holders, containers, and portless watchers, never the whole process table, and
  -- calling the row Processes promised a system monitor it deliberately is not. The
  -- spoon keeps its own name, since that one is an internal identifier and nobody reads it.
  processes = { description = "Local Servers" },

  -- The scopes over the launcher's own catalog rather than over a tool. Each narrows the list to
  -- one kind of row the launcher already holds, so they open nothing and have no key and no
  -- chooser. They exist here only because this is where an alias lives, and their description
  -- names what the scoped list is rather than a tool. Each is a group of rows rather than one
  -- row, so like menu search they have nowhere to advertise their aliases until the alias
  -- editor exists.
  apps = { description = "Applications", aliases = { "a", "app" } },
  windowActions = { description = "Window actions", aliases = { "w", "window" } },
  settingsPanes = { description = "System Settings", aliases = { "s", "system" } },

  -- Feature toggles
  toggleDock = { modifiers = CTRL_ALT, key = "D" },

  -- Terminal handler
  terminal = { modifiers = { "alt" }, key = "`" },
}
