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
    { app = "Preview",          modifiers = HYPER, key = "P" },
    -- Second character
    { app = "Bruno",            modifiers = HYPER, key = "R" },
    { app = "Stickies",         modifiers = HYPER, key = "T" },
    { app = "Slack",            modifiers = HYPER, key = "L" },
    -- Third character
    { app = "Claude",           modifiers = HYPER, key = "A" },
    -- Default terminal: plain focus/cycle. (alt+` summons it placed via TerminalHandler)
    { app = "Ghostty",          modifiers = HYPER, key = "`" },
    -- Activity Monitor
    { app = "ActivityMonitor",  modifiers = HYPER, key = "/" },
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

  -- Clipboard history (for ClipboardHistory.spoon). Same modifiers/key shape as
  -- appToggles so the HYPER field acts as the fallback combo when HyperKey is
  -- not wired up. The `description` labels its row on the Hyper cheat sheet.
  clipboardHistory = { modifiers = HYPER, key = "X", description = "Clipboard history" },

  -- Keep awake (for Caffeinate.spoon). Same shape as clipboardHistory. Hyper+K
  -- opens the keep awake panel, a typed field, not a list. It is a base binding,
  -- suppressed while a modal context owns Hyper.
  caffeinate = { modifiers = HYPER, key = "K", description = "Keep awake" },

  -- VPN controls (for Vpn.spoon). Same shape again. Hyper+Y opens the VPN control
  -- panel, a short list of actions with the live connection state at the top. It is
  -- a base binding, suppressed while a modal context owns Hyper.
  vpn = { modifiers = HYPER, key = "Y", description = "VPN" },

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
  -- items can be gathered and pasted together on close, and x closes the chooser,
  -- the same as Escape. x needs its own binding because the context is modal, so
  -- the base Hyper+X toggle is suppressed while the chooser is open.
  --
  -- The keep awake panel is a list you navigate. j and k move the highlight down
  -- and up vim style, the same as the arrow keys the panel handles natively, and x
  -- closes it, the same as Escape. Typing the hours and minutes of a row happens with
  -- Hyper released, since a held Hyper owns the keys. This context stays modal, so
  -- while it is open the base Hyper toggles are suppressed and Hyper belongs to it,
  -- and it is the active context so holding Hyper reveals nothing.
  --
  -- The VPN control panel is the same kind of list, so it carries the same j, k, and
  -- x. Its location search is a separate chooser, like the clipboard, so it gets its
  -- own context with j and k to move, i to connect to the highlighted city, and x to
  -- close, plus the Hyper hold overlay that spells those out. Plain typing filters the
  -- list while Hyper is released.
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
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    {
      name = "caffeinate",
      when = "caffeinateOpen",
      priority = 100,
      bindings = {
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "j", action = "selectNext",     description = "Move down" },
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
    {
      name = "vpnLocations",
      when = "vpnLocationsOpen",
      priority = 100,
      bindings = {
        { key = "k", action = "selectPrev",     description = "Move up" },
        { key = "j", action = "selectNext",     description = "Move down" },
        { key = "i", action = "insertSelected", description = "Connect" },
        { key = "x", action = "closeChooser",   description = "Close" },
      },
    },
    -- The command palette chooser. i runs the highlighted command the same as
    -- Return, j and k navigate vim style, and Space closes it, the same as Escape.
    -- Space is the open key, so it doubles as the close, the way the clipboard's X
    -- does. Plain typing filters the list while Hyper is released.
    {
      name = "commandPalette",
      when = "commandPaletteOpen",
      priority = 100,
      bindings = {
        { key = "i",     action = "insertSelected", description = "Run" },
        { key = "j",     action = "selectNext",     description = "Move down" },
        { key = "k",     action = "selectPrev",     description = "Move up" },
        { key = "space", action = "closeChooser",   description = "Close" },
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
  -- Hyper+4 and Hyper+Shift+4 are distinct, file vs clipboard. `description`
  -- labels the row on the Hyper cheat sheet, where init.lua surfaces these as a
  -- CAPTURE section.
  capture = {
    { action = "ocrArea",              modifiers = HYPER, key = "3",                     description = "OCR" },
    { action = "captureArea",          modifiers = HYPER, key = "4",                     description = "Screenshot" },
    { action = "captureAreaClipboard", modifiers = HYPER, key = "4", mods = { "shift" }, description = "Screenshot (copy)" },
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
    -- Move (Shift+arrow) and center
    { action = "moveLeft",             key = "left",  mods = { "shift" } },
    { action = "moveRight",            key = "right", mods = { "shift" } },
    { action = "moveUp",               key = "up",    mods = { "shift" } },
    { action = "moveDown",             key = "down",  mods = { "shift" } },
    { action = "center",               key = "C" },
    -- Hide all except the focused window (kept last so it sits in the last row)
    { action = "hideAllExceptFocused", key = "H" },
  },

  -- Command palette / switcher (for the Chooser atom, wired in init.lua). Hyper+Space
  -- opens a filterable list of every installed app (open first, then not running) plus
  -- the Hyper and window-leader actions; apps with a Hyper toggle show their shortcut,
  -- and Return runs the highlighted row. Same shape as clipboardHistory/vpn: a base
  -- HyperKey binding, suppressed while a modal context owns Hyper, with the HYPER field
  -- as the fallback combo. It also has its own hyperContext below, so while open it
  -- takes the shared j/k/i navigation and Space closes it (the open key doubles as the
  -- close, like the clipboard's X).
  commandPalette = { modifiers = HYPER, key = "space", description = "Command palette" },

  -- Feature toggles
  toggleDock = { modifiers = CTRL_ALT, key = "D" },

  -- Terminal handler
  terminal = { modifiers = { "alt" }, key = "`" },
}
