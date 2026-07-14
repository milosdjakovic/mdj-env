-- Keybinding definitions
-- Pure data, no logic

-- Modifier key combinations
local HYPER = { "shift", "ctrl", "alt", "cmd" }
local CTRL_ALT = { "ctrl", "alt" }
local SHIFT_ALT = { "shift", "alt" }

-- Window-management leader keys. Right Option and Right Command are remapped to
-- F17 and F16 at the HID level (see src/setup-capslock-hyper.sh) and driven by
-- WindowLeader.spoon. Hold the leader, press the key. These are the (remapped)
-- virtual keycodes of the function keys, not modifier lists. They sit just below
-- HYPER, the F18 (Caps Lock) app toggler driven by HyperKey.spoon.
--
-- SUPER is the active window leader. All window management now lives on it, a
-- bare arrow resizes and a Shift+arrow moves. META is kept here as a definition
-- but is currently deactivated (nothing binds to it, and init.lua does not
-- register it). To bring it back, uncomment its addLeader in init.lua, add
-- [106]="META" to the WindowCheatSheet leaders map, and give some entries below
-- `leader = META`.
local SUPER = 64  -- F17 (Right Option), the active window leader
local META  = 106 -- F16 (Right Command), defined but deactivated (see above)

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
  -- not wired up. The `description` labels its row on the Hyper cheat sheet.
  clipboardHistory = { modifiers = HYPER, key = "X", description = "Clipboard history" },

  -- Screen capture (for Capture.spoon). Provider-agnostic action names; the
  -- active provider (macshot today, set in init.lua) maps them to its own
  -- commands, so swapping capture apps never touches this list. Keys mirror the
  -- macOS Cmd-Shift-4 / Cmd-Shift-5 muscle memory. The HYPER field is the
  -- fallback combo used when HyperKey is not wired up, matching appToggles.
  -- Optional `mods` are sub-modifiers within the Hyper modal, so Hyper+4 and
  -- Hyper+Shift+4 are distinct, file vs clipboard. `description` labels the row
  -- on the Hyper cheat sheet, where init.lua surfaces these as a CAPTURE section.
  capture = {
    { action = "captureArea",          modifiers = HYPER, key = "4",                     description = "Screenshot" },
    { action = "captureAreaClipboard", modifiers = HYPER, key = "4", mods = { "shift" }, description = "Screenshot (copy)" },
    { action = "recordArea",           modifiers = HYPER, key = "5",                     description = "Record" },
  },

  -- Window management bindings (for WindowManager.spoon via WindowLeader.spoon).
  -- This is an ORDERED list: the sequence here is exactly the cheat-sheet order
  -- (WindowCheatSheet fills row-major, two columns), so reorder these lines to
  -- reorder the overlay. `action` names the WindowManager handler; `leader` is
  -- the held function key; `key` is a single press. An optional `mods` list adds
  -- required sub-modifiers, so a bare arrow and a Shift+arrow are two actions on
  -- one key. Each label is the action name humanized (nextDisplay -> "Next
  -- Display"); add `description = "..."` to any entry to override its label. An
  -- optional `when = "<predicate>"` gates the binding on live state. When the
  -- named predicate returns false the key does nothing and its cheat-sheet row is
  -- hidden. Predicates live in the registry wired up in init.lua, so this stays
  -- pure data. Unknown names are treated as always active so a typo fails visibly
  -- rather than silently hiding a binding.
  --
  -- SUPER (Right Option) is the single window leader. Hold it, then a bare arrow
  -- resizes (halves, full height) while a Shift+arrow moves the window. Letters
  -- and symbols cover maximize, presets, grow/shrink, center, and display switch.
  -- Hold SUPER ~0.6s with no other key to reveal the cheat sheet.
  windowManagement = {
    -- Resize (bare key)
    { action = "leftHalf",             leader = SUPER, key = "left" },
    { action = "rightHalf",            leader = SUPER, key = "right" },
    { action = "fullHeight",           leader = SUPER, key = "up" },
    { action = "reasonableSize",       leader = SUPER, key = "down" },
    { action = "maximize",             leader = SUPER, key = "return" },
    { action = "smallSize",            leader = SUPER, key = "Z" },
    { action = "increaseSize",         leader = SUPER, key = "=" },
    { action = "decreaseSize",         leader = SUPER, key = "-" },
    { action = "hideAllExceptFocused", leader = SUPER, key = "H" },
    { action = "screenRecording",      leader = SUPER, key = "R" },
    -- Move (Shift+arrow), center, and switch display
    { action = "moveLeft",             leader = SUPER, key = "left",  mods = { "shift" } },
    { action = "moveRight",            leader = SUPER, key = "right", mods = { "shift" } },
    { action = "moveUp",               leader = SUPER, key = "up",    mods = { "shift" } },
    { action = "moveDown",             leader = SUPER, key = "down",  mods = { "shift" } },
    { action = "center",               leader = SUPER, key = "C" },
    { action = "previousDisplay",      leader = SUPER, key = ",", when = "multipleDisplays" },
    { action = "nextDisplay",          leader = SUPER, key = ".", when = "multipleDisplays" },
  },

  -- Feature toggles
  toggleDock = { modifiers = CTRL_ALT, key = "D" },

  -- Terminal handler
  terminal = { modifiers = { "alt" }, key = "`" },
}
