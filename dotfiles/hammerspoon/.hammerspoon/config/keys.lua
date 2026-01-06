-- Keybinding definitions
-- Pure data, no logic

-- Modifier key combinations
local HYPER = { "shift", "ctrl", "alt", "cmd" }
local CTRL_ALT = { "ctrl", "alt" }
local CTRL_ALT_CMD = { "ctrl", "alt", "cmd" }
local CTRL_ALT_SHIFT = { "ctrl", "alt", "shift" }
local SHIFT_ALT = { "shift", "alt" }

return {
  -- Expose modifiers for Spoons that need them
  modifiers = {
    HYPER = HYPER,
    CTRL_ALT = CTRL_ALT,
    CTRL_ALT_CMD = CTRL_ALT_CMD,
    CTRL_ALT_SHIFT = CTRL_ALT_SHIFT,
    SHIFT_ALT = SHIFT_ALT,
  },

  -- App toggle bindings (for AppToggler.spoon)
  -- Uses app names from config/apps.lua
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
    { app = "PyCharm",          modifiers = HYPER, key = "P" },
    { app = "Notes",            modifiers = HYPER, key = "N" },
    { app = "iPhoneMirroring",  modifiers = HYPER, key = "I" },
    { app = "Zed",              modifiers = HYPER, key = "Z" },
    -- Second character
    { app = "Bruno",            modifiers = HYPER, key = "R" },
    { app = "Stickies",         modifiers = HYPER, key = "T" },
    { app = "Slack",            modifiers = HYPER, key = "L" },
    { app = "Cursor",           modifiers = HYPER, key = "U" },
    { app = "ChatGPT",          modifiers = HYPER, key = "H" },
    -- Third character
    { app = "Claude",           modifiers = HYPER, key = "A" },
    -- Disabled (uncomment to enable)
    -- { app = "ChatGPTAtlas",   modifiers = HYPER, key = "A" },
    -- { app = "AndroidStudio",  modifiers = HYPER, key = "A" },
    -- { app = "Hammerspoon",    modifiers = HYPER, key = "H" },
    -- { app = "TablePlus",      modifiers = HYPER, key = "P" },
    -- { app = "Xcode",          modifiers = HYPER, key = "X" },
  },

  -- Window management bindings (for WindowManager.spoon)
  windowManagement = {
    maximize =             { modifiers = CTRL_ALT,       key = "return" },
    center =               { modifiers = CTRL_ALT,       key = "C" },
    fullHeightReasonable = { modifiers = CTRL_ALT,       key = "up" },
    almostMaximize =       { modifiers = CTRL_ALT,       key = "down" },
    leftHalf =             { modifiers = CTRL_ALT,       key = "left" },
    rightHalf =            { modifiers = CTRL_ALT,       key = "right" },
    reasonableSize =       { modifiers = CTRL_ALT,       key = "X" },
    smallSize =            { modifiers = CTRL_ALT,       key = "Z" },
    increaseSize =         { modifiers = CTRL_ALT,       key = "=" },
    decreaseSize =         { modifiers = CTRL_ALT,       key = "-" },
    nextDisplay =          { modifiers = CTRL_ALT_CMD,   key = "right" },
    previousDisplay =      { modifiers = CTRL_ALT_CMD,   key = "left" },
    hideAllExceptFocused = { modifiers = CTRL_ALT,       key = "H" },
    screenRecording =      { modifiers = CTRL_ALT,       key = "R" },
    moveLeft =             { modifiers = CTRL_ALT_SHIFT, key = "left" },
    moveRight =            { modifiers = CTRL_ALT_SHIFT, key = "right" },
    moveUp =               { modifiers = CTRL_ALT_SHIFT, key = "up" },
    moveDown =             { modifiers = CTRL_ALT_SHIFT, key = "down" },
  },

  -- Feature toggles
  toggleDock = { modifiers = CTRL_ALT, key = "D" },

  -- Terminal handler
  terminal = { modifiers = { "alt" }, key = "`" },
}
