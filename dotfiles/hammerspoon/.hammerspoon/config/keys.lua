-- Keybinding definitions
-- Pure data, no logic

-- Modifier key combinations
local HYPER = { "shift", "ctrl", "alt", "cmd" }
local CTRL_ALT = { "ctrl", "alt" }
local SHIFT_ALT = { "shift", "alt" }

-- Window-management leader keys. Right Option and Right Command are remapped to
-- F17 and F16 at the HID level (see src/setup-capslock-hyper.sh) and driven by
-- WindowLeader.spoon: hold the leader, press the key. These are the (remapped)
-- virtual keycodes of the function keys, not modifier lists.
--
-- Named for the classic modifier hierarchy META < SUPER < HYPER, ascending with
-- the function-key number: META=F16, SUPER=F17, HYPER=F18 (Caps Lock, the app
-- toggler driven by HyperKey.spoon -- the biggest, hence its own established
-- name).
local SUPER = 64  -- F17 (Right Option): base window ops
local META = 106  -- F16 (Right Command): switch display + move window

return {
  -- Expose modifiers for Spoons that need them
  modifiers = {
    HYPER = HYPER,
    CTRL_ALT = CTRL_ALT,
    SHIFT_ALT = SHIFT_ALT,
  },

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
  -- not wired up.
  clipboardHistory = { modifiers = HYPER, key = "X" },

  -- Window management bindings (for WindowManager.spoon via WindowLeader.spoon).
  -- `leader` is the held function key; `mods` (optional) requires extra real
  -- modifiers held alongside it.
  --   SUPER (Right Option): base ops -- hold + key.
  --   META (Right Command): hold + arrow switches display,
  --                         hold + Shift + arrow moves the window.
  windowManagement = {
    maximize =             { leader = SUPER, key = "return" },
    center =               { leader = SUPER, key = "C" },
    fullHeightReasonable = { leader = SUPER, key = "up" },
    almostMaximize =       { leader = SUPER, key = "down" },
    leftHalf =             { leader = SUPER, key = "left" },
    rightHalf =            { leader = SUPER, key = "right" },
    reasonableSize =       { leader = SUPER, key = "X" },
    smallSize =            { leader = SUPER, key = "Z" },
    increaseSize =         { leader = SUPER, key = "=" },
    decreaseSize =         { leader = SUPER, key = "-" },
    hideAllExceptFocused = { leader = SUPER, key = "H" },
    screenRecording =      { leader = SUPER, key = "R" },
    nextDisplay =          { leader = META, key = "right" },
    previousDisplay =      { leader = META, key = "left" },
    moveLeft =             { leader = META, mods = { "shift" }, key = "left" },
    moveRight =            { leader = META, mods = { "shift" }, key = "right" },
    moveUp =               { leader = META, mods = { "shift" }, key = "up" },
    moveDown =             { leader = META, mods = { "shift" }, key = "down" },
  },

  -- Feature toggles
  toggleDock = { modifiers = CTRL_ALT, key = "D" },

  -- Terminal handler
  terminal = { modifiers = { "alt" }, key = "`" },
}
